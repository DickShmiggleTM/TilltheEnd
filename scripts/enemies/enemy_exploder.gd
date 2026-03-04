class_name EnemyExploder
extends EnemyBase
## Detonator Wraith — orange suicide bomber with three tactical layers:
##
##   • Feint dash: periodically stops, shifts direction by 60-120°, then
##     resumes rushing, making it harder to line up a kill shot.
##   • Chain reaction: on death, any other Exploder within 5 m has its
##     fuse immediately ignited (zero-delay explosion). This creates
##     devastating chain detonations when they cluster.
##   • Spore cloud: after exploding, spawns a lingering hazard zone that
##     ticks 4 damage per second for 3 seconds. Colour shifts green as
##     it fades.
##
## Sprite: bomb_spritesheet.png
## Sheet layout assumed: 4 directional rows, 2 animation columns.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 15.0
	base_damage = 30.0
	speed = 5.0
	attack_range = 2.0
	attack_cooldown = 999.0  # Only triggers once
	base_exp_drop = 12.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/bomb_spritesheet.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 2

func _get_sprite_height() -> float:
	return 0.55

func _get_sprite_fps() -> float:
	return 6.0

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.0055

func _get_enemy_color() -> Color:
	return Color(1.0, 0.5, 0.0)

# ---------------------------------------------------------------------------
# Collision shape
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	return shape

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.45, 0.0)

# ---------------------------------------------------------------------------
# Exploder-specific constants
# ---------------------------------------------------------------------------

const EXPLOSION_RADIUS := 3.0
const PULSE_SPEED := 4.0
const PULSE_MIN_SCALE := 0.9
const PULSE_MAX_SCALE := 1.15

# Feint dash
const FEINT_INTERVAL_MIN := 2.0
const FEINT_INTERVAL_MAX := 4.5
const FEINT_PAUSE_DURATION := 0.35   ## Stops briefly before shifting direction
const FEINT_ANGLE_MIN := 60.0
const FEINT_ANGLE_MAX := 120.0

# Chain reaction
const CHAIN_RADIUS := 5.0

# Spore cloud
const SPORE_DURATION := 3.0
const SPORE_DPS := 4.0
const SPORE_RADIUS := 1.8
const SPORE_TICK_INTERVAL := 0.5

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _pulse_time: float = 0.0
var _has_exploded: bool = false

var _feint_timer: float = 0.0     ## Counts down to next feint
var _feint_pause_timer: float = 0.0  ## Pause duration during feint
var _is_feinting: bool = false
var _approach_dir: Vector3 = Vector3.ZERO  ## Cached approach direction

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_reset_feint_timer()

# ---------------------------------------------------------------------------
# Physics — pulse glow + feint movement
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
	var dist_to_player := 999.0
	var move_dir := Vector3.ZERO

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist_to_player = to_player.length()

		# Feint logic
		_feint_timer -= delta
		if _feint_timer <= 0.0 and not _is_feinting:
			_start_feint(to_player.normalized())

		if _is_feinting:
			_feint_pause_timer -= delta
			if _feint_pause_timer <= 0.0:
				_is_feinting = false
				_reset_feint_timer()
			# Move in feinted direction (already stored in _approach_dir)
			move_dir = _approach_dir
		else:
			_approach_dir = to_player.normalized()
			move_dir = _approach_dir

		if _approach_dir.length() > 0.1:
			look_at(global_position + Vector3(_approach_dir.x, 0, _approach_dir.z), Vector3.UP)

		if _sprite_billboard:
			_sprite_billboard.set_walking()

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Pulsing visual --------------------------------------------------
	_pulse_time += delta * PULSE_SPEED
	var pulse_factor := lerpf(PULSE_MIN_SCALE, PULSE_MAX_SCALE, (sin(_pulse_time) + 1.0) * 0.5)
	if _sprite_billboard:
		_sprite_billboard.scale = Vector3.ONE * pulse_factor

		# Glow shifts from orange to white/yellow as it gets close
		var proximity := clampf(1.0 - (dist_to_player / 15.0), 0.0, 1.0)
		var glow_color := Color(1.0, 0.5 + proximity * 0.5, proximity * 0.5)
		_sprite_billboard.set_tint(glow_color)

	# -- Explode when in range -------------------------------------------
	if dist_to_player <= attack_range and not _has_exploded:
		_explode()

