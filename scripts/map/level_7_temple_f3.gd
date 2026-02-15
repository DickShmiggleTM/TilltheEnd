extends Node3D
## Level 7 – "Throne of the Nameless" – Temple Floor 3 (FINAL LEVEL)
## The innermost sanctum of the nameless God's temple. Inhuman scale architecture
## with a grand approach corridor, antechambers, dimensional rifts, and a massive
## circular throne room serving as the final boss arena.
##
## Usage:
##   var level = preload("res://scripts/map/level_7_temple_f3.gd").new()
##   add_child(level)
##   level.generate_map(seed_value)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 90
const GRID_HEIGHT: int = 90
const CELL_SIZE: float = 4.5
const WALL_HEIGHT: float = 12.0

const MIN_PARTITION_SIZE: int = 9
const MAX_PARTITION_SIZE: int = 28
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 6
const CORRIDOR_WIDTH: int = 3

const ENVIRONMENT_LAYER: int = 1

const ARENA_SPAWN_DENSITY: int = 16
const MIN_ARENA_SPAWNS: int = 5

# Grand approach dimensions
const APPROACH_WIDTH: int = 6
const APPROACH_LENGTH: int = 42

# Throne room
const THRONE_RADIUS: int = 22

# Antechamber count
const ANTECHAMBER_COUNT: int = 6

# Pillar spacing along approach
const APPROACH_PILLAR_SPACING: int = 4
const APPROACH_PILLAR_RADIUS: float = 0.8

# Brazier spacing
const BRAZIER_SPACING: int = 5

# ---------------------------------------------------------------------------
# Cell types
# ---------------------------------------------------------------------------

enum Cell {
	VOID = 0,
	FLOOR = 1,
	WALL = 2,
}

# ---------------------------------------------------------------------------
# Inner classes
# ---------------------------------------------------------------------------

class Rect2i_BSP:
	var x: int
	var y: int
	var w: int
	var h: int

	func _init(px: int, py: int, pw: int, ph: int) -> void:
		x = px; y = py; w = pw; h = ph

	func center() -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(x + w / 2, y + h / 2)

	func area() -> int:
		return w * h


class BSPNode:
	var rect: Rect2i_BSP
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2i_BSP = null

	func _init(r: Rect2i_BSP) -> void:
		rect = r

	func is_leaf() -> bool:
		return left == null and right == null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _grid: Array = []
var _rooms: Array = []
var _arena_rooms: Array = []
var _antechambers: Array = []
var _throne_room_center: Vector2i = Vector2i.ZERO
var _throne_room_radius: int = THRONE_RADIUS
var _approach_rect: Rect2i_BSP = null
var _entrance_room: Rect2i_BSP = null
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null
var _decorations_root: Node3D = null

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

var _mat_floor: StandardMaterial3D = null
var _mat_wall: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_corridor_floor: StandardMaterial3D = null
var _mat_accent: StandardMaterial3D = null
var _mat_pillar: StandardMaterial3D = null
var _mat_throne: StandardMaterial3D = null
var _mat_void_orb: StandardMaterial3D = null
var _mat_rift: StandardMaterial3D = null
var _mat_brazier: StandardMaterial3D = null
var _mat_tile_light: StandardMaterial3D = null
var _mat_tile_dark: StandardMaterial3D = null
var _mat_bone: StandardMaterial3D = null
var _mat_void_portal: StandardMaterial3D = null
var _mat_jagged: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value
	_create_materials()
	_init_grid()

	# 1. Carve circular throne room
	_carve_throne_room()

	# 2. Carve grand approach corridor
	_carve_grand_approach()

	# 3. Carve entrance room
	_carve_entrance()

	# 4. Generate antechambers along the approach
	_generate_antechambers()

	# 5. Connect antechambers to approach
	_connect_antechambers()

	# 6. Build walls
	_build_walls()

	# 7. Classify rooms
	_classify_rooms()

	# 8. Build geometry
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)
	_build_geometry()

	# 9. Build decorations
	_decorations_root = Node3D.new()
	_decorations_root.name = "Decorations"
	add_child(_decorations_root)
	_build_approach_pillars()
	_build_approach_floor_pattern()
	_build_braziers()
	_build_throne()
	_build_void_orbs()
	_build_jagged_walls()
	_build_antechamber_themes()
	_build_dimensional_rifts()

	# 10. Build lighting
	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)
	_build_environment()

	# 11. Spawn points
	_determine_spawn_points()


func get_player_spawn() -> Vector3:
	return _player_spawn


func get_enemy_spawn_points() -> Array[Vector3]:
	return _enemy_spawns


func clear_map() -> void:
	for child_node in [_geometry_root, _lighting_root, _decorations_root]:
		if child_node and is_instance_valid(child_node):
			child_node.queue_free()
	_geometry_root = null
	_lighting_root = null
	_decorations_root = null
	_grid.clear()
	_rooms.clear()
	_arena_rooms.clear()
	_antechambers.clear()
	_throne_room_center = Vector2i.ZERO
	_approach_rect = null
	_entrance_room = null
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var c := room.center()
		var room_type: String = "normal"
		if room == _approach_rect:
			room_type = "approach"
		elif room == _entrance_room:
			room_type = "entrance"
		elif room in _antechambers:
			room_type = "antechamber"
		data.append({
			"position": Vector3(_grid_to_world_x(c.x), 0.0, _grid_to_world_z(c.y)),
			"size": Vector2(room.w * CELL_SIZE, room.h * CELL_SIZE),
			"is_arena": room in _arena_rooms,
			"room_type": room_type,
			"grid_rect": Rect2(room.x, room.y, room.w, room.h),
		})
	# Add the circular throne room as a special entry
	data.append({
		"position": Vector3(
			_grid_to_world_x(_throne_room_center.x),
			0.0,
			_grid_to_world_z(_throne_room_center.y)
		),
		"size": Vector2(_throne_room_radius * 2 * CELL_SIZE, _throne_room_radius * 2 * CELL_SIZE),
		"is_arena": true,
		"room_type": "throne_room",
		"grid_rect": Rect2(
			_throne_room_center.x - _throne_room_radius,
			_throne_room_center.y - _throne_room_radius,
			_throne_room_radius * 2,
			_throne_room_radius * 2
		),
	})
	return data


