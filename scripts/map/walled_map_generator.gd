extends Node3D
## Unified WALLED map generator for indoor levels.
## Reads level configuration from GameManager.current_level_data.
##
## Features:
##   - BSP room + corridor generation
##   - Full walls and ceiling (indoor feel)
##   - Doors placed at corridor chokepoints (some locked)
##   - Keys scattered in rooms (auto-collected when walked over)
##   - Locked doors auto-open when player carries the matching key
##   - Random item scatter (health, ammo, gold pickups) in rooms
##   - Level-themed materials (industrial, cave, temple variants)

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


## Stores info about a placed door
class DoorInfo:
	var world_pos: Vector3
	var is_locked: bool
	var key_id: int        ## Which key unlocks this door
	var door_node: Node3D  ## The 3D door object

	func _init(pos: Vector3, locked: bool, kid: int) -> void:
		world_pos = pos
		is_locked = locked
		key_id = kid
		door_node = null

# ---------------------------------------------------------------------------
# Cell types
# ---------------------------------------------------------------------------

enum Cell { VOID = 0, FLOOR = 1, WALL = 2, CORRIDOR = 3, DOOR = 4 }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CELL_SIZE: float = 4.0
const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 22
const MIN_ARENA_SPAWNS: int = 3
const ARENA_THRESHOLD: int = 10
const MIN_PARTITION_SIZE: int = 8
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 5
const CORRIDOR_WIDTH: int = 2
const INTERACTABLE_LAYER: int = 32  ## Bit 5

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _grid: Array = []
var _rooms: Array = []
var _arena_rooms: Array = []
var _corridor_midpoints: Array[Vector2i] = []  ## Candidate door positions
var _doors: Array = []                          ## Array of DoorInfo
var _key_positions: Array[Vector3] = []         ## World positions of key pickups
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null
var _interactive_root: Node3D = null  ## Doors, keys

# Config
var _grid_size: int = 64
var _prop_type: String = "industrial"
var _door_density: float = 0.45
var _lock_density: float = 0.35
var _item_scatter_density: float = 0.06
var _wall_height: float = 4.0

# Materials
var _mat_wall: StandardMaterial3D = null
var _mat_floor: StandardMaterial3D = null
var _mat_corridor_floor: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_door_open: StandardMaterial3D = null
var _mat_door_locked: StandardMaterial3D = null
var _mat_key: StandardMaterial3D = null
var _mat_prop: StandardMaterial3D = null
var _mat_item_health: StandardMaterial3D = null
var _mat_item_ammo: StandardMaterial3D = null
var _mat_item_gold: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value
	_load_config()
	_create_materials()
	_init_grid()

	var root := BSPNode.new(Rect2i_BSP.new(0, 0, _grid_size, _grid_size))
	_split_bsp(root, 0)
	_create_rooms(root)
	_connect_rooms(root)
	_build_walls()
	_classify_rooms()
	_find_door_candidates()

	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_interactive_root = Node3D.new()
	_interactive_root.name = "MapInteractives"
	add_child(_interactive_root)

	_build_geometry()
	_build_doors()
	_build_keys()
	_scatter_items()
	_build_props()
	_build_environment()

	_determine_spawn_points()


func get_player_spawn() -> Vector3:
	return _player_spawn


func get_enemy_spawn_points() -> Array[Vector3]:
	return _enemy_spawns


