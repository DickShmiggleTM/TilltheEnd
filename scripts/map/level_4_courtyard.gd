extends Node3D
## Level 4: The Outer Sanctum
## An occult temple courtyard and surrounding estate. Features a large central
## open courtyard with pillars, surrounding estate buildings with rooms,
## altars, pentagram decorations, gate entrance, and worship areas. Uses BSP
## for estate rooms. Courtyard is outdoor (no ceiling), estate has ceilings.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 90
const GRID_HEIGHT: int = 90
const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 6.0

const MIN_PARTITION_SIZE: int = 8
const MAX_PARTITION_SIZE: int = 25
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 5
const ARENA_THRESHOLD: int = 10
const CORRIDOR_WIDTH: int = 2

const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 25
const MIN_ARENA_SPAWNS: int = 4

const COURTYARD_SIZE: int = 32  # cells per side (centered in grid)
const PILLAR_SPACING: int = 4   # every N cells in courtyard
const ALTAR_COUNT: int = 4
const PENTAGRAM_COUNT: int = 3
const PEW_ROWS: int = 6

# ---------------------------------------------------------------------------
# Cell types
# ---------------------------------------------------------------------------

enum Cell {
	VOID = 0,
	FLOOR = 1,
	WALL = 2,
	COURTYARD = 3,
	WALKWAY = 4,
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
var _estate_rooms: Array = []  # Rooms in the estate buildings
var _courtyard_rect: Rect2i_BSP = null
var _altar_positions: Array = []  # Array of Vector2i
var _pentagram_positions: Array = []  # Array of Vector2i
var _gate_position: Vector2i = Vector2i.ZERO
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

var _mat_floor: StandardMaterial3D = null
var _mat_wall: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_courtyard_floor: StandardMaterial3D = null
var _mat_pillar: StandardMaterial3D = null
var _mat_altar: StandardMaterial3D = null
var _mat_altar_top: StandardMaterial3D = null
var _mat_accent: StandardMaterial3D = null
var _mat_walkway: StandardMaterial3D = null
var _mat_pew: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value

	_create_materials()
	_init_grid()

	# Place central courtyard
	_place_courtyard()

	# Generate estate buildings around the courtyard
	_generate_estate()

	# Connect estate to courtyard via covered walkways
	_connect_estate_to_courtyard()

	# Build walls
	_build_walls()

	# Place decorations
	_place_altars()
	_place_pentagrams()
	_place_gate()

	# Classify rooms
	_classify_rooms()

	# Build 3D geometry
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_build_geometry()
	_build_pillars()
	_build_altars()
	_build_pentagrams()
	_build_gate()
	_build_worship_areas()
	_build_environment()

	_determine_spawn_points()


func get_player_spawn() -> Vector3:
	return _player_spawn


func get_enemy_spawn_points() -> Array[Vector3]:
	return _enemy_spawns


func clear_map() -> void:
	if _geometry_root and is_instance_valid(_geometry_root):
		_geometry_root.queue_free()
		_geometry_root = null
	if _lighting_root and is_instance_valid(_lighting_root):
		_lighting_root.queue_free()
		_lighting_root = null

	_grid.clear()
	_rooms.clear()
	_arena_rooms.clear()
	_estate_rooms.clear()
	_altar_positions.clear()
	_pentagram_positions.clear()
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO
	_courtyard_rect = null


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	# Include the courtyard as a room entry
	if _courtyard_rect:
		var cc := _courtyard_rect.center()
		data.append({
			"position": Vector3(
				_grid_to_world_x(cc.x), 0.0, _grid_to_world_z(cc.y)
			),
			"size": Vector2(_courtyard_rect.w * CELL_SIZE, _courtyard_rect.h * CELL_SIZE),
			"is_arena": true,
			"grid_rect": Rect2(_courtyard_rect.x, _courtyard_rect.y, _courtyard_rect.w, _courtyard_rect.h),
		})

