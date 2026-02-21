extends AbilityBase
## Bouncing Star -- throws a large bouncing Morningstar projectile that
## ricochets between enemies, dealing damage to each one it contacts.
## Recharges after 2 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 35.0
var bounce_count: int = 5
var bounce_range: float = 10.0
var projectile_speed: float = 14.0
var cooldown: float = 120.0  # 2 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 4.0


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	pass


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		var nearest := _get_nearest_enemy(player.global_position, bounce_range * 1.5)
		if nearest != null:
			_cooldown_timer = cooldown
			_throw_star(nearest)
		else:
			_cooldown_timer = 1.5


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 35.0 * (1.0 + (level - 1) * 0.2)
	bounce_count = 5 + level
	bounce_range = 10.0 + level * 1.0
	cooldown = maxf(120.0 - level * 8.0, 60.0)


func _throw_star(first_target: Node3D) -> void:
	var star := _create_star_visual()
	get_tree().current_scene.add_child(star)
	star.global_position = player.global_position + Vector3.UP * 1.2

	var damage := get_scaled_damage(base_damage)
	_bounce_to_target(star, first_target, damage, bounce_count, {})


func _bounce_to_target(star: Node3D, target: Node3D, damage: float, bounces_left: int, hit_set: Dictionary) -> void:
	if not is_instance_valid(star) or not is_instance_valid(target):
		if is_instance_valid(star):
			star.queue_free()
		return

	var travel_time := star.global_position.distance_to(target.global_position) / projectile_speed
	travel_time = clampf(travel_time, 0.1, 1.0)

	var tw := get_tree().create_tween()
	tw.tween_property(star, "global_position", target.global_position + Vector3.UP * 1.0, travel_time).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(star):
			return

		# Deal damage on hit
		if is_instance_valid(target):
			_deal_damage(target, damage)
			hit_set[target.get_instance_id()] = true
			_spawn_hit_sparks(target.global_position + Vector3.UP * 1.0)

		# Find next bounce target
		if bounces_left > 0:
			var next := _find_next_bounce(star.global_position, hit_set)
			if next != null:
				# Each bounce does slightly less damage
				_bounce_to_target(star, next, damage * 0.9, bounces_left - 1, hit_set)
				return

		# No more bounces -- destroy star
		_despawn_star(star)
	)

	# Spin the star while traveling
	var spin_tw := get_tree().create_tween()
	spin_tw.tween_property(star, "rotation_degrees:y", star.rotation_degrees.y + 720.0, travel_time)


func _find_next_bounce(from_pos: Vector3, hit_set: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = bounce_range * bounce_range
	for e in _get_enemies():
		if hit_set.has(e.get_instance_id()):
			continue
		var d := e.global_position.distance_squared_to(from_pos)
		if d < best_dist_sq:
			best_dist_sq = d
			best = e
	# If all enemies have been hit, allow re-hitting
	if best == null:
		for e in _get_enemies():
			var d := e.global_position.distance_squared_to(from_pos)
			if d < best_dist_sq:
				best_dist_sq = d
				best = e
	return best


func _create_star_visual() -> Node3D:
	var star := Node3D.new()
	star.name = "BouncingStar"

	# Spiky sphere (morningstar head)
	var core := CSGSphere3D.new()
	core.radius = 0.4
	core.radial_segments = 6
	core.rings = 4
	core.name = "StarCore"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.65)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.7, 0.5)
	mat.emission_energy_multiplier = 2.0
	core.material = mat
	star.add_child(core)

	# Spikes (4 protruding boxes)
	for i in 6:
		var spike := CSGBox3D.new()
		spike.size = Vector3(0.1, 0.1, 0.35)
		spike.name = "Spike_%d" % i

		var spike_mat := StandardMaterial3D.new()
		spike_mat.albedo_color = Color(0.5, 0.5, 0.55)
		spike_mat.emission_enabled = true
		spike_mat.emission = Color(0.7, 0.6, 0.4)
		spike_mat.emission_energy_multiplier = 1.5
		spike.material = spike_mat

		var angle := TAU / 6.0 * i
		spike.position = Vector3(cos(angle) * 0.4, 0.0, sin(angle) * 0.4)
		spike.look_at_from_position(spike.position, spike.position + Vector3(cos(angle), 0.0, sin(angle)), Vector3.UP)
		star.add_child(spike)

	# Glowing trail aura
	var glow := CSGSphere3D.new()
	glow.radius = 0.55
	glow.radial_segments = 6
	glow.rings = 4
	glow.name = "StarGlow"

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.3)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.7, 0.2)
	glow_mat.emission_energy_multiplier = 3.0
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material = glow_mat
	star.add_child(glow)

	return star


func _spawn_hit_sparks(pos: Vector3) -> void:
	var sparks := CSGSphere3D.new()
	sparks.radius = 0.3
	sparks.radial_segments = 6
	sparks.rings = 4
	sparks.name = "StarSparks"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sparks.material = mat

	get_tree().current_scene.add_child(sparks)
	sparks.global_position = pos

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(sparks, "radius", 0.8, 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.set_parallel(false)
	tw.tween_callback(sparks.queue_free)


func _despawn_star(star: Node3D) -> void:
	if not is_instance_valid(star):
		return

	# Quick fade-out
	var tw := get_tree().create_tween()
	tw.tween_property(star, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(star.queue_free)