func is_walkable(world_pos: Vector3) -> bool:
	var gx: int = int(world_pos.x / CELL_SIZE)
	var gy: int = int(world_pos.z / CELL_SIZE)
	return _get_cell(gx, gy) == Cell.FLOOR

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.06, 0.0, 0.04)
	_mat_floor.roughness = 0.85
	_mat_floor.metallic = 0.05

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.08, 0.01, 0.06)
	_mat_wall.roughness = 0.9
	_mat_wall.metallic = 0.0

	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.02, 0.0, 0.01)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

	_mat_corridor_floor = StandardMaterial3D.new()
	_mat_corridor_floor.albedo_color = Color(0.04, 0.0, 0.03)
	_mat_corridor_floor.roughness = 0.9
	_mat_corridor_floor.metallic = 0.05

	_mat_accent = StandardMaterial3D.new()
	_mat_accent.albedo_color = Color(0.5, 0.05, 0.3)
	_mat_accent.roughness = 0.5
	_mat_accent.metallic = 0.15
	_mat_accent.emission_enabled = true
	_mat_accent.emission = Color(0.5, 0.05, 0.3)
	_mat_accent.emission_energy_multiplier = 0.6

	_mat_pillar = StandardMaterial3D.new()
	_mat_pillar.albedo_color = Color(0.1, 0.02, 0.08)
	_mat_pillar.roughness = 0.7
	_mat_pillar.metallic = 0.1

	_mat_throne = StandardMaterial3D.new()
	_mat_throne.albedo_color = Color(0.04, 0.0, 0.03)
	_mat_throne.roughness = 0.5
	_mat_throne.metallic = 0.3
	_mat_throne.emission_enabled = true
	_mat_throne.emission = Color(0.3, 0.02, 0.2)
	_mat_throne.emission_energy_multiplier = 0.4

	_mat_void_orb = StandardMaterial3D.new()
	_mat_void_orb.albedo_color = Color(0.15, 0.0, 0.1)
	_mat_void_orb.roughness = 0.1
	_mat_void_orb.metallic = 0.0
	_mat_void_orb.emission_enabled = true
	_mat_void_orb.emission = Color(0.4, 0.0, 0.25)
	_mat_void_orb.emission_energy_multiplier = 2.0
	_mat_void_orb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_void_orb.albedo_color.a = 0.7

	_mat_rift = StandardMaterial3D.new()
	_mat_rift.albedo_color = Color(0.2, 0.0, 0.15)
	_mat_rift.roughness = 0.2
	_mat_rift.metallic = 0.0
	_mat_rift.emission_enabled = true
	_mat_rift.emission = Color(0.5, 0.02, 0.35)
	_mat_rift.emission_energy_multiplier = 1.8

	_mat_brazier = StandardMaterial3D.new()
	_mat_brazier.albedo_color = Color(0.12, 0.02, 0.08)
	_mat_brazier.roughness = 0.6
	_mat_brazier.metallic = 0.2

	_mat_tile_light = StandardMaterial3D.new()
	_mat_tile_light.albedo_color = Color(0.1, 0.01, 0.07)
	_mat_tile_light.roughness = 0.7
	_mat_tile_light.metallic = 0.1

	_mat_tile_dark = StandardMaterial3D.new()
	_mat_tile_dark.albedo_color = Color(0.03, 0.0, 0.02)
	_mat_tile_dark.roughness = 0.8
	_mat_tile_dark.metallic = 0.05

	_mat_bone = StandardMaterial3D.new()
	_mat_bone.albedo_color = Color(0.7, 0.65, 0.55)
	_mat_bone.roughness = 0.8
	_mat_bone.metallic = 0.0

	_mat_void_portal = StandardMaterial3D.new()
	_mat_void_portal.albedo_color = Color(0.15, 0.0, 0.2)
	_mat_void_portal.roughness = 0.1
	_mat_void_portal.metallic = 0.0
	_mat_void_portal.emission_enabled = true
	_mat_void_portal.emission = Color(0.3, 0.0, 0.4)
	_mat_void_portal.emission_energy_multiplier = 1.5
	_mat_void_portal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_void_portal.albedo_color.a = 0.6

	_mat_jagged = StandardMaterial3D.new()
	_mat_jagged.albedo_color = Color(0.06, 0.005, 0.04)
	_mat_jagged.roughness = 1.0
	_mat_jagged.metallic = 0.0

# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

func _init_grid() -> void:
	_grid.resize(GRID_WIDTH)
	for x in range(GRID_WIDTH):
		var col: Array = []
		col.resize(GRID_HEIGHT)
		col.fill(Cell.VOID)
		_grid[x] = col


func _set_cell(x: int, y: int, value: int) -> void:
	if x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT:
		_grid[x][y] = value


func _get_cell(x: int, y: int) -> int:
	if x >= 0 and x < GRID_WIDTH and y >= 0 and y < GRID_HEIGHT:
		return _grid[x][y]
	return Cell.VOID


func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE

# ---------------------------------------------------------------------------
# Throne room — circular carving
# ---------------------------------------------------------------------------

func _carve_throne_room() -> void:
	# Place the throne room in the upper-center portion of the grid
	@warning_ignore("integer_division")
	var cx: int = GRID_WIDTH / 2
	var cy: int = THRONE_RADIUS + 4  # near the top

	_throne_room_center = Vector2i(cx, cy)

	# Carve circular area
	for x in range(cx - THRONE_RADIUS - 1, cx + THRONE_RADIUS + 2):
		for y in range(cy - THRONE_RADIUS - 1, cy + THRONE_RADIUS + 2):
			var dx: float = x - cx
			var dy: float = y - cy
			if dx * dx + dy * dy <= THRONE_RADIUS * THRONE_RADIUS:
				_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Grand approach corridor
# ---------------------------------------------------------------------------

func _carve_grand_approach() -> void:
	@warning_ignore("integer_division")
	var ax: int = GRID_WIDTH / 2 - APPROACH_WIDTH / 2
	var ay: int = _throne_room_center.y + THRONE_RADIUS  # starts right below throne room
	var ah: int = APPROACH_LENGTH

	# Ensure it fits in grid
	ah = mini(ah, GRID_HEIGHT - ay - 4)

	_approach_rect = Rect2i_BSP.new(ax, ay, APPROACH_WIDTH, ah)
	_rooms.append(_approach_rect)

	for x in range(ax, ax + APPROACH_WIDTH):
		for y in range(ay, ay + ah):
			_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Entrance room (stairway from floor 2)
