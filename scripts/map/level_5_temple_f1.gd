extends Node3D
## Level 5 – "Hall of Echoes" – Temple Floor 1
## The grand entrance floor of a massive temple dedicated to an ancient nameless God.
## Features a towering central worship hall with pillar-flanked aisles, side chambers,
## wide corridors with arched doorframes, and wall-niche statues.
##
## Usage:
##   var level = preload("res://scripts/map/level_5_temple_f1.gd").new()
##   add_child(level)
##   level.generate_map(seed_value)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 80
const GRID_HEIGHT: int = 80
const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 8.0

const MIN_PARTITION_SIZE: int = 8
const MAX_PARTITION_SIZE: int = 28
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 5
const CORRIDOR_WIDTH: int = 3

const ENVIRONMENT_LAYER: int = 1

const ARENA_SPAWN_DENSITY: int = 20
const MIN_ARENA_SPAWNS: int = 4

# Central hall dimensions (carved deterministically)
const CENTRAL_HALL_W: int = 22
const CENTRAL_HALL_H: int = 32
const PILLAR_SPACING: int = 4
const PILLAR_RADIUS: float = 0.6
const PILLAR_HEIGHT_FACTOR: float = 0.92  # fraction of WALL_HEIGHT

# Side chamber count target
const SIDE_CHAMBER_COUNT: int = 8

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
var _rooms: Array[Rect2i_BSP] = []
var _arena_rooms: Array[Rect2i_BSP] = []
var _side_chambers: Array[Rect2i_BSP] = []
var _central_hall: Rect2i_BSP = null
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
var _mat_statue: StandardMaterial3D = null
var _mat_inscription: StandardMaterial3D = null
var _mat_whisper: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value
	_create_materials()
	_init_grid()

	# 1. Carve the massive central hall first
	_carve_central_hall()

	# 2. BSP-partition the remaining space for side chambers
	_generate_side_chambers()

	# 3. Connect side chambers to the central hall with wide corridors
	_connect_chambers_to_hall()

	# 4. Build walls around all floor cells
	_build_walls()

	# 5. Classify rooms
	_classify_rooms()

	# 6. Create geometry root
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)
	_build_geometry()

	# 7. Decorations (pillars, statues, inscriptions, whispers)
	_decorations_root = Node3D.new()
	_decorations_root.name = "Decorations"
	add_child(_decorations_root)
	_build_pillars()
	_build_statues()
	_build_inscriptions()
	_build_whisper_particles()
	_build_arch_doorframes()

	# 8. Lighting
	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)
	_build_environment()

	# 9. Spawn points
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
	_side_chambers.clear()
	_central_hall = null
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var c := room.center()
		data.append({
			"position": Vector3(_grid_to_world_x(c.x), 0.0, _grid_to_world_z(c.y)),
			"size": Vector2(room.w * CELL_SIZE, room.h * CELL_SIZE),
			"is_arena": room in _arena_rooms,
			"is_central_hall": room == _central_hall,
			"grid_rect": Rect2(room.x, room.y, room.w, room.h),
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
	_mat_floor.albedo_color = Color(0.1, 0.04, 0.1)
	_mat_floor.roughness = 0.85
	_mat_floor.metallic = 0.05

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.14, 0.05, 0.14)
	_mat_wall.roughness = 0.9
	_mat_wall.metallic = 0.0

	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.04, 0.01, 0.04)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

	_mat_corridor_floor = StandardMaterial3D.new()
	_mat_corridor_floor.albedo_color = Color(0.08, 0.03, 0.08)
	_mat_corridor_floor.roughness = 0.9
	_mat_corridor_floor.metallic = 0.05

	_mat_accent = StandardMaterial3D.new()
	_mat_accent.albedo_color = Color(0.5, 0.1, 0.5)
	_mat_accent.roughness = 0.6
	_mat_accent.metallic = 0.2
	_mat_accent.emission_enabled = true
	_mat_accent.emission = Color(0.5, 0.1, 0.5)
	_mat_accent.emission_energy_multiplier = 0.5

	_mat_pillar = StandardMaterial3D.new()
	_mat_pillar.albedo_color = Color(0.16, 0.06, 0.16)
	_mat_pillar.roughness = 0.7
	_mat_pillar.metallic = 0.1

	_mat_statue = StandardMaterial3D.new()
	_mat_statue.albedo_color = Color(0.12, 0.04, 0.12)
	_mat_statue.roughness = 0.6
	_mat_statue.metallic = 0.15

	_mat_inscription = StandardMaterial3D.new()
	_mat_inscription.albedo_color = Color(0.3, 0.08, 0.3)
	_mat_inscription.roughness = 0.5
	_mat_inscription.metallic = 0.1
	_mat_inscription.emission_enabled = true
	_mat_inscription.emission = Color(0.3, 0.05, 0.3)
	_mat_inscription.emission_energy_multiplier = 0.3

	_mat_whisper = StandardMaterial3D.new()
	_mat_whisper.albedo_color = Color(0.6, 0.15, 0.6)
	_mat_whisper.roughness = 0.2
	_mat_whisper.metallic = 0.0
	_mat_whisper.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_whisper.albedo_color.a = 0.35
	_mat_whisper.emission_enabled = true
	_mat_whisper.emission = Color(0.5, 0.1, 0.5)
	_mat_whisper.emission_energy_multiplier = 1.0

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
# Central hall
# ---------------------------------------------------------------------------

