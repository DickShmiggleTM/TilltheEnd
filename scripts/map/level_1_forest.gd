extends Node3D
## Level 1: The Cursed Forest
## A wide outdoor forest area with clearings connected by paths, a central
## two-story house, and scattered ritual sites. Uses BSP to partition the
## space into clearings and dense tree zones. NO ceiling — outdoor level.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRID_WIDTH: int = 80
const GRID_HEIGHT: int = 80
const CELL_SIZE: float = 4.0
const WALL_HEIGHT: float = 4.0

const MIN_PARTITION_SIZE: int = 10
const MAX_PARTITION_SIZE: int = 30
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 6
const ARENA_THRESHOLD: int = 12
const CORRIDOR_WIDTH: int = 3

const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 25
const MIN_ARENA_SPAWNS: int = 3

const RITUAL_SITE_COUNT_MIN: int = 3
const RITUAL_SITE_COUNT_MAX: int = 5
const RITUAL_STONE_COUNT: int = 6
const RITUAL_STONE_RADIUS: float = 5.0

const HOUSE_SIZE: int = 12  # cells
const HOUSE_FLOOR_HEIGHT: float = 4.0

# ---------------------------------------------------------------------------
# Cell types
# ---------------------------------------------------------------------------

enum Cell {
	VOID = 0,
	FLOOR = 1,
	WALL = 2,
	PATH = 3,
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
var _clearings: Array = []  # Same as rooms but named for clarity
var _ritual_sites: Array = []  # Array of Vector2i (grid centers)
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null

var _house_rect: Rect2i_BSP = null  # The central house footprint

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

var _mat_floor: StandardMaterial3D = null
var _mat_path: StandardMaterial3D = null
var _mat_tree_trunk: StandardMaterial3D = null
var _mat_foliage: StandardMaterial3D = null
var _mat_house_wall: StandardMaterial3D = null
var _mat_house_floor: StandardMaterial3D = null
var _mat_ritual_stone: StandardMaterial3D = null
var _mat_ritual_circle: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_map(seed_value: int) -> void:
	clear_map()
	_rng.seed = seed_value

	_create_materials()
	_init_grid()

	# BSP partition to create clearings
	var root := BSPNode.new(Rect2i_BSP.new(0, 0, GRID_WIDTH, GRID_HEIGHT))
	_split_bsp(root, 0)
	_create_rooms(root)
	_connect_rooms(root)
	_build_walls()
	_classify_rooms()

	# Place the central house
	_place_house()

	# Place ritual sites in clearings
	_place_ritual_sites()

	# Build 3D geometry
	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_build_geometry()
	_build_trees()
	_build_house()
	_build_ritual_sites()
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
	_clearings.clear()
	_ritual_sites.clear()
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO
	_house_rect = null


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
	return cell == Cell.FLOOR or cell == Cell.PATH

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Ground / grass-dirt floor
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.15, 0.1, 0.05)
	_mat_floor.roughness = 0.95
	_mat_floor.metallic = 0.0

	# Path (slightly lighter dirt)
	_mat_path = StandardMaterial3D.new()
	_mat_path.albedo_color = Color(0.18, 0.12, 0.07)
	_mat_path.roughness = 0.9
	_mat_path.metallic = 0.0

	# Tree trunk (brown)
	_mat_tree_trunk = StandardMaterial3D.new()
	_mat_tree_trunk.albedo_color = Color(0.25, 0.15, 0.08)
	_mat_tree_trunk.roughness = 0.9
	_mat_tree_trunk.metallic = 0.0

	# Foliage / tree walls (dark green)
	_mat_foliage = StandardMaterial3D.new()
	_mat_foliage.albedo_color = Color(0.12, 0.18, 0.08)
	_mat_foliage.roughness = 0.85
	_mat_foliage.metallic = 0.0

	# House walls (dark brown)
	_mat_house_wall = StandardMaterial3D.new()
	_mat_house_wall.albedo_color = Color(0.2, 0.12, 0.06)
	_mat_house_wall.roughness = 0.85
	_mat_house_wall.metallic = 0.0

	# House floor (wood brown)
	_mat_house_floor = StandardMaterial3D.new()
	_mat_house_floor.albedo_color = Color(0.3, 0.2, 0.1)
	_mat_house_floor.roughness = 0.8
	_mat_house_floor.metallic = 0.0

	# Ritual standing stones (dark gray)
	_mat_ritual_stone = StandardMaterial3D.new()
	_mat_ritual_stone.albedo_color = Color(0.15, 0.15, 0.17)
	_mat_ritual_stone.roughness = 0.7
	_mat_ritual_stone.metallic = 0.1

	# Ritual circle (red)
	_mat_ritual_circle = StandardMaterial3D.new()
	_mat_ritual_circle.albedo_color = Color(0.5, 0.05, 0.02)
	_mat_ritual_circle.roughness = 0.6
	_mat_ritual_circle.metallic = 0.05
	_mat_ritual_circle.emission_enabled = true
	_mat_ritual_circle.emission = Color(0.4, 0.02, 0.02)
	_mat_ritual_circle.emission_energy_multiplier = 0.5

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
		var min_y: int = node.rect.y + MIN_PARTITION_SIZE
		var max_y: int = node.rect.y + node.rect.h - MIN_PARTITION_SIZE
		if min_y >= max_y:
			return
		var split_y: int = _rng.randi_range(min_y, max_y)
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y, node.rect.w, split_y - node.rect.y
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, split_y, node.rect.w, node.rect.y + node.rect.h - split_y
		))
	else:
		var min_x: int = node.rect.x + MIN_PARTITION_SIZE
		var max_x: int = node.rect.x + node.rect.w - MIN_PARTITION_SIZE
		if min_x >= max_x:
			return
		var split_x: int = _rng.randi_range(min_x, max_x)
		node.left = BSPNode.new(Rect2i_BSP.new(
			node.rect.x, node.rect.y, split_x - node.rect.x, node.rect.h
		))
		node.right = BSPNode.new(Rect2i_BSP.new(
			split_x, node.rect.y, node.rect.x + node.rect.w - split_x, node.rect.h
		))

	_split_bsp(node.left, depth + 1)
	_split_bsp(node.right, depth + 1)

