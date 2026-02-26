extends Node3D
## Level 2: The Dead Works
## An industrial complex with multiple separate buildings connected by outdoor
## corridors. Features multi-story buildings, puzzle markers, secret areas,
## and heavy machinery props. Uses BSP for building interiors.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 70
const GRID_HEIGHT: int = 70
const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 5.0

const MIN_PARTITION_SIZE: int = 8
const MAX_PARTITION_SIZE: int = 25
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 5
const ARENA_THRESHOLD: int = 10
const CORRIDOR_WIDTH: int = 2

const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 25
const MIN_ARENA_SPAWNS: int = 3

const BUILDING_COUNT_MIN: int = 4
const BUILDING_COUNT_MAX: int = 6
const SECOND_FLOOR_HEIGHT: float = 5.0
const PUZZLE_DOOR_COUNT: int = 3
const SECRET_ROOM_COUNT: int = 2

# ---------------------------------------------------------------------------
# Cell types
# ---------------------------------------------------------------------------

enum Cell {
	VOID = 0,
	FLOOR = 1,
	WALL = 2,
	OUTDOOR = 3,
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
var _buildings: Array = []  # Array of Rect2i_BSP — building footprints
var _building_rooms: Array = []  # Array of Array[Rect2i_BSP] — rooms per building
var _second_floor_buildings: Array = []  # Indices of buildings with 2nd floors
var _puzzle_doors: Array = []  # Array of {pos: Vector3, color: Color}
var _secret_rooms: Array = []  # Array of Rect2i_BSP
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
var _mat_outdoor: StandardMaterial3D = null
var _mat_rust: StandardMaterial3D = null
var _mat_metal: StandardMaterial3D = null
var _mat_crate: StandardMaterial3D = null
var _mat_pipe: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value

	_create_materials()
	_init_grid()

	# Place buildings on the grid
	_place_buildings()

	# BSP each building's interior
	for i in range(_buildings.size()):
		_generate_building_interior(i)

	# Connect buildings with outdoor corridors
	_connect_buildings()

	# Build walls around carved floor cells
	_build_walls()

	# Classify rooms
	_classify_rooms()

	# Place puzzle doors and secret rooms
	_place_puzzles()
	_place_secrets()

	# Build 3D geometry
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_build_geometry()
	_build_machinery()
	_build_puzzle_elements()
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
	_buildings.clear()
	_building_rooms.clear()
	_second_floor_buildings.clear()
	_puzzle_doors.clear()
	_secret_rooms.clear()
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
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
	return cell == Cell.FLOOR or cell == Cell.OUTDOOR

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Concrete floor
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.12, 0.1, 0.1)
	_mat_floor.roughness = 0.9
	_mat_floor.metallic = 0.05

	# Metal walls
	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.15, 0.13, 0.12)
	_mat_wall.roughness = 0.8
	_mat_wall.metallic = 0.15

	# Ceiling (darker)
	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.08, 0.07, 0.06)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

	# Outdoor floor
	_mat_outdoor = StandardMaterial3D.new()
	_mat_outdoor.albedo_color = Color(0.1, 0.09, 0.08)
	_mat_outdoor.roughness = 0.95
	_mat_outdoor.metallic = 0.0

	# Rust accent
	_mat_rust = StandardMaterial3D.new()
	_mat_rust.albedo_color = Color(0.7, 0.4, 0.1)
	_mat_rust.roughness = 0.85
	_mat_rust.metallic = 0.2

	# Metal prop
	_mat_metal = StandardMaterial3D.new()
	_mat_metal.albedo_color = Color(0.2, 0.2, 0.22)
	_mat_metal.roughness = 0.6
	_mat_metal.metallic = 0.4

	# Crate
	_mat_crate = StandardMaterial3D.new()
	_mat_crate.albedo_color = Color(0.25, 0.2, 0.12)
	_mat_crate.roughness = 0.85
	_mat_crate.metallic = 0.05

	# Pipe
	_mat_pipe = StandardMaterial3D.new()
	_mat_pipe.albedo_color = Color(0.3, 0.25, 0.2)
	_mat_pipe.roughness = 0.7
	_mat_pipe.metallic = 0.3

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
# Building placement
# ---------------------------------------------------------------------------

