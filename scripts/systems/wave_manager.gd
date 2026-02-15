class_name WaveManager
extends Node3D
## Manages wave progression and enemy spawning for the roguelike FPS.
##
## Uses GameManager.total_waves for wave count (varies per level).
## Enemy composition is driven by GameManager.get_level_enemy_types() and
## GameManager.get_level_enemy_weights() for weighted random selection.
## Boss spawning loads the boss script from boss_script_path.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const REST_PERIOD := 5.0           ## Seconds between waves
const SPAWN_BATCH_DELAY := 0.3     ## Delay between individual enemy spawns
const MIN_SPAWN_DISTANCE := 8.0    ## Minimum distance from player for spawn point selection

# ---------------------------------------------------------------------------
# Boss script (set by game_scene before waves start)
# ---------------------------------------------------------------------------

var boss_script_path: String = ""

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _spawn_points: Array[Vector3] = []
var _player: Node3D = null
var _current_wave: int = 0
var _is_spawning: bool = false
var _wave_active: bool = false
var _rest_timer: float = 0.0
var _is_resting: bool = false
var _enemies_to_spawn: Array[Dictionary] = []
var _spawn_timer: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.wave_completed.connect(_on_wave_completed)


func _process(delta: float) -> void:
	# -- Rest period between waves ---------------------------------------
	if _is_resting:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_is_resting = false
			_current_wave += 1
			_spawn_wave(_current_wave)
		return

	# -- Batch spawning --------------------------------------------------
	if _is_spawning and _enemies_to_spawn.size() > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var entry: Dictionary = _enemies_to_spawn.pop_front()
			_spawn_enemy(entry["type"], entry["position"], entry["wave"])
			_spawn_timer = SPAWN_BATCH_DELAY

			if _enemies_to_spawn.is_empty():
				_is_spawning = false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_waves(spawn_points: Array[Vector3], player: Node3D) -> void:
	_spawn_points = spawn_points
	_player = player
	_current_wave = 0

	# Start first wave after a brief delay
	_is_resting = true
	_rest_timer = 2.0  # Shorter delay for first wave


func stop_waves() -> void:
	_is_spawning = false
	_wave_active = false
	_is_resting = false
	_enemies_to_spawn.clear()

# ---------------------------------------------------------------------------
# Wave spawning
# ---------------------------------------------------------------------------

func _spawn_wave(wave_number: int) -> void:
	_wave_active = true
	GameManager.current_wave = wave_number

	var total_normal_waves: int = GameManager.total_waves
	var boss_wave: int = total_normal_waves + 1

	if wave_number >= boss_wave:
		_spawn_boss_wave()
		return

	# -- Get wave composition from level data ----------------------------
	var composition := _get_wave_composition(wave_number)

	# -- Build spawn queue -----------------------------------------------
	_enemies_to_spawn.clear()
	for enemy_type in composition:
		var count: int = composition[enemy_type]
		for i in count:
			var pos := _pick_spawn_point()
			_enemies_to_spawn.append({
				"type": enemy_type,
				"position": pos,
				"wave": wave_number,
			})

	# Shuffle for variety
	_enemies_to_spawn.shuffle()

	# -- Register total enemy count with GameManager ---------------------
	var total_count := _enemies_to_spawn.size()
	GameManager.register_enemies(total_count)

	# -- Start batch spawning --------------------------------------------
	_is_spawning = true
	_spawn_timer = 0.0

	# -- Emit wave started signal ----------------------------------------
	EventBus.wave_started.emit(wave_number)


func _spawn_boss_wave() -> void:
	GameManager.is_boss_wave = true

	var total_normal_waves: int = GameManager.total_waves
	var boss_wave: int = total_normal_waves + 1
	var pos := _pick_spawn_point()

	var hp_mult := GameManager.get_wave_enemy_hp_mult(boss_wave)
	var dmg_mult := GameManager.get_wave_enemy_dmg_mult(boss_wave)
	var spd_mult := GameManager.get_wave_enemy_speed_mult(boss_wave)

	# Load boss from script path if available, otherwise fall back to EnemyBoss
	var boss: Node3D = null
	if boss_script_path != "" and ResourceLoader.exists(boss_script_path):
		var boss_script = load(boss_script_path)
		if boss_script:
			boss = CharacterBody3D.new()
			boss.set_script(boss_script)
	if boss == null:
		# Fallback to default EnemyBoss class
		boss = EnemyBoss.new()

	if boss.has_method("initialize"):
		boss.initialize(hp_mult, dmg_mult, spd_mult)
	add_child(boss)
	boss.global_position = pos

	GameManager.register_enemies(1)
	EventBus.wave_started.emit(boss_wave)
	EventBus.boss_wave_started.emit()

