extends Node3D
## Level 6 – "The Crimson Nave" – Temple Floor 2
## The ritual floor of the temple. Blood-red themed with channels carved into stone,
## ritual circles, a cathedral-like nave with pews and altar, and sacrifice chambers.
##
## Usage:
##   var level = preload("res://scripts/map/level_6_temple_f2.gd").new()
##   add_child(level)
##   level.generate_map(seed_value)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 70
const GRID_HEIGHT: int = 70
const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 8.0

const MIN_PARTITION_SIZE: int = 8
const MAX_PARTITION_SIZE: int = 26
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 5
const CORRIDOR_WIDTH: int = 3

const ENVIRONMENT_LAYER: int = 1

const ARENA_SPAWN_DENSITY: int = 18
const MIN_ARENA_SPAWNS: int = 4

# Nave dimensions
const NAVE_W: int = 20
const NAVE_H: int = 26

# Ritual circle count
const RITUAL_CIRCLE_COUNT: int = 5

# Sacrifice chamber count
const SACRIFICE_CHAMBER_TARGET: int = 4

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
var _side_rooms: Array[Rect2i_BSP] = []
var _ritual_rooms: Array[Rect2i_BSP] = []
var _sacrifice_rooms: Array[Rect2i_BSP] = []
var _nave: Rect2i_BSP = null
var _entrance_room: Rect2i_BSP = null
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pulsing_lights: Array = []

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
var _mat_blood_channel: StandardMaterial3D = null
var _mat_altar: StandardMaterial3D = null
var _mat_pew: StandardMaterial3D = null
var _mat_pillar: StandardMaterial3D = null
var _mat_blood_stain: StandardMaterial3D = null
var _mat_ritual_glow: StandardMaterial3D = null
var _mat_pedestal: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value
	_create_materials()
	_init_grid()

	# 1. Carve the large nave
	_carve_nave()

	# 2. Carve stairway entrance
	_carve_entrance()

	# 3. Generate side rooms via BSP
	_generate_side_rooms()

	# 4. Connect all rooms to nave
	_connect_rooms_to_nave()

	# 5. Build walls
	_build_walls()

	# 6. Classify rooms
	_classify_rooms()

	# 7. Build geometry
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)
	_build_geometry()

	# 8. Build decorations
	_decorations_root = Node3D.new()
	_decorations_root.name = "Decorations"
	add_child(_decorations_root)
	_build_nave_columns()
	_build_altar_platform()
	_build_pews()
	_build_blood_channels()
	_build_ritual_circles()
	_build_sacrifice_altars()
	_build_corridor_archways()

	# 9. Build lighting
	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)
	_build_environment()

	# 10. Spawn points
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
	_side_rooms.clear()
	_ritual_rooms.clear()
	_sacrifice_rooms.clear()
	_nave = null
	_entrance_room = null
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO
	_pulsing_lights.clear()


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var c := room.center()
		var room_type: String = "normal"
		if room == _nave:
			room_type = "nave"
		elif room in _ritual_rooms:
			room_type = "ritual"
		elif room in _sacrifice_rooms:
			room_type = "sacrifice"
		elif room == _entrance_room:
			room_type = "entrance"
		data.append({
			"position": Vector3(_grid_to_world_x(c.x), 0.0, _grid_to_world_z(c.y)),
			"size": Vector2(room.w * CELL_SIZE, room.h * CELL_SIZE),
			"is_arena": room in _arena_rooms,
			"room_type": room_type,
			"grid_rect": Rect2(room.x, room.y, room.w, room.h),
		})
	return data


func is_walkable(world_pos: Vector3) -> bool:
	var gx: int = int(world_pos.x / CELL_SIZE)
	var gy: int = int(world_pos.z / CELL_SIZE)
	return _get_cell(gx, gy) == Cell.FLOOR