# ---------------------------------------------------------------------------
# Room (clearing) creation
# ---------------------------------------------------------------------------

func _create_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		var rw: int = _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		)
		var rh: int = _rng.randi_range(
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN * 3),
			maxi(MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)
		)
		rw = clampi(rw, MIN_ROOM_SIZE, node.rect.w - ROOM_MARGIN)
		rh = clampi(rh, MIN_ROOM_SIZE, node.rect.h - ROOM_MARGIN)

		var rx: int = _rng.randi_range(
			node.rect.x + 1,
			maxi(node.rect.x + 1, node.rect.x + node.rect.w - rw - 1)
		)
		var ry: int = _rng.randi_range(
			node.rect.y + 1,
			maxi(node.rect.y + 1, node.rect.y + node.rect.h - rh - 1)
		)

		rx = clampi(rx, 1, GRID_WIDTH - rw - 1)
		ry = clampi(ry, 1, GRID_HEIGHT - rh - 1)
		rw = mini(rw, GRID_WIDTH - rx - 1)
		rh = mini(rh, GRID_HEIGHT - ry - 1)

		node.room = Rect2i_BSP.new(rx, ry, rw, rh)
		_rooms.append(node.room)
		_clearings.append(node.room)

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

# ---------------------------------------------------------------------------
# Corridor (path) connections
# ---------------------------------------------------------------------------

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
			var cy: int = y + dy
			if _get_cell(x, cy) == Cell.VOID:
				_set_cell(x, cy, Cell.PATH)


func _carve_vertical(y1: int, y2: int, x: int) -> void:
	var start_y: int = mini(y1, y2)
	var end_y: int = maxi(y1, y2)
	for y in range(start_y, end_y + 1):
		for dx in range(CORRIDOR_WIDTH):
			var cx: int = x + dx
			if _get_cell(cx, y) == Cell.VOID:
				_set_cell(cx, y, Cell.PATH)

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
			if c == Cell.FLOOR or c == Cell.PATH:
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
# House placement
# ---------------------------------------------------------------------------

