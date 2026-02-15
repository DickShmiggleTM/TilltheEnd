extends Node
## Central game state manager. Handles run state, stats, game flow,
## and multi-level campaign progression with permadeath.

# ── Game state ──────────────────────────────────────────────────────────
enum GameState { MENU, PLAYING, PAUSED, LEVEL_UP, GAME_OVER, VICTORY, LEVEL_COMPLETE, TRANSITIONING }
var state: GameState = GameState.MENU

# ── Campaign / level tracking ───────────────────────────────────────────
var current_level: int = 1
var current_wave: int = 0
var total_waves: int = 8        # Set per level from LevelData
var enemies_alive: int = 0
var total_kills: int = 0
var run_time: float = 0.0
var is_boss_wave: bool = false
var level_kills: int = 0        # Kills this level only

# ── Player progression (persists across levels within a run) ────────────
var player_stats: Dictionary = {}
var player_weapons: Array[Dictionary] = []
var player_abilities: Array[Dictionary] = []
var player_traits: Dictionary = {}
var player_level: int = 1
var player_exp: float = 0.0
var player_exp_to_next: float = 100.0
var player_gold: int = 0

const MAX_WEAPONS := 6
var MAX_ABILITIES := 6
const EXP_GROWTH_RATE := 1.35
const BASE_EXP_NEEDED := 100.0
const TOTAL_LEVELS := 7

# ── Per-wave difficulty scaling (within a level) ────────────────────────
const ENEMY_HP_SCALE := 1.2
const ENEMY_DMG_SCALE := 1.12
const ENEMY_COUNT_SCALE := 1.25
const ENEMY_SPEED_SCALE := 1.04

# ── Current level data cache ────────────────────────────────────────────
var current_level_data: Dictionary = {}

func _ready() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.exp_collected.connect(_on_exp_collected)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.gold_collected.connect(_on_gold_collected)


# ══════════════════════════════════════════════════════════════════════════
# Run management
# ══════════════════════════════════════════════════════════════════════════

## Start a brand new run from level 1.
func start_new_run() -> void:
	state = GameState.PLAYING
	current_level = 1
	current_wave = 0
	total_kills = 0
	level_kills = 0
	run_time = 0.0
	is_boss_wave = false
	player_level = 1
	player_exp = 0.0
	player_exp_to_next = BASE_EXP_NEEDED
	player_gold = 0
	MAX_ABILITIES = 6
	player_weapons.clear()
	player_abilities.clear()
	_reset_traits()
	_load_level_data(1)
	EventBus.run_started.emit()
	EventBus.game_started.emit()


## Continue a run from a saved level (after loading save data).
func continue_run(from_level: int) -> void:
	state = GameState.PLAYING
	current_level = from_level
	current_wave = 0
	level_kills = 0
	is_boss_wave = false
	_load_level_data(from_level)
	EventBus.run_started.emit()
	EventBus.game_started.emit()


## Advance to the next level after beating the current boss.
func advance_to_next_level() -> void:
	current_level += 1
	if current_level > TOTAL_LEVELS:
		# Game complete! Final victory!
		state = GameState.VICTORY
		EventBus.game_won.emit()
		return
	current_wave = 0
	level_kills = 0
	is_boss_wave = false
	enemies_alive = 0
	_load_level_data(current_level)
	state = GameState.LEVEL_COMPLETE


## Load level configuration from LevelData.
func _load_level_data(level_num: int) -> void:
	current_level_data = LevelData.get_level(level_num)
	if current_level_data.is_empty():
		push_error("GameManager: No data for level %d" % level_num)
		return
	total_waves = current_level_data.get("waves", 10)


func _reset_traits() -> void:
	player_traits = {
		"max_health": 100.0,
		"defense": 0.0,
		"speed": 5.0,
		"fire_rate_mult": 1.0,
		"exp_mult": 1.0,
		"collect_range": 3.0,
		"damage_mult": 1.0,
		"crit_chance": 0.05,
		"crit_damage": 1.5,
		"dodge_chance": 0.0,
		"health_regen": 0.0,
		"armor": 0.0,
		"thorns": 0.0,
		"lifesteal": 0.0,
		"luck": 0.0,
	}


func get_trait(trait_name: String) -> float:
	return player_traits.get(trait_name, 0.0)


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		run_time += delta


# ══════════════════════════════════════════════════════════════════════════
# Difficulty scaling (combines per-wave + per-level multipliers)
# ══════════════════════════════════════════════════════════════════════════

func get_level_enemy_hp_mult() -> float:
	return current_level_data.get("enemy_hp_mult", 1.0)

func get_level_enemy_dmg_mult() -> float:
	return current_level_data.get("enemy_dmg_mult", 1.0)

func get_level_enemy_speed_mult() -> float:
	return current_level_data.get("enemy_speed_mult", 1.0)

func get_level_enemy_count_mult() -> float:
	return current_level_data.get("enemy_count_mult", 1.0)

func get_level_exp_mult() -> float:
	return current_level_data.get("exp_mult", 1.0)

