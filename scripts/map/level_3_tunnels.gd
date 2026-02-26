extends Node3D
## Level 3: The Deep Warrens
## A claustrophobic underground tunnel maze generated via recursive backtracker.
## Features narrow corridors, branching hallways, cavern rooms, dead-end loot
## rooms, and purple crystal accents. Full ceiling coverage — underground.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 80
const GRID_HEIGHT: int = 80
const CELL_SIZE: float = 3.5
const WALL_HEIGHT: float = 3.5

const CORRIDOR_WIDTH: int = 2
const ROOM_MIN_SIZE: int = 6
const ROOM_MAX_SIZE: int = 10
const CAVERN_MIN_SIZE: int = 12
const CAVERN_MAX_SIZE: int = 16
const ARENA_THRESHOLD: int = 10

const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 20
const MIN_ARENA_SPAWNS: int = 3

const TARGET_ROOM_COUNT: int = 10
const TARGET_CAVERN_COUNT: int = 3
const DEAD_END_LOOT_CHANCE: float = 0.4
const CRYSTAL_DENSITY: float = 0.02

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

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _grid: Array = []
var _maze_visited: Array = []  # For recursive backtracker (half-grid)
var _rooms: Array = []
var _arena_rooms: Array = []
var _caverns: Array = []
var _dead_ends: Array = []  # Array of Vector2i — dead-end positions
var _crystal_positions: Array = []  # Array of Vector3
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null

# Maze dimensions (half of grid, each maze cell = 2 grid cells)
var _maze_w: int = 0
var _maze_h: int = 0

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

var _mat_floor: StandardMaterial3D = null
var _mat_wall: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_crystal: StandardMaterial3D = null
var _mat_cavern_floor: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value

	_create_materials()
	_init_grid()

	# Generate maze using recursive backtracker
	_generate_maze()

	# Widen corridors to 2-cell width
	_widen_corridors()

	# Place rooms at intersections
	_place_rooms()

	# Place larger caverns for arena fights
	_place_caverns()

	# Identify dead ends
	_find_dead_ends()

	# Build walls around carved floor cells
	_build_walls()

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
	_build_crystals()
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
	_maze_visited.clear()
	_rooms.clear()
	_arena_rooms.clear()
	_caverns.clear()
	_dead_ends.clear()
	_crystal_positions.clear()
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
	return _get_cell(gx, gy) == Cell.FLOOR

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Dark stone floor
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.08, 0.06, 0.1)
	_mat_floor.roughness = 0.95
	_mat_floor.metallic = 0.0

	# Cave walls
	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.1, 0.07, 0.12)
	_mat_wall.roughness = 0.9
	_mat_wall.metallic = 0.0

	# Ceiling
	_mat_ceiling = StandardMaterial3D.new()
	_mat_ceiling.albedo_color = Color(0.03, 0.02, 0.05)
	_mat_ceiling.roughness = 1.0
	_mat_ceiling.metallic = 0.0

	# Purple crystal accent
	_mat_crystal = StandardMaterial3D.new()
	_mat_crystal.albedo_color = Color(0.4, 0.15, 0.6)
	_mat_crystal.roughness = 0.3
	_mat_crystal.metallic = 0.2
	_mat_crystal.emission_enabled = true
	_mat_crystal.emission = Color(0.5, 0.15, 0.8)
	_mat_crystal.emission_energy_multiplier = 2.0

	# Cavern floor (slightly different shade)
	_mat_cavern_floor = StandardMaterial3D.new()
	_mat_cavern_floor.albedo_color = Color(0.1, 0.07, 0.12)
	_mat_cavern_floor.roughness = 0.9
	_mat_cavern_floor.metallic = 0.05

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
# Maze generation — recursive backtracker
# ---------------------------------------------------------------------------