# ---------------------------------------------------------------------------

func _carve_entrance() -> void:
	var ew: int = 8
	var eh: int = 7
	@warning_ignore("integer_division")
	var ex: int = GRID_WIDTH / 2 - ew / 2
	var ey: int = _approach_rect.y + _approach_rect.h + 1

	# Clamp to grid
	ey = mini(ey, GRID_HEIGHT - eh - 2)

	_entrance_room = Rect2i_BSP.new(ex, ey, ew, eh)
	_rooms.append(_entrance_room)

	for x in range(ex, ex + ew):
		for y in range(ey, ey + eh):
			_set_cell(x, y, Cell.FLOOR)

	# Connect entrance to approach
	_carve_corridor(_entrance_room.center(), _approach_rect.center())

# ---------------------------------------------------------------------------
# Antechambers along the approach
# ---------------------------------------------------------------------------

func _generate_antechambers() -> void:
	var ax: int = _approach_rect.x
	var ay: int = _approach_rect.y
	var aw: int = _approach_rect.w
	var ah: int = _approach_rect.h

	# Place antechambers alternating left and right along the approach
	var chamber_spacing: int = ah / (ANTECHAMBER_COUNT / 2 + 1)
	var placed: int = 0

	for i in range(ANTECHAMBER_COUNT):
		if placed >= ANTECHAMBER_COUNT:
			break

		var side: int = 1 if i % 2 == 0 else -1  # right or left
		@warning_ignore("integer_division")
		var slot_y: int = ay + chamber_spacing * ((i / 2) + 1)

		var cw: int = _rng.randi_range(8, 12)
		var ch: int = _rng.randi_range(8, 12)

		var cx_val: int
		if side == 1:
			cx_val = ax + aw + 2
		else:
			cx_val = ax - cw - 2

		var cy_val: int = slot_y - ch / 2

		# Ensure in bounds
		cx_val = clampi(cx_val, 2, GRID_WIDTH - cw - 2)
		cy_val = clampi(cy_val, 2, GRID_HEIGHT - ch - 2)

		var chamber := Rect2i_BSP.new(cx_val, cy_val, cw, ch)
		_rooms.append(chamber)
		_antechambers.append(chamber)

		for x in range(cx_val, cx_val + cw):
			for y in range(cy_val, cy_val + ch):
				_set_cell(x, y, Cell.FLOOR)

		placed += 1

# ---------------------------------------------------------------------------
# Connect antechambers to approach
# ---------------------------------------------------------------------------

func _connect_antechambers() -> void:
	for chamber: Rect2i_BSP in _antechambers:
		var cc := chamber.center()
		# Connect to the nearest point on the approach
		var approach_x: int = clampi(cc.x, _approach_rect.x, _approach_rect.x + _approach_rect.w - 1)
		var approach_y: int = clampi(cc.y, _approach_rect.y, _approach_rect.y + _approach_rect.h - 1)
		_carve_corridor(cc, Vector2i(approach_x, approach_y))


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var go_horizontal_first: bool = _rng.randf() < 0.5
	if go_horizontal_first:
		_carve_horizontal(from.x, to.x, from.y)
		_carve_vertical(from.y, to.y, to.x)
	else:
		_carve_vertical(from.y, to.y, from.x)
		_carve_horizontal(from.x, to.x, to.y)


func _carve_horizontal(x1: int, x2: int, y: int) -> void:
	var start_x: int = mini(x1, x2)
	var end_x: int = maxi(x1, x2)
	for x in range(start_x, end_x + 1):
		for dy in range(CORRIDOR_WIDTH):
			var cy: int = y + dy - 1
			if _get_cell(x, cy) == Cell.VOID:
				_set_cell(x, cy, Cell.FLOOR)


func _carve_vertical(y1: int, y2: int, x: int) -> void:
	var start_y: int = mini(y1, y2)
	var end_y: int = maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx: int = x + dx - 1
			if _get_cell(cx, y) == Cell.VOID:
				_set_cell(cx, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Walls
# ---------------------------------------------------------------------------

func _build_walls() -> void:
	var wall_cells: Array[Vector2i] = []
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			if _grid[x][y] == Cell.VOID:
				if _has_floor_neighbor(x, y):
					wall_cells.append(Vector2i(x, y))
	for pos in wall_cells:
		_grid[pos.x][pos.y] = Cell.WALL


func _has_floor_neighbor(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if _get_cell(x + dx, y + dy) == Cell.FLOOR:
				return true
	return false

# ---------------------------------------------------------------------------
# Room classification
# ---------------------------------------------------------------------------

func _classify_rooms() -> void:
	_arena_rooms.clear()
	# The throne room is the primary arena (not stored as Rect2i_BSP, handled separately)
	# Antechambers are combat rooms
	for chamber: Rect2i_BSP in _antechambers:
		if chamber.area() >= 60:
			_arena_rooms.append(chamber)

# ---------------------------------------------------------------------------
# 3D geometry
# ---------------------------------------------------------------------------

func _build_geometry() -> void:
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		_create_floor_box(strip)

	var wall_strips := _build_horizontal_strips(Cell.WALL)
	for strip: Rect2i_BSP in wall_strips:
		_create_wall_box(strip)

	for strip: Rect2i_BSP in floor_strips:
		_create_ceiling_box(strip)


func _build_horizontal_strips(cell_type: int) -> Array:
	var visited: Array = []
	visited.resize(GRID_WIDTH)
	for x in range(GRID_WIDTH):
		var col: Array = []
		col.resize(GRID_HEIGHT)
		col.fill(false)
		visited[x] = col

	var strips: Array = []
	for y in range(GRID_HEIGHT):
		var x: int = 0
		while x < GRID_WIDTH:
			if _grid[x][y] == cell_type and not visited[x][y]:
				var start_x: int = x
				while x < GRID_WIDTH and _grid[x][y] == cell_type and not visited[x][y]:
					x += 1
				var strip_w: int = x - start_x
				var strip_h: int = 1
				var can_extend: bool = true
				while can_extend and y + strip_h < GRID_HEIGHT:
					for sx in range(start_x, start_x + strip_w):
						if _grid[sx][y + strip_h] != cell_type or visited[sx][y + strip_h]:
							can_extend = false
							break
					if can_extend:
						strip_h += 1
				for sy in range(y, y + strip_h):
					for sx in range(start_x, start_x + strip_w):
						visited[sx][sy] = true
				strips.append(Rect2i_BSP.new(start_x, y, strip_w, strip_h))
			else:
				x += 1
	return strips


func _create_floor_box(strip: Rect2i_BSP) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(strip.w * CELL_SIZE, 0.2, strip.h * CELL_SIZE)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		-0.1,
		_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
	)
	box.use_collision = true
	box.collision_layer = ENVIRONMENT_LAYER
	box.collision_mask = 0
	var is_in_room := _strip_overlaps_any_room(strip) or _strip_in_throne_room(strip)
	box.material = _mat_floor if is_in_room else _mat_corridor_floor
	box.name = "Floor_%d_%d" % [strip.x, strip.y]
	_geometry_root.add_child(box)


func _create_wall_box(strip: Rect2i_BSP) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(strip.w * CELL_SIZE, WALL_HEIGHT, strip.h * CELL_SIZE)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		WALL_HEIGHT * 0.5,
		_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
	)
	box.use_collision = true
	box.collision_layer = ENVIRONMENT_LAYER
	box.collision_mask = 0
	box.material = _mat_wall
	box.name = "Wall_%d_%d" % [strip.x, strip.y]
	_geometry_root.add_child(box)