# ---------------------------------------------------------------------------
# Enemy instantiation
# ---------------------------------------------------------------------------

func _spawn_enemy(type: String, position: Vector3, wave: int) -> void:
	var hp_mult := GameManager.get_wave_enemy_hp_mult(wave)
	var dmg_mult := GameManager.get_wave_enemy_dmg_mult(wave)
	var spd_mult := GameManager.get_wave_enemy_speed_mult(wave)

	var enemy: EnemyBase = null

	match type:
		"melee":
			enemy = EnemyMelee.new()
		"ranged":
			enemy = EnemyRanged.new()
		"tank":
			enemy = EnemyTank.new()
		"fast":
			enemy = EnemyFast.new()
		"exploder":
			enemy = EnemyExploder.new()
		_:
			enemy = EnemyMelee.new()

	enemy.initialize(hp_mult, dmg_mult, spd_mult)
	add_child(enemy)
	enemy.global_position = position

# ---------------------------------------------------------------------------
# Spawn point selection -- prefer points far from player
# ---------------------------------------------------------------------------

func _pick_spawn_point() -> Vector3:
	if _spawn_points.is_empty():
		# Fallback: spawn in a ring around origin
		var angle := randf() * TAU
		var dist := 15.0 + randf() * 10.0
		return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

	if _player == null or not is_instance_valid(_player):
		return _spawn_points[randi() % _spawn_points.size()]

	# Filter spawn points that are far enough from the player
	var valid_points: Array[Vector3] = []
	for point in _spawn_points:
		if point.distance_to(_player.global_position) >= MIN_SPAWN_DISTANCE:
			valid_points.append(point)

	if valid_points.is_empty():
		# All too close -- pick the farthest available
		var best_point := _spawn_points[0]
		var best_dist := 0.0
		for point in _spawn_points:
			var dist := point.distance_to(_player.global_position)
			if dist > best_dist:
				best_dist = dist
				best_point = point
		return best_point

	# Pick a random valid point with some jitter
	var chosen := valid_points[randi() % valid_points.size()]
	var jitter := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	return chosen + jitter

# ---------------------------------------------------------------------------
# Wave composition -- uses weighted random selection from level data
# ---------------------------------------------------------------------------

func _get_wave_composition(wave: int) -> Dictionary:
	var base_count := GameManager.get_wave_enemy_count(wave)
	var enemy_types: Array = GameManager.get_level_enemy_types()
	var enemy_weights: Dictionary = GameManager.get_level_enemy_weights()

	if enemy_types.is_empty() or enemy_weights.is_empty():
		return { "melee": maxi(base_count, 1) }

	# Calculate total weight for normalization
	var total_weight: float = 0.0
	for etype in enemy_types:
		total_weight += enemy_weights.get(etype, 0.0)

	if total_weight <= 0.0:
		return { "melee": maxi(base_count, 1) }

	# Distribute enemies according to weights
	var composition: Dictionary = {}
	var assigned: int = 0

	for i in enemy_types.size():
		var etype: String = enemy_types[i]
		var weight: float = enemy_weights.get(etype, 0.0)
		var ratio: float = weight / total_weight
		var count: int = int(base_count * ratio)

		# Ensure at least 1 of each type that has weight
		if count <= 0 and weight > 0.0:
			count = 1

		composition[etype] = count
		assigned += count

	# If rounding left us short, add remainder to the highest-weight type
	var remainder := base_count - assigned
	if remainder > 0:
		var best_type: String = enemy_types[0]
		var best_weight: float = 0.0
		for etype in enemy_types:
			if enemy_weights.get(etype, 0.0) > best_weight:
				best_weight = enemy_weights.get(etype, 0.0)
				best_type = etype
		composition[best_type] = composition.get(best_type, 0) + remainder

	# Ensure at least 1 enemy total
	var total := 0
	for key in composition:
		total += composition[key]
	if total <= 0:
		composition["melee"] = 1

	return composition

# ---------------------------------------------------------------------------
# Wave completion
# ---------------------------------------------------------------------------

func _on_wave_completed(wave_number: int) -> void:
	_wave_active = false

	var total_normal_waves: int = GameManager.total_waves
	if wave_number >= total_normal_waves:
		# All normal waves done - boss wave next
		EventBus.all_waves_completed.emit()
		return

	# Start rest period before next wave
	_is_resting = true
	_rest_timer = REST_PERIOD


func start_boss_wave() -> void:
	var total_normal_waves: int = GameManager.total_waves
	var boss_wave: int = total_normal_waves + 1
	_current_wave = boss_wave
	_spawn_wave(boss_wave)
