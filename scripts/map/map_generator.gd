extends Node3D
## Procedural dungeon/arena map generator using BSP partitioning.
## Generates a hellscape arena for a DOOM-style roguelike FPS using CSGBox3D geometry.
##
## Usage:
##   var map = MapGenerator.new()
##   add_child(map)
##   map.generate_map(12345)
##   var player_pos = map.get_player_spawn()
##   var enemy_positions = map.get_enemy_spawn_points()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Grid dimensions (cells)
const GRID_WIDTH: int = 60
const GRID_HEIGHT: int = 60

## World-space size of each grid cell
const CELL_SIZE: float = 4.0

## Wall / ceiling height
const WALL_HEIGHT: float = 4.0

## BSP split constraints
const MIN_PARTITION_SIZE: int = 8
const MAX_PARTITION_SIZE: int = 30
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 4
const ARENA_THRESHOLD: int = 10  ## Rooms wider AND taller than this are arenas

## Target room count
const MIN_ROOMS: int = 8
const MAX_ROOMS: int = 15

## Corridor width in cells
const CORRIDOR_WIDTH: int = 2

## Collision layer for environment (bit 0 = layer 1)
const ENVIRONMENT_LAYER: int = 1

## Enemy spawn density: one spawn point per N floor cells in an arena room
const ARENA_SPAWN_DENSITY: int = 25
## Minimum spawns per arena
const MIN_ARENA_SPAWNS: int = 3

# ---------------------------------------------------------------------------
# Cell types for the grid
# ---------------------------------------------------------------------------

enum Cell {
	VOID = 0,
	FLOOR = 1,
	WALL = 2,
}

# ---------------------------------------------------------------------------
# Internal data structures
# ---------------------------------------------------------------------------

## Axis-aligned rectangle in grid space (integer coordinates).
class Rect2i_BSP:
	var x: int
	var y: int
	var w: int
	var h: int

	func _init(px: int, py: int, pw: int, ph: int) -> void:
		x = px
		y = py
		w = pw
		h = ph

	func center() -> Vector2i:
		@warning_ignore("integer_division")
		return Vector2i(x + w / 2, y + h / 2)

## BSP tree node.
class BSPNode:
	var rect: Rect2i_BSP
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2i_BSP = null  ## Only leaves have rooms

	func _init(r: Rect2i_BSP) -> void:
		rect = r

	func is_leaf() -> bool:
		return left == null and right == null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _grid: Array = []          # 2D array [x][y] of Cell
var _rooms: Array = []         # Array of Rect2i_BSP – all carved rooms
var _arena_rooms: Array = []   # Subset of _rooms that are arenas
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Container nodes for easy cleanup
var _geometry_root: Node3D = null
var _lighting_root: Node3D = null

# ---------------------------------------------------------------------------
# Materials (created once, reused)
# ---------------------------------------------------------------------------

var _mat_wall: StandardMaterial3D = null
var _mat_floor: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_corridor_floor: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Generate the full map from scratch using the given seed.
func generate_map(seed_value: int) -> void:
	clear_map()

	_rng.seed = seed_value

	_create_materials()
	_init_grid()

	# BSP partition and carve
	var root := BSPNode.new(Rect2i_BSP.new(0, 0, GRID_WIDTH, GRID_HEIGHT))
	_split_bsp(root, 0)
	_create_rooms(root)
	_connect_rooms(root)

	# Build walls around carved floor cells
	_build_walls()

	# Classify rooms
	_classify_rooms()

	# Create 3D geometry from the grid
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_build_geometry()

	# Lighting and environment
	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_build_environment()

	# Spawn points
	_determine_spawn_points()


## Return the player spawn position in world space (y = 0 plane, slightly above floor).
func get_player_spawn() -> Vector3:
	return _player_spawn


## Return all enemy spawn positions in world space.
func get_enemy_spawn_points() -> Array[Vector3]:
	return _enemy_spawns


## Remove all generated geometry and reset internal state.
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
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Wall – dark brownish-gray, rough stone
	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.18, 0.12, 0.10)
	_mat_wall.roughness = 0.95
	_mat_wall.metallic = 0.0

	# Floor – dark crimson / blood red-brown
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.22, 0.06, 0.04)
	_mat_floor.roughness = 0.85
	_mat_floor.metallic = 0.05

	# Corridor floor – slightly different tone to break up monotony
	_mat_corridor_floor = StandardMaterial3D.new()
	_mat_corridor_floor.albedo_color = Color(0.16, 0.07, 0.05)
	_mat_corridor_floor.roughness = 0.90
	_mat_corridor_floor.metallic = 0.05

	# Ceiling – very dark, almost black
	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.06, 0.03, 0.03)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

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
# BSP partitioning
# ---------------------------------------------------------------------------