func _create_ceiling_box(strip: Rect2i_BSP) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(strip.w * CELL_SIZE, 0.2, strip.h * CELL_SIZE)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		WALL_HEIGHT + 0.1,
		_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
	)
	box.use_collision = true
	box.collision_layer = ENVIRONMENT_LAYER
	box.collision_mask = 0
	box.material = _mat_ceiling
	box.name = "Ceiling_%d_%d" % [strip.x, strip.y]
	_geometry_root.add_child(box)


func _strip_overlaps_any_room(strip: Rect2i_BSP) -> bool:
	for room: Rect2i_BSP in _rooms:
		if strip.x < room.x + room.w and strip.x + strip.w > room.x \
			and strip.y < room.y + room.h and strip.y + strip.h > room.y:
			return true
	return false


func _strip_in_throne_room(strip: Rect2i_BSP) -> bool:
	# Check if center of strip falls within throne room radius
	@warning_ignore("integer_division")
	var scx: int = strip.x + strip.w / 2
	@warning_ignore("integer_division")
	var scy: int = strip.y + strip.h / 2
	var dx: float = scx - _throne_room_center.x
	var dy: float = scy - _throne_room_center.y
	return dx * dx + dy * dy <= _throne_room_radius * _throne_room_radius

# ---------------------------------------------------------------------------
# Decorations — Approach pillars
# ---------------------------------------------------------------------------

func _build_approach_pillars() -> void:
	if not _approach_rect:
		return
	var ax: int = _approach_rect.x
	var ay: int = _approach_rect.y
	var aw: int = _approach_rect.w
	var ah: int = _approach_rect.h

	var pillar_h: float = WALL_HEIGHT * 0.88
	var left_col: int = ax
	var right_col: int = ax + aw - 1

	var idx: int = 0
	for row_y in range(ay + 1, ay + ah - 1, APPROACH_PILLAR_SPACING):
		for col_x in [left_col, right_col]:
			var cyl := CSGCylinder3D.new()
			cyl.radius = APPROACH_PILLAR_RADIUS
			cyl.height = pillar_h
			cyl.sides = 14
			cyl.position = Vector3(
				_grid_to_world_x(col_x) + CELL_SIZE * 0.5,
				pillar_h * 0.5,
				_grid_to_world_z(row_y) + CELL_SIZE * 0.5
			)
			cyl.use_collision = true
			cyl.collision_layer = ENVIRONMENT_LAYER
			cyl.collision_mask = 0
			cyl.material = _mat_pillar
			cyl.name = "ApproachPillar_%d" % idx
			_decorations_root.add_child(cyl)

			# Wide base
			var base := CSGCylinder3D.new()
			base.radius = APPROACH_PILLAR_RADIUS * 1.7
			base.height = 0.5
			base.sides = 14
			base.position = Vector3(cyl.position.x, 0.25, cyl.position.z)
			base.use_collision = true
			base.collision_layer = ENVIRONMENT_LAYER
			base.collision_mask = 0
			base.material = _mat_pillar
			base.name = "ApproachPillarBase_%d" % idx
			_decorations_root.add_child(base)

			# Capital
			var cap := CSGCylinder3D.new()
			cap.radius = APPROACH_PILLAR_RADIUS * 1.5
			cap.height = 0.4
			cap.sides = 14
			cap.position = Vector3(cyl.position.x, pillar_h - 0.2, cyl.position.z)
			cap.use_collision = true
			cap.collision_layer = ENVIRONMENT_LAYER
			cap.collision_mask = 0
			cap.material = _mat_pillar
			cap.name = "ApproachPillarCap_%d" % idx
			_decorations_root.add_child(cap)

			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Approach floor pattern (alternating tiles)
# ---------------------------------------------------------------------------

func _build_approach_floor_pattern() -> void:
	if not _approach_rect:
		return
	var ax: int = _approach_rect.x
	var ay: int = _approach_rect.y
	var aw: int = _approach_rect.w
	var ah: int = _approach_rect.h

	var idx: int = 0
	for y in range(ay, ay + ah, 2):
		for x in range(ax, ax + aw, 2):
			# Checkerboard pattern with thin overlay tiles
			var is_light: bool = ((x + y) % 4) < 2
			var tile := CSGBox3D.new()
			tile.size = Vector3(CELL_SIZE * 1.9, 0.03, CELL_SIZE * 1.9)
			tile.position = Vector3(
				_grid_to_world_x(x) + CELL_SIZE,
				0.015,
				_grid_to_world_z(y) + CELL_SIZE
			)
			tile.material = _mat_tile_light if is_light else _mat_tile_dark
			tile.name = "ApproachTile_%d" % idx
			_decorations_root.add_child(tile)
			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Braziers along approach and in throne room
