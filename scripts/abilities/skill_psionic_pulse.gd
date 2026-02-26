extends AbilityBase
## Psionic Pulse -- blasts a telekinetic force that knocks back all enemies
## within a 10-meter area around the player and deals minor damage.
## Recharges every 4 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 15.0
var pulse_radius: float = 10.0
var knockback_force: float = 20.0
var cooldown: float = 240.0  # 4 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 5.0  # initial delay


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
		var enemies := _get_enemies_in_range(player.global_position, pulse_radius)
		if enemies.size() >= 3:
			_cooldown_timer = cooldown
			_fire_pulse()
		else:
			_cooldown_timer = 2.0  # re-check when more enemies are around


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 15.0 * (1.0 + (level - 1) * 0.25)
	pulse_radius = 10.0 + level * 1.0
	knockback_force = 20.0 + level * 3.0
	cooldown = maxf(240.0 - level * 15.0, 120.0)


func _fire_pulse() -> void:
	var origin := player.global_position
	var damage := get_scaled_damage(base_damage)
	var enemies := _get_enemies_in_range(origin, pulse_radius)

	for enemy in enemies:
		# Deal damage
		_deal_damage(enemy, damage)

		# Apply knockback
		if is_instance_valid(enemy):
			var dir := (enemy.global_position - origin).normalized()
			if dir.length_squared() < 0.01:
				dir = Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)).normalized()
			dir.y = 0.3  # slight upward push
			dir = dir.normalized()

			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(dir * knockback_force)
			else:
				# Tween-based fallback knockback
				var push_target := enemy.global_position + dir * knockback_force * 0.3
				var tw := get_tree().create_tween()
				tw.tween_property(enemy, "global_position", push_target, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_spawn_pulse_vfx(origin)


func _spawn_pulse_vfx(origin: Vector3) -> void:
	# Expanding shockwave ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 1.0
	ring.sides = 20
	ring.ring_sides = 6
	ring.name = "PsionicShockwave"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.3, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.4, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	ring.rotation_degrees.x = 90.0

	get_tree().current_scene.add_child(ring)
	ring.global_position = origin + Vector3.UP * 0.5

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "inner_radius", pulse_radius * 0.8, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "outer_radius", pulse_radius, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)

	# Central burst sphere
	var burst := CSGSphere3D.new()
	burst.radius = 0.5
	burst.radial_segments = 10
	burst.rings = 6
	burst.name = "PsionicBurst"

	var burst_mat := StandardMaterial3D.new()
	burst_mat.albedo_color = Color(0.8, 0.5, 1.0, 0.7)
	burst_mat.emission_enabled = true
	burst_mat.emission = Color(0.7, 0.3, 1.0)
	burst_mat.emission_energy_multiplier = 6.0
	burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst.material = burst_mat

	get_tree().current_scene.add_child(burst)
	burst.global_position = origin + Vector3.UP * 1.0

	var tw2 := get_tree().create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(burst, "radius", 3.0, 0.3).set_ease(Tween.EASE_OUT)
	tw2.tween_property(burst_mat, "albedo_color:a", 0.0, 0.4)
	tw2.set_parallel(false)
	tw2.tween_callback(burst.queue_free)
