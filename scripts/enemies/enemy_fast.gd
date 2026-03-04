class_name EnemyFast
extends EnemyBase
## Skitter — small yellow swarmer with erratic movement and pack synergy.
##
## Unique behaviours:
##   • Zigzag approach: sine-wave lateral offset while advancing.
##   • Hit-and-run: after landing a hit, retreats 3-4 m before re-engaging.
##   • Speed burst: every 3 s, triples speed briefly (0.4 s).
##   • Pack flank: when ≥ 2 other Skitters are near, this one attempts to
##     circle around to the player's side or rear before attacking.
##
## Sprite: bat32x32_spritesheet.png
## Sheet layout assumed: 4 directional rows, 4 columns (wing-flap animation).

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
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/bat32x32_spritesheet.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 4

func _get_sprite_height() -> float:
	return 0.5   # Small creature

func _get_sprite_fps() -> float:
	return 10.0

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.005

func _get_enemy_color() -> Color:
	return Color(1.0, 0.9, 0.1)  # Bright yellow fallback

# ---------------------------------------------------------------------------
# Collision shape
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	return shape

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.35, 0.0)

# ---------------------------------------------------------------------------
# Fast-specific constants
# ---------------------------------------------------------------------------

const ZIGZAG_FREQUENCY := 4.0
const ZIGZAG_AMPLITUDE := 0.7

const HIT_AND_RUN_DIST := 3.5    ## Distance to back away after a hit
const HIT_AND_RUN_DURATION := 0.8

const BURST_INTERVAL := 3.0      ## Seconds between speed bursts
const BURST_DURATION := 0.4
const BURST_SPEED_MULT := 3.0

const FLANK_PACK_THRESHOLD := 2  ## Allies needed before flanking
const FLANK_ANGLE_STEP := 90.0   ## Degrees to orbit per flank cycle

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _zigzag_time: float = 0.0
var _zigzag_offset: float = 0.0

var _is_retreating: bool = false
var _retreat_timer: float = 0.0
var _retreat_dir: Vector3 = Vector3.ZERO

var _burst_timer: float = 0.0
var _burst_active: bool = false
var _burst_countdown: float = 0.0

var _flank_angle: float = 0.0    ## Current orbit offset in degrees
var _is_flanking: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_zigzag_offset = randf() * TAU
	_burst_timer = BURST_INTERVAL * (0.5 + randf() * 0.5)  # Stagger bursts

# ---------------------------------------------------------------------------
# Physics override
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Speed burst timer -----------------------------------------------
	_burst_timer -= delta
	if _burst_timer <= 0.0 and not _burst_active:
		_burst_active = true
		_burst_countdown = BURST_DURATION
		if _sprite_billboard:
			_sprite_billboard.set_tint(Color(1.5, 1.5, 0.2))  # Yellow flash
	if _burst_active:
		_burst_countdown -= delta
		if _burst_countdown <= 0.0:
			_burst_active = false
			_burst_timer = BURST_INTERVAL
			if _sprite_billboard:
				_sprite_billboard.reset_tint()

	# -- Retreat state ---------------------------------------------------
	if _is_retreating:
		_retreat_timer -= delta
		if _retreat_timer <= 0.0:
			_is_retreating = false
		else:
			var eff_speed := speed * wave_speed_mult * slow_mult * 1.2
			var horizontal := _retreat_dir * eff_speed
			velocity.x = horizontal.x
			velocity.z = horizontal.z
			move_and_slide()
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_handle_attack(delta)
			return

	var player := get_player()
	var move_dir := Vector3.ZERO

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var forward := to_player.normalized()

		# -- Check for pack flanking opportunity -------------------------
		_is_flanking = _count_nearby_allies() >= FLANK_PACK_THRESHOLD
		if _is_flanking:
			# Orbit incrementally around the player
			_flank_angle += delta * 45.0
			var flank_basis := Basis(Vector3.UP, deg_to_rad(_flank_angle))
			var flank_forward := flank_basis * forward
			move_dir = flank_forward.normalized()
		else:
			# Zigzag approach
			var right := Vector3(-forward.z, 0.0, forward.x)
			_zigzag_time += delta
			var zigzag := sin(_zigzag_time * ZIGZAG_FREQUENCY + _zigzag_offset) * ZIGZAG_AMPLITUDE
			move_dir = (forward + right * zigzag).normalized()

		# Face movement direction
		if move_dir.length() > 0.1:
			look_at(global_position + Vector3(move_dir.x, 0, move_dir.z), Vector3.UP)

		if _sprite_billboard and dist > attack_range:
			_sprite_billboard.set_walking()

	var eff_speed := speed * wave_speed_mult * slow_mult
	if _burst_active:
		eff_speed *= BURST_SPEED_MULT

	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Attack — quick nip then retreat
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
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()

		# Hit-and-run: immediately back away
		var away := (global_position - player.global_position)
		away.y = 0.0
		_retreat_dir = away.normalized()
		_retreat_timer = HIT_AND_RUN_DURATION
		_is_retreating = true

# ---------------------------------------------------------------------------
# Pack detection
# ---------------------------------------------------------------------------

func _count_nearby_allies() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		if not (e is EnemyFast):
			continue
		if global_position.distance_to(e.global_position) < 8.0:
			count += 1
	return count