# ---------------------------------------------------------------------------
# Process — pulsing lights
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var time: float = Time.get_ticks_msec() / 1000.0
	for light_data in _pulsing_lights:
		var light: OmniLight3D = light_data["light"]
		var base_energy: float = light_data["base_energy"]
		var pulse_speed: float = light_data["pulse_speed"]
		if is_instance_valid(light):
			light.light_energy = base_energy + sin(time * pulse_speed) * base_energy * 0.3

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.18, 0.03, 0.03)
	_mat_floor.roughness = 0.85
	_mat_floor.metallic = 0.05

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.2, 0.04, 0.04)
	_mat_wall.roughness = 0.9
	_mat_wall.metallic = 0.0

	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.05, 0.01, 0.01)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

	_mat_corridor_floor = StandardMaterial3D.new()
	_mat_corridor_floor.albedo_color = Color(0.14, 0.025, 0.025)
	_mat_corridor_floor.roughness = 0.9
	_mat_corridor_floor.metallic = 0.05

	_mat_accent = StandardMaterial3D.new()
	_mat_accent.albedo_color = Color(0.9, 0.1, 0.05)
	_mat_accent.roughness = 0.5
	_mat_accent.metallic = 0.1
	_mat_accent.emission_enabled = true
	_mat_accent.emission = Color(0.9, 0.1, 0.05)
	_mat_accent.emission_energy_multiplier = 0.6

	_mat_blood_channel = StandardMaterial3D.new()
	_mat_blood_channel.albedo_color = Color(0.7, 0.02, 0.02)
	_mat_blood_channel.roughness = 0.3
	_mat_blood_channel.metallic = 0.1
	_mat_blood_channel.emission_enabled = true
	_mat_blood_channel.emission = Color(0.8, 0.05, 0.02)
	_mat_blood_channel.emission_energy_multiplier = 0.8

	_mat_altar = StandardMaterial3D.new()
	_mat_altar.albedo_color = Color(0.1, 0.02, 0.02)
	_mat_altar.roughness = 0.6
	_mat_altar.metallic = 0.2

	_mat_pew = StandardMaterial3D.new()
	_mat_pew.albedo_color = Color(0.12, 0.03, 0.02)
	_mat_pew.roughness = 0.8
	_mat_pew.metallic = 0.0

	_mat_pillar = StandardMaterial3D.new()
	_mat_pillar.albedo_color = Color(0.22, 0.05, 0.05)
	_mat_pillar.roughness = 0.7
	_mat_pillar.metallic = 0.1

	_mat_blood_stain = StandardMaterial3D.new()
	_mat_blood_stain.albedo_color = Color(0.4, 0.01, 0.01)
	_mat_blood_stain.roughness = 0.5
	_mat_blood_stain.metallic = 0.05

	_mat_ritual_glow = StandardMaterial3D.new()
	_mat_ritual_glow.albedo_color = Color(0.9, 0.05, 0.02)
	_mat_ritual_glow.roughness = 0.3
	_mat_ritual_glow.metallic = 0.0
	_mat_ritual_glow.emission_enabled = true
	_mat_ritual_glow.emission = Color(1.0, 0.1, 0.05)
	_mat_ritual_glow.emission_energy_multiplier = 1.5

	_mat_pedestal = StandardMaterial3D.new()
	_mat_pedestal.albedo_color = Color(0.15, 0.03, 0.03)
	_mat_pedestal.roughness = 0.7
	_mat_pedestal.metallic = 0.15

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
# Nave carving
# ---------------------------------------------------------------------------

func _carve_nave() -> void:
	@warning_ignore("integer_division")
	var nx: int = (GRID_WIDTH - NAVE_W) / 2
	@warning_ignore("integer_division")
	var ny: int = (GRID_HEIGHT - NAVE_H) / 2
	_nave = Rect2i_BSP.new(nx, ny, NAVE_W, NAVE_H)
	_rooms.append(_nave)

	for x in range(nx, nx + NAVE_W):
		for y in range(ny, ny + NAVE_H):
			_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Entrance (stairway room)
# ---------------------------------------------------------------------------

func _carve_entrance() -> void:
	var ew: int = 7
	var eh: int = 7
	@warning_ignore("integer_division")
	var ex: int = (GRID_WIDTH - ew) / 2
	var ey: int = _nave.y + _nave.h + 2
	_entrance_room = Rect2i_BSP.new(ex, ey, ew, eh)
	_rooms.append(_entrance_room)

	for x in range(ex, ex + ew):
		for y in range(ey, ey + eh):
			_set_cell(x, y, Cell.FLOOR)

	# Connect entrance to nave
	_carve_corridor(_entrance_room.center(), _nave.center())

# ---------------------------------------------------------------------------
# Side rooms via BSP
# ---------------------------------------------------------------------------

