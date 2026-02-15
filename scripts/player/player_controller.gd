extends CharacterBody3D
## DOOM-style 2.5D first-person player controller for mobile Android.
##
## Handles movement, touch input (virtual joystick + look), health system,
## EXP magnetic collection, hitscan aiming, invincibility frames, head-bob,
## camera sway, jumping, sprinting, kicking, and recoil camera shake.
## All child nodes are created programmatically in _ready().

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Movement
const ACCELERATION := 30.0
const FRICTION := 20.0
const GRAVITY := 9.8
const MAX_FALL_SPEED := 30.0
const JUMP_FORCE := 6.0
const SPRINT_MULTIPLIER := 1.6

## Camera / look
const LOOK_SENSITIVITY_TOUCH := 0.003
const LOOK_SENSITIVITY_MOUSE := 0.002
const VERTICAL_LOOK_LIMIT := deg_to_rad(10.0) # DOOM-style: very limited pitch

## Head bob (DOOM-style: fast, punchy -- slightly boosted)
const BOB_FREQUENCY := 15.0
const BOB_AMPLITUDE_Y := 0.07
const BOB_AMPLITUDE_X := 0.035

## Camera sway (lateral rotation while moving)
const SWAY_SPEED := 6.0
const SWAY_AMOUNT := 0.008

## Combat
const INVINCIBILITY_DURATION := 0.1

## Kick
const KICK_RANGE := 2.5
const KICK_KNOCKBACK := 8.0
const KICK_DAMAGE := 5.0
const KICK_COOLDOWN := 1.0

## Touch zones (fraction of screen width)
const JOYSTICK_ZONE_FRACTION := 0.4  # Left 40 % of screen is joystick
const JOYSTICK_DEAD_ZONE := 20.0      # Pixels
const JOYSTICK_MAX_RADIUS := 120.0    # Pixels

## Jump touch zone (bottom-left corner)
const JUMP_TOUCH_ZONE_X_FRACTION := 0.25
const JUMP_TOUCH_ZONE_Y_FRACTION := 0.25  # Bottom 25 % of screen

## EXP magnet
const EXP_PULL_SPEED := 12.0

# ---------------------------------------------------------------------------
# Child node references (created in _ready)
# ---------------------------------------------------------------------------

var camera: Camera3D
var collision_shape: CollisionShape3D
var aim_ray: RayCast3D
var fire_point: Marker3D

# ---------------------------------------------------------------------------
# Player state
# ---------------------------------------------------------------------------

var current_health: float = 100.0
var _alive: bool = true
var _invincible: bool = false
var _invincibility_timer: float = 0.0

## Head bob state
var _bob_time: float = 0.0
var _camera_base_y: float = 0.0

## Jumping state
var _is_jumping: bool = false

## Sprint state
var _is_sprinting: bool = false

## Kick cooldown
var _kick_cooldown_timer: float = 0.0

## Recoil / camera shake
var _recoil_offset: Vector2 = Vector2.ZERO
var _recoil_recovery_speed := 10.0

## Touch input state
var _joystick_touch_index: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_current: Vector2 = Vector2.ZERO
var _look_touch_index: int = -1
var _look_previous_pos: Vector2 = Vector2.ZERO

## Movement input (normalised direction on the XZ plane, local space)
var _move_input: Vector2 = Vector2.ZERO

## Regen accumulator
var _regen_accumulator: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# -- Collision layers ------------------------------------------------
	collision_layer = 2   # Layer 2: Player
	collision_mask = 1 | 4 | 16  # Layers 1 (Environment), 3 (Enemies), 5 (Pickups)

	# -- Collision shape -------------------------------------------------
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(collision_shape)

	# -- Camera ----------------------------------------------------------
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 0.0)
	camera.fov = 90.0
	camera.current = true
	add_child(camera)
	_camera_base_y = camera.position.y

	# -- Aim RayCast3D ---------------------------------------------------
	aim_ray = RayCast3D.new()
	aim_ray.position = Vector3.ZERO
	aim_ray.target_position = Vector3(0.0, 0.0, -100.0) # forward
	aim_ray.enabled = true
	aim_ray.collide_with_areas = false
	aim_ray.collide_with_bodies = true
	aim_ray.collision_mask = 1 | 4  # Environment + Enemies
	camera.add_child(aim_ray)

	# -- Fire point (projectile spawn marker) ----------------------------
	fire_point = Marker3D.new()
	fire_point.position = Vector3(0.0, 0.0, -0.8)
	camera.add_child(fire_point)

	# -- Initialise health from GameManager ------------------------------
	_sync_stats_from_manager()
	current_health = GameManager.get_trait("max_health")

	# -- Connect EventBus pickups ---------------------------------------
	EventBus.health_collected.connect(_on_health_collected)