func _carve_central_hall() -> void:
	@warning_ignore("integer_division")
	var cx: int = (GRID_WIDTH - CENTRAL_HALL_W) / 2
	@warning_ignore("integer_division")
	var cy: int = (GRID_HEIGHT - CENTRAL_HALL_H) / 2
	_central_hall = Rect2i_BSP.new(cx, cy, CENTRAL_HALL_W, CENTRAL_HALL_H)
	_rooms.append(_central_hall)

	for x in range(cx, cx + CENTRAL_HALL_W):
		for y in range(cy, cy + CENTRAL_HALL_H):
			_set_cell(x, y, Cell.FLOOR)

	# Carve an entrance room at the bottom of the hall
	var entrance_w: int = 8
	var entrance_h: int = 6
	@warning_ignore("integer_division")
	var ex: int = cx + (CENTRAL_HALL_W - entrance_w) / 2
	var ey: int = cy + CENTRAL_HALL_H
	var entrance := Rect2i_BSP.new(ex, ey, entrance_w, entrance_h)
	_rooms.append(entrance)
	for x in range(ex, ex + entrance_w):
		for y in range(ey, ey + entrance_h):
			_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Side chambers via BSP on remaining quadrants
# ---------------------------------------------------------------------------

func _generate_side_chambers() -> void:
	# Define regions around the central hall for BSP subdivision
	@warning_ignore("integer_division")
	var hall_cx: int = (GRID_WIDTH - CENTRAL_HALL_W) / 2
	@warning_ignore("integer_division")
	var hall_cy: int = (GRID_HEIGHT - CENTRAL_HALL_H) / 2

	var regions: Array = []
	# Left region
	if hall_cx > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(2, 2, hall_cx - 4, GRID_HEIGHT - 4))
	# Right region
	var right_x: int = hall_cx + CENTRAL_HALL_W + 2
	if GRID_WIDTH - right_x > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(right_x, 2, GRID_WIDTH - right_x - 2, GRID_HEIGHT - 4))
	# Top region
	if hall_cy > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(hall_cx, 2, CENTRAL_HALL_W, hall_cy - 4))
	# Bottom region (below entrance)
	var bottom_y: int = hall_cy + CENTRAL_HALL_H + 8
	if GRID_HEIGHT - bottom_y > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(hall_cx, bottom_y, CENTRAL_HALL_W, GRID_HEIGHT - bottom_y - 2))

	for region in regions:
		var root := BSPNode.new(region)
		_split_bsp(root, 0)
		_create_rooms_from_bsp(root)


