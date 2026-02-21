extends AbilityBase
## Lifting Winds -- launches the player upward with a burst of wind,
## performing an extra midair jump. Useful for repositioning and dodging.
## Recharges every 10 seconds.

# ── Tuning ────────────────────────────────────────────────────────────
var jump_force: float = 10.0
var cooldown: float = 10.0

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0
var _was_airborne: bool = false


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 3.0


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
		# Trigger the wind jump when enemies are nearby (evasive maneuver)
		var nearest := _get_nearest_enemy(player.global_position, 6.0)
		if nearest != null:
			_cooldown_timer = cooldown
			_perform_wind_jump()
		else:
			_cooldown_timer = 1.0


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	jump_force = 10.0 + level * 1.5
	cooldown = maxf(10.0 - level * 0.5, 5.0)


func _perform_wind_jump() -> void:
	var origin := player.global_position

	# Apply upward velocity to player
	if player.has_method("apply_impulse"):
		player.apply_impulse(Vector3.UP * jump_force)
	elif player is CharacterBody3D:
		player.velocity.y = jump_force
	else:
		# Tween fallback: lift the player up and let physics handle descent
		var target := origin + Vector3.UP * (jump_force * 0.3)
		var tw := get_tree().create_tween()
		tw.tween_property(player, "global_position", target, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_spawn_wind_vfx(origin)


func _spawn_wind_vfx(origin: Vector3) -> void:
	# Swirling wind rings rising upward
	for i in 3:
		var ring := CSGTorus3D.new()
		ring.inner_radius = 0.3
		ring.outer_radius = 0.8 + i * 0.3
		ring.sides = 12
		ring.ring_sides = 4
		ring.name = "WindRing_%d" % i

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.9, 1.0, 0.6 - i * 0.15)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.85, 1.0)
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material = mat
		ring.rotation_degrees.x = 90.0

		get_tree().current_scene.add_child(ring)
		ring.global_position = origin + Vector3.UP * (0.2 + i * 0.5)

		var delay := i * 0.08
		var tw := get_tree().create_tween()
		tw.tween_interval(delay)
		tw.set_parallel(true)
		tw.tween_property(ring, "global_position:y", origin.y + 3.0 + i * 1.0, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(ring, "outer_radius", 0.1, 0.5)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

	# Central updraft column
	var column := CSGCylinder3D.new()
	column.radius = 0.5
	column.height = 3.0
	column.sides = 8
	column.name = "WindColumn"

	var col_mat := StandardMaterial3D.new()
	col_mat.albedo_color = Color(0.8, 0.95, 1.0, 0.3)
	col_mat.emission_enabled = true
	col_mat.emission = Color(0.7, 0.9, 1.0)
	col_mat.emission_energy_multiplier = 2.0
	col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	column.material = col_mat

	get_tree().current_scene.add_child(column)
	column.global_position = origin + Vector3.UP * 1.5

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(column, "height", 6.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(col_mat, "albedo_color:a", 0.0, 0.5)
	tw.set_parallel(false)
	tw.tween_callback(column.queue_free)
