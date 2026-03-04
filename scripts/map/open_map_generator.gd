extends Node3D
## Unified OPEN map generator for outdoor levels.
## Reads level configuration from GameManager.current_level_data.
##
## Features:
##   - BSP-based clearing (open area) generation
##   - No ceiling — outdoor feel with skybox/fog horizon
##   - Solid barrier walls (trees, pillars, ruins) around clearings
##   - Object scatter: rocks, stumps, logs, ritual sites, altars based on prop_type
##   - Subtle low-poly terrain height variation
##   - Level-themed materials (forest green, courtyard stone, etc.)
##   - Proper enemy spawn points in clearings

# ---------------------------------------------------------------------------
# Inner classes (duplicated to stay self-contained)
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
# Cell types
# ---------------------------------------------------------------------------

enum Cell { VOID = 0, FLOOR = 1, WALL = 2, PATH = 3 }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CELL_SIZE: float = 4.0
const ENVIRONMENT_LAYER: int = 1
const ARENA_SPAWN_DENSITY: int = 20
const MIN_ARENA_SPAWNS: int = 3
const ARENA_THRESHOLD: int = 12
const MIN_PARTITION_SIZE: int = 10
const ROOM_MARGIN: int = 2
const MIN_ROOM_SIZE: int = 6
const CORRIDOR_WIDTH: int = 3

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _grid: Array = []
var _rooms: Array = []
var _arena_rooms: Array = []
var _scatter_sites: Array = []   # World-space positions for prop scatter
var _player_spawn: Vector3 = Vector3.ZERO
var _enemy_spawns: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _geometry_root: Node3D = null
var _lighting_root: Node3D = null

# Config loaded from level data
var _grid_size: int = 80
var _prop_type: String = "forest"
var _scatter_density: float = 0.12
var _terrain_height: float = 0.5
var _barrier_height: float = 5.0
var _site_count_min: int = 3
var _site_count_max: int = 5

# Materials
var _mat_floor: StandardMaterial3D = null
var _mat_path: StandardMaterial3D = null
var _mat_barrier: StandardMaterial3D = null
var _mat_barrier_accent: StandardMaterial3D = null
var _mat_prop_a: StandardMaterial3D = null
var _mat_prop_b: StandardMaterial3D = null
var _mat_site_marker: StandardMaterial3D = null

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
	_build_wall_border()
	_classify_rooms()

	_geometry_root = Node3D.new()
	_geometry_root.name = "MapGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "MapLighting"
	add_child(_lighting_root)

	_build_floor_geometry()
	_build_barriers()
	_build_terrain_details()
	_build_scatter_props()
	_build_special_sites()
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
	_scatter_sites.clear()
	_enemy_spawns.clear()
	_player_spawn = Vector3.ZERO