func _split_bsp(node: BSPNode, depth: int) -> void:
	if node.rect.w <= MAX_PARTITION_SIZE and node.rect.h <= MAX_PARTITION_SIZE:
		if node.rect.w < MIN_PARTITION_SIZE * 2 and node.rect.h < MIN_PARTITION_SIZE * 2:
			return
		if depth > 3 and _rng.randf() < 0.3:
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
	elif node.rect.w > node.rect.h * 1.25:
		split_horizontal = false
	elif node.rect.h > node.rect.w * 1.25:
		split_horizontal = true
	else:
		split_horizontal = _rng.randf() < 0.5

	if split_horizontal:
		var min_y: int = node.rect.y + MIN_PARTITION_SIZE
		var max_y: int = node.rect.y + node.rect.h - MIN_PARTITION_SIZE
		if min_y >= max_y:
			return
		var split_y: int = _rng.randi_range(min_y, max_y)
		node.left = BSPNode.new(Rect2i_BSP.new(node.rect.x, node.rect.y, node.rect.w, split_y - node.rect.y))
		node.right = BSPNode.new(Rect2i_BSP.new(node.rect.x, split_y, node.rect.w, node.rect.y + node.rect.h - split_y))
	else:
		var min_x: int = node.rect.x + MIN_PARTITION_SIZE
		var max_x: int = node.rect.x + node.rect.w - MIN_PARTITION_SIZE
		if min_x >= max_x:
			return
		var split_x: int = _rng.randi_range(min_x, max_x)
		node.left = BSPNode.new(Rect2i_BSP.new(node.rect.x, node.rect.y, split_x - node.rect.x, node.rect.h))
		node.right = BSPNode.new(Rect2i_BSP.new(split_x, node.rect.y, node.rect.x + node.rect.w - split_x, node.rect.h))

	_split_bsp(node.left, depth + 1)
	_split_bsp(node.right, depth + 1)


func _create_rooms_from_bsp(node: BSPNode) -> void:
	if node.is_leaf():
		var rw: int = _rng.randi_range(maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN * 3), maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN))
		var rh: int = _rng.randi_range(maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN * 3), maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN))
		rw = clampi(rw, MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		rh = clampi(rh, MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)

		var rx: int = _rng.randi_range(node.rect.x + 1, maxi(node.rect.x + 1, node.rect.x + node.rect.w - rw - 1))
		var ry: int = _rng.randi_range(node.rect.y + 1, maxi(node.rect.y + 1, node.rect.y + node.rect.h - rh - 1))
		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)
		_side_chambers.append(node.room)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left:
		_create_rooms_from_bsp(node.left)
	if node.right:
		_create_rooms_from_bsp(node.right)

	# Connect sibling rooms
	if node.left and node.right:
		var room_a := _get_room_from_node(node.left)
		var room_b := _get_room_from_node(node.right)
		if room_a and room_b:
			_carve_corridor(room_a.center(), room_b.center())


func _get_room_from_node(node: BSPNode) -> Rect2i_BSP:
	if node.room:
		return node.room
	if node.left:
		var r := _get_room_from_node(node.left)
		if r:
			return r
	if node.right:
		var r := _get_room_from_node(node.right)
		if r:
			return r
	return null

# ---------------------------------------------------------------------------
# Connect chambers to central hall
# ---------------------------------------------------------------------------

func _connect_chambers_to_hall() -> void:
	var hall_center := _central_hall.center()
	for chamber: Rect2i_BSP in _side_chambers:
		_carve_corridor(chamber.center(), hall_center)


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
			if _get_cell(x + dx, y + dy) == Cell.FLOOR:
				return true
	return false

# ---------------------------------------------------------------------------
# Room classification
# ---------------------------------------------------------------------------

func _classify_rooms() -> void:
	_arena_rooms.clear()
	_arena_rooms.append(_central_hall)
	for room: Rect2i_BSP in _side_chambers:
		if room.w >= 8 and room.h >= 8:
			_arena_rooms.append(room)

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
	box.material = _mat_floor if _strip_overlaps_room(strip) else _mat_corridor_floor
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


func _strip_overlaps_room(strip: Rect2i_BSP) -> bool:
	for room: Rect2i_BSP in _rooms:
		if strip.x < room.x + room.w and strip.x + strip.w > room.x \
			and strip.y < room.y + room.h and strip.y + strip.h > room.y:
			return true
	return false

# ---------------------------------------------------------------------------
# Decorations — Pillars
# ---------------------------------------------------------------------------

