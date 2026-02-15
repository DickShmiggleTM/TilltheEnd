extends CanvasLayer
## Mobile touch controls overlay.
## Provides virtual joystick (left), look/aim area (right), pause button,
## skill button, kick button, jump button, sprint toggle, and weapon switch buttons.
##
## Readable properties for other systems:
##   movement_vector : Vector2 -- joystick direction (-1..1 per axis)
##   look_delta      : Vector2 -- look/aim delta this frame
##   is_firing       : bool    -- true while right side is touched
##   skill_pressed   : bool    -- true on the frame skill button is pressed
##   kick_pressed    : bool    -- true on the frame kick button is pressed
##   jump_pressed    : bool    -- true on the frame jump button is pressed
##   is_sprinting    : bool    -- true while sprint is toggled on

# ── Exports ──────────────────────────────────────────────────────────────────
@export var sensitivity: float = 0.004
@export var dead_zone: float = 20.0
@export var joystick_radius: float = 120.0

# ── Public readable state ───────────────────────────────────────────────────
var movement_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO
var is_firing: bool = false
var skill_pressed: bool = false
var kick_pressed: bool = false
var jump_pressed: bool = false
var is_sprinting: bool = false

# ── Node references ──────────────────────────────────────────────────────────
var joystick_outer: Control
var joystick_inner: Control
var joystick_touch_area: Control
var look_area: Control
var pause_button: Button
var skill_button: Button
var kick_button: Button
var jump_button: Button
var sprint_button: Button
var weapon_prev_button: Button
var weapon_next_button: Button

# ── Internal touch state ────────────────────────────────────────────────────
var _joystick_touch_id: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _look_touch_id: int = -1
var _look_prev_pos: Vector2 = Vector2.ZERO
var _frame_look_delta: Vector2 = Vector2.ZERO
var _skill_was_pressed: bool = false
var _kick_was_pressed: bool = false
var _jump_was_pressed: bool = false


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS

	joystick_outer = %JoystickOuter
	joystick_inner = %JoystickInner
	joystick_touch_area = %JoystickTouchArea
	look_area = %LookArea
	pause_button = %PauseButton
	weapon_prev_button = %WeaponPrevButton
	weapon_next_button = %WeaponNextButton

	# Skill button: prefer %SkillButton, fall back to %BombButton
	if has_node("%SkillButton"):
		skill_button = %SkillButton
	elif has_node("%BombButton"):
		skill_button = %BombButton

	# Optional new buttons -- null-safe
	if has_node("%KickButton"):
		kick_button = %KickButton
	if has_node("%JumpButton"):
		jump_button = %JumpButton
	if has_node("%SprintButton"):
		sprint_button = %SprintButton

	# Connect buttons
	pause_button.pressed.connect(_on_pause_pressed)
	if skill_button:
		skill_button.pressed.connect(_on_skill_pressed)
	if kick_button:
		kick_button.pressed.connect(_on_kick_pressed)
	if jump_button:
		jump_button.pressed.connect(_on_jump_pressed)
	if sprint_button:
		sprint_button.pressed.connect(_on_sprint_pressed)
	weapon_prev_button.pressed.connect(_on_weapon_prev)
	weapon_next_button.pressed.connect(_on_weapon_next)

	# Hide joystick visuals initially
	joystick_outer.modulate.a = 0.0
	joystick_inner.modulate.a = 0.0


func _process(_delta: float) -> void:
	# Transfer accumulated look delta and reset for next frame
	look_delta = _frame_look_delta
	_frame_look_delta = Vector2.ZERO

	# Reset single-frame skill press
	if skill_pressed and _skill_was_pressed:
		skill_pressed = false
	if skill_pressed:
		_skill_was_pressed = true

	# Reset single-frame kick press
	if kick_pressed and _kick_was_pressed:
		kick_pressed = false
	if kick_pressed:
		_kick_was_pressed = true

	# Reset single-frame jump press
	if jump_pressed and _jump_was_pressed:
		jump_pressed = false
	if jump_pressed:
		_jump_was_pressed = true


func _input(event: InputEvent) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _handle_screen_touch(touch: InputEventScreenTouch) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var half_x := screen_size.x * 0.5

	if touch.pressed:
		# Check if touch is on left half (joystick area)
		if touch.position.x < half_x and _joystick_touch_id == -1:
			# Ignore if touching buttons in the left area
			if touch.position.y > screen_size.y * 0.8:
				return  # Skill button area
			_joystick_touch_id = touch.index
			_joystick_center = touch.position
			joystick_outer.global_position = _joystick_center - joystick_outer.size * 0.5
			joystick_inner.global_position = _joystick_center - joystick_inner.size * 0.5
			joystick_outer.modulate.a = 0.5
			joystick_inner.modulate.a = 0.7

		# Right half (look / fire area)
		elif touch.position.x >= half_x and _look_touch_id == -1:
			# Ignore if touching top-right buttons
			if touch.position.y < 120.0 and touch.position.x > screen_size.x - 120.0:
				return  # Pause button area
			if touch.position.y > screen_size.y - 160.0:
				return  # Weapon switch area
			_look_touch_id = touch.index
			_look_prev_pos = touch.position
			is_firing = true
	else:
		# Touch released
		if touch.index == _joystick_touch_id:
			_joystick_touch_id = -1
			movement_vector = Vector2.ZERO
			joystick_outer.modulate.a = 0.0
			joystick_inner.modulate.a = 0.0

		elif touch.index == _look_touch_id:
			_look_touch_id = -1
			is_firing = false


func _handle_screen_drag(drag: InputEventScreenDrag) -> void:
	if drag.index == _joystick_touch_id:
		var diff := drag.position - _joystick_center
		# Clamp to radius
		if diff.length() > joystick_radius:
			diff = diff.normalized() * joystick_radius
		# Apply dead zone
		if diff.length() < dead_zone:
			movement_vector = Vector2.ZERO
			joystick_inner.global_position = _joystick_center - joystick_inner.size * 0.5
		else:
			movement_vector = diff / joystick_radius
			joystick_inner.global_position = _joystick_center + diff - joystick_inner.size * 0.5

	elif drag.index == _look_touch_id:
		var delta := drag.position - _look_prev_pos
		_look_prev_pos = drag.position
		_frame_look_delta += delta * sensitivity


# ── Button callbacks ─────────────────────────────────────────────────────────

func _on_pause_pressed() -> void:
	if GameManager.state == GameManager.GameState.PLAYING:
		GameManager.pause_game()


func _on_skill_pressed() -> void:
	skill_pressed = true
	_skill_was_pressed = false


func _on_kick_pressed() -> void:
	kick_pressed = true
	_kick_was_pressed = false


func _on_jump_pressed() -> void:
	jump_pressed = true
	_jump_was_pressed = false


func _on_sprint_pressed() -> void:
	is_sprinting = not is_sprinting


func _on_weapon_prev() -> void:
	# Find the weapon manager in the scene and call switch
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player := players[0]
		for child in player.get_children():
			if child.has_method("switch_weapon"):
				child.switch_weapon(-1)
				break


func _on_weapon_next() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player := players[0]
		for child in player.get_children():
			if child.has_method("switch_weapon"):
				child.switch_weapon(1)
				break