	for room: Rect2i_BSP in _rooms:
		var center := room.center()
		data.append({
			"position": Vector3(
				_grid_to_world_x(center.x), 0.0, _grid_to_world_z(center.y)
			),
			"size": Vector2(room.w * CELL_SIZE, room.h * CELL_SIZE),
			"is_arena": room in _arena_rooms,
			"grid_rect": Rect2(room.x, room.y, room.w, room.h),
		})
	return data


func is_walkable(world_pos: Vector3) -> bool:
	@warning_ignore("narrowing_conversion")
	var gx: int = int(world_pos.x / CELL_SIZE)
	@warning_ignore("narrowing_conversion")
	var gy: int = int(world_pos.z / CELL_SIZE)
	var cell := _get_cell(gx, gy)
	return cell == Cell.FLOOR or cell == Cell.COURTYARD or cell == Cell.WALKWAY

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Blood stone floor
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.15, 0.05, 0.05)
	_mat_floor.roughness = 0.85
	_mat_floor.metallic = 0.05

	# Dark red marble walls
	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.2, 0.08, 0.06)
	_mat_wall.roughness = 0.7
	_mat_wall.metallic = 0.1

	# Ceiling
	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.06, 0.02, 0.02)
	_mat_ceiling.roughness = 0.9
	_mat_ceiling.metallic = 0.0

	# Courtyard floor (slightly different tone)
	_mat_courtyard_floor = StandardMaterial3D.new()
	_mat_courtyard_floor.albedo_color = Color(0.18, 0.07, 0.06)
	_mat_courtyard_floor.roughness = 0.8
	_mat_courtyard_floor.metallic = 0.05

	# Marble pillars (white-gray)
	_mat_pillar = StandardMaterial3D.new()
	_mat_pillar.albedo_color = Color(0.7, 0.65, 0.6)
	_mat_pillar.roughness = 0.4
	_mat_pillar.metallic = 0.15

	# Altar base
	_mat_altar = StandardMaterial3D.new()
	_mat_altar.albedo_color = Color(0.25, 0.1, 0.08)
	_mat_altar.roughness = 0.6
	_mat_altar.metallic = 0.1

	# Altar top (blood stained)
	_mat_altar_top = StandardMaterial3D.new()
	_mat_altar_top.albedo_color = Color(0.5, 0.05, 0.02)
	_mat_altar_top.roughness = 0.5
	_mat_altar_top.metallic = 0.05
	_mat_altar_top.emission_enabled = true
	_mat_altar_top.emission = Color(0.3, 0.02, 0.01)
	_mat_altar_top.emission_energy_multiplier = 0.5

	# Accent (red-orange)
	_mat_accent = StandardMaterial3D.new()
	_mat_accent.albedo_color = Color(0.8, 0.15, 0.1)
	_mat_accent.roughness = 0.5
	_mat_accent.metallic = 0.1
	_mat_accent.emission_enabled = true
	_mat_accent.emission = Color(0.6, 0.1, 0.05)
	_mat_accent.emission_energy_multiplier = 1.0

	# Walkway
	_mat_walkway = StandardMaterial3D.new()
	_mat_walkway.albedo_color = Color(0.12, 0.05, 0.04)
	_mat_walkway.roughness = 0.85
	_mat_walkway.metallic = 0.05

	# Pew (dark wood)
	_mat_pew = StandardMaterial3D.new()
	_mat_pew.albedo_color = Color(0.18, 0.08, 0.04)
	_mat_pew.roughness = 0.8
	_mat_pew.metallic = 0.0

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

# ---------------------------------------------------------------------------
# Courtyard placement
# ---------------------------------------------------------------------------

func _place_courtyard() -> void:
	@warning_ignore("integer_division")
	var cx := (GRID_WIDTH - COURTYARD_SIZE) / 2
	@warning_ignore("integer_division")
	var cy := (GRID_HEIGHT - COURTYARD_SIZE) / 2
	_courtyard_rect = Rect2i_BSP.new(cx, cy, COURTYARD_SIZE, COURTYARD_SIZE)

	for x in range(cx, cx + COURTYARD_SIZE):
		for y in range(cy, cy + COURTYARD_SIZE):
			_set_cell(x, y, Cell.COURTYARD)

# ---------------------------------------------------------------------------
# Estate generation (BSP around the courtyard)
# ---------------------------------------------------------------------------