func clear_map() -> void:
	if _geometry_root and is_instance_valid(_geometry_root):
		_geometry_root.queue_free(); _geometry_root = null
	if _lighting_root and is_instance_valid(_lighting_root):
		_lighting_root.queue_free(); _lighting_root = null
	if _interactive_root and is_instance_valid(_interactive_root):
		_interactive_root.queue_free(); _interactive_root = null

	_grid.clear(); _rooms.clear(); _arena_rooms.clear()
	_corridor_midpoints.clear(); _doors.clear(); _key_positions.clear()
	_enemy_spawns.clear(); _player_spawn = Vector3.ZERO


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var c := room.center()
		data.append({
			"position": Vector3(_grid_to_world_x(c.x), 0.0, _grid_to_world_z(c.y)),
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
	var c := _get_cell(gx, gy)
	return c == Cell.FLOOR or c == Cell.CORRIDOR

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

func _load_config() -> void:
	var level_data: Dictionary = GameManager.current_level_data

	var cfg: Dictionary = level_data.get("map_config", {})
	_grid_size = cfg.get("grid_size", 64)
	_prop_type = cfg.get("prop_type", "industrial")
	_door_density = cfg.get("door_density", 0.45)
	_lock_density = cfg.get("lock_density", 0.35)
	_item_scatter_density = cfg.get("item_scatter_density", 0.06)
	_wall_height = level_data.get("wall_height", 4.0)

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	match _prop_type:
		"cave":
			_mat_wall = _make_mat(Color(0.10, 0.07, 0.12), 0.95)
			_mat_floor = _make_mat(Color(0.08, 0.06, 0.10), 0.90)
			_mat_corridor_floor = _make_mat(Color(0.07, 0.05, 0.09), 0.92)
			_mat_ceiling = _make_mat(Color(0.05, 0.03, 0.07), 1.0)
			_mat_prop = _make_mat(Color(0.12, 0.08, 0.15), 0.85)
		"temple", "temple_final":
			_mat_wall = _make_mat(Color(0.14, 0.05, 0.14), 0.80)
			_mat_floor = _make_mat(Color(0.10, 0.04, 0.10), 0.85)
			_mat_corridor_floor = _make_mat(Color(0.08, 0.03, 0.08), 0.88)
			_mat_ceiling = _make_mat(Color(0.04, 0.01, 0.04), 1.0)
			_mat_prop = _make_mat(Color(0.20, 0.06, 0.20), 0.70)
		_:  # industrial
			_mat_wall = _make_mat(Color(0.15, 0.13, 0.12), 0.85, true, 0.1)
			_mat_floor = _make_mat(Color(0.12, 0.10, 0.10), 0.90)
			_mat_corridor_floor = _make_mat(Color(0.10, 0.08, 0.08), 0.92)
			_mat_ceiling = _make_mat(Color(0.08, 0.07, 0.06), 0.95)
			_mat_prop = _make_mat(Color(0.18, 0.15, 0.10), 0.75, true, 0.15)

	_mat_door_open = _make_mat(Color(0.3, 0.2, 0.1), 0.70)
	_mat_door_open.albedo_color = Color(0.3, 0.2, 0.1)

	_mat_door_locked = _make_mat(Color(0.5, 0.05, 0.02), 0.65, false, 0.0)
	_mat_door_locked.emission_enabled = true
	_mat_door_locked.emission = Color(0.4, 0.04, 0.02)
	_mat_door_locked.emission_energy_multiplier = 0.8

	_mat_key = _make_mat(Color(0.9, 0.75, 0.1), 0.30)
	_mat_key.emission_enabled = true
	_mat_key.emission = Color(0.7, 0.55, 0.05)
	_mat_key.emission_energy_multiplier = 1.0

	_mat_item_health = _make_mat(Color(0.2, 0.8, 0.2), 0.40)
	_mat_item_health.emission_enabled = true
	_mat_item_health.emission = Color(0.1, 0.6, 0.1)
	_mat_item_health.emission_energy_multiplier = 0.8

	_mat_item_ammo = _make_mat(Color(0.8, 0.6, 0.1), 0.40)
	_mat_item_ammo.emission_enabled = true
	_mat_item_ammo.emission = Color(0.6, 0.4, 0.05)
	_mat_item_ammo.emission_energy_multiplier = 0.7

	_mat_item_gold = _make_mat(Color(1.0, 0.85, 0.1), 0.20, false)
	_mat_item_gold.metallic = 0.8
	_mat_item_gold.emission_enabled = true
	_mat_item_gold.emission = Color(0.8, 0.65, 0.05)
	_mat_item_gold.emission_energy_multiplier = 0.6


func _make_mat(color: Color, roughness: float, metal: bool = false, metallic_val: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if metal:
		m.metallic = metallic_val
	return m

# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

func _init_grid() -> void:
	_grid.resize(_grid_size)
	for x in range(_grid_size):
		var col: Array = []
		col.resize(_grid_size)
		col.fill(Cell.VOID)
		_grid[x] = col


func _set_cell(x: int, y: int, v: int) -> void:
	if x >= 0 and x < _grid_size and y >= 0 and y < _grid_size:
		_grid[x][y] = v


func _get_cell(x: int, y: int) -> int:
	if x >= 0 and x < _grid_size and y >= 0 and y < _grid_size:
		return _grid[x][y]
	return Cell.VOID


func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE

# ---------------------------------------------------------------------------
# BSP partitioning
# ---------------------------------------------------------------------------

func _split_bsp(node: BSPNode, depth: int) -> void:
	var max_part: int = maxi(18, _grid_size / 4)
	if node.rect.w <= max_part and node.rect.h <= max_part:
		if node.rect.w < MIN_PARTITION_SIZE * 2 and node.rect.h < MIN_PARTITION_SIZE * 2:
			return
		if depth > 3 and _rng.randf() < 0.25:
			return

	var can_h := node.rect.h >= MIN_PARTITION_SIZE * 2
	var can_v := node.rect.w >= MIN_PARTITION_SIZE * 2
	if not can_h and not can_v: return

	var horiz: bool
	if not can_v: horiz = true
	elif not can_h: horiz = false
	elif node.rect.w > node.rect.h * 1.25: horiz = false
	elif node.rect.h > node.rect.w * 1.25: horiz = true
	else: horiz = _rng.randf() < 0.5

	if horiz:
		var min_y := node.rect.y + MIN_PARTITION_SIZE
		var max_y := node.rect.y + node.rect.h - MIN_PARTITION_SIZE
		if min_y >= max_y: return
		var sy := _rng.randi_range(min_y, max_y)
		node.left = BSPNode.new(Rect2i_BSP.new(node.rect.x, node.rect.y, node.rect.w, sy - node.rect.y))
		node.right = BSPNode.new(Rect2i_BSP.new(node.rect.x, sy, node.rect.w, node.rect.y + node.rect.h - sy))
	else:
		var min_x := node.rect.x + MIN_PARTITION_SIZE
		var max_x := node.rect.x + node.rect.w - MIN_PARTITION_SIZE
		if min_x >= max_x: return
		var sx := _rng.randi_range(min_x, max_x)
		node.left = BSPNode.new(Rect2i_BSP.new(node.rect.x, node.rect.y, sx - node.rect.x, node.rect.h))
		node.right = BSPNode.new(Rect2i_BSP.new(sx, node.rect.y, node.rect.x + node.rect.w - sx, node.rect.h))

	_split_bsp(node.left, depth + 1)
	_split_bsp(node.right, depth + 1)

# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

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

		rx = clampi(rx, 1, _grid_size - rw - 1)
		ry = clampi(ry, 1, _grid_size - rh - 1)
		rw = mini(rw, _grid_size - rx - 1)
		rh = mini(rh, _grid_size - ry - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)
		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left: _create_rooms(node.left)
	if node.right: _create_rooms(node.right)


func _get_room(node: BSPNode) -> Rect2i_BSP:
	if node.room: return node.room
	if node.left:
		var r := _get_room(node.left)
		if r: return r
	if node.right:
		var r := _get_room(node.right)
		if r: return r
	return null

# ---------------------------------------------------------------------------
# Corridors
# ---------------------------------------------------------------------------

func _connect_rooms(node: BSPNode) -> void:
	if node.is_leaf(): return
	if node.left: _connect_rooms(node.left)
	if node.right: _connect_rooms(node.right)

	if node.left and node.right:
		var ra := _get_room(node.left)
		var rb := _get_room(node.right)
		if ra and rb:
			_carve_corridor(ra.center(), rb.center())


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	# Record corridor midpoint as door candidate
	var mid := Vector2i((from.x + to.x) / 2, (from.y + to.y) / 2)
	_corridor_midpoints.append(mid)

	if _rng.randf() < 0.5:
		_carve_horiz(from.x, to.x, from.y)
		_carve_vert(from.y, to.y, to.x)
	else:
		_carve_vert(from.y, to.y, from.x)
		_carve_horiz(from.x, to.x, to.y)


func _carve_horiz(x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		for dy in range(CORRIDOR_WIDTH):
			if _get_cell(x, y + dy) == Cell.VOID:
				_set_cell(x, y + dy, Cell.CORRIDOR)


func _carve_vert(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		for dx in range(CORRIDOR_WIDTH):
			if _get_cell(x + dx, y) == Cell.VOID:
				_set_cell(x + dx, y, Cell.CORRIDOR)

# ---------------------------------------------------------------------------
# Walls
# ---------------------------------------------------------------------------

func _build_walls() -> void:
	var wc: Array[Vector2i] = []
	for x in range(_grid_size):
		for y in range(_grid_size):
			if _grid[x][y] == Cell.VOID and _has_walkable_neighbor(x, y):
				wc.append(Vector2i(x, y))
	for pos in wc:
		_grid[pos.x][pos.y] = Cell.WALL


func _has_walkable_neighbor(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var c := _get_cell(x + dx, y + dy)
			if c == Cell.FLOOR or c == Cell.CORRIDOR:
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
		var sorted := _rooms.duplicate()
		sorted.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool: return (a.w * a.h) > (b.w * b.h))
		@warning_ignore("integer_division")
		var cnt := maxi(1, sorted.size() / 3)
		for i in range(cnt):
			_arena_rooms.append(sorted[i])

# ---------------------------------------------------------------------------
# Door candidate detection
# ---------------------------------------------------------------------------

func _find_door_candidates() -> void:
	# The corridor midpoints array was populated during _connect_rooms
	pass  # Already done in _carve_corridor

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

func _build_geometry() -> void:
	# Floors
	for strip in _build_strips(Cell.FLOOR):
		_make_floor_box(strip, _mat_floor)
	for strip in _build_strips(Cell.CORRIDOR):
		_make_floor_box(strip, _mat_corridor_floor)

	# Walls
	for strip in _build_strips(Cell.WALL):
		var box := CSGBox3D.new()
		box.size = Vector3(strip.w * CELL_SIZE, _wall_height, strip.h * CELL_SIZE)
		box.position = Vector3(
			_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
			_wall_height * 0.5,
			_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
		)
		box.use_collision = true
		box.collision_layer = ENVIRONMENT_LAYER
		box.collision_mask = 0
		box.material = _mat_wall
		box.name = "Wall_%d_%d" % [strip.x, strip.y]
		_geometry_root.add_child(box)

	# Ceiling — same footprint as floor
	var all_floor_strips: Array = _build_strips(Cell.FLOOR)
	var all_cor_strips: Array = _build_strips(Cell.CORRIDOR)
	for strip in all_floor_strips + all_cor_strips:
		var box := CSGBox3D.new()
		box.size = Vector3(strip.w * CELL_SIZE, 0.2, strip.h * CELL_SIZE)
		box.position = Vector3(
			_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
			_wall_height + 0.1,
			_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
		)
		box.use_collision = true
		box.collision_layer = ENVIRONMENT_LAYER
		box.collision_mask = 0
		box.material = _mat_ceiling
		box.name = "Ceiling_%d_%d" % [strip.x, strip.y]
		_geometry_root.add_child(box)


func _make_floor_box(strip: Rect2i_BSP, mat: StandardMaterial3D) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(strip.w * CELL_SIZE, 0.2, strip.h * CELL_SIZE)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5, -0.1,
		_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
	)
	box.use_collision = true
	box.collision_layer = ENVIRONMENT_LAYER
	box.collision_mask = 0
	box.material = mat
	box.name = "Floor_%d_%d" % [strip.x, strip.y]
	_geometry_root.add_child(box)

# ---------------------------------------------------------------------------
# Doors — placed at corridor midpoints, some locked
# ---------------------------------------------------------------------------

func _build_doors() -> void:
	_doors.clear()

	# Shuffle corridor midpoints to randomize door placement
	var candidates := _corridor_midpoints.duplicate()
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = candidates[i]; candidates[i] = candidates[j]; candidates[j] = tmp

	var max_doors := int(candidates.size() * _door_density)
	var max_locked := int(max_doors * _lock_density)
	var locked_count := 0
	var key_id_counter := 0

	for i in range(mini(max_doors, candidates.size())):
		var grid_pos: Vector2i = candidates[i]
		var c := _get_cell(grid_pos.x, grid_pos.y)
		if c != Cell.CORRIDOR and c != Cell.FLOOR:
			continue

		var world_x := _grid_to_world_x(grid_pos.x) + CELL_SIZE * 0.5
		var world_z := _grid_to_world_z(grid_pos.y) + CELL_SIZE * 0.5
		var world_pos := Vector3(world_x, 0.0, world_z)

		var should_lock := locked_count < max_locked and _rng.randf() < _lock_density
		if should_lock:
			locked_count += 1

		var door_info := DoorInfo.new(world_pos, should_lock, key_id_counter if should_lock else -1)
		if should_lock:
			key_id_counter += 1

		_doors.append(door_info)
		_spawn_door_object(door_info)


func _spawn_door_object(door_info: DoorInfo) -> void:
	## Create the door as an interactable StaticBody3D
	var body := StaticBody3D.new()
	body.name = "Door_Locked" if door_info.is_locked else "Door_Unlocked"
	body.add_to_group("interactable")
	body.add_to_group("door")

	## Visual mesh
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(CELL_SIZE * 0.8, _wall_height * 0.85, 0.3)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = _mat_door_locked if door_info.is_locked else _mat_door_open
	mesh_inst.name = "DoorMesh"
	body.add_child(mesh_inst)

	## Collision shape
	var col_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL_SIZE * 0.8, _wall_height * 0.85, 0.3)
	col_shape.shape = shape
	body.add_child(col_shape)

	## Area3D for proximity detection by player
	var area := Area3D.new()
	area.name = "DoorArea"
	var area_col := CollisionShape3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3(CELL_SIZE * 1.5, _wall_height, CELL_SIZE * 1.5)
	area_col.shape = area_shape
	area.add_child(area_col)
	body.add_child(area)

	body.position = door_info.world_pos + Vector3(0.0, _wall_height * 0.4, 0.0)
	body.collision_layer = ENVIRONMENT_LAYER
	body.collision_mask = 0

	# Store data on the body node for interaction
	body.set_meta("is_locked", door_info.is_locked)
	body.set_meta("key_id", door_info.key_id)
	body.set_meta("door_info_ref", door_info)
	body.set_meta("interact_label", "LOCKED — Find the key" if door_info.is_locked else "Open Door [E]")

	door_info.door_node = body
	_interactive_root.add_child(body)

	# Connect area signals for auto-key-unlock
	area.body_entered.connect(_on_door_area_body_entered.bind(body))

# ---------------------------------------------------------------------------
# Keys — scattered in rooms, glowing yellow pickups
# ---------------------------------------------------------------------------

func _build_keys() -> void:
	_key_positions.clear()
	var locked_doors: Array = []
	for door_info in _doors:
		if door_info.is_locked:
			locked_doors.append(door_info)

	if locked_doors.is_empty():
		return

	# Place one key per locked door in a random room (not the spawn room)
	var spawn_room: Rect2i_BSP = null
	var sorted_rooms := _rooms.duplicate()
	sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool: return (a.w * a.h) < (b.w * b.h))
	if sorted_rooms.size() > 0:
		spawn_room = sorted_rooms[0]

	var available_rooms: Array = []
	for room: Rect2i_BSP in _rooms:
		if room != spawn_room:
			available_rooms.append(room)

	for door_info: DoorInfo in locked_doors:
		if available_rooms.is_empty():
			break

		# Pick a random room
		var room_idx := _rng.randi_range(0, available_rooms.size() - 1)
		var room: Rect2i_BSP = available_rooms[room_idx]
		available_rooms.remove_at(room_idx)  ## Each room holds one key max for fairness

		var c := room.center()
		var kx := _grid_to_world_x(c.x) + _rng.randf_range(-CELL_SIZE, CELL_SIZE)
		var kz := _grid_to_world_z(c.y) + _rng.randf_range(-CELL_SIZE, CELL_SIZE)
		var key_pos := Vector3(kx, 0.6, kz)
		_key_positions.append(key_pos)
		_spawn_key_object(key_pos, door_info.key_id)


func _spawn_key_object(pos: Vector3, key_id: int) -> void:
	## Key as an Area3D that auto-collects when player overlaps
	var area := Area3D.new()
	area.name = "Key_%d" % key_id
	area.add_to_group("key_pickup")
	area.set_meta("key_id", key_id)
	area.set_meta("interact_label", "Key [auto-collect]")

	## Visual
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 0.5
	mesh_inst.mesh = cyl
	mesh_inst.material_override = _mat_key
	mesh_inst.rotation_degrees = Vector3(90, 0, 0)
	area.add_child(mesh_inst)

	## Collision
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.8
	shape.height = 1.5
	col.shape = shape
	area.add_child(col)

	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2  ## Player layer (bit 1)

	area.body_entered.connect(_on_key_body_entered.bind(area))

	_interactive_root.add_child(area)

	# Floating bob animation
	var tween := create_tween().set_loops()
	tween.tween_property(area, "position:y", pos.y + 0.3, 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(area, "position:y", pos.y, 1.0).set_trans(Tween.TRANS_SINE)

# ---------------------------------------------------------------------------
# Item scatter — health, ammo, gold in rooms
# ---------------------------------------------------------------------------

func _scatter_items() -> void:
	for room: Rect2i_BSP in _rooms:
		var floor_cells := room.w * room.h
		var item_count := int(floor_cells * _item_scatter_density)
		for _i in range(item_count):
			var ix := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var iy := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(ix, iy) == Cell.FLOOR:
				_place_floor_item(ix, iy)


func _place_floor_item(gx: int, gy: int) -> void:
	var wx := _grid_to_world_x(gx) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)
	var wz := _grid_to_world_z(gy) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)

	var roll := _rng.randf()
	var mat: StandardMaterial3D
	var item_type: String
	if roll < 0.40:
		mat = _mat_item_health; item_type = "health"
	elif roll < 0.70:
		mat = _mat_item_ammo; item_type = "ammo"
	else:
		mat = _mat_item_gold; item_type = "gold"

	var area := Area3D.new()
	area.name = "Item_%s_%d_%d" % [item_type, gx, gy]
	area.add_to_group("world_item")
	area.set_meta("item_type", item_type)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.35, 0.35, 0.35)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat
	area.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.7)
	col.shape = shape
	area.add_child(col)

	area.position = Vector3(wx, 0.4, wz)
	area.collision_layer = 0
	area.collision_mask = 2  ## Player layer

	area.body_entered.connect(_on_item_body_entered.bind(area))
	_interactive_root.add_child(area)

	# Gentle spin
	var tween := create_tween().set_loops()
	tween.tween_property(mesh_inst, "rotation_degrees:y", 360.0, 3.0).set_trans(Tween.TRANS_LINEAR)

