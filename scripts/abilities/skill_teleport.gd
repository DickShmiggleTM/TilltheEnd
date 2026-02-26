extends AbilityBase
## Teleport -- teleports the player forward in the direction they are facing
## to the furthest safe ground position within range.
## Recharges after 45 seconds.

# ── Tuning ────────────────────────────────────────────────────────────
var teleport_range: float = 12.0
var cooldown: float = 45.0

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


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
		# Only teleport when enemies are nearby (tactical use)
		var nearest := _get_nearest_enemy(player.global_position, 15.0)
		if nearest != null:
			_cooldown_timer = cooldown
			_execute_teleport()
		else:
			_cooldown_timer = 1.0  # check again soon


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	teleport_range = 12.0 + level * 2.0
	cooldown = maxf(45.0 - level * 3.0, 20.0)


func _execute_teleport() -> void:
	var origin := player.global_position
	# Get player facing direction (horizontal only)
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var target_pos := origin + forward * teleport_range
	# Keep on the ground plane
	target_pos.y = origin.y

	# Spawn departure visual
	_spawn_teleport_vfx(origin, Color(0.3, 0.5, 1.0, 0.8))

	# Move player
	player.global_position = target_pos

	# Spawn arrival visual
	_spawn_teleport_vfx(target_pos, Color(0.5, 0.7, 1.0, 0.8))


func _spawn_teleport_vfx(pos: Vector3, color: Color) -> void:
	# Vertical beam of light
	var beam := CSGCylinder3D.new()
	beam.radius = 0.6
	beam.height = 4.0
	beam.sides = 8
	beam.name = "TeleportBeam"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material = mat

	get_tree().current_scene.add_child(beam)
	beam.global_position = pos + Vector3.UP * 2.0

	# Ring at feet
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.4
	ring.outer_radius = 0.8
	ring.sides = 12
	ring.ring_sides = 4
	ring.name = "TeleportRing"
	ring.material = mat
	ring.rotation_degrees.x = 90.0

	get_tree().current_scene.add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.1

	# Fade and expand
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "radius", 0.05, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_property(ring, "outer_radius", 2.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		beam.queue_free()
		ring.queue_free()
	)