func _generate_side_rooms() -> void:
	@warning_ignore("integer_division")
	var nave_x: int = (GRID_WIDTH - NAVE_W) / 2
	@warning_ignore("integer_division")
	var nave_y: int = (GRID_HEIGHT - NAVE_H) / 2

	# Define BSP regions around the nave
	var regions: Array = []
	# Left side
	if nave_x > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(2, 2, nave_x - 4, GRID_HEIGHT - 4))
	# Right side
	var right_x: int = nave_x + NAVE_W + 2
	if GRID_WIDTH - right_x > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(right_x, 2, GRID_WIDTH - right_x - 2, GRID_HEIGHT - 4))
	# Top
	if nave_y > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(nave_x, 2, NAVE_W, nave_y - 4))
	# Bottom (below entrance)
	var bottom_y: int = _entrance_room.y + _entrance_room.h + 2
	if GRID_HEIGHT - bottom_y > MIN_PARTITION_SIZE + 2:
		regions.append(Rect2i_BSP.new(nave_x, bottom_y, NAVE_W, GRID_HEIGHT - bottom_y - 2))

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
		_side_rooms.append(node.room)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left:
		_create_rooms_from_bsp(node.left)
	if node.right:
		_create_rooms_from_bsp(node.right)

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
# Connect rooms to nave
# ---------------------------------------------------------------------------

func _connect_rooms_to_nave() -> void:
	var nave_center := _nave.center()
	for room: Rect2i_BSP in _side_rooms:
		_carve_corridor(room.center(), nave_center)


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
	_ritual_rooms.clear()
	_sacrifice_rooms.clear()

	_arena_rooms.append(_nave)

	# Sort side rooms by area descending
	var sorted_sides := _side_rooms.duplicate()
	sorted_sides.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
		return a.area() > b.area()
	)

	# Assign ritual rooms (larger ones)
	var ritual_count: int = 0
	for room: Rect2i_BSP in sorted_sides:
		if ritual_count >= RITUAL_CIRCLE_COUNT:
			break
		if room.w >= 7 and room.h >= 7:
			_ritual_rooms.append(room)
			_arena_rooms.append(room)
			ritual_count += 1

	# Assign sacrifice rooms (smaller ones)
	var sacrifice_count: int = 0
	for room: Rect2i_BSP in sorted_sides:
		if sacrifice_count >= SACRIFICE_CHAMBER_TARGET:
			break
		if room not in _ritual_rooms and room.w >= 5 and room.h >= 5:
			_sacrifice_rooms.append(room)
			sacrifice_count += 1

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
# Decorations — Nave columns
# ---------------------------------------------------------------------------

func _build_nave_columns() -> void:
	if not _nave:
		return
	var nx: int = _nave.x
	var ny: int = _nave.y
	var nw: int = _nave.w
	var nh: int = _nave.h

	var col_left: int = nx + 3
	var col_right: int = nx + nw - 4
	var pillar_h: float = WALL_HEIGHT * 0.9

	var idx: int = 0
	for row_y in range(ny + 2, ny + nh - 2, 4):
		for col_x in [col_left, col_right]:
			var cyl := CSGCylinder3D.new()
			cyl.radius = 0.55
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
			cyl.name = "NaveColumn_%d" % idx
			_decorations_root.add_child(cyl)

			# Capital
			var cap := CSGCylinder3D.new()
			cap.radius = 0.8
			cap.height = 0.3
			cap.sides = 12
			cap.position = Vector3(cyl.position.x, pillar_h - 0.15, cyl.position.z)
			cap.use_collision = true
			cap.collision_layer = ENVIRONMENT_LAYER
			cap.collision_mask = 0
			cap.material = _mat_pillar
			cap.name = "NaveColCap_%d" % idx
			_decorations_root.add_child(cap)

			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Altar platform at front of nave
# ---------------------------------------------------------------------------

func _build_altar_platform() -> void:
	if not _nave:
		return
	var nx: int = _nave.x
	var ny: int = _nave.y
	var nw: int = _nave.w

	# Raised platform at the top (north) end of the nave
	var platform_w: float = nw * CELL_SIZE * 0.6
	var platform_d: float = CELL_SIZE * 4.0
	var platform_h: float = 2.0

	var world_cx: float = _grid_to_world_x(nx) + nw * CELL_SIZE * 0.5
	var world_cz: float = _grid_to_world_z(ny) + CELL_SIZE * 2.0

	var platform := CSGBox3D.new()
	platform.size = Vector3(platform_w, platform_h, platform_d)
	platform.position = Vector3(world_cx, platform_h * 0.5, world_cz)
	platform.use_collision = true
	platform.collision_layer = ENVIRONMENT_LAYER
	platform.collision_mask = 0
	platform.material = _mat_altar
	platform.name = "AltarPlatform"
	_decorations_root.add_child(platform)

	# Altar table on the platform
	var table := CSGBox3D.new()
	table.size = Vector3(3.0, 1.2, 1.5)
	table.position = Vector3(world_cx, platform_h + 0.6, world_cz)
	table.use_collision = true
	table.collision_layer = ENVIRONMENT_LAYER
	table.collision_mask = 0
	table.material = _mat_altar
	table.name = "AltarTable"
	_decorations_root.add_child(table)

	# Blood stain on top of altar
	var stain := CSGBox3D.new()
	stain.size = Vector3(2.0, 0.02, 1.0)
	stain.position = Vector3(world_cx, platform_h + 1.22, world_cz)
	stain.material = _mat_blood_stain
	stain.name = "AltarBloodStain"
	_decorations_root.add_child(stain)