func _generate_maze() -> void:
	# The maze operates on a half-resolution grid. Each maze cell = 2x2 grid cells.
	# Walls between maze cells are 1 grid cell thick (shared).
	# We use odd-numbered grid positions for passages.

	@warning_ignore("integer_division")
	_maze_w = (GRID_WIDTH - 2) / 2
	@warning_ignore("integer_division")
	_maze_h = (GRID_HEIGHT - 2) / 2

	# Initialize visited array
	_maze_visited.resize(_maze_w)
	for x in range(_maze_w):
		var col: Array = []
		col.resize(_maze_h)
		col.fill(false)
		_maze_visited[x] = col

	# Start from a random position
	var start_x := _rng.randi_range(0, _maze_w - 1)
	var start_y := _rng.randi_range(0, _maze_h - 1)

	# Iterative backtracker (using explicit stack to avoid recursion limit)
	var stack: Array = []
	stack.append(Vector2i(start_x, start_y))
	_maze_visited[start_x][start_y] = true
	_carve_maze_cell(start_x, start_y)

	while stack.size() > 0:
		var current: Vector2i = stack[stack.size() - 1]
		var neighbors := _get_unvisited_neighbors(current.x, current.y)

		if neighbors.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = neighbors[_rng.randi_range(0, neighbors.size() - 1)]
			# Carve passage between current and next
			_carve_passage(current.x, current.y, next.x, next.y)
			_maze_visited[next.x][next.y] = true
			_carve_maze_cell(next.x, next.y)
			stack.append(next)

			# Add extra connections for multiple paths (branching)
			if _rng.randf() < 0.15 and neighbors.size() > 1:
				for extra in neighbors:
					if extra != next and not _maze_visited[extra.x][extra.y]:
						if _rng.randf() < 0.3:
							_carve_passage(current.x, current.y, extra.x, extra.y)
							_maze_visited[extra.x][extra.y] = true
							_carve_maze_cell(extra.x, extra.y)
							stack.append(extra)
							break


func _maze_to_grid(mx: int, my: int) -> Vector2i:
	return Vector2i(mx * 2 + 1, my * 2 + 1)


func _carve_maze_cell(mx: int, my: int) -> void:
	var gp := _maze_to_grid(mx, my)
	# Carve a 2x2 area for the cell
	for dx in range(2):
		for dy in range(2):
			_set_cell(gp.x + dx, gp.y + dy, Cell.FLOOR)


func _carve_passage(from_x: int, from_y: int, to_x: int, to_y: int) -> void:
	var g_from := _maze_to_grid(from_x, from_y)
	var g_to := _maze_to_grid(to_x, to_y)

	# Carve cells between the two maze cells
	var dx := signi(g_to.x - g_from.x)
	var dy := signi(g_to.y - g_from.y)

	var cx := g_from.x
	var cy := g_from.y

	while cx != g_to.x or cy != g_to.y:
		_set_cell(cx, cy, Cell.FLOOR)
		_set_cell(cx + 1, cy, Cell.FLOOR)
		_set_cell(cx, cy + 1, Cell.FLOOR)
		_set_cell(cx + 1, cy + 1, Cell.FLOOR)
		if cx != g_to.x:
			cx += dx
		elif cy != g_to.y:
			cy += dy

	# Carve destination
	_set_cell(g_to.x, g_to.y, Cell.FLOOR)
	_set_cell(g_to.x + 1, g_to.y, Cell.FLOOR)
	_set_cell(g_to.x, g_to.y + 1, Cell.FLOOR)
	_set_cell(g_to.x + 1, g_to.y + 1, Cell.FLOOR)


func _get_unvisited_neighbors(mx: int, my: int) -> Array:
	var neighbors: Array = []
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in dirs:
		var nx: int = mx + d.x
		var ny: int = my + d.y
		if nx >= 0 and nx < _maze_w and ny >= 0 and ny < _maze_h:
			if not _maze_visited[nx][ny]:
				neighbors.append(Vector2i(nx, ny))
	return neighbors

# ---------------------------------------------------------------------------
# Widen corridors
# ---------------------------------------------------------------------------

func _widen_corridors() -> void:
	# Already built with 2-cell wide passages via _carve_maze_cell.
	# Add extra random connections between adjacent corridors for variety.
	for x in range(2, GRID_WIDTH - 2):
		for y in range(2, GRID_HEIGHT - 2):
			if _grid[x][y] == Cell.VOID:
				# Check if this void cell is sandwiched between two floor cells
				if (_get_cell(x - 1, y) == Cell.FLOOR and _get_cell(x + 1, y) == Cell.FLOOR) \
					or (_get_cell(x, y - 1) == Cell.FLOOR and _get_cell(x, y + 1) == Cell.FLOOR):
					if _rng.randf() < 0.08:
						_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Room placement
