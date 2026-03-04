extends Node3D
## Main game scene orchestrator. Manages multi-level roguelike campaign flow
## with permadeath. Instantiates and manages all gameplay systems: dynamic map
## generation per level, player, UI layers, wave management, upgrades, weapons,
## and abilities. Coordinates everything through EventBus signals.

# ---------------------------------------------------------------------------
# Preloaded scene / script resources (player, weapons, abilities, systems)
# ---------------------------------------------------------------------------

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const WeaponManagerScript := preload("res://scripts/weapons/weapon_manager.gd")
const AbilityManagerScript := preload("res://scripts/abilities/ability_manager.gd")
const WaveManagerScript := preload("res://scripts/systems/wave_manager.gd")
const UpgradeGeneratorScript := preload("res://scripts/systems/upgrade_generator.gd")

# UI scene paths (loaded dynamically)
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const TOUCH_CONTROLS_SCENE_PATH := "res://scenes/ui/touch_controls.tscn"
const LEVEL_UP_SCREEN_SCENE_PATH := "res://scenes/ui/level_up_screen.tscn"
const GAME_OVER_SCREEN_SCENE_PATH := "res://scenes/ui/game_over_screen.tscn"
const PAUSE_MENU_SCENE_PATH := "res://scenes/ui/pause_menu.tscn"
const LEVEL_INTRO_SCREEN_SCENE_PATH := "res://scenes/ui/level_intro_screen.tscn"

# ---------------------------------------------------------------------------
# Node references (created at runtime)
# ---------------------------------------------------------------------------

var map_generator: Node3D = null
var player: CharacterBody3D = null
var weapon_manager: Node3D = null
var ability_manager: Node3D = null
var wave_manager: Node = null
var upgrade_generator: Node = null

# UI layers
var hud: Control = null
var touch_controls: Control = null
var level_up_screen: Control = null
var game_over_screen: Control = null
var pause_menu: Control = null
var level_intro_screen = null  # CanvasLayer root

# Container for dynamically spawned entities (enemies, pickups, projectiles)
var entity_container: Node3D = null

# Countdown state
var _countdown_timer: float = 0.0
var _countdown_active: bool = false
var _game_started: bool = false

# Level transition state
var _level_complete_pending: bool = false
var _level_complete_timer: float = 0.0
const LEVEL_COMPLETE_DELAY := 3.0

# Map seed for reproducibility
var map_seed: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Create a container for dynamically spawned entities
	entity_container = Node3D.new()
	entity_container.name = "EntityContainer"
	add_child(entity_container)

	# Set up all subsystems in order
	_setup_map()
	_setup_player()
	_setup_ui()
	_setup_wave_system()

	# Connect EventBus signals
	_connect_signals()

	# Generate the map
	map_seed = randi()
	map_generator.generate_map(map_seed)

	# Place the player at the map's spawn point
	var spawn_pos: Vector3 = map_generator.get_player_spawn()
	player.global_position = spawn_pos

	# Give the player a starting weapon only on level 1 with no weapons
	if GameManager.current_level == 1 and GameManager.player_weapons.is_empty():
		_give_starting_weapon()

	# Pass boss script path to wave manager
	var boss_script: String = GameManager.current_level_data.get("boss_script", "")
	if wave_manager:
		wave_manager.boss_script_path = boss_script

	# Show level intro screen before gameplay starts
	_show_level_intro()


func _process(delta: float) -> void:
	# -- Level intro is handled by the intro screen; wait for it to finish --

	# -- Countdown before waves begin --
	if _countdown_active:
		_countdown_timer -= delta
		if _countdown_timer <= 0.0:
			_countdown_active = false
			_game_started = true
			# Start the wave system
			if wave_manager and wave_manager.has_method("start_waves"):
				var spawn_pts: Array[Vector3] = map_generator.get_enemy_spawn_points()
				wave_manager.start_waves(spawn_pts, player)

	# -- Level complete transition --
	if _level_complete_pending:
		_level_complete_timer -= delta
		if _level_complete_timer <= 0.0:
			_level_complete_pending = false
			_transition_to_next_level()


func _exit_tree() -> void:
	_disconnect_signals()


# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _setup_map() -> void:
	# Load map generator script dynamically from level data
	var script_path: String = GameManager.current_level_data.get("map_script", "")
	map_generator = Node3D.new()
	map_generator.name = "MapGenerator"

	if script_path != "" and ResourceLoader.exists(script_path):
		var script = load(script_path)
		if script:
			map_generator.set_script(script)
	else:
		# Fallback to default map generator
		var fallback_script := preload("res://scripts/map/map_generator.gd")
		map_generator.set_script(fallback_script)
		push_warning("GameScene: Map script '%s' not found, using default generator." % script_path)

	add_child(map_generator)


func _setup_player() -> void:
	# Create the player CharacterBody3D with the player controller script
	player = CharacterBody3D.new()
	player.set_script(PlayerControllerScript)
	player.name = "Player"
	add_child(player)

	# Add the player to the "player" group so enemies and abilities can find it
	player.add_to_group("player")

	# Create WeaponManager as a child of the player
	weapon_manager = Node3D.new()
	weapon_manager.set_script(WeaponManagerScript)
	weapon_manager.name = "WeaponManager"
	player.add_child(weapon_manager)

	# Create AbilityManager as a child of the player
	ability_manager = Node3D.new()
	ability_manager.set_script(AbilityManagerScript)
	ability_manager.name = "AbilityManager"
	player.add_child(ability_manager)


func _setup_ui() -> void:
	# HUD (CanvasLayer root -- add directly to scene tree)
	var hud_node := _load_ui_node(HUD_SCENE_PATH, "HUD")
	if hud_node:
		add_child(hud_node)
		hud = hud_node

	# Touch controls
	var tc_node := _load_ui_node(TOUCH_CONTROLS_SCENE_PATH, "TouchControls")
	if tc_node:
		add_child(tc_node)
		touch_controls = tc_node
		if tc_node.has_signal("pause_pressed"):
			tc_node.pause_pressed.connect(_on_pause_pressed)

	# Level-up screen (CanvasLayer root -- handles its own visibility & pause)
	var lu_node := _load_ui_node(LEVEL_UP_SCREEN_SCENE_PATH, "LevelUpScreen")
	if lu_node:
		add_child(lu_node)
		level_up_screen = lu_node

	# Game over screen
	var go_node := _load_ui_node(GAME_OVER_SCREEN_SCENE_PATH, "GameOverScreen")
	if go_node:
		add_child(go_node)
		game_over_screen = go_node

	# Pause menu
	var pm_node := _load_ui_node(PAUSE_MENU_SCENE_PATH, "PauseMenu")
	if pm_node:
		add_child(pm_node)
		pause_menu = pm_node

	# Level intro screen
	var li_node := _load_ui_node(LEVEL_INTRO_SCREEN_SCENE_PATH, "LevelIntroScreen")
	if li_node:
		add_child(li_node)
		level_intro_screen = li_node


func _setup_wave_system() -> void:
	# WaveManager orchestrates enemy spawning per wave
	wave_manager = Node3D.new()
	wave_manager.set_script(WaveManagerScript)
	wave_manager.name = "WaveManager"
	add_child(wave_manager)

	# UpgradeGenerator creates randomized level-up choices
	upgrade_generator = Node.new()
	upgrade_generator.set_script(UpgradeGeneratorScript)
	upgrade_generator.name = "UpgradeGenerator"
	add_child(upgrade_generator)


# ---------------------------------------------------------------------------
# UI scene loader
# ---------------------------------------------------------------------------

func _load_ui_node(scene_path: String, fallback_name: String) -> Node:
	if ResourceLoader.exists(scene_path):
		var packed_scene := load(scene_path) as PackedScene
		if packed_scene:
			return packed_scene.instantiate()
	push_warning("GameScene: UI scene '%s' not found -- skipping %s." % [scene_path, fallback_name])
	return null


# ---------------------------------------------------------------------------
# Starting weapon
# ---------------------------------------------------------------------------