# ---------------------------------------------------------------------------

func _build_braziers() -> void:
	if not _approach_rect:
		return
	var ax: int = _approach_rect.x
	var ay: int = _approach_rect.y
	var aw: int = _approach_rect.w
	var ah: int = _approach_rect.h

	var idx: int = 0
	for row_y in range(ay + 2, ay + ah - 2, BRAZIER_SPACING):
		for col_x in [ax, ax + aw - 1]:
			var world_x: float = _grid_to_world_x(col_x) + CELL_SIZE * 0.5
			var world_z: float = _grid_to_world_z(row_y) + CELL_SIZE * 0.5

			# Brazier bowl — short wide cylinder
			var bowl := CSGCylinder3D.new()
			bowl.radius = 0.5
			bowl.height = 1.2
			bowl.sides = 10
			bowl.position = Vector3(world_x, 0.6, world_z)
			bowl.use_collision = true
			bowl.collision_layer = ENVIRONMENT_LAYER
			bowl.collision_mask = 0
			bowl.material = _mat_brazier
			bowl.name = "Brazier_%d" % idx
			_decorations_root.add_child(bowl)

			# Fire glow (small bright sphere on top)
			var fire := CSGSphere3D.new()
			fire.radius = 0.3
			fire.radial_segments = 8
			fire.rings = 6
			fire.position = Vector3(world_x, 1.4, world_z)
			fire.material = _mat_accent
			fire.name = "BrazierFire_%d" % idx
			_decorations_root.add_child(fire)

			idx += 1

	# Braziers around the throne room perimeter
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)
	var perimeter_r: float = (_throne_room_radius - 2) * CELL_SIZE
	var brazier_count: int = 12
	for i in range(brazier_count):
		var angle: float = (TAU / brazier_count) * i
		var bx: float = tr_cx + cos(angle) * perimeter_r
		var bz: float = tr_cz + sin(angle) * perimeter_r

		var bowl := CSGCylinder3D.new()
		bowl.radius = 0.6
		bowl.height = 1.5
		bowl.sides = 10
		bowl.position = Vector3(bx, 0.75, bz)
		bowl.use_collision = true
		bowl.collision_layer = ENVIRONMENT_LAYER
		bowl.collision_mask = 0
		bowl.material = _mat_brazier
		bowl.name = "ThroneBrazier_%d" % i
		_decorations_root.add_child(bowl)

		var fire := CSGSphere3D.new()
		fire.radius = 0.35
		fire.radial_segments = 8
		fire.rings = 6
		fire.position = Vector3(bx, 1.7, bz)
		fire.material = _mat_accent
		fire.name = "ThroneBrazierFire_%d" % i
		_decorations_root.add_child(fire)

# ---------------------------------------------------------------------------
# Decorations — The Throne
# ---------------------------------------------------------------------------

func _build_throne() -> void:
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)

	# Throne is at the far end of the throne room (top/north)
	var throne_z: float = tr_cz - (_throne_room_radius - 4) * CELL_SIZE

	# Base platform — wide stepped structure
	var base1 := CSGBox3D.new()
	base1.size = Vector3(12.0, 1.0, 8.0)
	base1.position = Vector3(tr_cx, 0.5, throne_z)
	base1.use_collision = true
	base1.collision_layer = ENVIRONMENT_LAYER
	base1.collision_mask = 0
	base1.material = _mat_throne
	base1.name = "ThroneBase1"
	_decorations_root.add_child(base1)

	var base2 := CSGBox3D.new()
	base2.size = Vector3(9.0, 1.0, 6.0)
	base2.position = Vector3(tr_cx, 1.5, throne_z)
	base2.use_collision = true
	base2.collision_layer = ENVIRONMENT_LAYER
	base2.collision_mask = 0
	base2.material = _mat_throne
	base2.name = "ThroneBase2"
	_decorations_root.add_child(base2)

	var base3 := CSGBox3D.new()
	base3.size = Vector3(6.0, 1.0, 4.0)
	base3.position = Vector3(tr_cx, 2.5, throne_z)
	base3.use_collision = true
	base3.collision_layer = ENVIRONMENT_LAYER
	base3.collision_mask = 0
	base3.material = _mat_throne
	base3.name = "ThroneBase3"
	_decorations_root.add_child(base3)

	# The seat
	var seat := CSGBox3D.new()
	seat.size = Vector3(4.0, 3.0, 3.0)
	seat.position = Vector3(tr_cx, 4.5, throne_z)
	seat.use_collision = true
	seat.collision_layer = ENVIRONMENT_LAYER
	seat.collision_mask = 0
	seat.material = _mat_throne
	seat.name = "ThroneSeat"
	_decorations_root.add_child(seat)

	# The backrest — towering slab
	var back := CSGBox3D.new()
	back.size = Vector3(5.0, 8.0, 1.0)
	back.position = Vector3(tr_cx, 7.0, throne_z - 1.5)
	back.use_collision = true
	back.collision_layer = ENVIRONMENT_LAYER
	back.collision_mask = 0
	back.material = _mat_throne
	back.name = "ThroneBack"
	_decorations_root.add_child(back)

	# Armrests
	for side in [-1, 1]:
		var arm := CSGBox3D.new()
		arm.size = Vector3(0.8, 2.0, 3.0)
		arm.position = Vector3(tr_cx + side * 2.4, 5.0, throne_z)
		arm.use_collision = true
		arm.collision_layer = ENVIRONMENT_LAYER
		arm.collision_mask = 0
		arm.material = _mat_throne
		arm.name = "ThroneArm_%d" % [side]
		_decorations_root.add_child(arm)

	# Crown spikes on backrest
	for i in range(5):
		var spike := CSGBox3D.new()
		var spike_h: float = 2.0 + _rng.randf_range(0.0, 2.5)
		spike.size = Vector3(0.6, spike_h, 0.6)
		var offset_x: float = (i - 2) * 1.1
		spike.position = Vector3(tr_cx + offset_x, 11.0 + spike_h * 0.5, throne_z - 1.5)
		spike.use_collision = true
		spike.collision_layer = ENVIRONMENT_LAYER
		spike.collision_mask = 0
		spike.material = _mat_throne
		spike.name = "ThroneSpike_%d" % i
		_decorations_root.add_child(spike)