func get_wave_enemy_count(wave: int) -> int:
	var base := 8
	var wave_scale := pow(ENEMY_COUNT_SCALE, wave - 1)
	var level_scale := get_level_enemy_count_mult()
	return int(base * wave_scale * level_scale)

func get_wave_enemy_hp_mult(wave: int) -> float:
	return pow(ENEMY_HP_SCALE, wave - 1) * get_level_enemy_hp_mult()

func get_wave_enemy_dmg_mult(wave: int) -> float:
	return pow(ENEMY_DMG_SCALE, wave - 1) * get_level_enemy_dmg_mult()

func get_wave_enemy_speed_mult(wave: int) -> float:
	return pow(ENEMY_SPEED_SCALE, wave - 1) * get_level_enemy_speed_mult()

## Get which enemy types are available this level and their spawn weights.
func get_level_enemy_types() -> Array:
	return current_level_data.get("enemy_types", ["melee"])

func get_level_enemy_weights() -> Dictionary:
	return current_level_data.get("enemy_weights", { "melee": 1.0 })


# ══════════════════════════════════════════════════════════════════════════
# Event handlers
# ══════════════════════════════════════════════════════════════════════════

func _on_enemy_killed(_enemy: Node3D, _position: Vector3) -> void:
	total_kills += 1
	level_kills += 1
	enemies_alive -= 1
	EventBus.enemies_remaining_changed.emit(enemies_alive)
	if enemies_alive <= 0 and state == GameState.PLAYING:
		if is_boss_wave:
			return  # Handled by boss_killed signal
		EventBus.wave_completed.emit(current_wave)


func _on_exp_collected(amount: float) -> void:
	var level_exp_mult := get_level_exp_mult()
	var modified_amount := amount * player_traits.get("exp_mult", 1.0) * level_exp_mult
	player_exp += modified_amount
	EventBus.player_exp_gained.emit(modified_amount, player_exp, player_exp_to_next)
	while player_exp >= player_exp_to_next:
		player_exp -= player_exp_to_next
		player_level += 1
		player_exp_to_next = BASE_EXP_NEEDED * pow(EXP_GROWTH_RATE, player_level - 1)
		state = GameState.LEVEL_UP
		EventBus.player_level_up.emit(player_level)


func _on_upgrade_selected(upgrade: Dictionary) -> void:
	match upgrade.get("type", ""):
		"weapon":
			if player_weapons.size() < MAX_WEAPONS:
				player_weapons.append(upgrade)
				EventBus.weapon_acquired.emit(upgrade)
			else:
				_upgrade_random_weapon()
		"ability":
			if player_abilities.size() < MAX_ABILITIES:
				player_abilities.append(upgrade)
				EventBus.ability_acquired.emit(upgrade)
			else:
				_upgrade_random_ability()
		"trait":
			var trait_name: String = upgrade.get("trait_name", "")
			var trait_value: float = upgrade.get("trait_value", 0.0)
			if player_traits.has(trait_name):
				player_traits[trait_name] += trait_value
				EventBus.trait_upgraded.emit(trait_name, player_traits[trait_name])
		"weapon_upgrade":
			var idx: int = upgrade.get("weapon_index", 0)
			if idx < player_weapons.size():
				player_weapons[idx]["level"] = player_weapons[idx].get("level", 1) + 1
				EventBus.weapon_upgraded.emit(player_weapons[idx].get("id", ""), player_weapons[idx]["level"])
		"ability_upgrade":
			var idx: int = upgrade.get("ability_index", 0)
			if idx < player_abilities.size():
				player_abilities[idx]["level"] = player_abilities[idx].get("level", 1) + 1
				EventBus.ability_upgraded.emit(player_abilities[idx].get("id", ""), player_abilities[idx]["level"])
	state = GameState.PLAYING
	get_tree().paused = false


func _upgrade_random_weapon() -> void:
	if player_weapons.is_empty():
		return
	var idx := randi() % player_weapons.size()
	player_weapons[idx]["level"] = player_weapons[idx].get("level", 1) + 1
	EventBus.weapon_upgraded.emit(player_weapons[idx].get("id", ""), player_weapons[idx]["level"])


func _upgrade_random_ability() -> void:
	if player_abilities.is_empty():
		return
	var idx := randi() % player_abilities.size()
	player_abilities[idx]["level"] = player_abilities[idx].get("level", 1) + 1
	EventBus.ability_upgraded.emit(player_abilities[idx].get("id", ""), player_abilities[idx]["level"])


func _on_gold_collected(amount: int) -> void:
	player_gold += amount


func _on_boss_killed() -> void:
	# Boss defeated — advance to next level (not immediate victory anymore)
	advance_to_next_level()


func register_enemies(count: int) -> void:
	enemies_alive += count
	EventBus.enemies_remaining_changed.emit(enemies_alive)


func pause_game() -> void:
	if state == GameState.PLAYING:
		state = GameState.PAUSED
		get_tree().paused = true
		EventBus.game_paused.emit()


func resume_game() -> void:
	if state == GameState.PAUSED:
		state = GameState.PLAYING
		get_tree().paused = false
		EventBus.game_resumed.emit()


func game_over() -> void:
	state = GameState.GAME_OVER
	EventBus.game_over.emit(current_wave, total_kills)