func _generate_estate() -> void:
	# Create building zones around the courtyard on all four sides
	var cy_x := _courtyard_rect.x
	var cy_y := _courtyard_rect.y
	var cy_w := _courtyard_rect.w
	var cy_h := _courtyard_rect.h
	var margin := 3  # gap between courtyard and buildings

	# North wing
	var north := Rect2i_BSP.new(cy_x - 5, 2, cy_w + 10, cy_y - margin - 2)
	if north.h > MIN_PARTITION_SIZE:
		_generate_estate_wing(north)

	# South wing
	var south_y := cy_y + cy_h + margin
	var south_h := GRID_HEIGHT - south_y - 2
	var south := Rect2i_BSP.new(cy_x - 5, south_y, cy_w + 10, south_h)
	if south.h > MIN_PARTITION_SIZE:
		_generate_estate_wing(south)

	# East wing
	var east_x := cy_x + cy_w + margin
	var east_w := GRID_WIDTH - east_x - 2
	var east := Rect2i_BSP.new(east_x, cy_y - 3, east_w, cy_h + 6)
	if east.w > MIN_PARTITION_SIZE:
		_generate_estate_wing(east)

	# West wing
	var west_w := cy_x - margin - 2
	var west := Rect2i_BSP.new(2, cy_y - 3, west_w, cy_h + 6)
	if west.w > MIN_PARTITION_SIZE:
		_generate_estate_wing(west)


func _generate_estate_wing(bounds: Rect2i_BSP) -> void:
	# Clamp to grid
	bounds.x = clampi(bounds.x, 1, GRID_WIDTH - 2)
	bounds.y = clampi(bounds.y, 1, GRID_HEIGHT - 2)
	bounds.w = mini(bounds.w, GRID_WIDTH - bounds.x - 1)
	bounds.h = mini(bounds.h, GRID_HEIGHT - bounds.y - 1)

	if bounds.w < MIN_PARTITION_SIZE or bounds.h < MIN_PARTITION_SIZE:
		return

	var root := BSPNode.new(bounds)
	_split_bsp(root, 0)
	_create_rooms(root)
	_connect_rooms(root)


func _split_bsp(node: BSPNode, depth: int) -> void:
	if node.rect.w <= MAX_PARTITION_SIZE and node.rect.h <= MAX_PARTITION_SIZE:
		if node.rect.w < MIN_PARTITION_SIZE * 2 and node.rect.h < MIN_PARTITION_SIZE * 2:
			return
		if depth > 3 and _rng.randf() < 0.25:
			return

	var can_split_h: bool = node.rect.h >= MIN_PARTITION_SIZE * 2
	var can_split_v: bool = node.rect.w >= MIN_PARTITION_SIZE * 2

	if not can_split_h and not can_split_v:
		return

	var split_horizontal: bool
	if not can_split_v:
		split_horizontal = true
	elif not can_split_h:
		split_horizontal = false
	else:
		if node.rect.w > node.rect.h * 1.25:
			split_horizontal = false
		elif node.rect.h > node.rect.w * 1.25:
			split_horizontal = true
		else:
			split_horizontal = _rng.randf() < 0.5

	if split_horizontal:
		var min_y := node.rect.y + MIN_PARTITION_SIZE
		var max_y := node.rect.y + node.rect.h - MIN_PARTITION_SIZE
		if min_y >= max_y:
			return
		var split_y := _rng.randi_range(min_y, max_y)
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y, node.rect.w, split_y - node.rect.y
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, split_y, node.rect.w, node.rect.y + node.rect.h - split_y
		))
	else:
		var min_x := node.rect.x + MIN_PARTITION_SIZE
		var max_x := node.rect.x + node.rect.w - MIN_PARTITION_SIZE
		if min_x >= max_x:
			return
		var split_x := _rng.randi_range(min_x, max_x)
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y, split_x - node.rect.x, node.rect.h
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			split_x, node.rect.y, node.rect.x + node.rect.w - split_x, node.rect.h
		))

	_split_bsp(node.left, depth + 1)
	_split_bsp(node.right, depth + 1)