func _place_buildings() -> void:
	_buildings.clear()
	_building_rooms.clear()
	var count := _rng.randi_range(BUILDING_COUNT_MIN, BUILDING_COUNT_MAX)

	# Divide grid into zones for buildings with some spacing
	var zone_w := GRID_WIDTH / 3
	var zone_h := GRID_HEIGHT / 2
	var zones: Array = []
	for zx in range(3):
		for zy in range(2):
			zones.append(Vector2i(zx * zone_w + 2, zy * zone_h + 2))

	# Shuffle zones
	for i in range(zones.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = zones[i]
		zones[i] = zones[j]
		zones[j] = tmp

	for i in range(mini(count, zones.size())):
		var zone_pos: Vector2i = zones[i]
		var bw := _rng.randi_range(10, mini(18, zone_w - 4))
		var bh := _rng.randi_range(10, mini(18, zone_h - 4))
		var bx := zone_pos.x + _rng.randi_range(0, maxi(0, zone_w - bw - 4))
		var by := zone_pos.y + _rng.randi_range(0, maxi(0, zone_h - bh - 4))
		bx = clampi(bx, 1, GRID_WIDTH - bw - 1)
		by = clampi(by, 1, GRID_HEIGHT - bh - 1)

		var building := Rect2i_BSP.new(bx, by, bw, bh)
		_buildings.append(building)
		_building_rooms.append([])

	# Select 2+ buildings for second floors
	_second_floor_buildings.clear()
	var sf_count := mini(2 + (_rng.randi() % 2), _buildings.size())
	var indices: Array = []
	for i in range(_buildings.size()):
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	for i in range(sf_count):
		_second_floor_buildings.append(indices[i])

# ---------------------------------------------------------------------------
# Building interior BSP
# ---------------------------------------------------------------------------

func _generate_building_interior(building_idx: int) -> void:
	var bldg: Rect2i_BSP = _buildings[building_idx]

	# Carve the whole building footprint as floor
	for x in range(bldg.x, bldg.x + bldg.w):
		for y in range(bldg.y, bldg.y + bldg.h):
			_set_cell(x, y, Cell.FLOOR)

	# BSP the interior to create rooms
	var root := BSPNode.new(Rect2i_BSP.new(bldg.x, bldg.y, bldg.w, bldg.h))
	_split_building_bsp(root, 0)
	_create_building_rooms(root, building_idx)
	_connect_building_rooms(root)


func _split_building_bsp(node: BSPNode, depth: int) -> void:
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

	_split_building_bsp(node.left, depth + 1)
	_split_building_bsp(node.right, depth + 1)


func _create_building_rooms(node: BSPNode, building_idx: int) -> void:
	if node.is_leaf():
		var rw := _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN * 2),
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		)
		var rh := _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN * 2),
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)
		)
		rw = clampi(rw, MIN_ROOM_SIZE, node.rect.w - 1)
		rh = clampi(rh, MIN_ROOM_SIZE, node.rect.h - 1)

		var rx := node.rect.x + _rng.randi_range(0, maxi(0, node.rect.w - rw - 1))
		var ry := node.rect.y + _rng.randi_range(0, maxi(0, node.rect.h - rh - 1))
		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)
		_building_rooms[building_idx].append(node.room)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left:
		_create_building_rooms(node.left, building_idx)
	if node.right:
		_create_building_rooms(node.right, building_idx)


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


func _connect_building_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		return
	if node.left:
		_connect_building_rooms(node.left)
	if node.right:
		_connect_building_rooms(node.right)
	if node.left and node.right:
		var room_a := _get_room(node.left)
		var room_b := _get_room(node.right)
		if room_a and room_b:
			_carve_corridor(room_a.center(), room_b.center())

# ---------------------------------------------------------------------------
# Building connection via outdoor corridors
# ---------------------------------------------------------------------------

func _connect_buildings() -> void:
	if _buildings.size() < 2:
		return

	# Connect each building to the next in a chain
	for i in range(_buildings.size() - 1):
		var a: Rect2i_BSP = _buildings[i]
		var b: Rect2i_BSP = _buildings[i + 1]
		_carve_outdoor_corridor(a.center(), b.center())

	# Also connect last to first for a loop
	if _buildings.size() > 2:
		var a: Rect2i_BSP = _buildings[_buildings.size() - 1]
		var b: Rect2i_BSP = _buildings[0]
		_carve_outdoor_corridor(a.center(), b.center())