func _split_bsp(node: BSPNode, depth: int) -> void:
	# Stop splitting if the partition is small enough or we've gone deep enough
	if node.rect.w <= MAX_PARTITION_SIZE and node.rect.h <= MAX_PARTITION_SIZE:
		if node.rect.w < MIN_PARTITION_SIZE * 2 and node.rect.h < MIN_PARTITION_SIZE * 2:
			return
		# Random chance to stop splitting for variety
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
		# Prefer splitting the longer axis, with some randomness
		if node.rect.w > node.rect.h * 1.25:
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
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y,
			node.rect.w, split_y - node.rect.y
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, split_y,
			node.rect.w, node.rect.y + node.rect.h - split_y
		))
	else:
		var min_x: int = node.rect.x + MIN_PARTITION_SIZE
		var max_x: int = node.rect.x + node.rect.w - MIN_PARTITION_SIZE
		if min_x >= max_x:
			return
		var split_x: int = _rng.randi_range(min_x, max_x)
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y,
			split_x - node.rect.x, node.rect.h
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			split_x, node.rect.y,
			node.rect.x + node.rect.w - split_x, node.rect.h
		))

	_split_bsp(node.left, depth + 1)
	_split_bsp(node.right, depth + 1)

# ---------------------------------------------------------------------------
# Room creation
# ---------------------------------------------------------------------------

func _create_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		# Carve a room inside this partition with some margin
		var rw: int = _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		)
		var rh: int = _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)
		)
		rw = mini(rw, node.rect.w - ROOM_MARGIN)
		rh = mini(rh, node.rect.h - ROOM_MARGIN)
		rw = maxi(rw, MIN_ROOM_SIZE)
		rh = maxi(rh, MIN_ROOM_SIZE)

		var rx: int = _rng.randi_range(
			node.rect.x + 1,
			maxi(node.rect.x + 1, node.rect.x + node.rect.w - rw - 1)
		)
		var ry: int = _rng.randi_range(
			node.rect.y + 1,
			maxi(node.rect.y + 1, node.rect.y + node.rect.h - rh - 1)
		)

		# Clamp to grid bounds
		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)
		rw = mini(rw, GRID_WIDTH - rx - 1)
		rh = mini(rh, GRID_HEIGHT - ry - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)

		# Carve floor cells
		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		return

	if node.left:
		_create_rooms(node.left)
	if node.right:
		_create_rooms(node.right)


## Get any room from a subtree (for corridor connections).
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

# ---------------------------------------------------------------------------
# Corridor connections
# ---------------------------------------------------------------------------

func _connect_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		return

	if node.left:
		_connect_rooms(node.left)
	if node.right:
		_connect_rooms(node.right)

	# Connect a room from the left subtree to one from the right subtree
	if node.left and node.right:
		var room_a := _get_room(node.left)
		var room_b := _get_room(node.right)
		if room_a and room_b:
			_carve_corridor(room_a.center(), room_b.center())


func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	# L-shaped corridor: go horizontal first, then vertical (or vice-versa randomly)
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
			var cy: int = y + dy
			if _get_cell(x, cy) == Cell.VOID:
				_set_cell(x, cy, Cell.FLOOR)


func _carve_vertical(y1: int, y2: int, x: int) -> void:
	var start_y: int = mini(y1, y2)
	var end_y: int = maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx: int = x + dx
			if _get_cell(cx, y) == Cell.VOID:
				_set_cell(cx, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Wall construction
# ---------------------------------------------------------------------------

func _build_walls() -> void:
	# Any VOID cell adjacent to a FLOOR cell becomes a WALL
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
	for room: Rect2i_BSP in _rooms:
		if room.w >= ARENA_THRESHOLD and room.h >= ARENA_THRESHOLD:
			_arena_rooms.append(room)

	# If no arenas found, pick the largest rooms
	if _arena_rooms.is_empty() and _rooms.size() > 0:
		var sorted_rooms := _rooms.duplicate()
		sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
			return (a.w * a.h) > (b.w * b.h)
		)
		# Top third become arenas (at least 1)
		@warning_ignore("integer_division")
		var count := maxi(1, sorted_rooms.size() / 3)
		for i in range(count):
			_arena_rooms.append(sorted_rooms[i])