func _create_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		var rw := _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		)
		var rh := _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)
		)
		rw = clampi(rw, MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		rh = clampi(rh, MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)

		var rx := _rng.randi_range(
			node.rect.x + 1,
			maxi(node.rect.x + 1, node.rect.x + node.rect.w - rw - 1)
		)
		var ry := _rng.randi_range(
			node.rect.y + 1,
			maxi(node.rect.y + 1, node.rect.y + node.rect.h - rh - 1)
		)
		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)
		rw = mini(rw, GRID_WIDTH - rx - 1)
		rh = mini(rh, GRID_HEIGHT - ry - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)
		_estate_rooms.append(node.room)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left:
		_create_rooms(node.left)
	if node.right:
		_create_rooms(node.right)


func _get_room(node: BSPNode) -> Rect2i_BSP:
	if node.room:
		return node.room
	if node.left:
		var r := _get_room(node.left)
		if r:
			return r
	if node.right:
		var r := _get_room(node.right)
		if r:
			return r
	return null


func _connect_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		return
	if node.left:
		_connect_rooms(node.left)
	if node.right:
		_connect_rooms(node.right)
	if node.left and node.right:
		var room_a := _get_room(node.left)
		var room_b := _get_room(node.right)
		if room_a and room_b:
			_carve_corridor(room_a.center(), room_b.center())

# ---------------------------------------------------------------------------
# Corridor carving
# ---------------------------------------------------------------------------

func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var go_horizontal_first := _rng.randf() < 0.5
	if go_horizontal_first:
		_carve_horizontal(from.x, to.x, from.y)
		_carve_vertical(from.y, to.y, to.x)
	else:
		_carve_vertical(from.y, to.y, from.x)
		_carve_horizontal(from.x, to.x, to.y)


func _carve_horizontal(x1: int, x2: int, y: int) -> void:
	var start_x := mini(x1, x2)
	var end_x := maxi(x1, x2)
	for x in range(start_x, end_x + 1):
		for dy in range(CORRIDOR_WIDTH):
			var cy := y + dy
			var cell := _get_cell(x, cy)
			if cell == Cell.VOID:
				_set_cell(x, cy, Cell.FLOOR)


func _carve_vertical(y1: int, y2: int, x: int) -> void:
	var start_y := mini(y1, y2)
	var end_y := maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx := x + dx
			var cell := _get_cell(cx, y)
			if cell == Cell.VOID:
				_set_cell(cx, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Connect estate to courtyard
# ---------------------------------------------------------------------------

func _connect_estate_to_courtyard() -> void:
	var cy_center := _courtyard_rect.center()

	for room: Rect2i_BSP in _estate_rooms:
		var rc := room.center()
		# Carve walkway from room center toward courtyard
		_carve_walkway(rc, cy_center)


func _carve_walkway(from: Vector2i, to: Vector2i) -> void:
	var go_horizontal_first := _rng.randf() < 0.5
	if go_horizontal_first:
		_carve_walkway_h(from.x, to.x, from.y)
		_carve_walkway_v(from.y, to.y, to.x)
	else:
		_carve_walkway_v(from.y, to.y, from.x)
		_carve_walkway_h(from.x, to.x, to.y)


func _carve_walkway_h(x1: int, x2: int, y: int) -> void:
	var start_x := mini(x1, x2)
	var end_x := maxi(x1, x2)
	for x in range(start_x, end_x + 1):
		for dy in range(CORRIDOR_WIDTH + 1):
			var cy := y + dy
			var cell := _get_cell(x, cy)
			if cell == Cell.VOID:
				_set_cell(x, cy, Cell.WALKWAY)


func _carve_walkway_v(y1: int, y2: int, x: int) -> void:
	var start_y := mini(y1, y2)
	var end_y := maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH + 1):
			var cx := x + dx
			var cell := _get_cell(cx, y)
			if cell == Cell.VOID:
				_set_cell(cx, y, Cell.WALKWAY)

# ---------------------------------------------------------------------------
# Wall construction
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
			var c := _get_cell(x + dx, y + dy)
			if c == Cell.FLOOR or c == Cell.COURTYARD or c == Cell.WALKWAY:
				return true
	return false

# ---------------------------------------------------------------------------
# Decoration placement
# ---------------------------------------------------------------------------