# ---------------------------------------------------------------------------
# Decorations — Pews (rows of small benches)
# ---------------------------------------------------------------------------

func _build_pews() -> void:
	if not _nave:
		return
	var nx: int = _nave.x
	var ny: int = _nave.y
	var nw: int = _nave.w
	var nh: int = _nave.h

	# Pews in the lower two-thirds of the nave, in two blocks left and right of center aisle
	@warning_ignore("integer_division")
	var aisle_center_x: float = _grid_to_world_x(nx) + nw * CELL_SIZE * 0.5
	var pew_block_width: float = (nw * CELL_SIZE * 0.5) - CELL_SIZE * 4.0

	var idx: int = 0
	for row_y in range(ny + 8, ny + nh - 2, 2):
		var world_z: float = _grid_to_world_z(row_y) + CELL_SIZE * 0.5
		for side in [-1, 1]:
			var pew_cx: float = aisle_center_x + side * (CELL_SIZE * 2.0 + pew_block_width * 0.5)
			var pew := CSGBox3D.new()
			pew.size = Vector3(pew_block_width, 0.6, 0.8)
			pew.position = Vector3(pew_cx, 0.3, world_z)
			pew.use_collision = true
			pew.collision_layer = ENVIRONMENT_LAYER
			pew.collision_mask = 0
			pew.material = _mat_pew
			pew.name = "Pew_%d" % idx
			_decorations_root.add_child(pew)
			idx += 1

# ---------------------------------------------------------------------------
# Decorations — Blood channels along corridors
# ---------------------------------------------------------------------------

func _build_blood_channels() -> void:
	# Place thin red-glowing channel strips along corridor center lines
	var idx: int = 0
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			if _get_cell(x, y) != Cell.FLOOR:
				continue
			# Only place in corridor cells (not inside rooms)
			if _cell_inside_any_room(x, y):
				continue
			# Thin chance per cell so channels are sparse but present
			if _rng.randf() > 0.15:
				continue
			var channel := CSGBox3D.new()
			channel.size = Vector3(CELL_SIZE * 0.15, 0.04, CELL_SIZE * 0.9)
			channel.position = Vector3(
				_grid_to_world_x(x) + CELL_SIZE * 0.5,
				0.02,
				_grid_to_world_z(y) + CELL_SIZE * 0.5
			)
			channel.material = _mat_blood_channel
			channel.name = "BloodChannel_%d" % idx
			_decorations_root.add_child(channel)
			idx += 1

	# Also run channels along the nave aisle
	if _nave:
		var nave_cx: float = _grid_to_world_x(_nave.x) + _nave.w * CELL_SIZE * 0.5
		for row_y in range(_nave.y + 6, _nave.y + _nave.h - 1, 1):
			var channel := CSGBox3D.new()
			channel.size = Vector3(0.2, 0.04, CELL_SIZE * 0.95)
			channel.position = Vector3(nave_cx, 0.02, _grid_to_world_z(row_y) + CELL_SIZE * 0.5)
			channel.material = _mat_blood_channel
			channel.name = "NaveChannel_%d" % idx
			_decorations_root.add_child(channel)
			idx += 1


func _cell_inside_any_room(x: int, y: int) -> bool:
	for room: Rect2i_BSP in _rooms:
		if x >= room.x and x < room.x + room.w and y >= room.y and y < room.y + room.h:
			return true
	return false

# ---------------------------------------------------------------------------
# Decorations — Ritual circles
# ---------------------------------------------------------------------------

