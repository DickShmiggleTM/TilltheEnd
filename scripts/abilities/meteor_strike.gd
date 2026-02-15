extends SkillBase
## Meteor Strike -- player-activated skill that drops a meteor on the densest
## cluster of enemies. Massive area damage with screen shake. Recharges over time.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 60.0
var impact_radius: float = 4.0
var fall_height: float = 30.0
var fall_duration: float = 0.6
var cluster_search_radius: float = 6.0


# ── Skill interface ──────────────────────────────────────────────────

func on_activate() -> void:
	_apply_level_stats()


func _on_upgrade() -> void:
	_apply_level_stats()


func _execute() -> void:
	_launch_meteor()


func deactivate() -> void:
	pass


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 60.0 * (1.0 + (level - 1) * 0.25)
	impact_radius = 4.0 + level * 0.5
	cooldown = maxf(15.0 - level * 1.0, 6.0)
	cluster_search_radius = 6.0 + level * 0.5


func _launch_meteor() -> void:
	var target_pos := _find_best_cluster()
	if target_pos == Vector3.ZERO:
		# No enemies found -- refund cooldown partially
		cooldown_remaining = 2.0
		is_ready = false
		return

	_spawn_meteor(target_pos)


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
			if other.global_position.distance_to(pos) <= cluster_search_radius:
				score += 1
		if score > best_score:
			best_score = score
			best_pos = pos

	return best_pos


func _spawn_meteor(target_pos: Vector3) -> void:
	var meteor := Node3D.new()
	meteor.name = "Meteor"

	var sphere := CSGSphere3D.new()
	sphere.radius = 1.0
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.name = "MeteorMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 5.0
	sphere.material = mat
	meteor.add_child(sphere)

	var trail := CSGSphere3D.new()
	trail.radius = 0.6
	trail.radial_segments = 6
	trail.rings = 4
	trail.name = "MeteorTrail"

	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.6)
	trail_mat.emission_enabled = true
	trail_mat.emission = Color(1.0, 0.5, 0.0)
	trail_mat.emission_energy_multiplier = 3.0
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material = trail_mat
	trail.position = Vector3.UP * 1.2
	meteor.add_child(trail)

	var shadow := CSGCylinder3D.new()
	shadow.radius = impact_radius * 0.5
	shadow.height = 0.05
	shadow.sides = 16
	shadow.name = "TargetIndicator"

	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(1.0, 0.2, 0.0, 0.4)
	shadow_mat.emission_enabled = true
	shadow_mat.emission = Color(1.0, 0.2, 0.0)
	shadow_mat.emission_energy_multiplier = 2.0
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material = shadow_mat

	get_tree().current_scene.add_child(shadow)
	shadow.global_position = Vector3(target_pos.x, 0.05, target_pos.z)

	var shadow_tw := get_tree().create_tween()
	shadow_tw.tween_property(shadow, "radius", impact_radius, fall_duration * 0.8).set_ease(Tween.EASE_OUT)
	shadow_tw.tween_property(shadow_mat, "albedo_color:a", 0.0, 0.2)
	shadow_tw.tween_callback(shadow.queue_free)

	get_tree().current_scene.add_child(meteor)
	meteor.global_position = target_pos + Vector3.UP * fall_height

	var tw := get_tree().create_tween()
	tw.tween_property(meteor, "global_position", target_pos, fall_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		_on_meteor_impact(meteor, target_pos)
	)


func _on_meteor_impact(meteor: Node3D, impact_pos: Vector3) -> void:
	if is_instance_valid(meteor):
		meteor.queue_free()

	var damage := get_scaled_damage(base_damage)

	for enemy in _get_enemies_in_range(impact_pos, impact_radius):
		var dist := enemy.global_position.distance_to(impact_pos)
		var falloff := 1.0 - (dist / impact_radius) * 0.4
		_deal_damage(enemy, damage * falloff)

	_spawn_impact_visual(impact_pos)
	_apply_screen_shake()


func _spawn_impact_visual(pos: Vector3) -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 1.0
	explosion.radial_segments = 10
	explosion.rings = 6
	explosion.name = "MeteorExplosion"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.0)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos + Vector3.UP * 0.5

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(explosion, "radius", impact_radius * 0.7, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(explosion.queue_free)

	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 1.0
	ring.sides = 16
	ring.ring_sides = 4
	ring.name = "Shockwave"

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.7)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.0)
	ring_mat.emission_energy_multiplier = 4.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = ring_mat
	ring.rotation_degrees.x = 90.0

	get_tree().current_scene.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.2

	var tw2 := get_tree().create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring, "inner_radius", impact_radius * 0.8, 0.4).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring, "outer_radius", impact_radius * 1.0, 0.4).set_ease(Tween.EASE_OUT)
	tw2.tween_property(ring_mat, "albedo_color:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw2.set_parallel(false)
	tw2.tween_callback(ring.queue_free)


func _apply_screen_shake() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var original_pos := camera.position
	var shake_intensity := 0.3
	var shake_duration := 0.3

	var tw := get_tree().create_tween()
	var steps := 8
	for i in steps:
		var offset := Vector3(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity),
			0.0
		)
		offset *= 1.0 - (float(i) / steps)
		tw.tween_property(camera, "position", original_pos + offset, shake_duration / steps)
	tw.tween_property(camera, "position", original_pos, shake_duration / steps)