# ---------------------------------------------------------------------------
# Props — themed decoration
# ---------------------------------------------------------------------------

func _build_props() -> void:
	for room: Rect2i_BSP in _rooms:
		var prop_count := _rng.randi_range(2, 5)
		for _i in range(prop_count):
			var px := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var pz := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(px, pz) == Cell.FLOOR:
				_place_prop(px, pz)


func _place_prop(gx: int, gy: int) -> void:
	var wx := _grid_to_world_x(gx) + CELL_SIZE * 0.5 + _rng.randf_range(-0.3, 0.3)
	var wz := _grid_to_world_z(gy) + CELL_SIZE * 0.5 + _rng.randf_range(-0.3, 0.3)

	match _prop_type:
		"cave":
			# Stalagmite
			var h := _rng.randf_range(0.5, 2.0)
			var r := _rng.randf_range(0.1, 0.35)
			var cyl := CSGCylinder3D.new()
			cyl.top_radius = r * 0.1
			cyl.bottom_radius = r
			cyl.height = h
			cyl.sides = 5
			cyl.position = Vector3(wx, h * 0.5, wz)
			cyl.use_collision = false
			cyl.material = _mat_prop
			cyl.name = "Stalagmite_%d_%d" % [gx, gy]
			_geometry_root.add_child(cyl)
		"temple", "temple_final":
			# Pillar or pedestal
			var h := _rng.randf_range(0.5, _wall_height * 0.8)
			var r := _rng.randf_range(0.2, 0.45)
			var cyl := CSGCylinder3D.new()
			cyl.top_radius = r
			cyl.bottom_radius = r
			cyl.height = h
			cyl.sides = 8
			cyl.position = Vector3(wx, h * 0.5, wz)
			cyl.use_collision = false
			cyl.material = _mat_prop
			cyl.name = "Pillar_%d_%d" % [gx, gy]
			_geometry_root.add_child(cyl)
		_:  # industrial
			# Crate / barrel
			var sz := _rng.randf_range(0.5, 1.0)
			var box := CSGBox3D.new()
			box.size = Vector3(sz, sz * _rng.randf_range(0.7, 1.5), sz)
			box.position = Vector3(wx, box.size.y * 0.5, wz)
			box.use_collision = false
			box.material = _mat_prop
			box.name = "Crate_%d_%d" % [gx, gy]
			_geometry_root.add_child(box)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var level_data: Dictionary = GameManager.current_level_data

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.01, 0.01)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = level_data.get("ambient_color", Color(0.18, 0.05, 0.18))
	env.ambient_light_energy = 0.30

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = level_data.get("fog_color", Color(0.06, 0.02, 0.06))
	env.fog_density = level_data.get("fog_density", 0.015)
	env.fog_light_energy = 0.4

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Dim directional light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirLight"
	dir_light.light_color = level_data.get("light_color", Color(0.5, 0.2, 0.5))
	dir_light.light_energy = level_data.get("light_energy", 0.3)
	dir_light.shadow_enabled = false
	dir_light.rotation_degrees = Vector3(-60, -30, 0)
	_lighting_root.add_child(dir_light)

	# OmniLights in arena rooms
	for room: Rect2i_BSP in _arena_rooms:
		var c := room.center()
		var omni := OmniLight3D.new()
		omni.name = "ArenaLight_%d_%d" % [c.x, c.y]
		omni.light_color = level_data.get("light_color", Color(0.5, 0.15, 0.5))
		omni.light_energy = _rng.randf_range(1.0, 2.0)
		omni.omni_range = maxi(room.w, room.h) * CELL_SIZE * 0.6
		omni.omni_attenuation = 1.5
		omni.shadow_enabled = false
		omni.position = Vector3(_grid_to_world_x(c.x), _wall_height * 0.7, _grid_to_world_z(c.y))
		_lighting_root.add_child(omni)

	# Dim corridor lights
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms: continue
		if _rng.randf() < 0.5: continue
		var c := room.center()
		var omni := OmniLight3D.new()
		omni.name = "RoomLight_%d_%d" % [c.x, c.y]
		omni.light_color = level_data.get("light_color", Color(0.4, 0.1, 0.4))
		omni.light_energy = _rng.randf_range(0.4, 0.9)
		omni.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.8
		omni.omni_attenuation = 2.0
		omni.shadow_enabled = false
		omni.position = Vector3(_grid_to_world_x(c.x), _wall_height * 0.6, _grid_to_world_z(c.y))
		_lighting_root.add_child(omni)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	var sorted_rooms := _rooms.duplicate()
	sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool: return (a.w * a.h) < (b.w * b.h))

	var spawn_room: Rect2i_BSP = sorted_rooms[0]
	var sc := spawn_room.center()
	_player_spawn = Vector3(_grid_to_world_x(sc.x), 0.5, _grid_to_world_z(sc.y))

	for room: Rect2i_BSP in _arena_rooms:
		@warning_ignore("integer_division")
		var cnt := maxi(MIN_ARENA_SPAWNS, (room.w * room.h) / ARENA_SPAWN_DENSITY)
		for _i in range(cnt):
			var sx := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms or room == spawn_room: continue
		var area := room.w * room.h
		if area < MIN_ROOM_SIZE * MIN_ROOM_SIZE: continue
		@warning_ignore("integer_division")
		var cnt := maxi(1, area / (ARENA_SPAWN_DENSITY * 2))
		for _i in range(cnt):
			var sx := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	if _enemy_spawns.is_empty():
		for room: Rect2i_BSP in _rooms:
			if room == spawn_room: continue
			var c := room.center()
			_enemy_spawns.append(Vector3(_grid_to_world_x(c.x), 0.5, _grid_to_world_z(c.y)))

