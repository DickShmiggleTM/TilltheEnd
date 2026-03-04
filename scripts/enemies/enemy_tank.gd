class_name EnemyTank
extends EnemyBase
## Iron Sentinel — slow, massively armoured melee tank with three abilities:
##
##   • Ground pound: leaps then slams, dealing AoE damage within 4 m and
##     applying knockback to everyone in range. Telegraphed by a crouch.
##   • Bull rush: charges forward at 3× speed in a straight line, damaging
##     anything it collides with (player or breakable geometry). 6 s cooldown.
##   • Shield stance: while not moving (idle after an attack), blocks 75 %
##     of all frontal incoming damage. Side/rear hits bypass the shield.
##   • Base damage resistance: takes only 80 % of all damage regardless.
##
## Sprite: stability_officer_sheet_palette.png
## Sheet layout assumed: 4 directional rows, 4 animation columns.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 120.0
	base_damage = 20.0
	speed = 2.0
	attack_range = 2.5
	attack_cooldown = 1.5
	base_exp_drop = 30.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/stability_officer_sheet_palette.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 4

func _get_sprite_height() -> float:
	return 1.1   # Tall/heavy enemy

func _get_sprite_fps() -> float:
	return 5.0   # Slow lumbering animation

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.007  # Larger sprite for big enemy

func _get_enemy_color() -> Color:
	return Color(0.3, 0.3, 0.35)

# ---------------------------------------------------------------------------
# Collision shape
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.6, 1.0)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.8, 0.0)

# ---------------------------------------------------------------------------
# Tank-specific constants
# ---------------------------------------------------------------------------

const DAMAGE_RESISTANCE := 0.8      ## Base: takes 80 % of all damage
const SHIELD_BLOCK := 0.25          ## Shield stance: takes only 25 % from front
const SHIELD_ANGLE := 60.0          ## Half-angle of frontal shield cone (deg)
const PLAYER_KNOCKBACK := 8.0

# Ground pound
const POUND_COOLDOWN := 6.0
const POUND_RANGE := 3.5            ## Max distance to trigger pound
const POUND_AOE_RADIUS := 4.0
const POUND_KNOCKBACK_FORCE := 12.0
const POUND_WIND_UP := 0.6          ## Telegraph crouch before slam

# Bull rush
const RUSH_COOLDOWN := 8.0
const RUSH_TRIGGER_RANGE := 6.0
const RUSH_SPEED_MULT := 3.0
const RUSH_DURATION := 0.7
const RUSH_DAMAGE_MULT := 1.5

# Shield stance
const SHIELD_IDLE_THRESHOLD := 0.05  ## Velocity length below which shield is active

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _pound_timer: float = 2.0
var _is_pounding: bool = false
var _pound_wind_timer: float = 0.0

var _rush_timer: float = RUSH_COOLDOWN * 0.5
var _is_rushing: bool = false
var _rush_countdown: float = 0.0
var _rush_dir: Vector3 = Vector3.ZERO

var _shield_active: bool = false