func _place_altars() -> void:
	_altar_positions.clear()
	if _courtyard_rect == null:
		return

	var cc := _courtyard_rect.center()
	# Place altars symmetrically in the courtyard
	var offsets := [
		Vector2i(-8, -8), Vector2i(8, -8),
		Vector2i(-8, 8), Vector2i(8, 8),
	]
	for i in range(mini(ALTAR_COUNT, offsets.size())):
		_altar_positions.append(Vector2i(cc.x + offsets[i].x, cc.y + offsets[i].y))


func _place_pentagrams() -> void:
	_pentagram_positions.clear()
	if _courtyard_rect == null:
		return

	var cc := _courtyard_rect.center()
	# Center pentagram
	_pentagram_positions.append(cc)
	# Two more at offsets
	_pentagram_positions.append(Vector2i(cc.x - 12, cc.y))
	_pentagram_positions.append(Vector2i(cc.x + 12, cc.y))


func _place_gate() -> void:
	if _courtyard_rect == null:
		return
	# Gate at the south edge of the courtyard
	_gate_position = Vector2i(
		_courtyard_rect.x + _courtyard_rect.w / 2,
		_courtyard_rect.y + _courtyard_rect.h
	)

# ---------------------------------------------------------------------------
# Room classification
# ---------------------------------------------------------------------------

func _classify_rooms() -> void:
	_arena_rooms.clear()

	# The courtyard itself is the main arena (tracked separately)

	for room: Rect2i_BSP in _rooms:
		if room.w >= ARENA_THRESHOLD and room.h >= ARENA_THRESHOLD:
			_arena_rooms.append(room)

	if _arena_rooms.is_empty() and _rooms.size() > 0:
		var sorted_rooms := _rooms.duplicate()
		sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
			return (a.w * a.h) > (b.w * b.h)
		)
		@warning_ignore("integer_division")
		var count := maxi(1, sorted_rooms.size() / 3)
		for i in range(count):
			_arena_rooms.append(sorted_rooms[i])

# ---------------------------------------------------------------------------
# Geometry building
# ---------------------------------------------------------------------------

func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE


func _build_geometry() -> void:
	# Estate floors
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		_create_floor_box(strip, _mat_floor, "Floor")

	# Courtyard floor
	var courtyard_strips := _build_horizontal_strips(Cell.COURTYARD)
	for strip: Rect2i_BSP in courtyard_strips:
		_create_floor_box(strip, _mat_courtyard_floor, "Courtyard")

	# Walkway floors
	var walkway_strips := _build_horizontal_strips(Cell.WALKWAY)
	for strip: Rect2i_BSP in walkway_strips:
		_create_floor_box(strip, _mat_walkway, "Walkway")

	# Walls
	var wall_strips := _build_horizontal_strips(Cell.WALL)
	for strip: Rect2i_BSP in wall_strips:
		_create_wall_box(strip)

	# Ceilings only in estate buildings (NOT courtyard)
	for strip: Rect2i_BSP in floor_strips:
		_create_ceiling_box(strip)

	# Covered walkway ceilings
	for strip: Rect2i_BSP in walkway_strips:
		_create_ceiling_box(strip)

	# NO ceiling for courtyard_strips (outdoor)


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


func _create_floor_box(strip: Rect2i_BSP, mat: StandardMaterial3D, prefix: String) -> void:
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
	box.material = mat
	box.name = "%s_%d_%d" % [prefix, strip.x, strip.y]
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

# ---------------------------------------------------------------------------
# Pillar construction
# ---------------------------------------------------------------------------

