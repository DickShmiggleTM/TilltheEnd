class_name EnemyRanged
extends EnemyBase
## Hex Archer — green ranged enemy with three distinct shot types.
##
## Unique behaviours:
##   • Burst fire: fires 3 quick projectiles in succession, then enters
##     a standard cooldown before the next burst.
##   • Charged shot: telegraphs for 1.5 s (glows brighter, stops moving),
##     then fires a large, high-damage projectile.
##   • Curse bolt: every 4th shot is purple; if it hits the player it
##     applies a 40 % slow for 3 seconds via player.apply_slow().
##   • Positioning: maintains 8-12 m optimal range while strafing.
##
## Sprite: grell_sheet.png
## Sheet layout assumed: 4 directional rows, 4 animation columns.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 20.0
	base_damage = 6.0
	speed = 3.0
	attack_range = 15.0
	attack_cooldown = 1.5
	base_exp_drop = 15.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/grell_sheet.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 4

func _get_sprite_height() -> float:
	return 0.9

func _get_sprite_fps() -> float:
	return 7.0

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.006

func _get_enemy_color() -> Color:
	return Color(0.2, 0.85, 0.2)

# ---------------------------------------------------------------------------
# Collision shape
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.3
	return capsule

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.65, 0.0)

# ---------------------------------------------------------------------------
# Ranged-specific constants
# ---------------------------------------------------------------------------

const OPTIMAL_RANGE_MIN := 8.0
const OPTIMAL_RANGE_MAX := 12.0
const STRAFE_SPEED := 2.5
const STRAFE_SWITCH_TIME := 2.0

const PROJECTILE_SPEED := 15.0

# Burst fire
const BURST_COUNT := 3
const BURST_INTERVAL := 0.22     ## Seconds between burst shots
const BURST_COOLDOWN := 2.2      ## Full cooldown after a burst

# Charged shot
const CHARGE_INTERVAL := 5.0    ## Every N seconds, trigger a charged shot
const CHARGE_WIND_UP := 1.5     ## Telegraph duration
const CHARGED_DAMAGE_MULT := 2.5
const CHARGED_PROJECTILE_SPEED := 10.0
const CHARGED_PROJECTILE_SIZE := 0.35

# Curse bolt
const CURSE_SHOT_EVERY := 4     ## Every Nth shot becomes a curse bolt
const CURSE_SLOW_AMOUNT := 0.4  ## 40 % slow (multiplier = 0.6 applied)
const CURSE_SLOW_DURATION := 3.0

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _strafe_direction: float = 1.0
var _strafe_timer: float = 0.0

var _burst_remaining: int = 0    ## Shots left in current burst
var _burst_timer: float = 0.0    ## Timer until next burst shot
var _shot_count: int = 0         ## Total shots fired (for curse tracking)

var _charge_cooldown_timer: float = CHARGE_INTERVAL * 0.5  # Start half-way
var _is_winding_up: bool = false
var _wind_up_timer: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_strafe_timer = STRAFE_SWITCH_TIME * randf()
	_charge_cooldown_timer = CHARGE_INTERVAL * (0.4 + randf() * 0.3)

# ---------------------------------------------------------------------------
# Physics override — positioning + burst countdown
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

	var player := get_player()
	var move_dir := Vector3.ZERO

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var forward := to_player.normalized()

		# Face player
		if dist > 0.1:
			look_at(global_position + Vector3(to_player.x, 0, to_player.z), Vector3.UP)

		# During wind-up: stop moving, glow brighter
		if _is_winding_up:
			_wind_up_timer -= delta
			if _wind_up_timer <= 0.0:
				_is_winding_up = false
				_fire_charged_shot(player)
				_charge_cooldown_timer = CHARGE_INTERVAL
				if _sprite_billboard:
					_sprite_billboard.reset_tint()
			else:
				# Hold position, pulse the sprite
				var pulse := 0.5 + 0.5 * sin(_wind_up_timer * 10.0)
				if _sprite_billboard:
					_sprite_billboard.set_tint(Color(0.5 + pulse, 1.0, 0.5 + pulse))
		else:
			# Normal positioning
			if dist > OPTIMAL_RANGE_MAX:
				move_dir += forward
			elif dist < OPTIMAL_RANGE_MIN:
				move_dir -= forward

			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				_strafe_direction *= -1.0
				_strafe_timer = STRAFE_SWITCH_TIME + randf() * 1.0

			var strafe := Vector3(-forward.z, 0.0, forward.x) * _strafe_direction
			move_dir += strafe * 0.6
			if move_dir.length() > 0.001:
				move_dir = move_dir.normalized()

		if _sprite_billboard:
			_sprite_billboard.set_walking()

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Burst fire countdown -------------------------------------------
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			var p := get_player()
			if p and is_instance_valid(p):
				_fire_single_shot(p)
			_burst_remaining -= 1
			if _burst_remaining > 0:
				_burst_timer = BURST_INTERVAL
			else:
				_attack_timer = BURST_COOLDOWN
	else:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_handle_attack(delta)

	# -- Charged shot cooldown -----------------------------------------
	if not _is_winding_up:
		_charge_cooldown_timer -= delta