func _place_house() -> void:
	# Find the room closest to the grid center for the house
	var grid_center := Vector2i(GRID_WIDTH / 2, GRID_HEIGHT / 2)
	var best_room: Rect2i_BSP = null
	var best_dist: float = INF

	for room: Rect2i_BSP in _rooms:
		if room.w >= HOUSE_SIZE and room.h >= HOUSE_SIZE:
			var c := room.center()
			var dist := Vector2(c.x - grid_center.x, c.y - grid_center.y).length()
			if dist < best_dist:
				best_dist = dist
				best_room = room

	# Fallback: use largest room
	if best_room == null:
		var sorted_rooms := _rooms.duplicate()
		sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
			return (a.w * a.h) > (b.w * b.h)
		)
		best_room = sorted_rooms[0]

	var hx: int = best_room.x + (best_room.w - HOUSE_SIZE) / 2
	var hy: int = best_room.y + (best_room.h - HOUSE_SIZE) / 2
	hx = clampi(hx, 1, GRID_WIDTH - HOUSE_SIZE - 1)
	hy = clampi(hy, 1, GRID_HEIGHT - HOUSE_SIZE - 1)
	_house_rect = Rect2i_BSP.new(hx, hy, HOUSE_SIZE, HOUSE_SIZE)

	# Mark house cells as floor
	for x in range(hx, hx + HOUSE_SIZE):
		for y in range(hy, hy + HOUSE_SIZE):
			_set_cell(x, y, Cell.FLOOR)

# ---------------------------------------------------------------------------
# Ritual site placement
# ---------------------------------------------------------------------------

func _place_ritual_sites() -> void:
	_ritual_sites.clear()
	var count := _rng.randi_range(RITUAL_SITE_COUNT_MIN, RITUAL_SITE_COUNT_MAX)

	# Use clearing centers, pick ones spread apart
	var available: Array = []
	for room: Rect2i_BSP in _clearings:
		var c := room.center()
		# Don't place rituals in the house
		if _house_rect and c.x >= _house_rect.x and c.x < _house_rect.x + _house_rect.w \
			and c.y >= _house_rect.y and c.y < _house_rect.y + _house_rect.h:
			continue
		available.append(c)

	# Shuffle and pick
	for i in range(available.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = available[i]
		available[i] = available[j]
		available[j] = tmp

	for i in range(mini(count, available.size())):
		_ritual_sites.append(available[i])

# ---------------------------------------------------------------------------
# Geometry building
# ---------------------------------------------------------------------------

func _grid_to_world_x(gx: float) -> float:
	return gx * CELL_SIZE


func _grid_to_world_z(gy: float) -> float:
	return gy * CELL_SIZE


func _build_geometry() -> void:
	# Build floor strips for FLOOR cells
	var floor_strips := _build_horizontal_strips(Cell.FLOOR)
	for strip: Rect2i_BSP in floor_strips:
		_create_floor_box(strip, _mat_floor)

	# Build floor strips for PATH cells
	var path_strips := _build_horizontal_strips(Cell.PATH)
	for strip: Rect2i_BSP in path_strips:
		_create_floor_box(strip, _mat_path)

	# Walls are tree masses — handled by _build_trees()
	# NO ceiling for this outdoor level


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

# ---------------------------------------------------------------------------
# Tree generation — WALL cells become tree clusters
# ---------------------------------------------------------------------------

func _build_trees() -> void:
	# For wall cells, place tree-like obstacles. We batch wall strips first
	# then scatter individual tree trunks + canopies on them.
	var wall_strips := _build_horizontal_strips(Cell.WALL)

	for strip: Rect2i_BSP in wall_strips:
		# Create a solid collision block for the tree wall
		var wall_box := CSGBox3D.new()
		wall_box.size = Vector3(strip.w * CELL_SIZE, WALL_HEIGHT, strip.h * CELL_SIZE)
		wall_box.position = Vector3(
			_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5,
			WALL_HEIGHT * 0.5,
			_grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
		)
		wall_box.use_collision = true
		wall_box.collision_layer = ENVIRONMENT_LAYER
		wall_box.collision_mask = 0
		wall_box.material = _mat_foliage
		wall_box.name = "TreeWall_%d_%d" % [strip.x, strip.y]
		_geometry_root.add_child(wall_box)

	# Scatter decorative tree trunks on top of wall areas for visual variety
	for x in range(GRID_WIDTH):
		for y in range(GRID_HEIGHT):
			if _grid[x][y] == Cell.WALL:
				if _rng.randf() < 0.12:
					_create_tree_trunk(x, y)


func _create_tree_trunk(gx: int, gy: int) -> void:
	var world_x := _grid_to_world_x(gx) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)
	var world_z := _grid_to_world_z(gy) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)

	var trunk_height := _rng.randf_range(4.0, 7.0)
	var trunk_radius := _rng.randf_range(0.25, 0.5)

	# Trunk cylinder
	var trunk := CSGCylinder3D.new()
	trunk.radius = trunk_radius
	trunk.height = trunk_height
	trunk.sides = 6
	trunk.position = Vector3(world_x, trunk_height * 0.5 + WALL_HEIGHT, world_z)
	trunk.material = _mat_tree_trunk
	trunk.use_collision = false
	trunk.name = "Trunk_%d_%d" % [gx, gy]
	_geometry_root.add_child(trunk)

	# Canopy (green sphere-like top) — use CSGCylinder for a flat disc shape
	var canopy_radius := _rng.randf_range(1.5, 3.0)
	var canopy := CSGCylinder3D.new()
	canopy.radius = canopy_radius
	canopy.height = _rng.randf_range(1.5, 3.0)
	canopy.sides = 8
	canopy.position = Vector3(world_x, trunk_height + WALL_HEIGHT, world_z)
	canopy.material = _mat_foliage
	canopy.use_collision = false
	canopy.name = "Canopy_%d_%d" % [gx, gy]
	_geometry_root.add_child(canopy)

