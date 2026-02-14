extends CanvasLayer
## Pause menu overlay.
## Shows PAUSED title, Resume, and Main Menu buttons.
## Works while paused (PROCESS_MODE_ALWAYS).

# ── Node references ──────────────────────────────────────────────────────────
var overlay: ColorRect
var title_label: Label
var resume_button: Button
var main_menu_button: Button
var confirm_container: VBoxContainer
var confirm_label: Label
var confirm_yes_button: Button
var confirm_no_button: Button

# ── State ────────────────────────────────────────────────────────────────────
var _confirming_quit: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 22

	overlay = %Overlay
	title_label = %TitleLabel
	resume_button = %ResumeButton
	main_menu_button = %MainMenuButton
	confirm_container = %ConfirmContainer
	confirm_label = %ConfirmLabel
	confirm_yes_button = %ConfirmYesButton
	confirm_no_button = %ConfirmNoButton

	# Connect buttons
	resume_button.pressed.connect(_on_resume)
	main_menu_button.pressed.connect(_on_main_menu)
	confirm_yes_button.pressed.connect(_on_confirm_yes)
	confirm_no_button.pressed.connect(_on_confirm_no)

	# Connect EventBus
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.game_resumed.connect(_on_game_resumed)

	# Start hidden
	visible = false
	confirm_container.visible = false


func _on_game_paused() -> void:
	_confirming_quit = false
	confirm_container.visible = false
	visible = true


func _on_game_resumed() -> void:
	visible = false


func _on_resume() -> void:
	GameManager.resume_game()


func _on_main_menu() -> void:
	if not _confirming_quit:
		_confirming_quit = true
		confirm_container.visible = true
		confirm_label.text = "Return to main menu?\nCurrent run will be lost."
	else:
		_confirm_quit()


func _on_confirm_yes() -> void:
	_confirm_quit()


func _on_confirm_no() -> void:
	_confirming_quit = false
	confirm_container.visible = false


func _confirm_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Allow back button / escape to resume
	if event.is_action_pressed("ui_cancel"):
		_on_resume()
		get_viewport().set_input_as_handled()
