extends CanvasLayer
## Level intro screen shown before each level starts.
## Displays level name, number, description, and story text with a typewriter
## effect. Dismisses on tap/click or auto-advances after text finishes.
## Process mode ALWAYS so it works while the game is paused.

# ── Node references ──────────────────────────────────────────────────────────
var overlay: ColorRect
var level_number_label: Label
var level_name_label: Label
var description_label: Label
var story_label: Label
var continue_prompt: Label

# ── State ────────────────────────────────────────────────────────────────────
var _level_data: Dictionary = {}
var _full_story_text: String = ""
var _typewriter_index: int = 0
var _typewriter_timer: float = 0.0
var _typewriter_active: bool = false
var _text_finished: bool = false
var _is_showing: bool = false
var _auto_advance_timer: float = 0.0
var _prompt_blink_timer: float = 0.0

const TYPEWRITER_SPEED := 0.025  ## Seconds per character
const AUTO_ADVANCE_DELAY := 2.0  ## Seconds after text finishes before auto-dismiss
const PROMPT_BLINK_RATE := 0.6   ## Seconds per blink cycle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30

	# Get node references
	overlay = %Overlay
	level_number_label = %LevelNumberLabel
	level_name_label = %LevelNameLabel
	description_label = %DescriptionLabel
	story_label = %StoryLabel
	continue_prompt = %ContinuePrompt

	# Start hidden
	visible = false

	# Connect to EventBus
	EventBus.level_started.connect(_on_level_started)


func _process(delta: float) -> void:
	if not _is_showing:
		return

	# Typewriter effect
	if _typewriter_active:
		_typewriter_timer -= delta
		if _typewriter_timer <= 0.0:
			_typewriter_index += 1
			if _typewriter_index >= _full_story_text.length():
				_typewriter_index = _full_story_text.length()
				_typewriter_active = false
				_text_finished = true
				_auto_advance_timer = AUTO_ADVANCE_DELAY
			story_label.text = _full_story_text.substr(0, _typewriter_index)
			_typewriter_timer = TYPEWRITER_SPEED

	# Blink the continue prompt
	if _text_finished:
		_prompt_blink_timer += delta
		if _prompt_blink_timer >= PROMPT_BLINK_RATE:
			_prompt_blink_timer -= PROMPT_BLINK_RATE
			continue_prompt.visible = not continue_prompt.visible

		# Auto-advance countdown
		_auto_advance_timer -= delta
		if _auto_advance_timer <= 0.0:
			_dismiss()


func _input(event: InputEvent) -> void:
	if not _is_showing:
		return

	# Accept tap / click / any key to advance
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed:
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		pressed = true

	if pressed:
		if _typewriter_active:
			# Skip typewriter -- show full text immediately
			_typewriter_active = false
			_typewriter_index = _full_story_text.length()
			story_label.text = _full_story_text
			_text_finished = true
			_auto_advance_timer = AUTO_ADVANCE_DELAY
		elif _text_finished:
			_dismiss()
		get_viewport().set_input_as_handled()


# ── Show / dismiss ───────────────────────────────────────────────────────────

func _on_level_started(level_number: int, level_data: Dictionary) -> void:
	_level_data = level_data
	_show(level_number, level_data)


func _show(level_number: int, level_data: Dictionary) -> void:
	_is_showing = true
	_text_finished = false
	_typewriter_active = true
	_typewriter_index = 0
	_typewriter_timer = TYPEWRITER_SPEED
	_prompt_blink_timer = 0.0

	# Populate labels
	level_number_label.text = "LEVEL %d" % level_number
	level_name_label.text = level_data.get("name", "Unknown")
	description_label.text = level_data.get("description", "")

	# Set theme color from level's accent color
	var env_data: Dictionary = level_data.get("environment", {})
	var accent_color: Color = env_data.get("accent_color", Color(0.8, 0.15, 0.1))
	level_name_label.add_theme_color_override("font_color", accent_color)
	level_number_label.add_theme_color_override("font_color", accent_color.lightened(0.3))

	# Story text for typewriter
	_full_story_text = level_data.get("intro_text", "")
	story_label.text = ""

	# Continue prompt starts hidden
	continue_prompt.visible = false
	continue_prompt.text = "TAP TO CONTINUE"

	visible = true


func _dismiss() -> void:
	_is_showing = false
	_typewriter_active = false
	visible = false

	# Notify game scene that intro is finished
	EventBus.level_intro_finished.emit()