func _build_pillars() -> void:
	if not _central_hall:
		return
	var hx: int = _central_hall.x
	var hy: int = _central_hall.y
	var hw: int = _central_hall.w
	var hh: int = _central_hall.h

	# Two rows of pillars flanking the central aisle
	var aisle_margin: int = 4  # distance from left/right wall to pillar row
	var left_col: int = hx + aisle_margin
	var right_col: int = hx + hw - aisle_margin - 1

	var pillar_h: float = WALL_HEIGHT * PILLAR_HEIGHT_FACTOR
	var idx: int = 0
	for row_y in range(hy + 2, hy + hh - 2, PILLAR_SPACING):
		for col_x in [left_col, right_col]:
			var cyl := CSGCylinder3D.new()
			cyl.radius = PILLAR_RADIUS
			cyl.height = pillar_h
			cyl.sides = 12
			cyl.position = Vector3(
				_grid_to_world_x(col_x) + CELL_SIZE * 0.5,
				pillar_h * 0.5,
				_grid_to_world_z(row_y) + CELL_SIZE * 0.5
			)
			cyl.use_collision = true
			cyl.collision_layer = ENVIRONMENT_LAYER
			cyl.collision_mask = 0
			cyl.material = _mat_pillar
			cyl.name = "Pillar_%d" % idx
			_decorations_root.add_child(cyl)

			# Pillar base — wider disc
			var base := CSGCylinder3D.new()
			base.radius = PILLAR_RADIUS * 1.6
			base.height = 0.4
			base.sides = 12
			base.position = Vector3(cyl.position.x, 0.2, cyl.position.z)
			base.use_collision = true
			base.collision_layer = ENVIRONMENT_LAYER
			base.collision_mask = 0
			base.material = _mat_pillar
			base.name = "PillarBase_%d" % idx
			_decorations_root.add_child(base)

			# Pillar capital — wider disc at top
			var capital := CSGCylinder3D.new()
			capital.radius = PILLAR_RADIUS * 1.4
			capital.height = 0.35
			capital.sides = 12
			capital.position = Vector3(cyl.position.x, pillar_h - 0.175, cyl.position.z)
			capital.use_collision = true
			capital.collision_layer = ENVIRONMENT_LAYER
			capital.collision_mask = 0
			capital.material = _mat_pillar
			capital.name = "PillarCap_%d" % idx
			_decorations_root.add_child(capital)

			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Statues in niches
# ---------------------------------------------------------------------------

func _build_statues() -> void:
	if not _central_hall:
		return
	var hx: int = _central_hall.x
	var hy: int = _central_hall.y
	var hw: int = _central_hall.w
	var hh: int = _central_hall.h

	# Place statues along the left and right walls of the hall
	var statue_spacing: int = 6
	var idx: int = 0
	for row_y in range(hy + 3, hy + hh - 3, statue_spacing):
		for side in [0, 1]:
			var sx: int = hx + 1 if side == 0 else hx + hw - 2
			var world_x: float = _grid_to_world_x(sx) + CELL_SIZE * 0.5
			var world_z: float = _grid_to_world_z(row_y) + CELL_SIZE * 0.5

			# Statue body — tall box
			var body := CSGBox3D.new()
			body.size = Vector3(1.2, 3.0, 0.8)
			body.position = Vector3(world_x, 1.5, world_z)
			body.use_collision = true
			body.collision_layer = ENVIRONMENT_LAYER
			body.collision_mask = 0
			body.material = _mat_statue
			body.name = "StatueBody_%d" % idx
			_decorations_root.add_child(body)

			# Statue head — sphere
			var head := CSGSphere3D.new()
			head.radius = 0.5
			head.radial_segments = 12
			head.rings = 8
			head.position = Vector3(world_x, 3.4, world_z)
			head.use_collision = false
			head.material = _mat_statue
			head.name = "StatueHead_%d" % idx
			_decorations_root.add_child(head)

			# Statue pedestal
			var pedestal := CSGBox3D.new()
			pedestal.size = Vector3(1.6, 0.5, 1.2)
			pedestal.position = Vector3(world_x, 0.25, world_z)
			pedestal.use_collision = true
			pedestal.collision_layer = ENVIRONMENT_LAYER
			pedestal.collision_mask = 0
			pedestal.material = _mat_pillar
			pedestal.name = "StatuePedestal_%d" % idx
			_decorations_root.add_child(pedestal)

			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Wall inscriptions
# ---------------------------------------------------------------------------

func _build_inscriptions() -> void:
	if not _central_hall:
		return
	var hx: int = _central_hall.x
	var hy: int = _central_hall.y
	var hw: int = _central_hall.w
	var hh: int = _central_hall.h

	# Place thin horizontal inscription strips along left and right outer walls
	var idx: int = 0
	for row_y in range(hy + 1, hy + hh - 1, 3):
		for side in [0, 1]:
			var wx: int = hx - 1 if side == 0 else hx + hw
			if _get_cell(wx, row_y) != Cell.WALL:
				continue
			var world_x: float = _grid_to_world_x(wx) + CELL_SIZE * 0.5
			var world_z: float = _grid_to_world_z(row_y) + CELL_SIZE * 0.5

			# Three horizontal strips at different heights to simulate carved text
			for h_offset in [2.5, 3.0, 3.5]:
				var strip := CSGBox3D.new()
				strip.size = Vector3(0.05, 0.08, CELL_SIZE * 0.8)
				var face_offset: float = CELL_SIZE * 0.48 if side == 0 else -CELL_SIZE * 0.48
				strip.position = Vector3(world_x + face_offset, h_offset, world_z)
				strip.material = _mat_inscription
				strip.name = "Inscription_%d" % idx
				_decorations_root.add_child(strip)
				idx += 1