func get_room_data() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for room: Rect2i_BSP in _rooms:
		var center := room.center()
		data.append({
			"position": Vector3(_grid_to_world_x(center.x), 0.0, _grid_to_world_z(center.y)),
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
	return c == Cell.FLOOR or c == Cell.PATH

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

func _load_config() -> void:
	var level_data: Dictionary = GameManager.current_level_data
	var cfg: Dictionary = level_data.get("map_config", {})
	_grid_size = cfg.get("grid_size", 80)
	_prop_type = cfg.get("prop_type", "forest")
	_scatter_density = cfg.get("scatter_density", 0.12)
	_terrain_height = cfg.get("terrain_height", 0.5)
	_barrier_height = cfg.get("barrier_height", 5.0)
	_site_count_min = cfg.get("site_count_min", 3)
	_site_count_max = cfg.get("site_count_max", 5)

# ---------------------------------------------------------------------------
# Materials — themed per prop_type
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	match _prop_type:
		"courtyard":
			_mat_floor = _make_mat(Color(0.22, 0.18, 0.15), 0.85)         # stone
			_mat_path = _make_mat(Color(0.28, 0.24, 0.20), 0.80)           # lighter stone path
			_mat_barrier = _make_mat(Color(0.25, 0.20, 0.16), 0.90)        # stone walls
			_mat_barrier_accent = _make_mat(Color(0.32, 0.25, 0.20), 0.70)
			_mat_prop_a = _make_mat(Color(0.30, 0.24, 0.18), 0.75)         # stone pillar
			_mat_prop_b = _make_mat(Color(0.35, 0.08, 0.06), 0.60, true, Color(0.3, 0.04, 0.02))  # altar (glowing)
			_mat_site_marker = _make_mat(Color(0.5, 0.08, 0.04), 0.55, true, Color(0.4, 0.04, 0.02))
		_:  # "forest" default
			_mat_floor = _make_mat(Color(0.15, 0.10, 0.05), 0.95)
			_mat_path = _make_mat(Color(0.18, 0.12, 0.07), 0.90)
			_mat_barrier = _make_mat(Color(0.12, 0.18, 0.08), 0.85)        # foliage wall
			_mat_barrier_accent = _make_mat(Color(0.25, 0.15, 0.08), 0.90) # tree trunk
			_mat_prop_a = _make_mat(Color(0.15, 0.15, 0.17), 0.70)         # stone/rock
			_mat_prop_b = _make_mat(Color(0.20, 0.12, 0.06), 0.85)         # log / stump
			_mat_site_marker = _make_mat(Color(0.5, 0.05, 0.02), 0.60, true, Color(0.4, 0.02, 0.02))


func _make_mat(color: Color, roughness: float, emit: bool = false, emit_color: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	if emit:
		m.emission_enabled = true
		m.emission = emit_color
		m.emission_energy_multiplier = 0.6
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
	var max_part: int = maxi(20, _grid_size / 4)
	if node.rect.w <= max_part and node.rect.h <= max_part:
		if node.rect.w < MIN_PARTITION_SIZE * 2 and node.rect.h < MIN_PARTITION_SIZE * 2:
			return
		if depth > 3 and _rng.randf() < 0.25:
			return

	var can_h: bool = node.rect.h >= MIN_PARTITION_SIZE * 2
	var can_v: bool = node.rect.w >= MIN_PARTITION_SIZE * 2
	if not can_h and not can_v:
		return

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
# Room / clearing creation
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
# Corridor paths
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
				_set_cell(x, y + dy, Cell.PATH)


func _carve_vert(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		for dx in range(CORRIDOR_WIDTH):
			if _get_cell(x + dx, y) == Cell.VOID:
				_set_cell(x + dx, y, Cell.PATH)

# ---------------------------------------------------------------------------
# Wall border — VOID adjacent to walkable becomes WALL
# ---------------------------------------------------------------------------

func _build_wall_border() -> void:
	var wall_cells: Array[Vector2i] = []
	for x in range(_grid_size):
		for y in range(_grid_size):
			if _grid[x][y] == Cell.VOID and _has_walkable_neighbor(x, y):
				wall_cells.append(Vector2i(x, y))
	for pos in wall_cells:
		_grid[pos.x][pos.y] = Cell.WALL


func _has_walkable_neighbor(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
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
		var sorted := _rooms.duplicate()
		sorted.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool: return (a.w * a.h) > (b.w * b.h))
		@warning_ignore("integer_division")
		var cnt := maxi(1, sorted.size() / 3)
		for i in range(cnt):
			_arena_rooms.append(sorted[i])

# ---------------------------------------------------------------------------
# Geometry — floor + paths
# ---------------------------------------------------------------------------

func _build_floor_geometry() -> void:
	for strip in _build_strips(Cell.FLOOR):
		_make_box(
			Vector3(_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5, -0.1, _grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5),
			Vector3(strip.w * CELL_SIZE, 0.2, strip.h * CELL_SIZE),
			_mat_floor, "Floor_%d_%d" % [strip.x, strip.y], true
		)
	for strip in _build_strips(Cell.PATH):
		_make_box(
			Vector3(_grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5, -0.08, _grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5),
			Vector3(strip.w * CELL_SIZE, 0.16, strip.h * CELL_SIZE),
			_mat_path, "Path_%d_%d" % [strip.x, strip.y], true
		)

# ---------------------------------------------------------------------------
# Barriers — wall cells become opaque barriers (trees / stone walls)
# ---------------------------------------------------------------------------

func _build_barriers() -> void:
	for strip in _build_strips(Cell.WALL):
		var wx := _grid_to_world_x(strip.x) + strip.w * CELL_SIZE * 0.5
		var wz := _grid_to_world_z(strip.y) + strip.h * CELL_SIZE * 0.5
		_make_box(
			Vector3(wx, _barrier_height * 0.5, wz),
			Vector3(strip.w * CELL_SIZE, _barrier_height, strip.h * CELL_SIZE),
			_mat_barrier, "Barrier_%d_%d" % [strip.x, strip.y], true
		)

	# Scatter decorative props on barrier cells
	if _prop_type == "forest":
		_scatter_tree_trunks()
	elif _prop_type == "courtyard":
		_scatter_courtyard_pillars()

# ---------------------------------------------------------------------------
# Terrain detail — slight height bumps on floor for low-poly look
# ---------------------------------------------------------------------------

func _build_terrain_details() -> void:
	if _terrain_height <= 0.0:
		return
	# Scatter small terrain bumps in non-path floor areas
	for room: Rect2i_BSP in _rooms:
		var bump_count := int((room.w * room.h) * 0.04)
		for _i in range(bump_count):
			var bx := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var by := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			if _get_cell(bx, by) == Cell.FLOOR:
				var bw := _rng.randf_range(CELL_SIZE * 0.5, CELL_SIZE * 2.0)
				var bh := _rng.randf_range(_terrain_height * 0.2, _terrain_height)
				var box := CSGBox3D.new()
				box.size = Vector3(bw, bh, bw * _rng.randf_range(0.6, 1.4))
				box.position = Vector3(
					_grid_to_world_x(bx) + CELL_SIZE * 0.5 + _rng.randf_range(-1.0, 1.0),
					bh * 0.5,
					_grid_to_world_z(by) + CELL_SIZE * 0.5 + _rng.randf_range(-1.0, 1.0)
				)
				box.use_collision = false
				box.material = _mat_floor
				box.name = "TerrainBump_%d_%d" % [bx, by]
				_geometry_root.add_child(box)

# ---------------------------------------------------------------------------
# Scatter props — rocks, stumps, logs in rooms
# ---------------------------------------------------------------------------

func _build_scatter_props() -> void:
	for x in range(_grid_size):
		for y in range(_grid_size):
			if _grid[x][y] == Cell.FLOOR and _rng.randf() < _scatter_density:
				_place_scatter_prop(x, y)


func _place_scatter_prop(gx: int, gy: int) -> void:
	var wx := _grid_to_world_x(gx) + CELL_SIZE * 0.5 + _rng.randf_range(-0.8, 0.8)
	var wz := _grid_to_world_z(gy) + CELL_SIZE * 0.5 + _rng.randf_range(-0.8, 0.8)

	match _prop_type:
		"courtyard":
			# Scattered altar stones / debris
			var h := _rng.randf_range(0.3, 1.0)
			var r := _rng.randf_range(0.2, 0.6)
			var cyl := CSGCylinder3D.new()
			cyl.radius = r
			cyl.height = h
			cyl.sides = _rng.randi_range(4, 7)
			cyl.position = Vector3(wx, h * 0.5, wz)
			cyl.use_collision = false
			cyl.material = _mat_prop_a
			cyl.name = "Debris_%d_%d" % [gx, gy]
			_geometry_root.add_child(cyl)
		_:  # forest
			# Rock or log
			if _rng.randf() < 0.6:
				# Rock
				var sz := _rng.randf_range(0.3, 1.2)
				var rock := CSGBox3D.new()
				rock.size = Vector3(sz, sz * _rng.randf_range(0.5, 1.0), sz * _rng.randf_range(0.7, 1.3))
				rock.position = Vector3(wx, rock.size.y * 0.5, wz)
				rock.rotation.y = _rng.randf_range(0.0, TAU)
				rock.use_collision = false
				rock.material = _mat_prop_a
				rock.name = "Rock_%d_%d" % [gx, gy]
				_geometry_root.add_child(rock)
			else:
				# Log (short cylinder lying on side)
				var log := CSGCylinder3D.new()
				log.radius = _rng.randf_range(0.15, 0.35)
				log.height = _rng.randf_range(1.0, 2.5)
				log.sides = 6
				log.position = Vector3(wx, log.radius, wz)
				log.rotation = Vector3(PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)
				log.use_collision = false
				log.material = _mat_prop_b
				log.name = "Log_%d_%d" % [gx, gy]
				_geometry_root.add_child(log)

# ---------------------------------------------------------------------------
# Special sites — ritual circles, altars, focal points
# ---------------------------------------------------------------------------

func _build_special_sites() -> void:
	_scatter_sites.clear()
	var count := _rng.randi_range(_site_count_min, _site_count_max)
	var candidates: Array = []
	for room: Rect2i_BSP in _rooms:
		var c := room.center()
		candidates.append(Vector2i(c.x, c.y))

	# Shuffle
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = candidates[i]; candidates[i] = candidates[j]; candidates[j] = tmp

	for i in range(mini(count, candidates.size())):
		var pos: Vector2i = candidates[i]
		_scatter_sites.append(pos)
		_place_special_site(pos, i)


func _place_special_site(grid_pos: Vector2i, index: int) -> void:
	var wx := _grid_to_world_x(grid_pos.x)
	var wz := _grid_to_world_z(grid_pos.y)

	if _prop_type == "courtyard":
		# Altar: large raised platform with a pillar
		var plat := CSGBox3D.new()
		plat.size = Vector3(4.0, 0.5, 4.0)
		plat.position = Vector3(wx, 0.25, wz)
		plat.use_collision = true
		plat.collision_layer = ENVIRONMENT_LAYER
		plat.material = _mat_prop_a
		plat.name = "Altar_%d" % index
		_geometry_root.add_child(plat)

		var pillar := CSGCylinder3D.new()
		pillar.radius = 0.4
		pillar.height = 3.0
		pillar.sides = 8
		pillar.position = Vector3(wx, 2.0, wz)
		pillar.use_collision = true
		pillar.collision_layer = ENVIRONMENT_LAYER
		pillar.material = _mat_prop_b
		pillar.name = "AltarPillar_%d" % index
		_geometry_root.add_child(pillar)
	else:
		# Ritual circle: flat disc + standing stones
		var circle := CSGCylinder3D.new()
		circle.radius = 4.0
		circle.height = 0.05
		circle.sides = 24
		circle.position = Vector3(wx, 0.03, wz)
		circle.use_collision = false
		circle.material = _mat_site_marker
		circle.name = "RitualCircle_%d" % index
		_geometry_root.add_child(circle)

		for s in range(6):
			var angle := (TAU / 6.0) * s
			var sx := wx + cos(angle) * 4.5
			var sz := wz + sin(angle) * 4.5
			var sh := _rng.randf_range(2.0, 3.5)
			var stone := CSGCylinder3D.new()
			stone.radius = _rng.randf_range(0.3, 0.5)
			stone.height = sh
			stone.sides = 5
			stone.position = Vector3(sx, sh * 0.5, sz)
			stone.use_collision = true
			stone.collision_layer = ENVIRONMENT_LAYER
			stone.material = _mat_prop_a
			stone.name = "RitualStone_%d_%d" % [index, s]
			_geometry_root.add_child(stone)

	# Light at each site
	var site_light := OmniLight3D.new()
	site_light.name = "SiteLight_%d" % index
	site_light.light_color = Color(0.8, 0.15, 0.05) if _prop_type != "courtyard" else Color(0.9, 0.5, 0.1)
	site_light.light_energy = 1.8
	site_light.omni_range = 12.0
	site_light.omni_attenuation = 1.5
	site_light.shadow_enabled = false
	site_light.position = Vector3(wx, 2.5, wz)
	_lighting_root.add_child(site_light)

# ---------------------------------------------------------------------------
# Forest-specific: tree trunks on barrier cells
# ---------------------------------------------------------------------------

func _scatter_tree_trunks() -> void:
	for x in range(_grid_size):
		for y in range(_grid_size):
			if _grid[x][y] == Cell.WALL and _rng.randf() < 0.10:
				var wx := _grid_to_world_x(x) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)
				var wz := _grid_to_world_z(y) + CELL_SIZE * 0.5 + _rng.randf_range(-0.5, 0.5)
				var th := _rng.randf_range(4.0, 8.0)
				var tr := _rng.randf_range(0.25, 0.5)

				var trunk := CSGCylinder3D.new()
				trunk.radius = tr
				trunk.height = th
				trunk.sides = 6
				trunk.position = Vector3(wx, _barrier_height + th * 0.5, wz)
				trunk.use_collision = false
				trunk.material = _mat_barrier_accent
				trunk.name = "Trunk_%d_%d" % [x, y]
				_geometry_root.add_child(trunk)

				var cr := _rng.randf_range(1.5, 3.0)
				var canopy := CSGCylinder3D.new()
				canopy.radius = cr
				canopy.height = _rng.randf_range(1.5, 2.5)
				canopy.sides = 8
				canopy.position = Vector3(wx, _barrier_height + th, wz)
				canopy.use_collision = false
				canopy.material = _mat_barrier
				canopy.name = "Canopy_%d_%d" % [x, y]
				_geometry_root.add_child(canopy)

# ---------------------------------------------------------------------------
# Courtyard-specific: pillar accents on barriers
# ---------------------------------------------------------------------------

func _scatter_courtyard_pillars() -> void:
	for x in range(_grid_size):
		for y in range(_grid_size):
			if _grid[x][y] == Cell.WALL and _rng.randf() < 0.08:
				var wx := _grid_to_world_x(x) + CELL_SIZE * 0.5
				var wz := _grid_to_world_z(y) + CELL_SIZE * 0.5
				var ph := _rng.randf_range(_barrier_height * 0.6, _barrier_height * 1.2)

				var pillar := CSGCylinder3D.new()
				pillar.radius = _rng.randf_range(0.3, 0.6)
				pillar.height = ph
				pillar.sides = 8
				pillar.position = Vector3(wx, _barrier_height + ph * 0.5, wz)
				pillar.use_collision = false
				pillar.material = _mat_barrier_accent
				pillar.name = "Pillar_%d_%d" % [x, y]
				_geometry_root.add_child(pillar)

# ---------------------------------------------------------------------------
# Environment — lighting, fog, sky (outdoor, no ceiling)
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var level_data: Dictionary = GameManager.current_level_data

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()

	# Open sky background
	env.background_mode = Environment.BG_COLOR
	env.background_color = level_data.get("ambient_color", Color(0.05, 0.08, 0.03)) * 0.5

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = level_data.get("ambient_color", Color(0.15, 0.25, 0.1))
	env.ambient_light_energy = 0.45

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = level_data.get("fog_color", Color(0.08, 0.12, 0.05))
	env.fog_density = level_data.get("fog_density", 0.008)
	env.fog_light_energy = 0.5

	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Directional sun light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	dir_light.light_color = level_data.get("light_color", Color(0.5, 0.6, 0.35))
	dir_light.light_energy = level_data.get("light_energy", 0.5)
	dir_light.shadow_enabled = true
	dir_light.rotation_degrees = Vector3(-50, -20, 0)
	_lighting_root.add_child(dir_light)

	# Accent lights in arena rooms
	for room: Rect2i_BSP in _arena_rooms:
		var c := room.center()
		var al := OmniLight3D.new()
		al.name = "ArenaLight_%d_%d" % [c.x, c.y]
		al.light_color = level_data.get("light_color", Color(0.4, 0.6, 0.2))
		al.light_energy = _rng.randf_range(0.6, 1.2)
		al.omni_range = maxi(room.w, room.h) * CELL_SIZE * 0.5
		al.omni_attenuation = 1.8
		al.shadow_enabled = false
		al.position = Vector3(_grid_to_world_x(c.x), _barrier_height * 0.7, _grid_to_world_z(c.y))
		_lighting_root.add_child(al)

# ---------------------------------------------------------------------------
# Spawn points
# ---------------------------------------------------------------------------

func _determine_spawn_points() -> void:
	_enemy_spawns.clear()

	# Player spawns in the smallest room
	var sorted_rooms := _rooms.duplicate()
	sorted_rooms.sort_custom(func(a: Rect2i_BSP, b: Rect2i_BSP) -> bool: return (a.w * a.h) < (b.w * b.h))

	var spawn_room: Rect2i_BSP = sorted_rooms[0]
	var sc := spawn_room.center()
	_player_spawn = Vector3(_grid_to_world_x(sc.x), 0.5, _grid_to_world_z(sc.y))

	# Enemy spawns in arena rooms
	for room: Rect2i_BSP in _arena_rooms:
		@warning_ignore("integer_division")
		var cnt := maxi(MIN_ARENA_SPAWNS, (room.w * room.h) / ARENA_SPAWN_DENSITY)
		for _i in range(cnt):
			var sx := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			var c := _get_cell(sx, sy)
			if c == Cell.FLOOR or c == Cell.PATH:
				_enemy_spawns.append(Vector3(
					_grid_to_world_x(sx) + CELL_SIZE * 0.5, 0.5,
					_grid_to_world_z(sy) + CELL_SIZE * 0.5
				))

	# Additional spawns in larger non-arena rooms
	for room: Rect2i_BSP in _rooms:
		if room in _arena_rooms or room == spawn_room: continue
		var area := room.w * room.h
		if area < MIN_ROOM_SIZE * MIN_ROOM_SIZE: continue
		@warning_ignore("integer_division")
		var cnt := maxi(1, area / (ARENA_SPAWN_DENSITY * 2))
		for _i in range(cnt):
			var sx := _rng.randi_range(room.x + 1, room.x + room.w - 2)
			var sy := _rng.randi_range(room.y + 1, room.y + room.h - 2)
			var c := _get_cell(sx, sy)
			if c == Cell.FLOOR or c == Cell.PATH:
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


func _make_box(pos: Vector3, sz: Vector3, mat: StandardMaterial3D, nm: String, col: bool) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = sz
	box.position = pos
	box.material = mat
	box.use_collision = col
	if col:
		box.collision_layer = ENVIRONMENT_LAYER
		box.collision_mask = 0
	box.name = nm
	_geometry_root.add_child(box)
	return box