# ---------------------------------------------------------------------------
# 3D geometry building
# ---------------------------------------------------------------------------

func _build_geometry() -> void:
	# Batch floor, wall, and ceiling CSG boxes.
	# We merge adjacent cells into horizontal strips to reduce node count.

	# --- Floors ---
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		_create_floor_box(strip)

	# --- Walls ---
	var wall_strips := _build_horizontal_strips(Cell.WALL)
	for strip: Rect2i_BSP in wall_strips:
		_create_wall_box(strip)

	# --- Ceilings (same footprint as floor) ---
	for strip: Rect2i_BSP in floor_strips:
		_create_ceiling_box(strip)


## Merge cells of a given type into horizontal rectangular strips for fewer nodes.
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
				# Start a new strip
				var start_x: int = x
				while x < GRID_WIDTH and _grid[x][y] == cell_type and not visited[x][y]:
					x += 1
				var strip_w: int = x - start_x

				# Try to extend downward to form a rectangle
				var strip_h: int = 1
				var can_extend: bool = true
				while can_extend and y + strip_h < GRID_HEIGHT:
					for sx in range(start_x, start_x + strip_w):
						if _grid[sx][y + strip_h] != cell_type or visited[sx][y + strip_h]:
							can_extend = false
							break
					if can_extend:
						strip_h += 1

				# Mark visited
				for sy in range(y, y + strip_h):
					for sx in range(start_x, start_x + strip_w):
						visited[sx][sy] = true

				strips.append(Rect2i_BSP.new(start_x, y, strip_w, strip_h))
			else:
				x += 1

	return strips


func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE


func _create_floor_box(strip: Rect2i_BSP) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(
		strip.w * CELL_SIZE,
		0.2,
		strip.h * CELL_SIZE
	)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		-0.1,  # Top surface at y=0
		_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
	)
	box.use_collision = true
	box.collision_layer = ENVIRONMENT_LAYER
	box.collision_mask = 0

	# Determine material: check if this strip overlaps with a non-corridor area
	var is_room_floor := _strip_overlaps_any_room(strip)
	box.material = _mat_floor if is_room_floor else _mat_corridor_floor

	box.name = "Floor_%d_%d" % [strip.x, strip.y]
	_geometry_root.add_child(box)