func _build_pillars() -> void:
	if _courtyard_rect == null:
		return

	var cx := _courtyard_rect.x
	var cy := _courtyard_rect.y
	var cw := _courtyard_rect.w
	var ch := _courtyard_rect.h

	# Grid of pillars throughout the courtyard
	for gx in range(cx + 2, cx + cw - 2, PILLAR_SPACING):
		for gy in range(cy + 2, cy + ch - 2, PILLAR_SPACING):
			# Skip center area to leave space for pentagrams/altars
			var center := _courtyard_rect.center()
			if abs(gx - center.x) < 4 and abs(gy - center.y) < 4:
				continue

			var world_x := _grid_to_world_x(gx) + CELL_SIZE * 0.5
			var world_z := _grid_to_world_z(gy) + CELL_SIZE * 0.5
			var pillar_h := WALL_HEIGHT * _rng.randf_range(0.9, 1.1)

			var pillar := CSGCylinder3D.new()
			pillar.radius = 0.5
			pillar.height = pillar_h
			pillar.sides = 12
			pillar.position = Vector3(world_x, pillar_h * 0.5, world_z)
			pillar.material = _mat_pillar
			pillar.use_collision = true
			pillar.collision_layer = ENVIRONMENT_LAYER
			pillar.collision_mask = 0
			pillar.name = "Pillar_%d_%d" % [gx, gy]
			_geometry_root.add_child(pillar)

			# Capital (top decoration) — wider cylinder at top
			var capital := CSGCylinder3D.new()
			capital.radius = 0.7
			capital.height = 0.3
			capital.sides = 12
			capital.position = Vector3(world_x, pillar_h, world_z)
			capital.material = _mat_pillar
			capital.use_collision = false
			capital.name = "Capital_%d_%d" % [gx, gy]
			_geometry_root.add_child(capital)

# ---------------------------------------------------------------------------
# Altar construction
# ---------------------------------------------------------------------------

func _build_altars() -> void:
	for i in range(_altar_positions.size()):
		var pos: Vector2i = _altar_positions[i]
		var world_x := _grid_to_world_x(pos.x) + CELL_SIZE * 0.5
		var world_z := _grid_to_world_z(pos.y) + CELL_SIZE * 0.5

		# Raised platform base
		var base := CSGBox3D.new()
		base.size = Vector3(CELL_SIZE * 2.0, 0.8, CELL_SIZE * 2.0)
		base.position = Vector3(world_x, 0.4, world_z)
		base.use_collision = true
		base.collision_layer = ENVIRONMENT_LAYER
		base.collision_mask = 0
		base.material = _mat_altar
		base.name = "AltarBase_%d" % i
		_geometry_root.add_child(base)

		# Top slab (blood stained)
		var top := CSGBox3D.new()
		top.size = Vector3(CELL_SIZE * 1.8, 0.15, CELL_SIZE * 1.2)
		top.position = Vector3(world_x, 0.85, world_z)
		top.use_collision = true
		top.collision_layer = ENVIRONMENT_LAYER
		top.collision_mask = 0
		top.material = _mat_altar_top
		top.name = "AltarTop_%d" % i
		_geometry_root.add_child(top)

		# Light above altar
		var light := OmniLight3D.new()
		light.name = "AltarLight_%d" % i
		light.light_color = Color(0.9, 0.15, 0.05)
		light.light_energy = 2.0
		light.omni_range = 12.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(world_x, 3.0, world_z)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Pentagram decorations
# ---------------------------------------------------------------------------

func _build_pentagrams() -> void:
	for i in range(_pentagram_positions.size()):
		var pos: Vector2i = _pentagram_positions[i]
		var world_x := _grid_to_world_x(pos.x) + CELL_SIZE * 0.5
		var world_z := _grid_to_world_z(pos.y) + CELL_SIZE * 0.5
		var radius: float = 4.0

		# Inverted pentagram: 5 points arranged in a star pattern using small red boxes
		for p in range(5):
			# Star points
			var angle := (TAU / 5.0) * p - PI / 2.0  # Start from top, inverted
			var px := world_x + cos(angle) * radius
			var pz := world_z + sin(angle) * radius

			# Line from this point to the next-but-one (pentagram lines)
			var next_p := (p + 2) % 5
			var next_angle := (TAU / 5.0) * next_p - PI / 2.0
			var npx := world_x + cos(next_angle) * radius
			var npz := world_z + sin(next_angle) * radius

			# Create thin box along the line
			var line_len := Vector2(npx - px, npz - pz).length()
			var line_angle := atan2(npz - pz, npx - px)

			var line := CSGBox3D.new()
			line.size = Vector3(line_len, 0.06, 0.15)
			line.position = Vector3(
				(px + npx) * 0.5,
				0.03,
				(pz + npz) * 0.5
			)
			line.rotation.y = -line_angle
			line.material = _mat_accent
			line.use_collision = false
			line.name = "Pentagram_%d_Line_%d" % [i, p]
			_geometry_root.add_child(line)

		# Ritual circle around the pentagram
		var circle := CSGCylinder3D.new()
		circle.radius = radius * 1.2
		circle.height = 0.04
		circle.sides = 32
		circle.position = Vector3(world_x, 0.02, world_z)
		circle.material = _mat_accent
		circle.use_collision = false
		circle.name = "RitualCircle_%d" % i
		_geometry_root.add_child(circle)

		# Red light at pentagram center
		var light := OmniLight3D.new()
		light.name = "PentagramLight_%d" % i
		light.light_color = Color(0.8, 0.1, 0.05)
		light.light_energy = 1.5
		light.omni_range = radius * 3.0
		light.omni_attenuation = 1.8
		light.shadow_enabled = false
		light.position = Vector3(world_x, 1.5, world_z)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Gate structure
