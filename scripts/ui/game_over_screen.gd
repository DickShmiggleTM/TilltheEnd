extends CanvasLayer
## Game over and victory screen.
## Displays final run stats and offers retry / main menu options.
## Works while paused (PROCESS_MODE_ALWAYS).
##
## On death: shows "SAVE DELETED" to make permadeath clear,
## includes "Level Reached" in stats.
## On final victory (level 7): shows "THE NAMELESS ONE IS DEFEATED".

# ── Node references ──────────────────────────────────────────────────────────
var overlay: ColorRect
var title_label: Label
var stats_container: VBoxContainer
var waves_label: Label
var kills_label: Label
var time_label: Label
var level_label: Label
var level_reached_label: Label
var permadeath_label: Label
var try_again_button: Button
var main_menu_button: Button

# ── State ────────────────────────────────────────────────────────────────────
var _is_victory: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25

	overlay = %Overlay
	title_label = %TitleLabel
	stats_container = %StatsContainer
	waves_label = %WavesLabel
	kills_label = %KillsLabel
	time_label = %TimeLabel
	level_label = %LevelLabel
	level_reached_label = %LevelReachedLabel
	permadeath_label = %PermadeathLabel
	try_again_button = %TryAgainButton
	main_menu_button = %MainMenuButton

	# Connect buttons
	try_again_button.pressed.connect(_on_try_again)
	main_menu_button.pressed.connect(_on_main_menu)

	# Connect EventBus
	EventBus.game_over.connect(_on_game_over)
	EventBus.game_won.connect(_on_game_won)

	# Start hidden
	visible = false
	permadeath_label.visible = false


func _on_game_over(survived_waves: int, kills: int) -> void:
	_is_victory = false
	_show_screen(survived_waves, kills)


func _on_game_won() -> void:
	_is_victory = true
	_show_screen(GameManager.current_wave, GameManager.total_kills)


func _show_screen(waves: int, kills: int) -> void:
	get_tree().paused = true

	if _is_victory:
		# Check if this is the final boss (level 7)
		if GameManager.current_level >= GameManager.TOTAL_LEVELS:
			title_label.text = "THE NAMELESS ONE IS DEFEATED"
		else:
			title_label.text = "VICTORY"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
		permadeath_label.visible = false
		try_again_button.text = "NEW RUN"
	else:
		title_label.text = "GAME OVER"
		title_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))
		# Show permadeath warning
		permadeath_label.visible = true
		permadeath_label.text = "SAVE DELETED"
		permadeath_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))
		try_again_button.text = "TRY AGAIN"

	# Populate stats
	waves_label.text = "Waves Survived: %d / %d" % [waves, GameManager.total_waves]
	kills_label.text = "Enemies Killed: %d" % kills
	var minutes := int(GameManager.run_time) / 60
	var seconds := int(GameManager.run_time) % 60
	time_label.text = "Time Survived: %02d:%02d" % [minutes, seconds]
	level_label.text = "Player Level: %d" % GameManager.player_level

	# Show which campaign level the player reached
	var campaign_level: int = GameManager.current_level
	var level_name: String = GameManager.current_level_data.get("name", "")
	if level_name != "":
		level_reached_label.text = "Level Reached: %d - %s" % [campaign_level, level_name]
	else:
		level_reached_label.text = "Level Reached: %d / %d" % [campaign_level, GameManager.TOTAL_LEVELS]

	visible = true

	# Animate entrance
	var content := %ContentPanel
	if content:
		content.modulate.a = 0.0
		content.scale = Vector2(0.8, 0.8)
		content.pivot_offset = content.size * 0.5
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(content, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(content, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_try_again() -> void:
	get_tree().paused = false
	GameManager.start_new_run()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