# ---------------------------------------------------------------------------

func _place_rooms() -> void:
	var placed := 0

	# Find intersections in the maze (floor cells with 3+ floor neighbors in cardinal dirs)
	var intersections: Array = []
	for x in range(2, GRID_WIDTH - 2):
		for y in range(2, GRID_HEIGHT - 2):
			if _grid[x][y] == Cell.FLOOR:
				var floor_dirs := 0
				if _get_cell(x - 2, y) == Cell.FLOOR:
					floor_dirs += 1
				if _get_cell(x + 2, y) == Cell.FLOOR:
					floor_dirs += 1
				if _get_cell(x, y - 2) == Cell.FLOOR:
					floor_dirs += 1
				if _get_cell(x, y + 2) == Cell.FLOOR:
					floor_dirs += 1
				if floor_dirs >= 3:
					intersections.append(Vector2i(x, y))

	# Shuffle and pick some intersections for rooms
	for i in range(intersections.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = intersections[i]
		intersections[i] = intersections[j]
		intersections[j] = tmp

	for idx in range(mini(TARGET_ROOM_COUNT, intersections.size())):
		var pos: Vector2i = intersections[idx]
		var rw := _rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var rh := _rng.randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var rx := pos.x - rw / 2
		var ry := pos.y - rh / 2
		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)

		# Check overlap with existing rooms
		var overlaps := false
		for existing: Rect2i_BSP in _rooms:
			if rx < existing.x + existing.w + 2 and rx + rw + 2 > existing.x \
				and ry < existing.y + existing.h + 2 and ry + rh + 2 > existing.y:
				overlaps = true
				break

		if overlaps:
			continue

		var room := Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(room)

		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				_set_cell(x, y, Cell.FLOOR)
		placed += 1

# ---------------------------------------------------------------------------
# Cavern placement
# ---------------------------------------------------------------------------

func _place_caverns() -> void:
	_caverns.clear()
	var placed := 0
	var attempts := 0

	while placed < TARGET_CAVERN_COUNT and attempts < 50:
		attempts += 1
		var cw := _rng.randi_range(CAVERN_MIN_SIZE, CAVERN_MAX_SIZE)
		var ch := _rng.randi_range(CAVERN_MIN_SIZE, CAVERN_MAX_SIZE)
		var cx := _rng.randi_range(3, GRID_WIDTH - cw - 3)
		var cy := _rng.randi_range(3, GRID_HEIGHT - ch - 3)

		# Check no overlap with existing rooms or caverns
		var overlaps := false
		for existing: Rect2i_BSP in _rooms:
			if cx < existing.x + existing.w + 3 and cx + cw + 3 > existing.x \
				and cy < existing.y + existing.h + 3 and cy + ch + 3 > existing.y:
				overlaps = true
				break

		if overlaps:
			continue

		for existing: Rect2i_BSP in _caverns:
			if cx < existing.x + existing.w + 3 and cx + cw + 3 > existing.x \
				and cy < existing.y + existing.h + 3 and cy + ch + 3 > existing.y:
				overlaps = true
				break

		if overlaps:
			continue

		var cavern := Rect2i_BSP.new(cx, cy, cw, ch)
		_caverns.append(cavern)
		_rooms.append(cavern)

		# Carve with some irregular edges for organic feel
		for x in range(cx, cx + cw):
			for y in range(cy, cy + ch):
				# Slightly irregular edges
				var dist_x := minf(float(x - cx), float(cx + cw - 1 - x))
				var dist_y := minf(float(y - cy), float(cy + ch - 1 - y))
				var edge_dist := minf(dist_x, dist_y)
				if edge_dist > 0 or _rng.randf() < 0.7:
					_set_cell(x, y, Cell.FLOOR)

		# Connect cavern to nearest maze corridor
		_connect_cavern_to_maze(cavern)
		placed += 1