# ---------------------------------------------------------------------------

func _build_gate() -> void:
	var gx := _grid_to_world_x(_gate_position.x) + CELL_SIZE * 0.5
	var gz := _grid_to_world_z(_gate_position.y)

	var pillar_h: float = WALL_HEIGHT * 1.5
	var pillar_r: float = 0.8
	var gate_width: float = CELL_SIZE * 4.0

	# Left pillar
	var left_pillar := CSGCylinder3D.new()
	left_pillar.radius = pillar_r
	left_pillar.height = pillar_h
	left_pillar.sides = 12
	left_pillar.position = Vector3(gx - gate_width * 0.5, pillar_h * 0.5, gz)
	left_pillar.material = _mat_pillar
	left_pillar.use_collision = true
	left_pillar.collision_layer = ENVIRONMENT_LAYER
	left_pillar.collision_mask = 0
	left_pillar.name = "GatePillarL"
	_geometry_root.add_child(left_pillar)

	# Right pillar
	var right_pillar := CSGCylinder3D.new()
	right_pillar.radius = pillar_r
	right_pillar.height = pillar_h
	right_pillar.sides = 12
	right_pillar.position = Vector3(gx + gate_width * 0.5, pillar_h * 0.5, gz)
	right_pillar.material = _mat_pillar
	right_pillar.use_collision = true
	right_pillar.collision_layer = ENVIRONMENT_LAYER
	right_pillar.collision_mask = 0
	right_pillar.name = "GatePillarR"
	_geometry_root.add_child(right_pillar)

	# Crossbar
	var crossbar := CSGBox3D.new()
	crossbar.size = Vector3(gate_width + pillar_r * 2, 1.0, 1.5)
	crossbar.position = Vector3(gx, pillar_h - 0.5, gz)
	crossbar.material = _mat_wall
	crossbar.use_collision = true
	crossbar.collision_layer = ENVIRONMENT_LAYER
	crossbar.collision_mask = 0
	crossbar.name = "GateCrossbar"
	_geometry_root.add_child(crossbar)

	# Gate light
	var gate_light := OmniLight3D.new()
	gate_light.name = "GateLight"
	gate_light.light_color = Color(0.9, 0.2, 0.1)
	gate_light.light_energy = 2.5
	gate_light.omni_range = 15.0
	gate_light.omni_attenuation = 1.5
	gate_light.shadow_enabled = false
	gate_light.position = Vector3(gx, pillar_h * 0.6, gz)
	_lighting_root.add_child(gate_light)

# ---------------------------------------------------------------------------
# Worship areas — pew rows facing altars
# ---------------------------------------------------------------------------