# ---------------------------------------------------------------------------
# Attack dispatch
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	if _is_winding_up:
		return
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist > attack_range:
		return

	# Decide: charged shot or burst?
	if _charge_cooldown_timer <= 0.0:
		_begin_wind_up()
		return

	# Start a burst
	_burst_remaining = BURST_COUNT
	_burst_timer = 0.0   # Fire first shot immediately next frame

# ---------------------------------------------------------------------------
# Projectile firing
# ---------------------------------------------------------------------------

func _fire_single_shot(target: Node3D) -> void:
	_shot_count += 1
	var is_curse := (_shot_count % CURSE_SHOT_EVERY == 0)

	var proj := _HexProjectile.new()
	var spawn_pos := global_position + Vector3(0.0, 0.8, 0.0)
	proj.global_position = spawn_pos

	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()
	proj.direction = dir
	proj.projectile_speed = PROJECTILE_SPEED
	proj.damage = base_damage * wave_dmg_mult
	proj.is_curse = is_curse
	proj.curse_slow = CURSE_SLOW_AMOUNT
	proj.curse_duration = CURSE_SLOW_DURATION

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

	if _sprite_billboard:
		_sprite_billboard.trigger_attack()


func _fire_charged_shot(target: Node3D) -> void:
	var proj := _HexProjectile.new()
	var spawn_pos := global_position + Vector3(0.0, 0.8, 0.0)
	proj.global_position = spawn_pos

	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()
	proj.direction = dir
	proj.projectile_speed = CHARGED_PROJECTILE_SPEED
	proj.damage = base_damage * wave_dmg_mult * CHARGED_DAMAGE_MULT
	proj.visual_radius = CHARGED_PROJECTILE_SIZE
	proj.is_charged = true

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

	if _sprite_billboard:
		_sprite_billboard.trigger_attack()


func _begin_wind_up() -> void:
	_is_winding_up = true
	_wind_up_timer = CHARGE_WIND_UP
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(0.5, 2.0, 0.5))

# ---------------------------------------------------------------------------
# Inner class: hex projectile (normal, curse, and charged variants)
# ---------------------------------------------------------------------------

class _HexProjectile extends Area3D:

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 15.0
	var damage: float = 6.0
	var visual_radius: float = 0.15
	var is_curse: bool = false
	var is_charged: bool = false
	var curse_slow: float = 0.4
	var curse_duration: float = 3.0
	var _lifetime: float = 5.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = visual_radius
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		if is_charged:
			mat.albedo_color = Color(0.1, 1.0, 0.1)
			mat.emission = Color(0.2, 1.0, 0.2)
			mat.emission_energy_multiplier = 4.0
		elif is_curse:
			mat.albedo_color = Color(0.7, 0.1, 1.0)
			mat.emission = Color(0.6, 0.0, 1.0)
			mat.emission_energy_multiplier = 2.5
		else:
			mat.albedo_color = Color(0.3, 1.0, 0.3)
			mat.emission = Color(0.3, 1.0, 0.3)
			mat.emission_energy_multiplier = 2.0
		mat.emission_enabled = true
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = visual_radius
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		global_position += direction * projectile_speed * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(damage, self)
			# Apply curse slow if applicable
			if is_curse and body.has_method("apply_slow"):
				body.apply_slow(1.0 - curse_slow, curse_duration)
		queue_free()