func _create_wall_box(strip: Rect2i_BSP) -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(
		strip.w * CELL_SIZE,
		WALL_HEIGHT,
		strip.h * CELL_SIZE
	)
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
	box.size = Vector3(
		strip.w * CELL_SIZE,
		0.2,
		strip.h * CELL_SIZE
	)
	box.position = Vector3(
		_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
		WALL_HEIGHT + 0.1,  # Bottom surface at WALL_HEIGHT
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
		# AABB overlap test
		if strip.x < room.x + room.w and strip.x + strip.w > room.x \
			and strip.y < room.y + room.h and strip.y + strip.h > room.y:
			return true
	return false

# ---------------------------------------------------------------------------
# Lighting and environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	# --- WorldEnvironment ---
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.01, 0.01)

	# Ambient light – hellish red-orange glow
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.12, 0.05)
	env.ambient_light_energy = 0.35

	# Tonemap for that gritty look
	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	# Fog for atmosphere and draw distance
	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.04, 0.02)
	env.fog_density = 0.012
	env.fog_light_energy = 0.5

	# Glow / bloom for that hellish feel
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# --- DirectionalLight3D – dim, angled, blood-orange ---
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = Color(0.9, 0.35, 0.1)
	dir_light.light_energy = 0.4
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-45, -30, 0)
	_lighting_root.add_child(dir_light)

	# --- OmniLights in arena rooms for dramatic lighting ---
	for room: Rect2i_BSP in _arena_rooms:
		var center := room.center()
		var light := OmniLight3D.new()
		light.name = "ArenaLight_%d_%d" % [center.x, center.y]
		light.light_color = Color(
			_rng.randf_range(0.7, 1.0),
			_rng.randf_range(0.1, 0.3),
			_rng.randf_range(0.0, 0.1)
		)
		light.light_energy = _rng.randf_range(1.2, 2.5)
		light.omni_range = maxi(room.w, room.h) * CELL_SIZE * 0.6
		light.omni_attenuation = 1.5
		light.shadow_enabled = false  # Performance: skip shadows on fill lights
		light.position = Vector3(
			_grid_to_world_x(center.x),
			WALL_HEIGHT * 0.75,
			_grid_to_world_z(center.y)
		)
		_lighting_root.add_child(light)

	# Scattered dim lights in non-arena rooms for moody illumination
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms:
			continue
		# 50% chance for a small room to get a light
		if _rng.randf() < 0.5:
			continue
		var center := room.center()
		var light := OmniLight3D.new()
		light.name = "RoomLight_%d_%d" % [center.x, center.y]
		light.light_color = Color(
			_rng.randf_range(0.5, 0.8),
			_rng.randf_range(0.05, 0.15),
			_rng.randf_range(0.0, 0.05)
		)
		light.light_energy = _rng.randf_range(0.5, 1.0)
		light.omni_range = mini(room.w, room.h) * CELL_SIZE * 0.8
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(center.x),
			WALL_HEIGHT * 0.6,
			_grid_to_world_z(center.y)
		)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# --- Player spawn: pick the smallest non-arena room ---
	var non_arena_rooms: Array = []
	for room: Rect2i_BSP in _rooms:
		if room not in _arena_rooms:
			non_arena_rooms.append(room)

	# Fallback: if everything is an arena, use the smallest arena
	if non_arena_rooms.is_empty():
		non_arena_rooms = _rooms.duplicate()

	non_arena_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
		return (a.w * a.h) < (b.w * b.h)
	)

	var spawn_room: Rect2i_BSP = non_arena_rooms[0]
	var sc: Vector2i = spawn_room.center()
	_player_spawn = Vector3(
		_grid_to_world_x(sc.x),
		0.5,  # Slightly above floor
		_grid_to_world_z(sc.y)
	)

	# --- Enemy spawns: distribute across arena rooms ---
	for room: Rect2i_BSP in _arena_rooms:
		var area: int = room.w * room.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, area / ARENA_SPAWN_DENSITY)

		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			# Verify the cell is actually floor
			if _get_cell(sx, sy) == Cell.FLOOR:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Also place a few spawns in medium-sized non-arena rooms
	for room: Rect2i_BSP in non_arena_rooms:
		if room == spawn_room:
			continue  # Don't spawn enemies in the player's starting room
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
					_grid_to_world_x(sx) + CELL_SIZE * 0.5,
					0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Ensure we have at least some enemy spawns
	if _enemy_spawns.is_empty():
		for room: Rect2i_BSP in _rooms:
			if room == spawn_room:
				continue
			var center := room.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(center.x),
				0.5,
				_grid_to_world_z(center.y)
			))

# ---------------------------------------------------------------------------
# Debug / utility
# ---------------------------------------------------------------------------

## Print the grid to the console (for debugging).
func debug_print_grid() -> void:
	for y in range(GRID_HEIGHT):
		var line: String = ""
		for x in range(GRID_WIDTH):
			match _grid[x][y]:
				Cell.VOID:
					line += " "
				Cell.FLOOR:
					line += "."
				Cell.WALL:
					line += "#"
		print(line)


## Get the total number of rooms generated.
func get_room_count() -> int:
	return _rooms.size()


## Get the number of arena rooms.
func get_arena_count() -> int:
	return _arena_rooms.size()


## Get room data for external use (e.g. wave spawning, navigation).
## Returns an array of dictionaries with keys: position (Vector3), size (Vector2),
## is_arena (bool).
func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var center := room.center()
		data.append({
			"position": Vector3(
				_grid_to_world_x(center.x),
				0.0,
				_grid_to_world_z(center.y)
			),
			"size": Vector2(room.w * CELL_SIZE, room.h * CELL_SIZE),
			"is_arena": room in _arena_rooms,
			"grid_rect": Rect2(room.x, room.y, room.w, room.h),
		})
	return data


## Check whether a world position is on walkable floor.
func is_walkable(world_pos: Vector3) -> bool:
	@warning_ignore("narrowing_conversion")
	var gx: int = int(world_pos.x / CELL_SIZE)
	@warning_ignore("narrowing_conversion")
	var gy: int = int(world_pos.z / CELL_SIZE)
	return _get_cell(gx, gy) == Cell.FLOOR