# ---------------------------------------------------------------------------
# Feint
# ---------------------------------------------------------------------------

func _start_feint(current_dir: Vector3) -> void:
	_is_feinting = true
	_feint_pause_timer = FEINT_PAUSE_DURATION

	# Rotate approach direction by a random angle
	var angle := randf_range(FEINT_ANGLE_MIN, FEINT_ANGLE_MAX)
	if randf() < 0.5:
		angle = -angle
	var rot := Basis(Vector3.UP, deg_to_rad(angle))
	_approach_dir = rot * current_dir


func _reset_feint_timer() -> void:
	_feint_timer = randf_range(FEINT_INTERVAL_MIN, FEINT_INTERVAL_MAX)

# ---------------------------------------------------------------------------
# Explosion
# ---------------------------------------------------------------------------

func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	var effective_damage := base_damage * wave_dmg_mult

	# Damage the player
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= EXPLOSION_RADIUS:
			var falloff := 1.0 - (dist / EXPLOSION_RADIUS)
			if player.has_method("take_damage"):
				player.take_damage(effective_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 12.0

	# Damage other enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist <= EXPLOSION_RADIUS:
			var falloff := 1.0 - (dist / EXPLOSION_RADIUS)
			if enemy.has_method("take_damage"):
				var kb_dir := (enemy.global_position - global_position).normalized()
				enemy.take_damage(effective_damage * 0.5 * falloff, kb_dir)

	# Chain reaction: trigger nearby Exploders immediately
	_trigger_chain_reaction()

	# Visual effects
	_spawn_explosion_visual()
	_spawn_spore_cloud()

	die()


func _trigger_chain_reaction() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if not (enemy is EnemyExploder):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist <= CHAIN_RADIUS:
			var other := enemy as EnemyExploder
			if not other._has_exploded and other.is_alive:
				# Ignite the chain — short delay to feel sequential
				var t := other.get_tree().create_timer(0.15 + dist * 0.04)
				t.timeout.connect(func(): if is_instance_valid(other) and not other._has_exploded: other._explode())


func _spawn_explosion_visual() -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 0.1
	explosion.radial_segments = 12
	explosion.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat
	explosion.global_position = global_position + Vector3(0, 0.5, 0)

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(explosion)
		var tw := explosion.create_tween()
		tw.set_parallel(true)
		tw.tween_property(explosion, "radius", EXPLOSION_RADIUS, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.set_parallel(false)
		tw.tween_callback(explosion.queue_free)


func _spawn_spore_cloud() -> void:
	var cloud := _SporeCloud.new()
	cloud.global_position = global_position
	cloud.damage_per_tick = SPORE_DPS * wave_dmg_mult
	cloud.tick_interval = SPORE_TICK_INTERVAL
	cloud.duration = SPORE_DURATION
	cloud.radius = SPORE_RADIUS

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(cloud)

# ---------------------------------------------------------------------------
# Override die — ensure explosion triggers first
# ---------------------------------------------------------------------------

func die() -> void:
	if not _has_exploded:
		_explode()
		return
	super.die()

# ---------------------------------------------------------------------------
# Inner class: lingering spore cloud
# ---------------------------------------------------------------------------

class _SporeCloud extends Area3D:

	var damage_per_tick: float = 4.0
	var tick_interval: float = 0.5
	var duration: float = 3.0
	var radius: float = 1.8

	var _tick_timer: float = 0.0
	var _lifetime: float = 0.0
	var _visual: CSGSphere3D = null

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		_visual = CSGSphere3D.new()
		_visual.radius = radius
		_visual.radial_segments = 12
		_visual.rings = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.2, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.6, 0.1)
		mat.emission_energy_multiplier = 1.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_visual.material = mat
		add_child(_visual)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius
		col.shape = shape
		add_child(col)

	func _physics_process(delta: float) -> void:
		_lifetime += delta
		if _lifetime >= duration:
			queue_free()
			return

		# Fade out
		var fade := 1.0 - (_lifetime / duration)
		if _visual and _visual.material:
			(_visual.material as StandardMaterial3D).albedo_color.a = 0.35 * fade

		# Damage tick
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer = 0.0
			for body in get_overlapping_bodies():
				if body.has_method("take_damage"):
					body.take_damage(damage_per_tick * tick_interval, self)