# ---------------------------------------------------------------------------
# Interaction callbacks
# ---------------------------------------------------------------------------

## Called when a CharacterBody3D enters a door's proximity area
func _on_door_area_body_entered(body: Node3D, door_body: StaticBody3D) -> void:
	if not body.is_in_group("player"): return

	var is_locked: bool = door_body.get_meta("is_locked", false)
	if not is_locked:
		_open_door(door_body)
		return

	# Check if player carries the matching key
	var key_id: int = door_body.get_meta("key_id", -1)
	var player_keys: Array = body.get("carried_keys") if body.get("carried_keys") != null else []
	if key_id in player_keys:
		door_body.set_meta("is_locked", false)
		_open_door(door_body)


func _open_door(door_body: StaticBody3D) -> void:
	if not is_instance_valid(door_body): return
	## Animate door opening by moving it up out of the way
	var tween := create_tween()
	tween.tween_property(door_body, "position:y", _wall_height + 1.0, 0.5).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(door_body.queue_free)

	# Notify hub interaction changed
	EventBus.hub_interaction_changed.emit("")


## Key auto-collect when player walks into it
func _on_key_body_entered(body: Node3D, key_area: Area3D) -> void:
	if not body.is_in_group("player"): return

	var key_id: int = key_area.get_meta("key_id", -1)
	# Add key to player's carried_keys array
	if body.get("carried_keys") == null:
		body.set("carried_keys", [])
	var keys: Array = body.get("carried_keys")
	if key_id not in keys:
		keys.append(key_id)
		body.set("carried_keys", keys)

	# Visual feedback — emit a flash then remove key
	var tween := create_tween()
	tween.tween_property(key_area, "scale", Vector3(2.0, 2.0, 2.0), 0.2)
	tween.tween_callback(key_area.queue_free)


