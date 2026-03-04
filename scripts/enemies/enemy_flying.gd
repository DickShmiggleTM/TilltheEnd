class_name EnemyFlying
extends EnemyBase
## Wraith Scout — cyan flying enemy that hovers above the battlefield and
## uses aerial tactics the player can't dodge the same way as ground threats.
##
## Unique behaviours:
##   • Levitation: targets a hover altitude of 3-4 m above ground;
##     levitation force re-asserts after knockback displaces it.
##   • Dive bomb: when close enough horizontally, plunges straight down
##     to strike the player then pulls up; deals bonus dive damage.
##   • Evasive barrel roll: on taking damage, fires a random horizontal
##     impulse so the next shot is harder to land.
##   • Screech: every 8 s emits a terror cry that temporarily amplifies
##     all damage the player receives by 20 % for 4 s.
##
## Sprite: ghost.png
## Sheet layout assumed: single-direction, 1 frame (simple ghost icon).

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health   = 22.0
	base_damage  = 7.0
	speed        = 5.5
	attack_range = 1.6
	attack_cooldown = 1.2
	base_exp_drop = 18.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/ghost.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 1   # Ghost faces all directions equally (billboard only)

func _get_sprite_frames_per_dir() -> int:
	return 1

func _get_sprite_height() -> float:
	return 0.0   # Height managed by levitation, billboard at origin

func _get_sprite_fps() -> float:
	return 4.0

func _get_sprite_use_mirror() -> bool:
	return false

func _get_sprite_pixel_size() -> float:
	return 0.007

func _get_enemy_color() -> Color:
	return Color(0.5, 0.9, 1.0)   # Cyan ghost fallback

# ---------------------------------------------------------------------------
# Collision shape — narrow capsule (aerial enemy)
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 0.9
	return cap

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.45, 0.0)

# ---------------------------------------------------------------------------
# Flying-specific constants
# ---------------------------------------------------------------------------

const FLY_HEIGHT_MIN := 2.8      ## Minimum hover altitude above spawn Y
const FLY_HEIGHT_MAX := 4.2      ## Maximum hover altitude
const LEVITATION_FORCE := 18.0   ## Upward spring force coefficient
const LEVITATION_DAMPING := 6.0  ## Damps oscillation around target height
const HORIZONTAL_DRAG := 4.0     ## Air resistance on XZ movement

# Dive bomb
const DIVE_TRIGGER_DIST := 4.5   ## Horizontal distance to begin a dive
const DIVE_SPEED := 18.0         ## Downward velocity during dive
const DIVE_DAMAGE_MULT := 1.5    ## Bonus multiplier for dive hits
const DIVE_PULLUP_SPEED := 10.0  ## Upward exit velocity after hitting ground
const DIVE_COOLDOWN := 3.0

# Barrel roll evasion
const ROLL_IMPULSE := 6.0        ## Horizontal speed kick when evading
const ROLL_DURATION := 0.3       ## How long the evade impulse lasts

# Screech
const SCREECH_INTERVAL := 8.0
const SCREECH_DEBUFF_MULT := 1.20   ## Player takes 20 % more damage
const SCREECH_DURATION := 4.0

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

enum FlyState { HOVER, DIVE, PULLUP }
var _fly_state: FlyState = FlyState.HOVER

var _spawn_y: float = 0.0          ## Ground-level Y (set in _ready)
var _target_fly_y: float = 0.0

var _dive_cooldown: float = 1.0
var _roll_timer: float = 0.0       ## >0 means rolling; direction already applied
var _roll_dir: Vector3 = Vector3.ZERO

var _screech_timer: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_spawn_y = global_position.y
	_target_fly_y = _spawn_y + randf_range(FLY_HEIGHT_MIN, FLY_HEIGHT_MAX)
	_screech_timer = SCREECH_INTERVAL * (0.4 + randf() * 0.4)

	# Visual tint: semi-translucent cyan glow
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(0.7, 1.0, 1.0))

# ---------------------------------------------------------------------------
# Physics override — full aerial movement
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)

	# -- Cooldowns -------------------------------------------------------
	_dive_cooldown = maxf(_dive_cooldown - delta, 0.0)
	_screech_timer -= delta

	# -- Screech ability -------------------------------------------------
	if _screech_timer <= 0.0:
		_do_screech()
		_screech_timer = SCREECH_INTERVAL

	# -- Barrel roll cooldown -------------------------------------------
	if _roll_timer > 0.0:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			# Bleed off the roll impulse
			velocity.x = lerpf(velocity.x, 0.0, 0.5)
			velocity.z = lerpf(velocity.z, 0.0, 0.5)

	# -- Horizontal drag (air resistance) --------------------------------
	velocity.x = lerpf(velocity.x, 0.0, HORIZONTAL_DRAG * delta)
	velocity.z = lerpf(velocity.z, 0.0, HORIZONTAL_DRAG * delta)

	var player := get_player()
	var dist_horizontal := 0.0

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		var flat := Vector3(to_player.x, 0.0, to_player.z)
		dist_horizontal = flat.length()
		var forward := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD

		# Face player horizontally
		look_at(global_position + Vector3(to_player.x, 0.0, to_player.z), Vector3.UP)

		match _fly_state:
			FlyState.HOVER:
				_tick_hover(delta, forward, dist_horizontal)
			FlyState.DIVE:
				_tick_dive(delta, player)
			FlyState.PULLUP:
				_tick_pullup(delta)

	elif _fly_state == FlyState.HOVER:
		_tick_levitation(delta)

	move_and_slide()

	# -- Attack timer (melee while diving) --------------------------------
	_attack_timer -= delta
	if _attack_timer <= 0.0 and _fly_state == FlyState.HOVER:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Hover behaviour