func _carve_outdoor_corridor(from: Vector2i, to: Vector2i) -> void:
	var go_horizontal_first := _rng.randf() < 0.5
	if go_horizontal_first:
		_carve_outdoor_horizontal(from.x, to.x, from.y)
		_carve_outdoor_vertical(from.y, to.y, to.x)
	else:
		_carve_outdoor_vertical(from.y, to.y, from.x)
		_carve_outdoor_horizontal(from.x, to.x, to.y)


func _carve_outdoor_horizontal(x1: int, x2: int, y: int) -> void:
	var start_x := mini(x1, x2)
	var end_x := maxi(x1, x2)
	for x in range(start_x, end_x + 1):
		for dy in range(CORRIDOR_WIDTH):
			var cy := y + dy
			var cell := _get_cell(x, cy)
			if cell == Cell.VOID:
				_set_cell(x, cy, Cell.OUTDOOR)


func _carve_outdoor_vertical(y1: int, y2: int, x: int) -> void:
	var start_y := mini(y1, y2)
	var end_y := maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx := x + dx
			var cell := _get_cell(cx, y)
			if cell == Cell.VOID:
				_set_cell(cx, y, Cell.OUTDOOR)

# ---------------------------------------------------------------------------
# Interior corridors
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
			if _get_cell(x, cy) == Cell.VOID:
				_set_cell(x, cy, Cell.FLOOR)


func _carve_vertical(y1: int, y2: int, x: int) -> void:
	var start_y := mini(y1, y2)
	var end_y := maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx := x + dx
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
			var c := _get_cell(x + dx, y + dy)
			if c == Cell.FLOOR or c == Cell.OUTDOOR:
				return true
	return false

# ---------------------------------------------------------------------------
# Room classification
# ---------------------------------------------------------------------------

func _classify_rooms() -> void:
	_arena_rooms.clear()
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
# Puzzles and secrets
# ---------------------------------------------------------------------------

func _place_puzzles() -> void:
	_puzzle_doors.clear()
	var colors := [Color(1, 0.2, 0.2), Color(0.2, 0.8, 0.2), Color(0.2, 0.3, 1.0)]
	var placed := 0
	for room: Rect2i_BSP in _rooms:
		if placed >= PUZZLE_DOOR_COUNT:
			break
		if room.w < 6 or room.h < 6:
			continue
		# Place "locked door" on one wall edge
		var door_x := room.x + room.w - 1
		var door_y := room.y + room.h / 2
		_puzzle_doors.append({
			"grid_pos": Vector2i(door_x, door_y),
			"color": colors[placed % colors.size()],
			"switch_pos": Vector2i(room.x + 1, room.y + 1),
		})
		placed += 1


func _place_secrets() -> void:
	_secret_rooms.clear()
	var placed := 0
	for room: Rect2i_BSP in _rooms:
		if placed >= SECRET_ROOM_COUNT:
			break
		if room.w < 8 or room.h < 8:
			continue
		# Carve a small hidden room adjacent to this room
		var sx := room.x + room.w + 1
		var sy := room.y + 1
		if sx + 4 < GRID_WIDTH and sy + 4 < GRID_HEIGHT:
			var secret := Rect2i_BSP.new(sx, sy, 4, 4)
			_secret_rooms.append(secret)
			for x in range(sx, sx + 4):
				for y in range(sy, sy + 4):
					_set_cell(x, y, Cell.FLOOR)
			# Thin wall gap (1 cell connector)
			_set_cell(sx - 1, sy + 2, Cell.FLOOR)
			placed += 1

# ---------------------------------------------------------------------------
# Geometry building
# ---------------------------------------------------------------------------

func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE


func _build_geometry() -> void:
	# Indoor floors
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		_create_box(strip, -0.1, 0.2, _mat_floor, "Floor")

	# Outdoor corridor floors
	var outdoor_strips := _build_horizontal_strips(Cell.OUTDOOR)
	for strip: Rect2i_BSP in outdoor_strips:
		_create_box(strip, -0.1, 0.2, _mat_outdoor, "Outdoor")

	# Walls
	var wall_strips := _build_horizontal_strips(Cell.WALL)
	for strip: Rect2i_BSP in wall_strips:
		_create_wall_box(strip)

	# Ceilings (only inside buildings, not outdoor corridors)
	for strip: Rect2i_BSP in floor_strips:
		if _strip_in_any_building(strip):
			_create_ceiling_box(strip)

	# Second floors for selected buildings
	for idx in _second_floor_buildings:
		if idx < _buildings.size():
			_build_second_floor(idx)


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