# ---------------------------------------------------------------------------
# House construction
# ---------------------------------------------------------------------------

func _build_house() -> void:
	if _house_rect == null:
		return

	var hx := _grid_to_world_x(_house_rect.x)
	var hz := _grid_to_world_z(_house_rect.y)
	var hw := _house_rect.w * CELL_SIZE
	var hh := _house_rect.h * CELL_SIZE
	var wall_thick: float = 0.5

	# --- Ground floor ---
	# Floor
	var gf := CSGBox3D.new()
	gf.size = Vector3(hw, 0.3, hh)
	gf.position = Vector3(hx + hw * 0.5, 0.0, hz + hh * 0.5)
	gf.use_collision = true
	gf.collision_layer = ENVIRONMENT_LAYER
	gf.collision_mask = 0
	gf.material = _mat_house_floor
	gf.name = "HouseFloor_G"
	_geometry_root.add_child(gf)

	# Outer walls — four sides with doorways
	# North wall (full)
	_create_house_wall(Vector3(hx + hw * 0.5, WALL_HEIGHT * 0.5, hz), Vector3(hw, WALL_HEIGHT, wall_thick))
	# South wall (with gap for door in center)
	var door_w: float = CELL_SIZE * 2.0
	var half_w: float = (hw - door_w) * 0.5
	_create_house_wall(Vector3(hx + half_w * 0.5, WALL_HEIGHT * 0.5, hz + hh), Vector3(half_w, WALL_HEIGHT, wall_thick))
	_create_house_wall(Vector3(hx + hw - half_w * 0.5, WALL_HEIGHT * 0.5, hz + hh), Vector3(half_w, WALL_HEIGHT, wall_thick))
	# East wall (with door gap)
	var half_h: float = (hh - door_w) * 0.5
	_create_house_wall(Vector3(hx + hw, WALL_HEIGHT * 0.5, hz + half_h * 0.5), Vector3(wall_thick, WALL_HEIGHT, half_h))
	_create_house_wall(Vector3(hx + hw, WALL_HEIGHT * 0.5, hz + hh - half_h * 0.5), Vector3(wall_thick, WALL_HEIGHT, half_h))
	# West wall (full)
	_create_house_wall(Vector3(hx, WALL_HEIGHT * 0.5, hz + hh * 0.5), Vector3(wall_thick, WALL_HEIGHT, hh))

	# Interior dividing wall (vertical, splitting house roughly in half with a doorway)
	var mid_x := hx + hw * 0.5
	_create_house_wall(Vector3(mid_x, WALL_HEIGHT * 0.5, hz + hh * 0.25), Vector3(wall_thick, WALL_HEIGHT, hh * 0.35))
	_create_house_wall(Vector3(mid_x, WALL_HEIGHT * 0.5, hz + hh * 0.8), Vector3(wall_thick, WALL_HEIGHT, hh * 0.25))

	# Interior dividing wall (horizontal, splitting each half)
	var mid_z := hz + hh * 0.5
	_create_house_wall(Vector3(hx + hw * 0.2, WALL_HEIGHT * 0.5, mid_z), Vector3(hw * 0.3, WALL_HEIGHT, wall_thick))
	_create_house_wall(Vector3(hx + hw * 0.85, WALL_HEIGHT * 0.5, mid_z), Vector3(hw * 0.2, WALL_HEIGHT, wall_thick))

	# Furniture-like boxes (tables, shelves)
	for i in range(6):
		var fx := hx + _rng.randf_range(2.0, hw - 2.0)
		var fz := hz + _rng.randf_range(2.0, hh - 2.0)
		var fbox := CSGBox3D.new()
		fbox.size = Vector3(_rng.randf_range(0.8, 2.0), _rng.randf_range(0.5, 1.2), _rng.randf_range(0.8, 2.0))
		fbox.position = Vector3(fx, fbox.size.y * 0.5, fz)
		fbox.use_collision = true
		fbox.collision_layer = ENVIRONMENT_LAYER
		fbox.collision_mask = 0
		fbox.material = _mat_house_wall
		fbox.name = "Furniture_%d" % i
		_geometry_root.add_child(fbox)

	# --- Second floor ---
	var second_y := HOUSE_FLOOR_HEIGHT

	# Second floor platform
	var sf := CSGBox3D.new()
	sf.size = Vector3(hw, 0.3, hh)
	sf.position = Vector3(hx + hw * 0.5, second_y, hz + hh * 0.5)
	sf.use_collision = true
	sf.collision_layer = ENVIRONMENT_LAYER
	sf.collision_mask = 0
	sf.material = _mat_house_floor
	sf.name = "HouseFloor_2"
	_geometry_root.add_child(sf)

	# Second floor walls (shorter)
	var upper_wall_h := WALL_HEIGHT * 0.8
	_create_house_wall(
		Vector3(hx + hw * 0.5, second_y + upper_wall_h * 0.5, hz),
		Vector3(hw, upper_wall_h, wall_thick)
	)
	_create_house_wall(
		Vector3(hx + hw * 0.5, second_y + upper_wall_h * 0.5, hz + hh),
		Vector3(hw, upper_wall_h, wall_thick)
	)
	_create_house_wall(
		Vector3(hx + hw, second_y + upper_wall_h * 0.5, hz + hh * 0.5),
		Vector3(wall_thick, upper_wall_h, hh)
	)
	_create_house_wall(
		Vector3(hx, second_y + upper_wall_h * 0.5, hz + hh * 0.5),
		Vector3(wall_thick, upper_wall_h, hh)
	)

	# Second floor interior wall
	_create_house_wall(
		Vector3(mid_x, second_y + upper_wall_h * 0.5, hz + hh * 0.3),
		Vector3(wall_thick, upper_wall_h, hh * 0.4)
	)

	# Stairway ramp — from ground floor south-east corner going up
	var ramp := CSGBox3D.new()
	var ramp_length: float = CELL_SIZE * 4.0
	ramp.size = Vector3(CELL_SIZE * 2.0, 0.3, ramp_length)
	ramp.position = Vector3(
		hx + hw - CELL_SIZE * 1.5,
		second_y * 0.5,
		hz + hh - ramp_length * 0.5 - 1.0
	)
	ramp.rotation.x = -atan2(second_y, ramp_length)
	ramp.use_collision = true
	ramp.collision_layer = ENVIRONMENT_LAYER
	ramp.collision_mask = 0
	ramp.material = _mat_house_floor
	ramp.name = "Stairway"
	_geometry_root.add_child(ramp)

	# House light inside
	var house_light := OmniLight3D.new()
	house_light.name = "HouseLight"
	house_light.light_color = Color(0.8, 0.6, 0.3)
	house_light.light_energy = 1.5
	house_light.omni_range = hw * 0.6
	house_light.omni_attenuation = 1.5
	house_light.shadow_enabled = false
	house_light.position = Vector3(hx + hw * 0.5, WALL_HEIGHT * 0.7, hz + hh * 0.5)
	_lighting_root.add_child(house_light)