# ---------------------------------------------------------------------------

func _tick_hover(delta: float, forward: Vector3, dist_h: float) -> void:
	_tick_levitation(delta)

	# Approach player horizontally
	var eff_speed := speed * wave_speed_mult * slow_mult
	if dist_h > attack_range * 1.5:
		velocity.x += forward.x * eff_speed * delta * 8.0
		velocity.z += forward.z * eff_speed * delta * 8.0

	# Clamp horizontal speed
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length() > eff_speed:
		hv = hv.normalized() * eff_speed
		velocity.x = hv.x
		velocity.z = hv.z

	# Dive trigger
	if dist_h <= DIVE_TRIGGER_DIST and _dive_cooldown <= 0.0:
		_fly_state = FlyState.DIVE
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()


func _tick_levitation(delta: float) -> void:
	## Spring force to maintain target hover altitude.
	var err: float = _target_fly_y - global_position.y
	var spring: float = err * LEVITATION_FORCE - velocity.y * LEVITATION_DAMPING
	velocity.y += spring * delta
	# Safety: never fall below spawn_y + 0.2
	if global_position.y < _spawn_y + 0.2 and velocity.y < 0.0:
		velocity.y = 0.0

# ---------------------------------------------------------------------------
# Dive behaviour
# ---------------------------------------------------------------------------

func _tick_dive(delta: float, player: Node3D) -> void:
	# Plunge downward
	velocity.y = -DIVE_SPEED

	# Keep tracking player horizontally during dive (slow)
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length() > 0.01:
		var track := flat.normalized() * speed * wave_speed_mult * 0.4
		velocity.x = lerpf(velocity.x, track.x, delta * 4.0)
		velocity.z = lerpf(velocity.z, track.z, delta * 4.0)

	# Hit player while diving
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range * 1.4 and _attack_timer <= 0.0:
		var dmg := base_damage * wave_dmg_mult * DIVE_DAMAGE_MULT
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)
		_attack_timer = attack_cooldown
		_begin_pullup()
		return

	# Pull up if we've gone too low
	if global_position.y <= _spawn_y + 0.3:
		_begin_pullup()


func _begin_pullup() -> void:
	_fly_state = FlyState.PULLUP
	velocity.y = DIVE_PULLUP_SPEED
	_dive_cooldown = DIVE_COOLDOWN
	# Recalculate hover target
	_target_fly_y = _spawn_y + randf_range(FLY_HEIGHT_MIN, FLY_HEIGHT_MAX)

# ---------------------------------------------------------------------------
# Pull-up behaviour (ascend after dive)
# ---------------------------------------------------------------------------

func _tick_pullup(delta: float) -> void:
	# Bleed upward velocity and level off
	velocity.y = lerpf(velocity.y, 0.0, delta * 3.0)
	if global_position.y >= _target_fly_y * 0.85:
		_fly_state = FlyState.HOVER

# ---------------------------------------------------------------------------
# Attack — only fires outside dives
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	if _fly_state != FlyState.HOVER:
		return
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		var dmg := base_damage * wave_dmg_mult
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)
		_attack_timer = attack_cooldown
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Evasive barrel roll — triggered by take_damage override
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir)
	if not is_alive:
		return
	# Fire a random horizontal impulse
	var roll_angle := randf() * TAU
	_roll_dir = Vector3(cos(roll_angle), 0.0, sin(roll_angle))
	velocity.x += _roll_dir.x * ROLL_IMPULSE
	velocity.z += _roll_dir.z * ROLL_IMPULSE
	_roll_timer = ROLL_DURATION
	# Tilt sprite slightly
	if _sprite_billboard:
		var tw := create_tween()
		tw.tween_property(_sprite_billboard, "rotation_degrees:z",
			sign(_roll_dir.x) * 25.0, 0.08)
		tw.tween_property(_sprite_billboard, "rotation_degrees:z", 0.0, 0.15)

# ---------------------------------------------------------------------------
# Screech — debuffs player damage resistance
# ---------------------------------------------------------------------------

func _do_screech() -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	# Apply via method if player supports it, otherwise timed damage_amp
	if player.has_method("apply_damage_debuff"):
		player.apply_damage_debuff(SCREECH_DEBUFF_MULT, SCREECH_DURATION)
	elif "damage_amp" in player:
		# Temporarily boost player's incoming damage multiplier
		player.damage_amp *= SCREECH_DEBUFF_MULT
		# Use scene timer to revert
		var t := get_tree().create_timer(SCREECH_DURATION)
		t.timeout.connect(func():
			if is_instance_valid(player) and "damage_amp" in player:
				player.damage_amp /= SCREECH_DEBUFF_MULT)

	# Screech visual: pulse the sprite red-orange briefly
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(1.5, 0.5, 0.2))
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_callback(func():
			if is_instance_valid(_sprite_billboard):
				_sprite_billboard.set_tint(Color(0.7, 1.0, 1.0)))