# ---------------------------------------------------------------------------
# Decorations — Whisper particles (floating semi-transparent spheres)
# ---------------------------------------------------------------------------

func _build_whisper_particles() -> void:
	if not _central_hall:
		return
	var hx: int = _central_hall.x
	var hy: int = _central_hall.y
	var hw: int = _central_hall.w
	var hh: int = _central_hall.h

	var count: int = 30
	for i in range(count):
		var px: float = _grid_to_world_x(hx) + _rng.randf_range(CELL_SIZE, hw * CELL_SIZE - CELL_SIZE)
		var py: float = _rng.randf_range(1.5, WALL_HEIGHT - 1.0)
		var pz: float = _grid_to_world_z(hy) + _rng.randf_range(CELL_SIZE, hh * CELL_SIZE - CELL_SIZE)

		var sphere := CSGSphere3D.new()
		sphere.radius = _rng.randf_range(0.04, 0.12)
		sphere.radial_segments = 6
		sphere.rings = 4
		sphere.position = Vector3(px, py, pz)
		sphere.material = _mat_whisper
		sphere.name = "Whisper_%d" % i
		_decorations_root.add_child(sphere)

	# Also scatter a few in side chambers
	for chamber: Rect2i_BSP in _side_chambers:
		var whisper_count: int = _rng.randi_range(2, 5)
		for j in range(whisper_count):
			var px: float = _grid_to_world_x(chamber.x) + _rng.randf_range(0.5, chamber.w * CELL_SIZE - 0.5)
			var py: float = _rng.randf_range(1.0, WALL_HEIGHT - 1.5)
			var pz: float = _grid_to_world_z(chamber.y) + _rng.randf_range(0.5, chamber.h * CELL_SIZE - 0.5)
			var sphere := CSGSphere3D.new()
			sphere.radius = _rng.randf_range(0.03, 0.08)
			sphere.radial_segments = 6
			sphere.rings = 4
			sphere.position = Vector3(px, py, pz)
			sphere.material = _mat_whisper
			sphere.name = "WhisperChamber_%d_%d" % [chamber.x, j]
			_decorations_root.add_child(sphere)

# ---------------------------------------------------------------------------
# Decorations — Arch doorframes in corridors
# ---------------------------------------------------------------------------