func _create_box(strip: Rect2i_BSP, y_pos: float, height: float, mat: StandardMaterial3D, prefix: String) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(strip.w * CELL_SIZE, height, strip.h * CELL_SIZE)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		y_pos,
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


func _strip_in_any_building(strip: Rect2i_BSP) -> bool:
	for bldg: Rect2i_BSP in _buildings:
		if strip.x >= bldg.x and strip.x + strip.w <= bldg.x + bldg.w \
			and strip.y >= bldg.y and strip.y + strip.h <= bldg.y + bldg.h:
			return true
	return false

# ---------------------------------------------------------------------------
# Second floors
# ---------------------------------------------------------------------------

func _build_second_floor(building_idx: int) -> void:
	var bldg: Rect2i_BSP = _buildings[building_idx]
	var bx := _grid_to_world_x(bldg.x)
	var bz := _grid_to_world_z(bldg.y)
	var bw := bldg.w * CELL_SIZE
	var bh := bldg.h * CELL_SIZE

	# Second floor platform
	var sf := CSGBox3D.new()
	sf.size = Vector3(bw, 0.3, bh)
	sf.position = Vector3(bx + bw * 0.5, SECOND_FLOOR_HEIGHT, bz + bh * 0.5)
	sf.use_collision = true
	sf.collision_layer = ENVIRONMENT_LAYER
	sf.collision_mask = 0
	sf.material = _mat_floor
	sf.name = "SecondFloor_%d" % building_idx
	_geometry_root.add_child(sf)

	# Railing / short walls on second floor edges
	var railing_h := 1.2
	# North
	var rn := CSGBox3D.new()
	rn.size = Vector3(bw, railing_h, 0.3)
	rn.position = Vector3(bx + bw * 0.5, SECOND_FLOOR_HEIGHT + railing_h * 0.5, bz)
	rn.use_collision = true
	rn.collision_layer = ENVIRONMENT_LAYER
	rn.collision_mask = 0
	rn.material = _mat_metal
	rn.name = "Railing_N_%d" % building_idx
	_geometry_root.add_child(rn)
	# South
	var rs := CSGBox3D.new()
	rs.size = Vector3(bw, railing_h, 0.3)
	rs.position = Vector3(bx + bw * 0.5, SECOND_FLOOR_HEIGHT + railing_h * 0.5, bz + bh)
	rs.use_collision = true
	rs.collision_layer = ENVIRONMENT_LAYER
	rs.collision_mask = 0
	rs.material = _mat_metal
	rs.name = "Railing_S_%d" % building_idx
	_geometry_root.add_child(rs)

	# Upper ceiling
	var uc := CSGBox3D.new()
	uc.size = Vector3(bw, 0.2, bh)
	uc.position = Vector3(bx + bw * 0.5, SECOND_FLOOR_HEIGHT + WALL_HEIGHT + 0.1, bz + bh * 0.5)
	uc.use_collision = true
	uc.collision_layer = ENVIRONMENT_LAYER
	uc.collision_mask = 0
	uc.material = _mat_ceiling
	uc.name = "UpperCeiling_%d" % building_idx
	_geometry_root.add_child(uc)

	# Ramp to access second floor
	var ramp_length := CELL_SIZE * 5.0
	var ramp := CSGBox3D.new()
	ramp.size = Vector3(CELL_SIZE * 2.0, 0.3, ramp_length)
	var ramp_angle := atan2(SECOND_FLOOR_HEIGHT, ramp_length)
	ramp.position = Vector3(
		bx + CELL_SIZE * 2.0,
		SECOND_FLOOR_HEIGHT * 0.5,
		bz + bh - ramp_length * 0.5 - 1.0
	)
	ramp.rotation.x = -ramp_angle
	ramp.use_collision = true
	ramp.collision_layer = ENVIRONMENT_LAYER
	ramp.collision_mask = 0
	ramp.material = _mat_metal
	ramp.name = "Ramp_%d" % building_idx
	_geometry_root.add_child(ramp)

# ---------------------------------------------------------------------------
# Machinery props
# ---------------------------------------------------------------------------