# ---------------------------------------------------------------------------
# Decorations — Void orbs floating around throne
# ---------------------------------------------------------------------------

func _build_void_orbs() -> void:
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)
	var throne_z: float = tr_cz - (_throne_room_radius - 4) * CELL_SIZE

	var orb_count: int = 15
	for i in range(orb_count):
		var angle: float = _rng.randf_range(0, TAU)
		var dist: float = _rng.randf_range(3.0, 12.0)
		var height: float = _rng.randf_range(4.0, WALL_HEIGHT - 2.0)

		var orb := CSGSphere3D.new()
		orb.radius = _rng.randf_range(0.2, 0.6)
		orb.radial_segments = 10
		orb.rings = 8
		orb.position = Vector3(
			tr_cx + cos(angle) * dist,
			height,
			throne_z + sin(angle) * dist
		)
		orb.material = _mat_void_orb
		orb.name = "VoidOrb_%d" % i
		_decorations_root.add_child(orb)

	# A few larger orbs directly above the throne seat
	for i in range(4):
		var orb := CSGSphere3D.new()
		orb.radius = _rng.randf_range(0.5, 0.9)
		orb.radial_segments = 12
		orb.rings = 8
		orb.position = Vector3(
			tr_cx + _rng.randf_range(-2.0, 2.0),
			_rng.randf_range(8.0, WALL_HEIGHT - 1.0),
			throne_z + _rng.randf_range(-2.0, 2.0)
		)
		orb.material = _mat_void_orb
		orb.name = "VoidOrbLarge_%d" % i
		_decorations_root.add_child(orb)

# ---------------------------------------------------------------------------
# Decorations — Jagged wall formations around throne room edges
# ---------------------------------------------------------------------------

func _build_jagged_walls() -> void:
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)
	var edge_r: float = (_throne_room_radius - 1) * CELL_SIZE

	var jagged_count: int = 24
	for i in range(jagged_count):
		var angle: float = (TAU / jagged_count) * i + _rng.randf_range(-0.1, 0.1)
		var jx: float = tr_cx + cos(angle) * edge_r
		var jz: float = tr_cz + sin(angle) * edge_r

		var spike_h: float = _rng.randf_range(2.0, WALL_HEIGHT * 0.7)
		var spike_w: float = _rng.randf_range(0.5, 1.8)

		var spike := CSGBox3D.new()
		spike.size = Vector3(spike_w, spike_h, spike_w)
		spike.position = Vector3(jx, spike_h * 0.5, jz)
		# Rotate slightly for jagged look
		spike.rotation_degrees = Vector3(
			_rng.randf_range(-15, 15),
			_rng.randf_range(0, 45),
			_rng.randf_range(-15, 15)
		)
		spike.use_collision = true
		spike.collision_layer = ENVIRONMENT_LAYER
		spike.collision_mask = 0
		spike.material = _mat_jagged
		spike.name = "JaggedWall_%d" % i
		_decorations_root.add_child(spike)

# ---------------------------------------------------------------------------
# Decorations — Themed antechambers
# ---------------------------------------------------------------------------

func _build_antechamber_themes() -> void:
	# Each antechamber gets a different theme
	var themes: Array = ["void_portal", "bone_pillars", "rift_room", "dark_altar", "shadow_pit", "obelisks"]

	for i in range(mini(_antechambers.size(), themes.size())):
		var chamber: Rect2i_BSP = _antechambers[i]
		var theme: String = themes[i]
		var c := chamber.center()
		var world_x: float = _grid_to_world_x(c.x) + CELL_SIZE * 0.5
		var world_z: float = _grid_to_world_z(c.y) + CELL_SIZE * 0.5

		match theme:
			"void_portal":
				_build_void_portal_chamber(chamber, world_x, world_z)
			"bone_pillars":
				_build_bone_pillar_chamber(chamber, world_x, world_z)
			"rift_room":
				_build_rift_chamber(chamber, world_x, world_z)
			"dark_altar":
				_build_dark_altar_chamber(chamber, world_x, world_z)
			"shadow_pit":
				_build_shadow_pit_chamber(chamber, world_x, world_z)
			"obelisks":
				_build_obelisk_chamber(chamber, world_x, world_z)


func _build_void_portal_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# Dark purple circle portal on the back wall
	var portal := CSGCylinder3D.new()
	portal.radius = mini(chamber.w, chamber.h) * CELL_SIZE * 0.2
	portal.height = 0.15
	portal.sides = 24
	portal.rotation_degrees = Vector3(90, 0, 0)
	portal.position = Vector3(wx, WALL_HEIGHT * 0.4, wz - chamber.h * CELL_SIZE * 0.35)
	portal.material = _mat_void_portal
	portal.name = "VoidPortal"
	_decorations_root.add_child(portal)

	# Orbiting small spheres
	for j in range(6):
		var angle: float = (TAU / 6) * j
		var orb := CSGSphere3D.new()
		orb.radius = 0.15
		orb.radial_segments = 8
		orb.rings = 6
		orb.position = Vector3(
			wx + cos(angle) * portal.radius * 1.3,
			WALL_HEIGHT * 0.4 + sin(angle) * portal.radius * 1.3,
			portal.position.z - 0.2
		)
		orb.material = _mat_void_orb
		orb.name = "PortalOrb_%d" % j
		_decorations_root.add_child(orb)


func _build_bone_pillar_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# White bone pillars arranged in the room
	var pillar_count: int = _rng.randi_range(4, 6)
	for j in range(pillar_count):
		var angle: float = (TAU / pillar_count) * j
		var dist: float = mini(chamber.w, chamber.h) * CELL_SIZE * 0.25
		var cyl := CSGCylinder3D.new()
		cyl.radius = 0.35
		cyl.height = WALL_HEIGHT * 0.6
		cyl.sides = 8
		cyl.position = Vector3(
			wx + cos(angle) * dist,
			cyl.height * 0.5,
			wz + sin(angle) * dist
		)
		cyl.use_collision = true
		cyl.collision_layer = ENVIRONMENT_LAYER
		cyl.collision_mask = 0
		cyl.material = _mat_bone
		cyl.name = "BonePillar_%d" % j
		_decorations_root.add_child(cyl)

		# Skull on top
		var skull := CSGSphere3D.new()
		skull.radius = 0.28
		skull.radial_segments = 8
		skull.rings = 6
		skull.position = Vector3(cyl.position.x, cyl.height + 0.28, cyl.position.z)
		skull.material = _mat_bone
		skull.name = "BoneSkull_%d" % j
		_decorations_root.add_child(skull)