func _build_ritual_circles() -> void:
	var idx: int = 0
	for room: Rect2i_BSP in _ritual_rooms:
		var c := room.center()
		var world_x: float = _grid_to_world_x(c.x) + CELL_SIZE * 0.5
		var world_z: float = _grid_to_world_z(c.y) + CELL_SIZE * 0.5
		var circle_radius: float = mini(room.w, room.h) * CELL_SIZE * 0.3

		# Center glowing disc
		var disc := CSGCylinder3D.new()
		disc.radius = circle_radius * 0.35
		disc.height = 0.05
		disc.sides = 24
		disc.position = Vector3(world_x, 0.03, world_z)
		disc.material = _mat_ritual_glow
		disc.name = "RitualDisc_%d" % idx
		_decorations_root.add_child(disc)

		# Pedestals arranged in a circle
		var pedestal_count: int = _rng.randi_range(5, 8)
		for p in range(pedestal_count):
			var angle: float = (TAU / pedestal_count) * p
			var px: float = world_x + cos(angle) * circle_radius
			var pz: float = world_z + sin(angle) * circle_radius

			var pedestal := CSGCylinder3D.new()
			pedestal.radius = 0.3
			pedestal.height = 1.2
			pedestal.sides = 8
			pedestal.position = Vector3(px, 0.6, pz)
			pedestal.use_collision = true
			pedestal.collision_layer = ENVIRONMENT_LAYER
			pedestal.collision_mask = 0
			pedestal.material = _mat_pedestal
			pedestal.name = "RitualPedestal_%d_%d" % [idx, p]
			_decorations_root.add_child(pedestal)

		idx += 1

# ---------------------------------------------------------------------------
# Decorations — Sacrifice altars
# ---------------------------------------------------------------------------

func _build_sacrifice_altars() -> void:
	var idx: int = 0
	for room: Rect2i_BSP in _sacrifice_rooms:
		var c := room.center()
		var world_x: float = _grid_to_world_x(c.x) + CELL_SIZE * 0.5
		var world_z: float = _grid_to_world_z(c.y) + CELL_SIZE * 0.5

		# Single altar slab
		var altar := CSGBox3D.new()
		altar.size = Vector3(2.5, 1.0, 1.2)
		altar.position = Vector3(world_x, 0.5, world_z)
		altar.use_collision = true
		altar.collision_layer = ENVIRONMENT_LAYER
		altar.collision_mask = 0
		altar.material = _mat_altar
		altar.name = "SacrificeAltar_%d" % idx
		_decorations_root.add_child(altar)

		# Blood stain on floor around altar
		var stain := CSGBox3D.new()
		stain.size = Vector3(3.5, 0.02, 2.5)
		stain.position = Vector3(world_x, 0.01, world_z)
		stain.material = _mat_blood_stain
		stain.name = "SacrificeBlood_%d" % idx
		_decorations_root.add_child(stain)

		# Additional red floor patch behind altar
		var patch := CSGBox3D.new()
		patch.size = Vector3(2.0, 0.02, 1.5)
		patch.position = Vector3(world_x, 0.01, world_z - 1.5)
		patch.material = _mat_blood_channel
		patch.name = "SacrificePatch_%d" % idx
		_decorations_root.add_child(patch)

		idx += 1

# ---------------------------------------------------------------------------
# Decorations — Covered corridor archways
# ---------------------------------------------------------------------------

