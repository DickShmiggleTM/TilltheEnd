class_name EnemyMelee
extends EnemyBase
## Berserker Demon — red melee rusher with three distinct attack modes:
##   • Standard charge: direct approach and melee strike.
##   • Power charge: when 5-12 m away, bursts forward at 3× speed then slams.
##   • Berserker rage: below 30 % HP, permanently 1.6× speed and gains a
##     wide-arc sweep attack that can hit the player even when dodging.
##
## Sprite: wargrinsheet_a_palleted.png
## Sheet layout assumed: 4 directional rows, 4 animation columns (walk).

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 30.0
	base_damage = 8.0
	speed = 4.5
	attack_range = 1.8
	attack_cooldown = 0.8
	base_exp_drop = 10.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/wargrinsheet_a_palleted.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4   # South, East, North — West mirrored from East

func _get_sprite_frames_per_dir() -> int:
	return 4   # 4-frame walk cycle per direction

func _get_sprite_height() -> float:
	return 0.85

func _get_sprite_fps() -> float:
	return 8.0

func _get_sprite_use_mirror() -> bool:
	return true  # Left side mirrors right-side row

func _get_sprite_pixel_size() -> float:
	return 0.006

func _get_enemy_color() -> Color:
	return Color(0.9, 0.15, 0.1)  # Demonic red (used by fallback quad)

# ---------------------------------------------------------------------------
# Collision shape (kept for physics)
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	var scale_bonus := 1.0 + (wave_hp_mult - 1.0) * 0.05
	box.size = Vector3(0.7, 1.1, 0.5) * scale_bonus
	return box

func _get_collision_offset() -> Vector3:
	var scale_bonus := 1.0 + (wave_hp_mult - 1.0) * 0.05
	return Vector3(0.0, 0.55 * scale_bonus, 0.0)

# ---------------------------------------------------------------------------
# Melee-specific state
# ---------------------------------------------------------------------------

# --- Charge attack ---
const CHARGE_MIN_RANGE := 5.0    ## Minimum distance to trigger charge
const CHARGE_MAX_RANGE := 12.0   ## Maximum distance to trigger charge
const CHARGE_SPEED_MULT := 3.0   ## Speed multiplier during a charge
const CHARGE_DURATION := 0.55    ## How long the charge lasts (seconds)
const CHARGE_COOLDOWN := 4.0     ## Seconds between charge attempts

var _charge_timer: float = 0.0       ## Remaining charge active time
var _charge_cooldown_timer: float = 1.5  ## Starts with a brief delay
var _is_charging: bool = false
var _charge_dir: Vector3 = Vector3.ZERO

# --- Berserker rage ---
const BERSERK_HP_THRESHOLD := 0.30   ## Fraction of max HP to trigger rage
const BERSERK_SPEED_MULT := 1.6
const SWEEP_RANGE := 2.5             ## Arc sweep covers a wider area
const SWEEP_ANGLE_HALF := 50.0       ## Half-angle of sweep arc (degrees)

var _is_berserk: bool = false
var _sweep_attack_ready: bool = false  ## True when next melee is a sweep

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_charge_cooldown_timer = 1.5 + randf() * 1.0  # Stagger between instances

# ---------------------------------------------------------------------------
# Physics override — charge movement + berserk activation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)

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

	# -- Berserk check ---------------------------------------------------
	if not _is_berserk and get_health_ratio() < BERSERK_HP_THRESHOLD:
		_activate_berserk()

	var player := get_player()
	var move_dir := Vector3.ZERO
	var dist_to_player := INF

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist_to_player = to_player.length()
		var forward := to_player.normalized()

		# Face the player
		if dist_to_player > 0.1:
			look_at(global_position + Vector3(to_player.x, 0, to_player.z), Vector3.UP)

		# -- Charge state management ------------------------------------
		_charge_cooldown_timer -= delta

		if _is_charging:
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_is_charging = false
				_charge_cooldown_timer = CHARGE_COOLDOWN
				_sweep_attack_ready = true  # Follow up with a sweep
			else:
				move_dir = _charge_dir
		else:
			# Check if we should start a charge
			if (_charge_cooldown_timer <= 0.0
					and dist_to_player >= CHARGE_MIN_RANGE
					and dist_to_player <= CHARGE_MAX_RANGE):
				_start_charge(forward)
			else:
				# Standard approach
				if dist_to_player > attack_range * 0.8:
					move_dir = forward

		if _sprite_billboard and dist_to_player > attack_range * 0.8:
			_sprite_billboard.set_walking()

	# -- Effective speed -------------------------------------------------
	var eff_speed := speed * wave_speed_mult * slow_mult
	if _is_charging:
		eff_speed *= CHARGE_SPEED_MULT
	if _is_berserk:
		eff_speed *= BERSERK_SPEED_MULT

	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Attack logic ----------------------------------------------------
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Attack
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	# Sweep attack: wider arc, used after a charge or in berserk
	if _sweep_attack_ready and dist <= SWEEP_RANGE:
		_do_sweep_attack(player)
		_sweep_attack_ready = false
		_attack_timer = attack_cooldown * 1.3
		return

	# Standard melee
	if dist <= attack_range:
		var effective_damage := base_damage * wave_dmg_mult
		if player.has_method("take_damage"):
			player.take_damage(effective_damage, self)
		_attack_timer = attack_cooldown
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()
		# Lunge visual on the billboard
		_do_lunge_effect()


func _do_sweep_attack(player: Node3D) -> void:
	## Wide arc sweep — damages player if within cone regardless of exact angle.
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > SWEEP_RANGE:
		return

	# Check angle within sweep cone
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var angle := rad_to_deg(fwd.normalized().angle_to(to_player.normalized()))
	if angle <= SWEEP_ANGLE_HALF:
		var effective_damage := base_damage * wave_dmg_mult * 1.4  # 40% bonus
		if player.has_method("take_damage"):
			player.take_damage(effective_damage, self)

	if _sprite_billboard:
		_sprite_billboard.trigger_attack()
	_do_lunge_effect()


func _do_lunge_effect() -> void:
	if _sprite_billboard:
		# Scale the billboard node for a punchy lunge feel
		var tw := create_tween()
		tw.tween_property(_sprite_billboard, "scale", Vector3(1.2, 0.85, 1.2), 0.05)
		tw.tween_property(_sprite_billboard, "scale", Vector3.ONE, 0.12)

# ---------------------------------------------------------------------------
# Charge
# ---------------------------------------------------------------------------

func _start_charge(direction: Vector3) -> void:
	_is_charging = true
	_charge_timer = CHARGE_DURATION
	_charge_dir = direction
	if _sprite_billboard:
		_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Berserk
# ---------------------------------------------------------------------------

func _activate_berserk() -> void:
	_is_berserk = true
	# Tint sprite deep red-purple to signal rage
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(1.0, 0.1, 0.5))
	# Immediately ready a sweep
	_sweep_attack_ready = true