func _give_starting_weapon() -> void:
	# Give the player the pistol from the upgrade database
	var pistol_data: Dictionary = UpgradeGeneratorScript.WEAPON_DATABASE.get("pistol", {}).duplicate(true)
	if pistol_data.is_empty():
		push_warning("GameScene: Could not find pistol in weapon database.")
		return

	# Register the weapon with GameManager so the upgrade system tracks it
	GameManager.player_weapons.append(pistol_data)

	# Add it to the weapon manager directly (bypasses EventBus to avoid double-add)
	if weapon_manager and weapon_manager.has_method("add_weapon"):
		weapon_manager.add_weapon(pistol_data)


# ---------------------------------------------------------------------------
# Level intro
# ---------------------------------------------------------------------------

func _show_level_intro() -> void:
	# Pause the game during intro
	get_tree().paused = true

	# Emit level_started so the intro screen can display info
	EventBus.level_started.emit(GameManager.current_level, GameManager.current_level_data)


# ---------------------------------------------------------------------------
# Countdown
# ---------------------------------------------------------------------------

func _start_countdown() -> void:
	_countdown_timer = 3.0
	_countdown_active = true

	# Notify HUD about countdown if it supports it
	if hud and hud.has_method("show_countdown"):
		hud.show_countdown(3.0)


# ---------------------------------------------------------------------------
# Level transition (after boss kill)
# ---------------------------------------------------------------------------

func _on_level_complete() -> void:
	# Save progress for the NEXT level
	SaveManager.save_progress(SaveManager.create_save_from_state())

	# Show level complete message on HUD
	if hud and hud.has_method("show_level_complete"):
		hud.show_level_complete(GameManager.current_level)

	EventBus.level_complete.emit(GameManager.current_level)

	# Wait before transitioning
	_level_complete_pending = true
	_level_complete_timer = LEVEL_COMPLETE_DELAY


func _transition_to_next_level() -> void:
	## After completing a level, return to hub world — player selects next door.
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/hub_world.tscn")


# ---------------------------------------------------------------------------
# Signal connections
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.player_level_up.connect(_on_level_up)
	EventBus.player_died.connect(_on_player_died)
	EventBus.game_over.connect(_on_game_over)
	EventBus.game_won.connect(_on_game_won)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.all_waves_completed.connect(_on_all_waves_completed)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.game_resumed.connect(_on_game_resumed)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)
	EventBus.level_intro_finished.connect(_on_level_intro_finished)


func _disconnect_signals() -> void:
	if EventBus.player_level_up.is_connected(_on_level_up):
		EventBus.player_level_up.disconnect(_on_level_up)
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)
	if EventBus.game_over.is_connected(_on_game_over):
		EventBus.game_over.disconnect(_on_game_over)
	if EventBus.game_won.is_connected(_on_game_won):
		EventBus.game_won.disconnect(_on_game_won)
	if EventBus.wave_completed.is_connected(_on_wave_completed):
		EventBus.wave_completed.disconnect(_on_wave_completed)
	if EventBus.all_waves_completed.is_connected(_on_all_waves_completed):
		EventBus.all_waves_completed.disconnect(_on_all_waves_completed)
	if EventBus.boss_killed.is_connected(_on_boss_killed):
		EventBus.boss_killed.disconnect(_on_boss_killed)
	if EventBus.game_paused.is_connected(_on_game_paused):
		EventBus.game_paused.disconnect(_on_game_paused)
	if EventBus.game_resumed.is_connected(_on_game_resumed):
		EventBus.game_resumed.disconnect(_on_game_resumed)
	if EventBus.upgrade_selected.is_connected(_on_upgrade_selected):
		EventBus.upgrade_selected.disconnect(_on_upgrade_selected)
	if EventBus.level_intro_finished.is_connected(_on_level_intro_finished):
		EventBus.level_intro_finished.disconnect(_on_level_intro_finished)


# ---------------------------------------------------------------------------
# Level intro finished -- unpause and start countdown
# ---------------------------------------------------------------------------

func _on_level_intro_finished() -> void:
	get_tree().paused = false
	_start_countdown()


# ---------------------------------------------------------------------------
# Level-up flow
# ---------------------------------------------------------------------------

func _on_level_up(_new_level: int) -> void:
	# Level-up screen handles itself via EventBus.player_level_up
	pass


func _on_upgrade_selected(_upgrade: Dictionary) -> void:
	# GameManager handles the upgrade and sets state back to PLAYING + unpauses.
	pass