func _build_corridor_archways() -> void:
	var idx: int = 0
	for room: Rect2i_BSP in _side_rooms:
		var c := room.center()
		var nave_c := _nave.center()
		var dir := Vector2(nave_c.x - c.x, nave_c.y - c.y)

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

		# Posts
		for side in [-1, 1]:
			var post := CSGBox3D.new()
			post.size = Vector3(0.35, WALL_HEIGHT * 0.8, 0.35)
			post.position = Vector3(world_x + side * CELL_SIZE * 0.4, WALL_HEIGHT * 0.4, world_z)
			post.use_collision = true
			post.collision_layer = ENVIRONMENT_LAYER
			post.collision_mask = 0
			post.material = _mat_accent
			post.name = "CorridorPost_%d_%d" % [idx, side]
			_decorations_root.add_child(post)

		# Lintel
		var lintel := CSGBox3D.new()
		lintel.size = Vector3(CELL_SIZE * 0.85, 0.4, 0.4)
		lintel.position = Vector3(world_x, WALL_HEIGHT * 0.8, world_z)
		lintel.use_collision = true
		lintel.collision_layer = ENVIRONMENT_LAYER
		lintel.collision_mask = 0
		lintel.material = _mat_accent
		lintel.name = "CorridorLintel_%d" % idx
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
	env.background_color = Color(0.03, 0.005, 0.005)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.02, 0.02)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = RenderingServer.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.01, 0.01)
	env.fog_density = 0.015
	env.fog_light_energy = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	world_env.environment = env
	_lighting_root.add_child(world_env)

	# DirectionalLight — dim blood red
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "NaveLight"
	dir_light.light_color = Color(0.8, 0.15, 0.1)
	dir_light.light_energy = 0.35
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-50, -25, 0)
	_lighting_root.add_child(dir_light)

	# Strong red OmniLights near ritual circles
	for room: Rect2i_BSP in _ritual_rooms:
		var c := room.center()
		var light := OmniLight3D.new()
		light.light_color = Color(0.95, 0.08, 0.03)
		var base_energy: float = _rng.randf_range(2.0, 3.5)
		light.light_energy = base_energy
		light.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.8
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(c.x) + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			_grid_to_world_z(c.y) + CELL_SIZE * 0.5
		)
		light.name = "RitualLight_%d_%d" % [c.x, c.y]
		_lighting_root.add_child(light)

		# Register for pulsing effect
		_pulsing_lights.append({
			"light": light,
			"base_energy": base_energy,
			"pulse_speed": _rng.randf_range(1.5, 3.0),
		})

	# Altar light (strong, pulsing)
	if _nave:
		var nc := _nave.center()
		var altar_light := OmniLight3D.new()
		altar_light.light_color = Color(1.0, 0.1, 0.05)
		var altar_base: float = 3.0
		altar_light.light_energy = altar_base
		altar_light.omni_range = CELL_SIZE * 10.0
		altar_light.omni_attenuation = 1.2
		altar_light.shadow_enabled = true
		altar_light.position = Vector3(
			_grid_to_world_x(_nave.x) + _nave.w * CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.6,
			_grid_to_world_z(_nave.y) + CELL_SIZE * 3.0
		)
		altar_light.name = "AltarLight"
		_lighting_root.add_child(altar_light)
		_pulsing_lights.append({
			"light": altar_light,
			"base_energy": altar_base,
			"pulse_speed": 2.0,
		})

	# Nave hall lights along columns
	if _nave:
		var nx: int = _nave.x
		var ny: int = _nave.y
		var nw: int = _nave.w
		var nh: int = _nave.h
		for row_y in range(ny + 2, ny + nh - 2, 5):
			for col_offset in [3, nw - 4]:
				var light := OmniLight3D.new()
				light.light_color = Color(
					_rng.randf_range(0.7, 1.0),
					_rng.randf_range(0.04, 0.1),
					_rng.randf_range(0.02, 0.06)
				)
				light.light_energy = _rng.randf_range(1.0, 1.8)
				light.omni_range = CELL_SIZE * 5.0
				light.omni_attenuation = 1.8
				light.shadow_enabled = false
				light.position = Vector3(
					_grid_to_world_x(nx + col_offset) + CELL_SIZE * 0.5,
					WALL_HEIGHT * 0.65,
					_grid_to_world_z(row_y) + CELL_SIZE * 0.5
				)
				light.name = "NaveColLight_%d_%d" % [col_offset, row_y]
				_lighting_root.add_child(light)

	# Dim lights in sacrifice chambers
	for room: Rect2i_BSP in _sacrifice_rooms:
		var c := room.center()
		var light := OmniLight3D.new()
		light.light_color = Color(0.8, 0.05, 0.02)
		light.light_energy = _rng.randf_range(0.6, 1.2)
		light.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.6
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(c.x) + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			_grid_to_world_z(c.y) + CELL_SIZE * 0.5
		)
		light.name = "SacrificeLight_%d_%d" % [c.x, c.y]
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

	# Enemy spawns across arena and side rooms
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

	# Spawns in sacrifice rooms
	for room: Rect2i_BSP in _sacrifice_rooms:
		var c := room.center()
		_enemy_spawns.append(Vector3(
			_grid_to_world_x(c.x) + CELL_SIZE * 0.5,
			0.5,
			_grid_to_world_z(c.y) + CELL_SIZE * 0.5
		))
		# A few more around altar
		for i in range(2):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Remaining side rooms
	for room: Rect2i_BSP in _side_rooms:
		if room in _arena_rooms or room in _sacrifice_rooms:
			continue
		if room == _entrance_room:
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