func _build_rift_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# Multiple dimensional rift slashes
	for j in range(3):
		var rift := CSGBox3D.new()
		var rift_h: float = _rng.randf_range(2.0, 5.0)
		rift.size = Vector3(_rng.randf_range(0.08, 0.15), rift_h, _rng.randf_range(1.5, 3.0))
		rift.position = Vector3(
			wx + _rng.randf_range(-chamber.w * CELL_SIZE * 0.25, chamber.w * CELL_SIZE * 0.25),
			_rng.randf_range(1.5, WALL_HEIGHT * 0.5),
			wz + _rng.randf_range(-chamber.h * CELL_SIZE * 0.25, chamber.h * CELL_SIZE * 0.25)
		)
		rift.rotation_degrees = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(0, 180), _rng.randf_range(-10, 10))
		rift.material = _mat_rift
		rift.name = "ChamberRift_%d" % j
		_decorations_root.add_child(rift)


func _build_dark_altar_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# A dark altar with accent glow
	var altar := CSGBox3D.new()
	altar.size = Vector3(3.0, 1.5, 2.0)
	altar.position = Vector3(wx, 0.75, wz)
	altar.use_collision = true
	altar.collision_layer = ENVIRONMENT_LAYER
	altar.collision_mask = 0
	altar.material = _mat_throne
	altar.name = "DarkAltar"
	_decorations_root.add_child(altar)

	# Glowing rune on top
	var rune := CSGCylinder3D.new()
	rune.radius = 0.8
	rune.height = 0.04
	rune.sides = 16
	rune.position = Vector3(wx, 1.52, wz)
	rune.material = _mat_accent
	rune.name = "DarkAltarRune"
	_decorations_root.add_child(rune)


func _build_shadow_pit_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# A dark pit in the center (represented by a dark disc on the floor)
	var pit := CSGCylinder3D.new()
	pit.radius = mini(chamber.w, chamber.h) * CELL_SIZE * 0.2
	pit.height = 0.05
	pit.sides = 20
	pit.position = Vector3(wx, 0.025, wz)
	pit.material = _mat_tile_dark
	pit.name = "ShadowPit"
	_decorations_root.add_child(pit)

	# Rising void particles
	for j in range(8):
		var orb := CSGSphere3D.new()
		orb.radius = _rng.randf_range(0.08, 0.2)
		orb.radial_segments = 6
		orb.rings = 4
		orb.position = Vector3(
			wx + _rng.randf_range(-pit.radius * 0.7, pit.radius * 0.7),
			_rng.randf_range(0.5, WALL_HEIGHT * 0.6),
			wz + _rng.randf_range(-pit.radius * 0.7, pit.radius * 0.7)
		)
		orb.material = _mat_void_orb
		orb.name = "ShadowPitOrb_%d" % j
		_decorations_root.add_child(orb)


func _build_obelisk_chamber(chamber: Rect2i_BSP, wx: float, wz: float) -> void:
	# Tall dark obelisks
	for j in range(4):
		var angle: float = (TAU / 4) * j + PI / 4
		var dist: float = mini(chamber.w, chamber.h) * CELL_SIZE * 0.22
		var obelisk := CSGBox3D.new()
		var ob_h: float = _rng.randf_range(4.0, WALL_HEIGHT * 0.7)
		obelisk.size = Vector3(0.8, ob_h, 0.8)
		obelisk.position = Vector3(
			wx + cos(angle) * dist,
			ob_h * 0.5,
			wz + sin(angle) * dist
		)
		obelisk.use_collision = true
		obelisk.collision_layer = ENVIRONMENT_LAYER
		obelisk.collision_mask = 0
		obelisk.material = _mat_wall
		obelisk.name = "Obelisk_%d" % j
		_decorations_root.add_child(obelisk)

		# Glowing tip
		var tip := CSGSphere3D.new()
		tip.radius = 0.25
		tip.radial_segments = 8
		tip.rings = 6
		tip.position = Vector3(obelisk.position.x, ob_h + 0.25, obelisk.position.z)
		tip.material = _mat_accent
		tip.name = "ObeliskTip_%d" % j
		_decorations_root.add_child(tip)

# ---------------------------------------------------------------------------
# Decorations — Dimensional rifts scattered throughout
# ---------------------------------------------------------------------------

func _build_dimensional_rifts() -> void:
	# Place rifts in corridors and randomly in the approach
	var rift_count: int = 12
	var idx: int = 0

	# Rifts along the approach
	if _approach_rect:
		for i in range(5):
			var rx: float = _grid_to_world_x(_approach_rect.x) + _rng.randf_range(CELL_SIZE, _approach_rect.w * CELL_SIZE - CELL_SIZE)
			var ry: float = _rng.randf_range(2.0, WALL_HEIGHT * 0.6)
			var rz: float = _grid_to_world_z(_approach_rect.y) + _rng.randf_range(CELL_SIZE * 2, _approach_rect.h * CELL_SIZE - CELL_SIZE * 2)

			var rift := CSGBox3D.new()
			rift.size = Vector3(_rng.randf_range(0.06, 0.12), _rng.randf_range(1.5, 4.0), _rng.randf_range(0.8, 2.5))
			rift.position = Vector3(rx, ry, rz)
			rift.rotation_degrees = Vector3(_rng.randf_range(-25, 25), _rng.randf_range(0, 90), _rng.randf_range(-15, 15))
			rift.material = _mat_rift
			rift.name = "DimRift_%d" % idx
			_decorations_root.add_child(rift)
			idx += 1

	# Rifts scattered in the throne room
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)
	for i in range(7):
		var angle: float = _rng.randf_range(0, TAU)
		var dist: float = _rng.randf_range(CELL_SIZE * 3, (_throne_room_radius - 3) * CELL_SIZE)
		var rift := CSGBox3D.new()
		rift.size = Vector3(_rng.randf_range(0.06, 0.1), _rng.randf_range(2.0, 5.0), _rng.randf_range(1.0, 3.0))
		rift.position = Vector3(
			tr_cx + cos(angle) * dist,
			_rng.randf_range(1.5, WALL_HEIGHT * 0.5),
			tr_cz + sin(angle) * dist
		)
		rift.rotation_degrees = Vector3(_rng.randf_range(-30, 30), _rng.randf_range(0, 180), _rng.randf_range(-20, 20))
		rift.material = _mat_rift
		rift.name = "DimRift_%d" % idx
		_decorations_root.add_child(rift)
		idx += 1

