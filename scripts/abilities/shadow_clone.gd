extends AbilityBase
## Shadow Clone -- spawns a decoy at the player's position that attracts
## enemies. The decoy has health and explodes when destroyed or after its
## duration expires.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 25.0
var clone_health: float = 30.0
var duration: float = 5.0
var cooldown: float = 8.0
var explosion_radius: float = 5.0

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0
var _active_clone: Node3D = null


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 1.0  # brief delay before first clone


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if _active_clone and is_instance_valid(_active_clone):
		_active_clone.queue_free()
		_active_clone = null


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Only spawn a new clone when the previous one is gone
	if _active_clone != null and is_instance_valid(_active_clone):
		return

	_active_clone = null
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = cooldown
		_spawn_clone()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 25.0 * (1.0 + (level - 1) * 0.3)
	clone_health = 30.0 + level * 10.0
	duration = 5.0 + level
	cooldown = maxf(8.0 - level * 0.5, 3.0)
	explosion_radius = 5.0 + level * 0.3


func _spawn_clone() -> void:
	var clone := Node3D.new()
	clone.name = "ShadowClone"

	# Visual: dark semi-transparent cylinder (humanoid silhouette)
	var body := CSGCylinder3D.new()
	body.radius = 0.4
	body.height = 1.8
	body.sides = 8
	body.name = "CloneBody"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.0, 0.25, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.0, 0.4)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material = mat
	clone.add_child(body)
	body.position = Vector3.UP * 0.9  # offset so base is at floor

	# "Head" sphere
	var head := CSGSphere3D.new()
	head.radius = 0.25
	head.radial_segments = 6
	head.rings = 4
	head.name = "CloneHead"
	head.material = mat
	head.position = Vector3.UP * 2.05
	clone.add_child(head)

	# Enemy attraction area (large detection radius)
	var attract_area := Area3D.new()
	attract_area.name = "AttractArea"
	attract_area.collision_layer = 2  # Layer 2 (Player) -- enemies see it as a target
	attract_area.collision_mask  = 4  # Mask  3 (Enemies)
	attract_area.monitorable = true
	attract_area.monitoring = true

	var attract_col := CollisionShape3D.new()
	var attract_sphere := SphereShape3D.new()
	attract_sphere.radius = 8.0
	attract_col.shape = attract_sphere
	attract_area.add_child(attract_col)
	clone.add_child(attract_area)

	# Damage reception area (for enemies to hit the clone)
	var hit_area := Area3D.new()
	hit_area.name = "HitArea"
	hit_area.collision_layer = 2   # appear as player-like target
	hit_area.collision_mask  = 4   # detect enemies
	hit_area.monitorable = true
	hit_area.monitoring = true

	var hit_col := CollisionShape3D.new()
	var hit_sphere := SphereShape3D.new()
	hit_sphere.radius = 0.6
	hit_col.shape = hit_sphere
	hit_col.position = Vector3.UP * 0.9
	hit_area.add_child(hit_col)
	clone.add_child(hit_area)

	# Add clone to the group so enemies can target it
	clone.add_to_group("player_decoys")

	get_tree().current_scene.add_child(clone)
	clone.global_position = player.global_position
	_active_clone = clone

	# Track clone health and duration
	var hp := clone_health
	var time_left := duration
	var exploded := false
	var dmg := get_scaled_damage(base_damage)
	var radius := explosion_radius

	# Damage from enemy overlaps
	hit_area.body_entered.connect(func(body_node: Node3D) -> void:
		if body_node.is_in_group("enemies") and is_instance_valid(body_node):
			# Enemy "attacks" the clone
			var attack_dmg := 5.0  # approximate contact damage
			hp -= attack_dmg
			# Flash effect
			mat.emission_energy_multiplier = 6.0
			var flash_tw := get_tree().create_tween()
			flash_tw.tween_property(mat, "emission_energy_multiplier", 2.0, 0.15)
			if hp <= 0.0 and not exploded:
				exploded = true
				_explode_clone(clone, dmg, radius)
	)

	# Duration timer via tween
	var dur_tw := get_tree().create_tween()
	dur_tw.tween_callback(func() -> void:
		if not exploded and is_instance_valid(clone):
			time_left -= get_process_delta_time()
			# Pulse visual as time runs out
			if time_left < 2.0:
				mat.albedo_color.a = 0.3 + 0.35 * abs(sin(time_left * 4.0))
			if time_left <= 0.0:
				exploded = true
				_explode_clone(clone, dmg, radius)
				dur_tw.kill()
	).set_delay(0.0)
	dur_tw.set_loops()


func _explode_clone(clone: Node3D, damage: float, radius: float) -> void:
	if not is_instance_valid(clone):
		return

	var pos := clone.global_position

	# Area damage
	for enemy in _get_enemies_in_range(pos, radius):
		_deal_damage(enemy, damage)

	# Explosion visual
	_spawn_explosion(pos, radius)

	clone.queue_free()
	_active_clone = null


func _spawn_explosion(pos: Vector3, radius: float) -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 0.5
	explosion.radial_segments = 8
	explosion.rings = 4
	explosion.name = "CloneExplosion"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.0, 0.7, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.0, 0.8)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos + Vector3.UP * 0.5

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(explosion, "radius", radius * 0.5, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(explosion.queue_free)