func _sync_stats_from_manager() -> void:
	# Convenience alias; we read traits live each frame where needed, but
	# health cap is useful to cache at spawn and on trait change.
	pass


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return

	# ---- Mouse look (desktop testing) ----------------------------------
	if event is InputEventMouseMotion and _look_touch_index == -1:
		_apply_look(event.relative * LOOK_SENSITIVITY_MOUSE)

	# ---- Touch input ---------------------------------------------------
	if event is InputEventScreenTouch:
		var screen_size := get_viewport().get_visible_rect().size
		var screen_w := float(screen_size.x)
		var screen_h := float(screen_size.y)
		var touch: InputEventScreenTouch = event

		if touch.pressed:
			# -- Jump button area: bottom-left corner --------------------
			if _is_jump_touch(touch.position, screen_w, screen_h):
				_try_jump()
			elif touch.position.x < screen_w * JOYSTICK_ZONE_FRACTION and _joystick_touch_index == -1:
				# Start virtual joystick
				_joystick_touch_index = touch.index
				_joystick_origin = touch.position
				_joystick_current = touch.position
			elif touch.position.x >= screen_w * JOYSTICK_ZONE_FRACTION and _look_touch_index == -1:
				# Start look drag
				_look_touch_index = touch.index
				_look_previous_pos = touch.position
		else:
			if touch.index == _joystick_touch_index:
				_joystick_touch_index = -1
				_move_input = Vector2.ZERO
			elif touch.index == _look_touch_index:
				_look_touch_index = -1

	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _joystick_touch_index:
			_joystick_current = drag.position
			var diff := _joystick_current - _joystick_origin
			if diff.length() > JOYSTICK_MAX_RADIUS:
				diff = diff.normalized() * JOYSTICK_MAX_RADIUS
			if diff.length() < JOYSTICK_DEAD_ZONE:
				_move_input = Vector2.ZERO
			else:
				_move_input = diff / JOYSTICK_MAX_RADIUS
		elif drag.index == _look_touch_index:
			var delta := drag.position - _look_previous_pos
			_look_previous_pos = drag.position
			_apply_look(delta * LOOK_SENSITIVITY_TOUCH)


func _apply_look(delta: Vector2) -> void:
	# Horizontal rotation (yaw) on the player body
	rotate_y(-delta.x)

	# Vertical rotation (pitch) on the camera, clamped heavily (DOOM-style)
	camera.rotation.x = clampf(
		camera.rotation.x - delta.y,
		-VERTICAL_LOOK_LIMIT,
		VERTICAL_LOOK_LIMIT
	)


## Check whether a touch position falls inside the jump button area (bottom-left).
func _is_jump_touch(pos: Vector2, screen_w: float, screen_h: float) -> bool:
	return pos.x < screen_w * JUMP_TOUCH_ZONE_X_FRACTION and pos.y > screen_h * (1.0 - JUMP_TOUCH_ZONE_Y_FRACTION)


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	# -- Invincibility timer ---------------------------------------------
	if _invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_invincible = false

	# -- Kick cooldown ---------------------------------------------------
	if _kick_cooldown_timer > 0.0:
		_kick_cooldown_timer -= delta

	# -- Health regeneration ---------------------------------------------
	var regen_rate: float = GameManager.get_trait("health_regen")
	if regen_rate > 0.0:
		_regen_accumulator += regen_rate * delta
		if _regen_accumulator >= 1.0:
			var regen_amount := floorf(_regen_accumulator)
			_regen_accumulator -= regen_amount
			heal(regen_amount)

	# -- Keyboard: jump, sprint, kick ------------------------------------
	if Input.is_action_just_pressed("jump"):
		_try_jump()

	if Input.is_action_just_pressed("sprint"):
		_is_sprinting = not _is_sprinting

	if Input.is_action_just_pressed("kick"):
		kick()

	# -- Gather movement input -------------------------------------------
	var input_dir := _get_movement_input()

	# -- Calculate desired velocity on XZ plane --------------------------
	var move_speed: float = GameManager.get_trait("speed")
	if _is_sprinting:
		move_speed *= SPRINT_MULTIPLIER

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var desired_velocity := (forward * input_dir.y + right * input_dir.x) * move_speed

	# Smoothly accelerate / decelerate
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if desired_velocity.length() > 0.01:
		horizontal = horizontal.move_toward(desired_velocity, ACCELERATION * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)

	# -- Gravity / jumping -----------------------------------------------
	var vert := velocity.y
	if not is_on_floor():
		vert -= GRAVITY * delta
		vert = maxf(vert, -MAX_FALL_SPEED)
	else:
		if _is_jumping:
			_is_jumping = false
		vert = 0.0

	velocity = Vector3(horizontal.x, vert, horizontal.z)
	move_and_slide()

	# -- Head bob & sway -------------------------------------------------
	var is_moving_on_floor := input_dir.length() > 0.1 and is_on_floor()
	_update_head_bob(delta, is_moving_on_floor)
	_update_camera_sway(delta, is_moving_on_floor)

	# -- Recoil recovery -------------------------------------------------
	_update_recoil(delta)

	# -- EXP magnet pull -------------------------------------------------
	_pull_nearby_exp(delta)


