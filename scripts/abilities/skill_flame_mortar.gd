extends AbilityBase
## Flame Mortar -- shoots an arching fireball at the densest enemy cluster.
## On impact the fireball explodes dealing wide area damage and igniting
## enemies hit, dealing burn damage over time.
## Recharges after 5 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 50.0
var explosion_radius: float = 6.0
var burn_dps: float = 8.0
var burn_duration: float = 5.0
var arc_height: float = 12.0
var cooldown: float = 300.0  # 5 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0
var _burning_enemies: Dictionary = {}  # enemy_id -> { enemy, timer, tick_timer }


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 8.0


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	_burning_enemies.clear()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Process burn ticks
	_process_burns(delta)

	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		var enemies := _get_enemies()
		if enemies.size() >= 1:
			_cooldown_timer = cooldown
			_launch_mortar()
		else:
			_cooldown_timer = 3.0


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 50.0 * (1.0 + (level - 1) * 0.25)
	explosion_radius = 6.0 + level * 0.5
	burn_dps = 8.0 * (1.0 + (level - 1) * 0.2)
	burn_duration = 5.0 + level * 1.0
	cooldown = maxf(300.0 - level * 20.0, 150.0)


func _launch_mortar() -> void:
	var target_pos := _find_best_cluster()
	if target_pos == Vector3.ZERO:
		_cooldown_timer = 3.0
		return

	_spawn_fireball(target_pos)


func _find_best_cluster() -> Vector3:
	var enemies := _get_enemies()
	if enemies.is_empty():
		return Vector3.ZERO

	var best_pos := Vector3.ZERO
	var best_score := 0

	for e in enemies:
		var pos := e.global_position
		var score := 0
		for other in enemies:
			if other.global_position.distance_to(pos) <= explosion_radius:
				score += 1
		if score > best_score:
			best_score = score
			best_pos = pos

	return best_pos


func _spawn_fireball(target_pos: Vector3) -> void:
	var fireball := Node3D.new()
	fireball.name = "FlameMortar"

	# Main fireball sphere
	var sphere := CSGSphere3D.new()
	sphere.radius = 0.6
	sphere.radial_segments = 8
	sphere.rings = 6
	sphere.name = "FireballMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.0)
	mat.emission_energy_multiplier = 6.0
	sphere.material = mat
	fireball.add_child(sphere)

	# Flame trail
	var trail := CSGSphere3D.new()
	trail.radius = 0.4
	trail.radial_segments = 6
	trail.rings = 4
	trail.name = "FlameTrail"

	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = Color(1.0, 0.6, 0.0, 0.6)
	trail_mat.emission_enabled = true
	trail_mat.emission = Color(1.0, 0.5, 0.0)
	trail_mat.emission_energy_multiplier = 4.0
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material = trail_mat
	trail.position = Vector3.UP * 0.8
	fireball.add_child(trail)

	get_tree().current_scene.add_child(fireball)
	var start_pos := player.global_position + Vector3.UP * 2.0
	fireball.global_position = start_pos

	# Arc trajectory
	var mid_pos := (start_pos + target_pos) * 0.5 + Vector3.UP * arc_height
	var travel_time := clampf(start_pos.distance_to(target_pos) / 15.0, 0.5, 2.0)

	var tw := get_tree().create_tween()
	tw.tween_property(fireball, "global_position", mid_pos, travel_time * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(fireball, "global_position", target_pos, travel_time * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		_on_mortar_impact(fireball, target_pos)
	)


func _on_mortar_impact(fireball: Node3D, impact_pos: Vector3) -> void:
	if is_instance_valid(fireball):
		fireball.queue_free()

	var damage := get_scaled_damage(base_damage)

	for enemy in _get_enemies_in_range(impact_pos, explosion_radius):
		var dist := enemy.global_position.distance_to(impact_pos)
		var falloff := 1.0 - (dist / explosion_radius) * 0.4
		_deal_damage(enemy, damage * falloff)

		# Ignite the enemy
		var eid := enemy.get_instance_id()
		_burning_enemies[eid] = {
			"enemy": enemy,
			"timer": burn_duration,
			"tick_timer": 0.0,
		}

	_spawn_fire_explosion(impact_pos)


func _process_burns(delta: float) -> void:
	var expired: Array = []
	var tick_damage := burn_dps * delta

	for eid in _burning_enemies.keys():
		var data: Dictionary = _burning_enemies[eid]
		var enemy: Node3D = data.get("enemy")
		if enemy == null or not is_instance_valid(enemy):
			expired.append(eid)
			continue

		data["timer"] -= delta
		if data["timer"] <= 0.0:
			expired.append(eid)
			continue

		# Apply burn damage every frame (scaled by delta)
		_deal_damage(enemy, tick_damage)

	for eid in expired:
		_burning_enemies.erase(eid)


func _spawn_fire_explosion(pos: Vector3) -> void:
	# Main explosion
	var explosion := CSGSphere3D.new()
	explosion.radius = 1.0
	explosion.radial_segments = 10
	explosion.rings = 6
	explosion.name = "MortarExplosion"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos + Vector3.UP * 0.5

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(explosion, "radius", explosion_radius * 0.6, 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.set_parallel(false)
	tw.tween_callback(explosion.queue_free)

	# Ground fire ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 2.0
	ring.sides = 16
	ring.ring_sides = 4
	ring.name = "FireRing"

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.5, 0.0, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.3, 0.0)
	ring_mat.emission_energy_multiplier = 5.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = ring_mat
	ring.rotation_degrees.x = 90.0

	get_tree().current_scene.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.1

	var tw2 := get_tree().create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring, "inner_radius", explosion_radius * 0.6, 0.5).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring, "outer_radius", explosion_radius * 0.8, 0.5).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring_mat, "albedo_color:a", 0.0, 1.0)
	tw2.set_parallel(false)
	tw2.tween_callback(ring.queue_free)