func _build_arch_doorframes() -> void:
	# Place arched doorframes at the boundary between corridors and rooms
	var idx: int = 0
	for room: Rect2i_BSP in _side_chambers:
		var c := room.center()
		var hall_c := _central_hall.center()
		# Place an arch roughly at the room boundary toward the hall
		var dir := Vector2(hall_c.x - c.x, hall_c.y - c.y)
		var arch_x: int
		var arch_y: int
		if absf(dir.x) > absf(dir.y):
			arch_x = room.x + room.w if dir.x > 0 else room.x - 1
			arch_y = c.y
		else:
			arch_x = c.x
			arch_y = room.y + room.h if dir.y > 0 else room.y - 1

		if _get_cell(arch_x, arch_y) != Cell.FLOOR:
			continue

		var world_x: float = _grid_to_world_x(arch_x) + CELL_SIZE * 0.5
		var world_z: float = _grid_to_world_z(arch_y) + CELL_SIZE * 0.5

		# Left post
		var post_l := CSGBox3D.new()
		post_l.size = Vector3(0.4, WALL_HEIGHT * 0.85, 0.4)
		post_l.position = Vector3(world_x - CELL_SIZE * 0.4, WALL_HEIGHT * 0.85 * 0.5, world_z)
		post_l.use_collision = true
		post_l.collision_layer = ENVIRONMENT_LAYER
		post_l.collision_mask = 0
		post_l.material = _mat_accent
		post_l.name = "ArchPostL_%d" % idx
		_decorations_root.add_child(post_l)

		# Right post
		var post_r := CSGBox3D.new()
		post_r.size = Vector3(0.4, WALL_HEIGHT * 0.85, 0.4)
		post_r.position = Vector3(world_x + CELL_SIZE * 0.4, WALL_HEIGHT * 0.85 * 0.5, world_z)
		post_r.use_collision = true
		post_r.collision_layer = ENVIRONMENT_LAYER
		post_r.collision_mask = 0
		post_r.material = _mat_accent
		post_r.name = "ArchPostR_%d" % idx
		_decorations_root.add_child(post_r)

		# Lintel
		var lintel := CSGBox3D.new()
		lintel.size = Vector3(CELL_SIZE * 0.85, 0.5, 0.5)
		lintel.position = Vector3(world_x, WALL_HEIGHT * 0.85, world_z)
		lintel.use_collision = true
		lintel.collision_layer = ENVIRONMENT_LAYER
		lintel.collision_mask = 0
		lintel.material = _mat_accent
		lintel.name = "ArchLintel_%d" % idx
		_decorations_root.add_child(lintel)

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
	env.background_color = Color(0.02, 0.005, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.05, 0.15)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = RenderingServer.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.02, 0.06)
	env.fog_density = 0.012
	env.fog_light_energy = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	_lighting_root.add_child(world_env)

	# DirectionalLight
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "TempleLight"
	dir_light.light_color = Color(0.5, 0.15, 0.5)
	dir_light.light_energy = 0.4
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-50, -20, 0)
	_lighting_root.add_child(dir_light)

	# Purple OmniLights along the central hall
	if _central_hall:
		var hx: int = _central_hall.x
		var hy: int = _central_hall.y
		var hw: int = _central_hall.w
		var hh: int = _central_hall.h
		for row_y in range(hy + 2, hy + hh - 2, 5):
			for side_x in [hx + 3, hx + hw - 4]:
				var light := OmniLight3D.new()
				light.light_color = Color(
					_rng.randf_range(0.4, 0.6),
					_rng.randf_range(0.05, 0.15),
					_rng.randf_range(0.4, 0.6)
				)
				light.light_energy = _rng.randf_range(1.5, 2.5)
				light.omni_range = CELL_SIZE * 6.0
				light.omni_attenuation = 1.5
				light.shadow_enabled = false
				light.position = Vector3(
					_grid_to_world_x(side_x) + CELL_SIZE * 0.5,
					WALL_HEIGHT * 0.7,
					_grid_to_world_z(row_y) + CELL_SIZE * 0.5
				)
				light.name = "HallLight_%d_%d" % [side_x, row_y]
				_lighting_root.add_child(light)

	# Dimmer lights in side chambers
	for room: Rect2i_BSP in _side_chambers:
		var c := room.center()
		var light := OmniLight3D.new()
		light.light_color = Color(
			_rng.randf_range(0.3, 0.5),
			_rng.randf_range(0.02, 0.08),
			_rng.randf_range(0.3, 0.5)
		)
		light.light_energy = _rng.randf_range(0.5, 1.0)
		light.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.7
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(c.x),
			WALL_HEIGHT * 0.6,
			_grid_to_world_z(c.y)
		)
		light.name = "ChamberLight_%d_%d" % [c.x, c.y]
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns in the entrance room (last room added = entrance)
	if _rooms.size() >= 2:
		var entrance: Rect2i_BSP = _rooms[1]  # entrance room
		var ec := entrance.center()
		_player_spawn = Vector3(_grid_to_world_x(ec.x), 0.5, _grid_to_world_z(ec.y))
	elif _rooms.size() > 0:
		var c := _rooms[0].center()
		_player_spawn = Vector3(_grid_to_world_x(c.x), 0.5, _grid_to_world_z(c.y))

	# Enemy spawns in arena rooms
	for room: Rect2i_BSP in _arena_rooms:
		var spawn_area: int = room.w * room.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, spawn_area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Also place some spawns in non-arena side chambers (not the entrance)
	for room: Rect2i_BSP in _side_chambers:
		if room in _arena_rooms:
			continue
		if _rooms.size() >= 2 and room == _rooms[1]:
			continue
		var room_area: int = room.w * room.h
		if room_area < MIN_ROOM_SIZE * MIN_ROOM_SIZE:
			continue
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(1, room_area / (ARENA_SPAWN_DENSITY * 2))
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))