func _build_worship_areas() -> void:
	# Place pews in front of each altar
	for i in range(_altar_positions.size()):
		var pos: Vector2i = _altar_positions[i]
		var ax := _grid_to_world_x(pos.x) + CELL_SIZE * 0.5
		var az := _grid_to_world_z(pos.y) + CELL_SIZE * 0.5

		# Rows of pews extending away from the altar
		for row in range(PEW_ROWS):
			var row_z := az + CELL_SIZE * (row + 2)  # Start 2 cells away
			if row_z >= _grid_to_world_z(_courtyard_rect.y + _courtyard_rect.h) - CELL_SIZE:
				break

			# Two pews per row (left and right of center line)
			for side in range(2):
				var offset := -CELL_SIZE * 1.5 if side == 0 else CELL_SIZE * 1.5
				var pew := CSGBox3D.new()
				pew.size = Vector3(CELL_SIZE * 2.0, 0.7, 0.5)
				pew.position = Vector3(ax + offset, 0.35, row_z)
				pew.use_collision = true
				pew.collision_layer = ENVIRONMENT_LAYER
				pew.collision_mask = 0
				pew.material = _mat_pew
				pew.name = "Pew_%d_%d_%d" % [i, row, side]
				_geometry_root.add_child(pew)

				# Backrest
				var back := CSGBox3D.new()
				back.size = Vector3(CELL_SIZE * 2.0, 0.5, 0.1)
				back.position = Vector3(ax + offset, 0.85, row_z - 0.2)
				back.use_collision = false
				back.material = _mat_pew
				back.name = "PewBack_%d_%d_%d" % [i, row, side]
				_geometry_root.add_child(back)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.01, 0.02)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.05, 0.08)
	env.ambient_light_energy = 0.35

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.02, 0.04)
	env.fog_density = 0.01
	env.fog_light_energy = 0.5

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Directional light — dramatic red-orange
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = Color(0.8, 0.2, 0.1)
	dir_light.light_energy = 0.5
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-45, -30, 0)
	_lighting_root.add_child(dir_light)

	# Courtyard ambient lights
	if _courtyard_rect:
		var cc := _courtyard_rect.center()
		# Central courtyard light
		var main_light := OmniLight3D.new()
		main_light.name = "CourtyardMainLight"
		main_light.light_color = Color(0.8, 0.15, 0.08)
		main_light.light_energy = 2.0
		main_light.omni_range = COURTYARD_SIZE * CELL_SIZE * 0.4
		main_light.omni_attenuation = 1.5
		main_light.shadow_enabled = false
		main_light.position = Vector3(
			_grid_to_world_x(cc.x), WALL_HEIGHT * 0.8, _grid_to_world_z(cc.y)
		)
		_lighting_root.add_child(main_light)

	# Estate room lights
	for room: Rect2i_BSP in _estate_rooms:
		if _rng.randf() < 0.7:
			var rc := room.center()
			var light := OmniLight3D.new()
			light.name = "EstateLight_%d_%d" % [rc.x, rc.y]
			light.light_color = Color(
				_rng.randf_range(0.6, 0.9),
				_rng.randf_range(0.05, 0.2),
				_rng.randf_range(0.02, 0.1)
			)
			light.light_energy = _rng.randf_range(0.8, 1.5)
			light.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.7
			light.omni_attenuation = 1.8
			light.shadow_enabled = false
			light.position = Vector3(
				_grid_to_world_x(rc.x), WALL_HEIGHT * 0.6, _grid_to_world_z(rc.y)
			)
			_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns near the gate entrance
	_player_spawn = Vector3(
		_grid_to_world_x(_gate_position.x) + CELL_SIZE * 0.5,
		0.5,
		_grid_to_world_z(_gate_position.y) + CELL_SIZE * 2.0
	)

	# Enemy spawns across the courtyard
	if _courtyard_rect:
		var area: int = _courtyard_rect.w * _courtyard_rect.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS * 3, area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(
				_courtyard_rect.x + 2, _courtyard_rect.x + _courtyard_rect.w - 3
			)
			var sy: int = _rng.randi_range(
				_courtyard_rect.y + 2, _courtyard_rect.y + _courtyard_rect.h - 3
			)
			if _get_cell(sx, sy) == Cell.COURTYARD:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Enemy spawns in arena estate rooms
	for room: Rect2i_BSP in _arena_rooms:
		var area: int = room.w * room.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Spawns in non-arena estate rooms
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms:
			continue
		var area: int = room.w * room.h
		if area < MIN_ROOM_SIZE * MIN_ROOM_SIZE:
			continue
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(1, area / (ARENA_SPAWN_DENSITY * 2))
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	if _enemy_spawns.is_empty():
		if _courtyard_rect:
			var cc := _courtyard_rect.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(cc.x), 0.5, _grid_to_world_z(cc.y)
			))
		for room: Rect2i_BSP in _rooms:
			var center := room.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(center.x), 0.5, _grid_to_world_z(center.y)
			))