# ---------------------------------------------------------------------------
# Lighting and environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	# WorldEnvironment
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.0, 0.005)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.0, 0.05)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.0, 0.02)
	env.fog_density = 0.018
	env.fog_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	_lighting_root.add_child(world_env)

	# DirectionalLight — very dim and unsettling
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "VoidLight"
	dir_light.light_color = Color(0.6, 0.05, 0.3)
	dir_light.light_energy = 0.35
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-55, -15, 0)
	_lighting_root.add_child(dir_light)

	# Brazier lights along approach
	if _approach_rect:
		var ax: int = _approach_rect.x
		var ay: int = _approach_rect.y
		var aw: int = _approach_rect.w
		var ah: int = _approach_rect.h
		for row_y in range(ay + 2, ay + ah - 2, BRAZIER_SPACING):
			for col_x in [ax, ax + aw - 1]:
				var light := OmniLight3D.new()
				light.light_color = Color(
					_rng.randf_range(0.4, 0.6),
					_rng.randf_range(0.02, 0.06),
					_rng.randf_range(0.2, 0.4)
				)
				light.light_energy = _rng.randf_range(1.5, 2.5)
				light.omni_range = CELL_SIZE * 5.0
				light.omni_attenuation = 1.5
				light.shadow_enabled = false
				light.position = Vector3(
					_grid_to_world_x(col_x) + CELL_SIZE * 0.5,
					2.0,
					_grid_to_world_z(row_y) + CELL_SIZE * 0.5
				)
				light.name = "ApproachLight_%d_%d" % [col_x, row_y]
				_lighting_root.add_child(light)

	# Throne room perimeter lights
	var tr_cx: float = _grid_to_world_x(_throne_room_center.x)
	var tr_cz: float = _grid_to_world_z(_throne_room_center.y)
	var perimeter_r: float = (_throne_room_radius - 2) * CELL_SIZE
	for i in range(12):
		var angle: float = (TAU / 12) * i
		var light := OmniLight3D.new()
		light.light_color = Color(
			_rng.randf_range(0.4, 0.6),
			_rng.randf_range(0.01, 0.05),
			_rng.randf_range(0.2, 0.35)
		)
		light.light_energy = _rng.randf_range(1.5, 2.5)
		light.omni_range = CELL_SIZE * 6.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(
			tr_cx + cos(angle) * perimeter_r,
			2.0,
			tr_cz + sin(angle) * perimeter_r
		)
		light.name = "ThronePerimLight_%d" % i
		_lighting_root.add_child(light)

	# Faint throne glow
	var throne_z: float = tr_cz - (_throne_room_radius - 4) * CELL_SIZE
	var throne_light := OmniLight3D.new()
	throne_light.light_color = Color(0.5, 0.02, 0.3)
	throne_light.light_energy = 2.0
	throne_light.omni_range = CELL_SIZE * 10.0
	throne_light.omni_attenuation = 1.2
	throne_light.shadow_enabled = true
	throne_light.position = Vector3(tr_cx, WALL_HEIGHT * 0.5, throne_z)
	throne_light.name = "ThroneGlow"
	_lighting_root.add_child(throne_light)

	# Rift lights in antechambers
	for chamber: Rect2i_BSP in _antechambers:
		var c := chamber.center()
		var light := OmniLight3D.new()
		light.light_color = Color(
			_rng.randf_range(0.3, 0.5),
			_rng.randf_range(0.0, 0.03),
			_rng.randf_range(0.15, 0.3)
		)
		light.light_energy = _rng.randf_range(0.8, 1.5)
		light.omni_range = mini(chamber.w, chamber.h) * CELL_SIZE * 0.6
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(c.x) + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			_grid_to_world_z(c.y) + CELL_SIZE * 0.5
		)
		light.name = "AntechamberLight_%d_%d" % [c.x, c.y]
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns in the entrance room
	if _entrance_room:
		var ec := _entrance_room.center()
		_player_spawn = Vector3(_grid_to_world_x(ec.x), 0.5, _grid_to_world_z(ec.y))
	elif _rooms.size() > 0:
		var c := _rooms[0].center()
		_player_spawn = Vector3(_grid_to_world_x(c.x), 0.5, _grid_to_world_z(c.y))

	# Enemy spawns in the throne room (boss arena)
	var tr_cx: int = _throne_room_center.x
	var tr_cy: int = _throne_room_center.y
	var boss_spawn_count: int = 15
	for i in range(boss_spawn_count):
		var angle: float = _rng.randf_range(0, TAU)
		var dist: float = _rng.randf_range(3.0, float(_throne_room_radius - 3))
		var sx: int = tr_cx + int(cos(angle) * dist)
		var sy: int = tr_cy + int(sin(angle) * dist)
		if _get_cell(sx, sy) == Cell.FLOOR:
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(sx) + CELL_SIZE * 0.5,
				0.5,
				_grid_to_world_z(sy) + CELL_SIZE * 0.5
			))

	# Enemy spawns in antechambers
	for chamber: Rect2i_BSP in _antechambers:
		var spawn_area: int = chamber.w * chamber.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, spawn_area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(chamber.x + 1, chamber.x + chamber.w - 2)
			var sy: int = _rng.randi_range(chamber.y + 1, chamber.y + chamber.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# A few spawns along the approach for ambush encounters
	if _approach_rect:
		for i in range(6):
			var sx: int = _rng.randi_range(_approach_rect.x + 1, _approach_rect.x + _approach_rect.w - 2)
			var sy: int = _rng.randi_range(_approach_rect.y + 2, _approach_rect.y + _approach_rect.h - 3)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))