func _build_machinery() -> void:
	# Place crates, pipes, and tanks in buildings
	for i in range(_buildings.size()):
		var bldg: Rect2i_BSP = _buildings[i]
		var bx := _grid_to_world_x(bldg.x)
		var bz := _grid_to_world_z(bldg.y)
		var bw := bldg.w * CELL_SIZE
		var bh := bldg.h * CELL_SIZE

		# Crate clusters
		var crate_count := _rng.randi_range(3, 8)
		for c in range(crate_count):
			var cx := bx + _rng.randf_range(2.0, bw - 2.0)
			var cz := bz + _rng.randf_range(2.0, bh - 2.0)
			var cs := _rng.randf_range(0.8, 2.0)
			var crate := CSGBox3D.new()
			crate.size = Vector3(cs, cs, cs)
			crate.position = Vector3(cx, cs * 0.5, cz)
			crate.use_collision = true
			crate.collision_layer = ENVIRONMENT_LAYER
			crate.collision_mask = 0
			crate.material = _mat_crate
			crate.name = "Crate_%d_%d" % [i, c]
			_geometry_root.add_child(crate)

		# Pipes along walls
		var pipe_count := _rng.randi_range(1, 3)
		for p in range(pipe_count):
			var px := bx + _rng.randf_range(1.0, bw - 1.0)
			var pz := bz + (0.5 if _rng.randf() < 0.5 else bh - 0.5)
			var pipe := CSGCylinder3D.new()
			pipe.radius = _rng.randf_range(0.15, 0.35)
			pipe.height = bw * _rng.randf_range(0.3, 0.7)
			pipe.sides = 8
			pipe.position = Vector3(px, WALL_HEIGHT * 0.7, pz)
			pipe.rotation_degrees.z = 90.0
			pipe.material = _mat_pipe
			pipe.use_collision = false
			pipe.name = "Pipe_%d_%d" % [i, p]
			_geometry_root.add_child(pipe)

		# Large tanks (cylinders)
		if _rng.randf() < 0.6:
			var tx := bx + _rng.randf_range(3.0, bw - 3.0)
			var tz := bz + _rng.randf_range(3.0, bh - 3.0)
			var tank := CSGCylinder3D.new()
			tank.radius = _rng.randf_range(1.0, 2.0)
			tank.height = _rng.randf_range(3.0, WALL_HEIGHT - 0.5)
			tank.sides = 12
			tank.position = Vector3(tx, tank.height * 0.5, tz)
			tank.material = _mat_metal
			tank.use_collision = true
			tank.collision_layer = ENVIRONMENT_LAYER
			tank.collision_mask = 0
			tank.name = "Tank_%d" % i
			_geometry_root.add_child(tank)

# ---------------------------------------------------------------------------
# Puzzle elements
# ---------------------------------------------------------------------------