# ---------------------------------------------------------------------------
# Player death -> Game Over
# ---------------------------------------------------------------------------

func _on_player_died() -> void:
	# SaveManager already deletes the save via its own EventBus.player_died connection
	# Give a brief delay before showing game over -- this also allows
	# God's Tear (or other revive mechanics) time to trigger.
	await get_tree().create_timer(1.5).timeout
	# If the player was revived during the delay, skip game over
	if player and is_instance_valid(player) and player.get("_alive"):
		return
	GameManager.game_over()


func _on_game_over(survived_waves: int, kills: int) -> void:
	get_tree().paused = true
	if game_over_screen:
		game_over_screen.visible = true
		if game_over_screen.has_method("show_results"):
			game_over_screen.show_results(survived_waves, kills, false)


# ---------------------------------------------------------------------------
# Victory (final boss kill -- level 7 completed, GameManager set VICTORY)
# ---------------------------------------------------------------------------

func _on_boss_killed() -> void:
	# GameManager._on_boss_killed() calls advance_to_next_level() which either:
	# - Sets state to LEVEL_COMPLETE (levels 1-6) and loads next level data
	# - Sets state to VICTORY and emits game_won (level 7)
	# We check state in _process or handle via signals
	await get_tree().create_timer(0.1).timeout  # Allow GameManager to process first

	if GameManager.state == GameManager.GameState.LEVEL_COMPLETE:
		_on_level_complete()
	# If VICTORY, _on_game_won will be called via EventBus.game_won


func _on_game_won() -> void:
	# Final victory -- level 7 boss defeated
	# Delete save since the run is complete
	SaveManager.delete_save()
	get_tree().paused = true
	if game_over_screen:
		game_over_screen.visible = true
		if game_over_screen.has_method("show_results"):
			game_over_screen.show_results(
				GameManager.current_wave,
				GameManager.total_kills,
				true  # victory mode
			)


# ---------------------------------------------------------------------------
# Wave flow
# ---------------------------------------------------------------------------

func _on_wave_completed(wave_number: int) -> void:
	# Brief rest period between waves
	var delay := 3.0
	if hud and hud.has_method("show_wave_complete"):
		hud.show_wave_complete(wave_number)

	await get_tree().create_timer(delay).timeout

	# Start next wave if the game is still active
	if GameManager.state == GameManager.GameState.PLAYING:
		# Wave manager handles next wave via internal state
		pass  # Wave manager auto-advances via _on_wave_completed rest timer


func _on_all_waves_completed() -> void:
	# All regular waves done -- trigger the boss wave
	if hud and hud.has_method("show_boss_warning"):
		hud.show_boss_warning()

	await get_tree().create_timer(2.0).timeout

	# Show boss intro
	var boss_name: String = GameManager.current_level_data.get("boss_name", "BOSS")
	var boss_intro: String = GameManager.current_level_data.get("boss_intro", "")
	EventBus.boss_intro_started.emit(boss_name, boss_intro)

	EventBus.boss_wave_started.emit()
	if wave_manager and wave_manager.has_method("start_boss_wave"):
		wave_manager.start_boss_wave()


# ---------------------------------------------------------------------------
# Pause / Resume
# ---------------------------------------------------------------------------

func _on_pause_pressed() -> void:
	if GameManager.state == GameManager.GameState.PLAYING:
		GameManager.pause_game()


func _on_resume_pressed() -> void:
	if GameManager.state == GameManager.GameState.PAUSED:
		GameManager.resume_game()


func _on_game_paused() -> void:
	if pause_menu:
		pause_menu.visible = true


func _on_game_resumed() -> void:
	if pause_menu:
		pause_menu.visible = false


# ---------------------------------------------------------------------------
# Restart / Return to menu
# ---------------------------------------------------------------------------

func _restart() -> void:
	## After game over: return to hub world (doors reset by GameManager.game_over())
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/hub_world.tscn")


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ---------------------------------------------------------------------------
# Pickup container (used by EnemyBase for drop parenting)
# ---------------------------------------------------------------------------

func get_pickup_container() -> Node3D:
	return entity_container