func _create_house_wall(pos: Vector3, sz: Vector3) -> void:
	var wall := CSGBox3D.new()
	wall.size = sz
	wall.position = pos
	wall.use_collision = true
	wall.collision_layer = ENVIRONMENT_LAYER
	wall.collision_mask = 0
	wall.material = _mat_house_wall
	wall.name = "HouseWall"
	_geometry_root.add_child(wall)

# ---------------------------------------------------------------------------
# Ritual sites
# ---------------------------------------------------------------------------

func _build_ritual_sites() -> void:
	for i in range(_ritual_sites.size()):
		var site: Vector2i = _ritual_sites[i]
		var world_x := _grid_to_world_x(site.x)
		var world_z := _grid_to_world_z(site.y)

		# Red circle on the ground
		var circle := CSGCylinder3D.new()
		circle.radius = RITUAL_STONE_RADIUS * 0.7
		circle.height = 0.05
		circle.sides = 24
		circle.position = Vector3(world_x, 0.03, world_z)
		circle.material = _mat_ritual_circle
		circle.use_collision = false
		circle.name = "RitualCircle_%d" % i
		_geometry_root.add_child(circle)

		# Standing stones in a circle
		for s in range(RITUAL_STONE_COUNT):
			var angle := (TAU / RITUAL_STONE_COUNT) * s
			var sx := world_x + cos(angle) * RITUAL_STONE_RADIUS
			var sz := world_z + sin(angle) * RITUAL_STONE_RADIUS
			var stone_h := _rng.randf_range(2.0, 3.5)

			var stone := CSGCylinder3D.new()
			stone.radius = _rng.randf_range(0.3, 0.6)
			stone.height = stone_h
			stone.sides = 5
			stone.position = Vector3(sx, stone_h * 0.5, sz)
			stone.material = _mat_ritual_stone
			stone.use_collision = true
			stone.collision_layer = ENVIRONMENT_LAYER
			stone.collision_mask = 0
			stone.name = "RitualStone_%d_%d" % [i, s]
			_geometry_root.add_child(stone)

		# Red OmniLight at the ritual site
		var light := OmniLight3D.new()
		light.name = "RitualLight_%d" % i
		light.light_color = Color(0.8, 0.1, 0.05)
		light.light_energy = 1.8
		light.omni_range = RITUAL_STONE_RADIUS * 2.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.position = Vector3(world_x, 2.0, world_z)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Environment (lighting, fog, world environment)
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.03)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.25, 0.1)
	env.ambient_light_energy = 0.4

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.12, 0.05)
	env.fog_density = 0.008
	env.fog_light_energy = 0.5

	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Directional light — dim, murky natural light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = Color(0.4, 0.5, 0.3)
	dir_light.light_energy = 0.5
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-50, -20, 0)
	_lighting_root.add_child(dir_light)

	# Ambient accent lights scattered in clearings
	for room: Rect2i_BSP in _arena_rooms:
		var center := room.center()
		var light := OmniLight3D.new()
		light.name = "ClearingLight_%d_%d" % [center.x, center.y]
		light.light_color = Color(0.3, 0.5, 0.15)
		light.light_energy = _rng.randf_range(0.6, 1.2)
		light.omni_range = maxi(room.w, room.h) * CELL_SIZE * 0.5
		light.omni_attenuation = 1.8
		light.shadow_enabled = false
		light.position = Vector3(
			_grid_to_world_x(center.x), WALL_HEIGHT * 0.6, _grid_to_world_z(center.y)
		)
		_lighting_root.add_child(light)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns at the first (smallest) ritual site
	if _ritual_sites.size() > 0:
		# Sort by distance from corner (first/smallest)
		var sorted_sites := _ritual_sites.duplicate()
		sorted_sites.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a.x + a.y) < (b.x + b.y)
		)
		var spawn_site: Vector2i = sorted_sites[0]
		_player_spawn = Vector3(
			_grid_to_world_x(spawn_site.x), 0.5, _grid_to_world_z(spawn_site.y)
		)
	else:
		# Fallback: smallest room
		var sorted_rooms := _rooms.duplicate()
		sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool:
			return (a.w * a.h) < (b.w * b.h)
		)
		var sc = sorted_rooms[0].center()
		_player_spawn = Vector3(_grid_to_world_x(sc.x), 0.5, _grid_to_world_z(sc.y))

	# Enemy spawns in arena rooms and clearings
	for room: Rect2i_BSP in _arena_rooms:
		var area: int = room.w * room.h
		@warning_ignore("integer_division")
		var spawn_count: int = maxi(MIN_ARENA_SPAWNS, area / ARENA_SPAWN_DENSITY)
		for i in range(spawn_count):
			var sx: int = _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy: int = _rng.randi_range(room.y + 1, room.y + room.h - 2)
			var c := _get_cell(sx, sy)
			if c == Cell.FLOOR or c == Cell.PATH:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Some spawns in non-arena clearings
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
			var c := _get_cell(sx, sy)
			if c == Cell.FLOOR or c == Cell.PATH:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Ensure we have spawns
	if _enemy_spawns.is_empty():
		for room: Rect2i_BSP in _rooms:
			var center := room.center()
			_enemy_spawns.append(Vector3(
				_grid_to_world_x(center.x), 0.5, _grid_to_world_z(center.y)
			))
