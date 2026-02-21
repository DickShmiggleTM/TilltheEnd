extends AbilityBase
## Bombs -- throws a small bomb at the densest enemy cluster. The bomb
## explodes on impact dealing medium damage in a small area.
## Recharges after 30 seconds.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 30.0
var explosion_radius: float = 2.5
var cooldown: float = 30.0
var throw_speed: float = 18.0
var throw_arc_height: float = 4.0

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 2.0  # small initial delay


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
		_cooldown_timer = cooldown
		_throw_bomb()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 30.0 * (1.0 + (level - 1) * 0.25)
	explosion_radius = 2.5 + level * 0.3
	cooldown = maxf(30.0 - level * 2.0, 15.0)


func _throw_bomb() -> void:
	var target_pos := _find_best_cluster()
	if target_pos == Vector3.ZERO:
		_cooldown_timer = 2.0  # retry soon
		return

	_spawn_bomb(target_pos)


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
			if other.global_position.distance_to(pos) <= explosion_radius * 2.0:
				score += 1
		if score > best_score:
			best_score = score
			best_pos = pos

	return best_pos


func _spawn_bomb(target_pos: Vector3) -> void:
	var bomb := Node3D.new()
	bomb.name = "SkillBomb"

	# Visual: small dark sphere
	var sphere := CSGSphere3D.new()
	sphere.radius = 0.2
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.name = "BombMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	bomb.add_child(sphere)

	# Fuse glow
	var fuse := CSGSphere3D.new()
	fuse.radius = 0.08
	fuse.radial_segments = 4
	fuse.rings = 3
	fuse.name = "Fuse"

	var fuse_mat := StandardMaterial3D.new()
	fuse_mat.albedo_color = Color(1.0, 0.6, 0.0)
	fuse_mat.emission_enabled = true
	fuse_mat.emission = Color(1.0, 0.5, 0.0)
	fuse_mat.emission_energy_multiplier = 5.0
	fuse.material = fuse_mat
	fuse.position = Vector3.UP * 0.2
	bomb.add_child(fuse)

	get_tree().current_scene.add_child(bomb)
	var start_pos := player.global_position + Vector3.UP * 1.2
	bomb.global_position = start_pos

	# Arc trajectory via tween
	var mid_pos := (start_pos + target_pos) * 0.5 + Vector3.UP * throw_arc_height
	var travel_time := start_pos.distance_to(target_pos) / throw_speed

	var tw := get_tree().create_tween()
	# First half: rise to arc peak
	tw.tween_property(bomb, "global_position", mid_pos, travel_time * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Second half: fall to target
	tw.tween_property(bomb, "global_position", target_pos, travel_time * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		_on_bomb_impact(bomb, target_pos)
	)


func _on_bomb_impact(bomb: Node3D, impact_pos: Vector3) -> void:
	if is_instance_valid(bomb):
		bomb.queue_free()

	var damage := get_scaled_damage(base_damage)

	for enemy in _get_enemies_in_range(impact_pos, explosion_radius):
		var dist := enemy.global_position.distance_to(impact_pos)
		var falloff := 1.0 - (dist / explosion_radius) * 0.3
		_deal_damage(enemy, damage * falloff)

	_spawn_explosion(impact_pos)


func _spawn_explosion(pos: Vector3) -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 0.3
	explosion.radial_segments = 8
	explosion.rings = 4
	explosion.name = "BombExplosion"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos + Vector3.UP * 0.3

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(explosion, "radius", explosion_radius * 0.6, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(explosion.queue_free)