## Static world item (health/ammo/gold) auto-collect
func _on_item_body_entered(body: Node3D, item_area: Area3D) -> void:
	if not body.is_in_group("player"): return

	var item_type: String = item_area.get_meta("item_type", "")
	match item_type:
		"health":
			EventBus.health_collected.emit(25.0)
		"ammo":
			EventBus.ammo_collected.emit("generic", 20)
		"gold":
			EventBus.gold_collected.emit(10)

	item_area.queue_free()

# ---------------------------------------------------------------------------
# Strip merging utility
# ---------------------------------------------------------------------------

func _build_strips(cell_type: int) -> Array:
	var visited: Array = []
	visited.resize(_grid_size)
	for x in range(_grid_size):
		var col: Array = []
		col.resize(_grid_size)
		col.fill(false)
		visited[x] = col

	var strips: Array = []
	for y in range(_grid_size):
		var x: int = 0
		while x < _grid_size:
			if _grid[x][y] == cell_type and not visited[x][y]:
				var sx := x
				while x < _grid_size and _grid[x][y] == cell_type and not visited[x][y]:
					x += 1
				var sw := x - sx
				var sh := 1
				var can_ext := true
				while can_ext and y + sh < _grid_size:
					for cx in range(sx, sx + sw):
						if _grid[cx][y + sh] != cell_type or visited[cx][y + sh]:
							can_ext = false; break
					if can_ext: sh += 1
				for sy2 in range(y, y + sh):
					for cx in range(sx, sx + sw):
						visited[cx][sy2] = true
				strips.append(Rect2i_BSP.new(sx, y, sw, sh))
			else:
				x += 1
	return strips
