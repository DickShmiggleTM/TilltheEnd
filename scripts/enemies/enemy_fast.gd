class_name EnemyFast
extends EnemyBase
## Small yellow swarmer. Very fast with low health, comes in packs.
## Zigzags toward the player using a sine-wave offset on the movement
## direction, making it harder to hit.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 12.0
	base_damage = 4.0
	speed = 7.0
	attack_range = 1.5
	attack_cooldown = 0.5
	base_exp_drop = 5.0

# ---------------------------------------------------------------------------
# Fast-specific
# ---------------------------------------------------------------------------

const ZIGZAG_FREQUENCY := 4.0   ## How fast it zigzags
const ZIGZAG_AMPLITUDE := 0.7   ## How wide the zigzag is

var _zigzag_time: float = 0.0
var _zigzag_offset: float = 0.0  # Random phase offset per instance

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(1.0, 0.9, 0.1)  # Bright yellow


func _create_mesh() -> Node3D:
	var sphere := CSGSphere3D.new()
	sphere.radius = 0.3
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.position = Vector3(0.0, 0.35, 0.0)
	return sphere


func _create_collision_shape() -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	return shape


func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.35, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	# Each swarmer gets a random phase offset so they don't zigzag in unison
	_zigzag_offset = randf() * TAU

# ---------------------------------------------------------------------------
# Movement override — zigzag pattern
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# -- Flash timer -----------------------------------------------------
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and _mesh is CSGPrimitive3D:
			(_mesh as CSGPrimitive3D).material = _base_material

	# -- Gravity ---------------------------------------------------------
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# -- Knockback decay -------------------------------------------------
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Zigzag movement -------------------------------------------------
	var move_dir := Vector3.ZERO
	var player := get_player()

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var forward := to_player.normalized()

		# Perpendicular vector for zigzag
		var right := Vector3(-forward.z, 0.0, forward.x)

		_zigzag_time += delta
		var zigzag := sin(_zigzag_time * ZIGZAG_FREQUENCY + _zigzag_offset) * ZIGZAG_AMPLITUDE
		move_dir = forward + right * zigzag
		move_dir = move_dir.normalized()

		# Face movement direction for a more frantic look
		if move_dir.length() > 0.1:
			var look_target := global_position + Vector3(move_dir.x, 0, move_dir.z)
			look_at(look_target, Vector3.UP)

	# Apply movement
	var effective_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	# -- Attack logic ----------------------------------------------------
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Attack — quick nip
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		var effective_damage := base_damage * wave_dmg_mult
		if player.has_method("take_damage"):
			player.take_damage(effective_damage, self)
		_attack_timer = attack_cooldown
