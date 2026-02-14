extends AbilityBase
## Hellfire Nova -- periodically creates an expanding ring of fire around
## the player that damages all enemies in its radius.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 15.0
var nova_radius: float = 6.0
var cooldown: float = 4.0

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = cooldown * 0.3  # first nova triggers relatively quickly


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
		_fire_nova()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 15.0 * (1.0 + (level - 1) * 0.15)
	nova_radius = 6.0 + level
	cooldown = maxf(4.0 - level * 0.3, 1.5)


func _fire_nova() -> void:
	var origin := player.global_position
	var damage := get_scaled_damage(base_damage)

	# Damage all enemies in radius
	for enemy in _get_enemies_in_range(origin, nova_radius):
		_deal_damage(enemy, damage)

	# Expanding ring visual
	_spawn_nova_visual(origin)


func _spawn_nova_visual(origin: Vector3) -> void:
	# Use a CSGTorus3D as the fire ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.3
	ring.outer_radius = 0.6
	ring.sides = 16
	ring.ring_sides = 6
	ring.name = "FireNova"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	get_tree().current_scene.add_child(ring)
	ring.global_position = origin + Vector3.UP * 0.2
	ring.rotation_degrees.x = 90.0  # lay flat

	# Expand and fade
	var target_inner := nova_radius * 0.8
	var target_outer := nova_radius
	var duration := 0.45

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "inner_radius", target_inner, duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "outer_radius", target_outer, duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration * 1.2).set_ease(Tween.EASE_IN).set_delay(duration * 0.3)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)

	# Inner glow sphere
	var glow := CSGSphere3D.new()
	glow.radius = 0.5
	glow.radial_segments = 8
	glow.rings = 4
	glow.name = "NovaGlow"

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.6)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.4, 0.0)
	glow_mat.emission_energy_multiplier = 4.0
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material = glow_mat

	get_tree().current_scene.add_child(glow)
	glow.global_position = origin + Vector3.UP * 0.3

	var tw2 := get_tree().create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(glow, "radius", nova_radius * 0.3, duration * 0.5)
	tw2.tween_property(glow_mat, "albedo_color:a", 0.0, duration * 0.7)
	tw2.set_parallel(false)
	tw2.tween_callback(glow.queue_free)