func _connect_cavern_to_maze(cavern: Rect2i_BSP) -> void:
	var center := cavern.center()
	# Search outward from center for a floor cell that is NOT in this cavern
	var best_target := Vector2i(-1, -1)
	var best_dist := INF

	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			if _grid[x][y] == Cell.FLOOR:
				if x < cavern.x or x >= cavern.x + cavern.w \
					or y < cavern.y or y >= cavern.y + cavern.h:
					var dist := Vector2(x - center.x, y - center.y).length()
					if dist < best_dist:
						best_dist = dist
						best_target = Vector2i(x, y)

	if best_target.x >= 0:
		_carve_tunnel(center, best_target)


func _carve_tunnel(from: Vector2i, to: Vector2i) -> void:
	# L-shaped tunnel
	var go_h_first := _rng.randf() < 0.5
	if go_h_first:
		var sx := mini(from.x, to.x)
		var ex := maxi(from.x, to.x)
		for x in range(sx, ex + 1):
			for dw in range(CORRIDOR_WIDTH):
				_set_cell(x, from.y + dw, Cell.FLOOR)
		var sy := mini(from.y, to.y)
		var ey := maxi(from.y, to.y)
		for y in range(sy, ey + 1):
			for dw in range(CORRIDOR_WIDTH):
				_set_cell(to.x + dw, y, Cell.FLOOR)
	else:
		var sy := mini(from.y, to.y)
		var ey := maxi(from.y, to.y)
		for y in range(sy, ey + 1):
			for dw in range(CORRIDOR_WIDTH):
				_set_cell(from.x + dw, y, Cell.FLOOR)
		var sx := mini(from.x, to.x)
		var ex := maxi(from.x, to.x)
		for x in range(sx, ex + 1):
			for dw in range(CORRIDOR_WIDTH):
				_set_cell(x, to.y + dw, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Dead end detection
# ---------------------------------------------------------------------------

func _find_dead_ends() -> void:
	_dead_ends.clear()
	# A dead end is a floor cell with only one cardinally adjacent floor cell
	for x in range(1, GRID_WIDTH - 1):
		for y in range(1, GRID_HEIGHT - 1):
			if _grid[x][y] == Cell.FLOOR:
				var adj_floor := 0
				if _get_cell(x - 1, y) == Cell.FLOOR:
					adj_floor += 1
				if _get_cell(x + 1, y) == Cell.FLOOR:
					adj_floor += 1
				if _get_cell(x, y - 1) == Cell.FLOOR:
					adj_floor += 1
				if _get_cell(x, y + 1) == Cell.FLOOR:
					adj_floor += 1
				if adj_floor <= 1:
					_dead_ends.append(Vector2i(x, y))

	# Carve small loot rooms at some dead ends
	for de in _dead_ends:
		if _rng.randf() < DEAD_END_LOOT_CHANCE:
			# Small 3x3 room at the dead end
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					_set_cell(de.x + dx, de.y + dy, Cell.FLOOR)

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
	# Caverns are always arenas
	for cavern: Rect2i_BSP in _caverns:
		_arena_rooms.append(cavern)

	# Large rooms also count
	for room: Rect2i_BSP in _rooms:
		if room in _caverns:
			continue
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
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		# Check if this strip overlaps a cavern for special material
		var mat := _mat_floor
		for cavern: Rect2i_BSP in _caverns:
			if strip.x < cavern.x + cavern.w and strip.x + strip.w > cavern.x \
				and strip.y < cavern.y + cavern.h and strip.y + strip.h > cavern.y:
				mat = _mat_cavern_floor
				break
		_create_floor_box(strip, mat)

	var wall_strips := _build_horizontal_strips(Cell.WALL)
	for strip: Rect2i_BSP in wall_strips:
		_create_wall_box(strip)

	# Ceiling everywhere (underground)
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


func _create_floor_box(strip: Rect2i_BSP, mat: StandardMaterial3D) -> void:
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

# ---------------------------------------------------------------------------
# Crystal decorations
# ---------------------------------------------------------------------------

func _build_crystals() -> void:
	_crystal_positions.clear()

	# Place crystals on wall cells adjacent to floor
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			if _grid[x][y] == Cell.WALL and _rng.randf() < CRYSTAL_DENSITY:
				# Must be adjacent to floor
				if not _has_floor_neighbor(x, y):
					continue

				var world_x := _grid_to_world_x(x) + CELL_SIZE * 0.5
				var world_z := _grid_to_world_z(y) + CELL_SIZE * 0.5
				var crystal_h := _rng.randf_range(0.5, 1.5)

				var crystal := CSGSphere3D.new()
				crystal.radius = _rng.randf_range(0.2, 0.5)
				crystal.radial_segments = 6
				crystal.rings = 4
				crystal.position = Vector3(
					world_x + _rng.randf_range(-0.5, 0.5),
					crystal_h,
					world_z + _rng.randf_range(-0.5, 0.5)
				)
				crystal.material = _mat_crystal
				crystal.use_collision = false
				crystal.name = "Crystal_%d_%d" % [x, y]
				_geometry_root.add_child(crystal)

				_crystal_positions.append(crystal.position)

	# Add dim purple lights near crystal clusters
	# Group nearby crystals and add one light per cluster
	var lit_crystals: Array = []
	for pos: Vector3 in _crystal_positions:
		var too_close := false
		for lit: Vector3 in lit_crystals:
			if pos.distance_to(lit) < CELL_SIZE * 6.0:
				too_close = true
				break
		if too_close:
			continue

		lit_crystals.append(pos)
		var light := OmniLight3D.new()
		light.name = "CrystalLight"
		light.light_color = Color(0.5, 0.15, 0.8)
		light.light_energy = _rng.randf_range(0.5, 1.2)
		light.omni_range = _rng.randf_range(5.0, 10.0)
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(pos.x, 2.0, pos.z)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.01, 0.03)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.05, 0.12)
	env.ambient_light_energy = 0.25

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.02, 0.06)
	env.fog_density = 0.025
	env.fog_light_energy = 0.3

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Very dim directional light (underground, minimal)
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "AmbientGlow"
	dir_light.light_color = Color(0.4, 0.2, 0.6)
	dir_light.light_energy = 0.3
	dir_light.shadow_enabled = false
	dir_light.rotation_degrees = Vector3(-90, 0, 0)
	_lighting_root.add_child(dir_light)

	# Room lights — purple/violet only in rooms
	for room: Rect2i_BSP in _rooms:
		var center := room.center()
		var light := OmniLight3D.new()
		light.name = "RoomLight_%d_%d" % [center.x, center.y]
		light.light_color = Color(
			_rng.randf_range(0.3, 0.5),
			_rng.randf_range(0.1, 0.2),
			_rng.randf_range(0.5, 0.9)
		)
		light.light_energy = _rng.randf_range(0.8, 1.8)
		light.omni_range = maxi(room.w, room.h) * CELL_SIZE * 0.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(center.x), WALL_HEIGHT * 0.7, _grid_to_world_z(center.y)
		)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns at a dead-end room (entrance from above)
	if _dead_ends.size() > 0:
		# Pick the dead end closest to the grid corner (simulates entrance)
		var best_de: Vector2i = _dead_ends[0]
		var best_dist: float = INF
		for de: Vector2i in _dead_ends:
			var dist := Vector2(de.x, de.y).length()  # distance from (0,0)
			if dist < best_dist:
				best_dist = dist
				best_de = de
		_player_spawn = Vector3(
			_grid_to_world_x(best_de.x) + CELL_SIZE * 0.5, 0.5,
			_grid_to_world_z(best_de.y) + CELL_SIZE * 0.5
		)
	else:
		# Fallback: first room
		if _rooms.size() > 0:
			var sc = _rooms[0].center()
			_player_spawn = Vector3(
				_grid_to_world_x(sc.x), 0.5, _grid_to_world_z(sc.y)
			)
		else:
			_player_spawn = Vector3(CELL_SIZE * 5, 0.5, CELL_SIZE * 5)

	# Enemy spawns in arena rooms and caverns
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

	# Spawns in regular rooms too
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms:
			continue
		var area: int = room.w * room.h
		if area < ROOM_MIN_SIZE * ROOM_MIN_SIZE:
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

	# Some spawns in dead-end corridors
	for de: Vector2i in _dead_ends:
		if _rng.randf() < 0.3:
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(de.x) + CELL_SIZE * 0.5, 0.5,
				_grid_to_world_z(de.y) + CELL_SIZE * 0.5
			))

	if _enemy_spawns.is_empty():
		for room: Rect2i_BSP in _rooms:
			var center := room.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(center.x), 0.5, _grid_to_world_z(center.y)
			))