func _get_movement_input() -> Vector2:
	# Touch joystick takes priority when active
	if _joystick_touch_index != -1:
		return _move_input

	# Keyboard fallback for desktop testing
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		dir.y += 1.0
	if Input.is_action_pressed("move_backward"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	return dir.limit_length(1.0)


# ---------------------------------------------------------------------------
# Jumping
# ---------------------------------------------------------------------------

func _try_jump() -> void:
	if is_on_floor() and not _is_jumping:
		_is_jumping = true
		velocity.y = JUMP_FORCE


# ---------------------------------------------------------------------------
# Kick
# ---------------------------------------------------------------------------

func kick() -> void:
	if _kick_cooldown_timer > 0.0:
		return

	_kick_cooldown_timer = KICK_COOLDOWN

	var kick_direction := -global_transform.basis.z
	kick_direction.y = 0.0
	kick_direction = kick_direction.normalized()

	# Find enemies within range in front of the player
	var enemies := get_tree().get_nodes_in_group("enemies")
	for node: Node in enemies:
		if not node is Node3D:
			continue
		var enemy := node as Node3D
		if not is_instance_valid(enemy):
			continue

		var to_enemy := enemy.global_position - global_position
		var dist := to_enemy.length()
		if dist > KICK_RANGE:
			continue

		# Check if enemy is roughly in front of the player (dot > 0)
		var dir_to_enemy := to_enemy.normalized()
		var dot := kick_direction.dot(Vector3(dir_to_enemy.x, 0.0, dir_to_enemy.z).normalized())
		if dot < 0.3:
			continue

		# Apply knockback
		var knockback_dir := Vector3(dir_to_enemy.x, 0.2, dir_to_enemy.z).normalized()
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(knockback_dir * KICK_KNOCKBACK)

		# Apply small damage
		if enemy.has_method("take_damage"):
			enemy.take_damage(KICK_DAMAGE)

	# Emit kick signal
	EventBus.player_kicked.emit(kick_direction)


# ---------------------------------------------------------------------------
# Head Bob
# ---------------------------------------------------------------------------

func _update_head_bob(delta: float, moving: bool) -> void:
	if moving:
		_bob_time += delta * BOB_FREQUENCY
	else:
		# Smoothly return to rest
		_bob_time = lerpf(_bob_time, 0.0, 10.0 * delta)

	var bob_y := sin(_bob_time) * BOB_AMPLITUDE_Y
	var bob_x := cos(_bob_time * 0.5) * BOB_AMPLITUDE_X
	camera.position.y = _camera_base_y + bob_y
	camera.position.x = bob_x


# ---------------------------------------------------------------------------
# Camera Sway
# ---------------------------------------------------------------------------

func _update_camera_sway(delta: float, moving: bool) -> void:
	if moving:
		var sway_rotation := sin(_bob_time * SWAY_SPEED / BOB_FREQUENCY) * SWAY_AMOUNT
		camera.rotation.z = lerpf(camera.rotation.z, sway_rotation, 8.0 * delta)
	else:
		camera.rotation.z = lerpf(camera.rotation.z, 0.0, 8.0 * delta)


# ---------------------------------------------------------------------------
# Recoil / Camera Shake
# ---------------------------------------------------------------------------

func apply_recoil(amount: float) -> void:
	## Called by weapon_manager (or other systems) when a weapon fires.
	## Adds upward + random lateral recoil to the camera.
	_recoil_offset.x += randf_range(-amount * 0.3, amount * 0.3)
	_recoil_offset.y += amount


func _update_recoil(delta: float) -> void:
	if _recoil_offset.length() < 0.0001:
		_recoil_offset = Vector2.ZERO
		return

	# Apply recoil offset to camera rotation
	camera.rotation.x = clampf(
		camera.rotation.x + _recoil_offset.y * delta,
		-VERTICAL_LOOK_LIMIT,
		VERTICAL_LOOK_LIMIT
	)
	camera.rotation.z += _recoil_offset.x * delta

	# Recover recoil over time
	_recoil_offset = _recoil_offset.move_toward(Vector2.ZERO, _recoil_recovery_speed * delta)


# ---------------------------------------------------------------------------
# EXP Magnet
# ---------------------------------------------------------------------------

func _pull_nearby_exp(delta: float) -> void:
	var collect_range: float = GameManager.get_trait("collect_range")
	if collect_range <= 0.0:
		return

	# Find all nodes in the "exp_pickups" group within range
	var exp_nodes := get_tree().get_nodes_in_group("exp_pickups")
	for node: Node in exp_nodes:
		if not node is Node3D:
			continue
		var pickup := node as Node3D
		if not is_instance_valid(pickup):
			continue
		var dist := global_position.distance_to(pickup.global_position)
		if dist < collect_range:
			# Pull toward player
			var dir := (global_position - pickup.global_position).normalized()
			pickup.global_position += dir * EXP_PULL_SPEED * delta
			# Very close -> collect
			if dist < 0.6:
				if pickup.has_method("collect"):
					pickup.collect()


# ---------------------------------------------------------------------------
# Health / Combat
# ---------------------------------------------------------------------------

func take_damage(amount: float, source: Node3D) -> void:
	if not _alive:
		return
	if _invincible:
		return

	# -- Dodge chance ----------------------------------------------------
	var dodge_chance: float = GameManager.get_trait("dodge_chance")
	if dodge_chance > 0.0 and randf() < dodge_chance:
		# Dodged! Could emit a "MISS" floating text via signal later.
		return

	# -- Defense & armor reduction ---------------------------------------
	var defense: float = GameManager.get_trait("defense")
	var armor: float = GameManager.get_trait("armor")

	# Flat reduction from armor, then percentage reduction from defense
	var reduced := maxf(amount - armor, 0.0)
	if defense > 0.0:
		reduced *= maxf(1.0 - (defense / (defense + 100.0)), 0.0)

	# At least 1 damage if original amount was positive
	reduced = maxf(reduced, 1.0) if amount > 0.0 else 0.0

	current_health -= reduced
	current_health = maxf(current_health, 0.0)

	# -- Start invincibility frames --------------------------------------
	_invincible = true
	_invincibility_timer = INVINCIBILITY_DURATION

	# -- Emit signals ----------------------------------------------------
	EventBus.player_damaged.emit(reduced, source)
	EventBus.damage_dealt.emit(reduced, global_position + Vector3(0, 1.5, 0), false)

	# -- Death check -----------------------------------------------------
	if current_health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if not _alive:
		return
	if amount <= 0.0:
		return

	var max_hp: float = GameManager.get_trait("max_health")
	var old_health := current_health
	current_health = minf(current_health + amount, max_hp)

	var actual := current_health - old_health
	if actual > 0.0:
		EventBus.player_healed.emit(actual)


func _die() -> void:
	_alive = false
	EventBus.player_died.emit()
	# Disable further collision processing
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	set_process(false)


func _on_health_collected(amount: float) -> void:
	heal(amount)


# ---------------------------------------------------------------------------
# Aim helpers
# ---------------------------------------------------------------------------

func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


func get_fire_position() -> Vector3:
	return fire_point.global_position


func is_alive() -> bool:
	return _alive


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func get_health_ratio() -> float:
	var max_hp: float = GameManager.get_trait("max_health")
	return current_health / max_hp if max_hp > 0.0 else 0.0


func get_aim_target() -> Dictionary:
	## Returns info about whatever the aim RayCast3D is hitting.
	## { "hit": bool, "collider": Node3D or null, "position": Vector3, "normal": Vector3 }
	if aim_ray.is_colliding():
		return {
			"hit": true,
			"collider": aim_ray.get_collider(),
			"position": aim_ray.get_collision_point(),
			"normal": aim_ray.get_collision_normal(),
		}
	return {
		"hit": false,
		"collider": null,
		"position": fire_point.global_position + get_aim_direction() * 100.0,
		"normal": Vector3.UP,
	}