# ---------------------------------------------------------------------------
# Damage resistance + shield override
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	var reduced := amount * DAMAGE_RESISTANCE

	# Shield stance: check if hit is frontal
	if _shield_active and knockback_dir != Vector3.ZERO:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		var hit_dir := -knockback_dir  # Direction hit came from
		hit_dir.y = 0.0
		if hit_dir.length() > 0.001 and fwd.length() > 0.001:
			var angle := rad_to_deg(fwd.normalized().angle_to(hit_dir.normalized()))
			if angle <= SHIELD_ANGLE:
				reduced *= SHIELD_BLOCK  # Frontal hit: nearly blocked

	super.take_damage(reduced, knockback_dir * 0.5)  # Also resist knockback

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	# Tint to convey armoured look
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(0.85, 0.85, 0.9))

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

	# -- Cooldowns -------------------------------------------------------
	_pound_timer -= delta
	_rush_timer -= delta

	# -- Bull rush active ------------------------------------------------
	if _is_rushing:
		_rush_countdown -= delta
		if _rush_countdown <= 0.0:
			_is_rushing = false
			_rush_timer = RUSH_COOLDOWN
		else:
			var eff := speed * wave_speed_mult * RUSH_SPEED_MULT
			velocity.x = _rush_dir.x * eff
			velocity.z = _rush_dir.z * eff
			move_and_slide()
			# Damage player on collision
			var player := get_player()
			if player and is_instance_valid(player):
				var d := global_position.distance_to(player.global_position)
				if d <= attack_range * 1.2:
					var dmg := base_damage * wave_dmg_mult * RUSH_DAMAGE_MULT
					if player.has_method("take_damage"):
						player.take_damage(dmg, self)
					var kb := (player.global_position - global_position).normalized()
					if player is CharacterBody3D:
						player.velocity += kb * 14.0
					_attack_timer = attack_cooldown
		_attack_timer -= delta
		return

	# -- Ground pound wind-up -------------------------------------------
	if _is_pounding:
		_pound_wind_timer -= delta
		if _pound_wind_timer <= 0.0:
			_is_pounding = false
			_do_ground_pound()
		else:
			# Crouch/shrink visual during wind-up
			if _sprite_billboard:
				_sprite_billboard.scale.y = lerpf(0.8, 1.0, _pound_wind_timer / POUND_WIND_UP)
		_attack_timer -= delta
		return

	# -- Normal movement -------------------------------------------------
	var player := get_player()
	var move_dir := Vector3.ZERO

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var forward := to_player.normalized()

		if dist > 0.1:
			look_at(global_position + Vector3(to_player.x, 0, to_player.z), Vector3.UP)

		if dist > attack_range * 0.8:
			move_dir = forward

		if _sprite_billboard:
			_sprite_billboard.set_walking()

		# Trigger bull rush opportunistically
		if _rush_timer <= 0.0 and dist <= RUSH_TRIGGER_RANGE and dist > attack_range:
			_start_rush(forward)
			_attack_timer -= delta
			return

		# Trigger ground pound opportunistically
		if _pound_timer <= 0.0 and dist <= POUND_RANGE:
			_start_ground_pound()

	# Shield stance: active when barely moving
	var spd := Vector3(velocity.x, 0, velocity.z).length()
	_shield_active = spd < SHIELD_IDLE_THRESHOLD * (speed * wave_speed_mult)

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Attack — heavy melee with knockback
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

		if player is CharacterBody3D:
			var kb_dir := (player.global_position - global_position).normalized()
			player.velocity += kb_dir * PLAYER_KNOCKBACK

		_attack_timer = attack_cooldown

		if _sprite_billboard:
			_sprite_billboard.trigger_attack()
		# Ground-pound visual squish
		if _sprite_billboard:
			var tw := create_tween()
			tw.tween_property(_sprite_billboard, "scale", Vector3(1.25, 0.75, 1.25), 0.08)
			tw.tween_property(_sprite_billboard, "scale", Vector3.ONE, 0.18)

# ---------------------------------------------------------------------------
# Ground pound
# ---------------------------------------------------------------------------

func _start_ground_pound() -> void:
	_is_pounding = true
	_pound_wind_timer = POUND_WIND_UP
	if _sprite_billboard:
		_sprite_billboard.trigger_attack()


func _do_ground_pound() -> void:
	_pound_timer = POUND_COOLDOWN

	# Reset billboard scale
	if _sprite_billboard:
		_sprite_billboard.scale = Vector3.ONE

	# AoE damage to player
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= POUND_AOE_RADIUS:
			var falloff := 1.0 - (dist / POUND_AOE_RADIUS)
			var dmg := base_damage * wave_dmg_mult * 1.5 * falloff
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				kb.y = 0.4
				player.velocity += kb * POUND_KNOCKBACK_FORCE * falloff

	# AoE shockwave visual
	_spawn_shockwave()

	_attack_timer = attack_cooldown * 1.5


func _spawn_shockwave() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.3
	ring.height = 0.15
	ring.sides = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.6, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.4, 0.8)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	ring.global_position = global_position + Vector3(0, 0.05, 0)

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", POUND_AOE_RADIUS, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Bull rush
# ---------------------------------------------------------------------------

func _start_rush(direction: Vector3) -> void:
	_is_rushing = true
	_rush_countdown = RUSH_DURATION
	_rush_dir = direction
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(0.6, 0.6, 1.0))  # Blue tinge during rush
		_sprite_billboard.trigger_attack()


func _end_rush() -> void:
	_is_rushing = false
	_rush_timer = RUSH_COOLDOWN
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(0.85, 0.85, 0.9))