func _build_puzzle_elements() -> void:
	for i in range(_puzzle_doors.size()):
		var pd: Dictionary = _puzzle_doors[i]
		var door_pos := pd["grid_pos"] as Vector2i
		var col := pd["color"] as Color
		var switch_pos := pd["switch_pos"] as Vector2i

		# "Locked door" — a brightly colored wall section
		var door := CSGBox3D.new()
		door.size = Vector3(CELL_SIZE, WALL_HEIGHT, 0.5)
		door.position = Vector3(
			_grid_to_world_x(door_pos.x) + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			_grid_to_world_z(door_pos.y) + CELL_SIZE * 0.5
		)
		var door_mat := StandardMaterial3D.new()
		door_mat.albedo_color = col
		door_mat.emission_enabled = true
		door_mat.emission = col * 0.5
		door_mat.emission_energy_multiplier = 0.8
		door_mat.roughness = 0.5
		door.material = door_mat
		door.use_collision = true
		door.collision_layer = ENVIRONMENT_LAYER
		door.collision_mask = 0
		door.name = "PuzzleDoor_%d" % i
		_geometry_root.add_child(door)

		# "Switch" near the door — small box
		var sw := CSGBox3D.new()
		sw.size = Vector3(0.5, 0.5, 0.5)
		sw.position = Vector3(
			_grid_to_world_x(switch_pos.x) + CELL_SIZE * 0.5,
			1.2,
			_grid_to_world_z(switch_pos.y) + CELL_SIZE * 0.5
		)
		var sw_mat := StandardMaterial3D.new()
		sw_mat.albedo_color = col
		sw_mat.emission_enabled = true
		sw_mat.emission = col
		sw_mat.emission_energy_multiplier = 1.5
		sw.material = sw_mat
		sw.use_collision = true
		sw.collision_layer = ENVIRONMENT_LAYER
		sw.collision_mask = 0
		sw.name = "PuzzleSwitch_%d" % i
		_geometry_root.add_child(sw)

		# Visual cue sphere near switch
		var sphere := CSGSphere3D.new()
		sphere.radius = 0.25
		sphere.position = Vector3(
			_grid_to_world_x(switch_pos.x) + CELL_SIZE * 0.5,
			2.0,
			_grid_to_world_z(switch_pos.y) + CELL_SIZE * 0.5
		)
		var sphere_mat := StandardMaterial3D.new()
		sphere_mat.albedo_color = col
		sphere_mat.emission_enabled = true
		sphere_mat.emission = col
		sphere_mat.emission_energy_multiplier = 2.0
		sphere.material = sphere_mat
		sphere.use_collision = false
		sphere.name = "PuzzleCue_%d" % i
		_geometry_root.add_child(sphere)

		# Warning light near the door
		var warning := OmniLight3D.new()
		warning.name = "WarningLight_%d" % i
		warning.light_color = Color(1.0, 0.8, 0.0)
		warning.light_energy = 1.5
		warning.omni_range = 8.0
		warning.omni_attenuation = 1.5
		warning.shadow_enabled = false
		warning.position = Vector3(
			_grid_to_world_x(door_pos.x) + CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.8,
			_grid_to_world_z(door_pos.y) + CELL_SIZE * 0.5
		)
		_lighting_root.add_child(warning)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.02)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.15, 0.1)
	env.ambient_light_energy = 0.35

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.06, 0.03)
	env.fog_density = 0.015
	env.fog_light_energy = 0.5

	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Directional light — industrial warm
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = Color(0.8, 0.5, 0.2)
	dir_light.light_energy = 0.45
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-40, -30, 0)
	_lighting_root.add_child(dir_light)

	# Orange lights inside buildings
	for i in range(_buildings.size()):
		var bldg: Rect2i_BSP = _buildings[i]
		var center := bldg.center()
		var light := OmniLight3D.new()
		light.name = "BuildingLight_%d" % i
		light.light_color = Color(0.9, 0.5, 0.15)
		light.light_energy = _rng.randf_range(1.5, 2.5)
		light.omni_range = maxi(bldg.w, bldg.h) * CELL_SIZE * 0.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(center.x), WALL_HEIGHT * 0.7, _grid_to_world_z(center.y)
		)
		_lighting_root.add_child(light)

		# Additional interior room lights
		if i < _building_rooms.size():
			for room: Rect2i_BSP in _building_rooms[i]:
				if _rng.randf() < 0.6:
					var rc := room.center()
					var rl := OmniLight3D.new()
					rl.name = "RoomLight_%d_%d" % [rc.x, rc.y]
					rl.light_color = Color(
						_rng.randf_range(0.7, 1.0),
						_rng.randf_range(0.3, 0.6),
						_rng.randf_range(0.05, 0.2)
					)
					rl.light_energy = _rng.randf_range(0.8, 1.5)
					rl.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.7
					rl.omni_attenuation = 1.8
					rl.shadow_enabled = false
					rl.position = Vector3(
						_grid_to_world_x(rc.x), WALL_HEIGHT * 0.6, _grid_to_world_z(rc.y)
					)
					_lighting_root.add_child(rl)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns in the smallest room of the first building
	var spawn_room: Rect2i_BSP = null
	if _building_rooms.size() > 0 and _building_rooms[0].size() > 0:
		var rooms_copy: Array = _building_rooms[0].duplicate()
		rooms_copy.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
			return (a.w * a.h) < (b.w * b.h)
		)
		spawn_room = rooms_copy[0]
	else:
		spawn_room = _rooms[0]

	var sc: Vector2i = spawn_room.center()
	_player_spawn = Vector3(
		_grid_to_world_x(sc.x), 0.5, _grid_to_world_z(sc.y)
	)

	# Enemy spawns in arena rooms
	for room: Rect2i_BSP in _arena_rooms:
		var area: int = room.w * room.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			var c := _get_cell(sx, sy)
			if c == Cell.FLOOR or c == Cell.OUTDOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Also some spawns in non-arena rooms
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms or room == spawn_room:
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
		for room: Rect2i_BSP in _rooms:
			var center := room.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(center.x), 0.5, _grid_to_world_z(center.y)
			))
