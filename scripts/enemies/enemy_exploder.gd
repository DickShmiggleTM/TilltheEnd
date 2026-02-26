class_name EnemyExploder
extends EnemyBase
## Orange pulsing suicide bomber. Runs toward the player and explodes on
## contact or when killed. The explosion damages the player AND other enemies
## within the blast radius. Glows brighter as it approaches the player.
## Starts appearing at wave 4+.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 15.0
	base_damage = 30.0     # Explosion damage
	speed = 5.0
	attack_range = 2.0     # Explode trigger range
	attack_cooldown = 999.0  # Only explodes once
	base_exp_drop = 12.0

# ---------------------------------------------------------------------------
# Exploder-specific
# ---------------------------------------------------------------------------

const EXPLOSION_RADIUS := 3.0
const PULSE_SPEED := 4.0
const PULSE_MIN_SCALE := 0.9
const PULSE_MAX_SCALE := 1.15

var _pulse_time: float = 0.0
var _has_exploded: bool = false
var _glow_material: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(1.0, 0.5, 0.0)  # Orange


func _create_mesh() -> Node3D:
	var sphere := CSGSphere3D.new()
	sphere.radius = 0.4
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.position = Vector3(0.0, 0.45, 0.0)
	return sphere


func _create_collision_shape() -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	return shape


func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.45, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	# Store reference to the emission material for glow changes
	_glow_material = _base_material

# ---------------------------------------------------------------------------
# Physics — pulse and glow based on proximity
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# -- Flash timer (damage flash) --------------------------------------
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

	# -- Movement toward player ------------------------------------------
	var move_dir := Vector3.ZERO
	var player := get_player()
	var dist_to_player := 999.0

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist_to_player = to_player.length()
		move_dir = to_player.normalized()

		if to_player.length() > 0.1:
			var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
			look_at(look_target, Vector3.UP)

	# Apply movement
	var effective_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Pulsing visual --------------------------------------------------
	_pulse_time += delta * PULSE_SPEED
	var pulse_factor := lerpf(PULSE_MIN_SCALE, PULSE_MAX_SCALE, (sin(_pulse_time) + 1.0) * 0.5)
	if _mesh:
		_mesh.scale = Vector3.ONE * pulse_factor

	# -- Glow intensity increases as it gets closer ----------------------
	if _glow_material:
		var proximity_factor := clampf(1.0 - (dist_to_player / 15.0), 0.0, 1.0)
		var glow_strength := lerpf(0.5, 4.0, proximity_factor)
		_glow_material.emission_energy_multiplier = glow_strength
		# Shift color toward white/yellow when very close
		var glow_color := _get_enemy_color().lerp(Color(1.0, 1.0, 0.5), proximity_factor * 0.6)
		_glow_material.emission = glow_color

	# -- Explode when in range -------------------------------------------
	if dist_to_player <= attack_range and not _has_exploded:
		_explode()

# ---------------------------------------------------------------------------
# Explosion
# ---------------------------------------------------------------------------

func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	var effective_damage := base_damage * wave_dmg_mult

	# Damage the player if in radius
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= EXPLOSION_RADIUS:
			# Damage falloff based on distance
			var falloff := 1.0 - (dist / EXPLOSION_RADIUS)
			var final_damage := effective_damage * falloff
			if player.has_method("take_damage"):
				player.take_damage(final_damage, self)

			# Knockback player away from explosion
			if player is CharacterBody3D:
				var kb_dir: Vector3 = (player.global_position - global_position).normalized()
				player.velocity += kb_dir * 12.0

	# Damage other enemies in radius
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == self:
			continue
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist <= EXPLOSION_RADIUS:
			var falloff := 1.0 - (dist / EXPLOSION_RADIUS)
			var final_damage := effective_damage * 0.5 * falloff  # Half damage to other enemies
			if enemy.has_method("take_damage"):
				var kb_dir: Vector3 = (enemy.global_position - global_position).normalized()
				enemy.take_damage(final_damage, kb_dir)

	# Explosion visual effect
	_spawn_explosion_effect()

	# Die after exploding
	die()


func _spawn_explosion_effect() -> void:
	# Create a brief expanding sphere as an explosion visual
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
		# Animate expansion then fade
		var tw := explosion.create_tween()
		tw.set_parallel(true)
		tw.tween_property(explosion, "radius", EXPLOSION_RADIUS, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.set_parallel(false)
		tw.tween_callback(explosion.queue_free)

# ---------------------------------------------------------------------------
# Override die to trigger explosion if still alive
# ---------------------------------------------------------------------------

func die() -> void:
	if not _has_exploded:
		_explode()
		return  # _explode calls die() again after setting _has_exploded
	super.die()
