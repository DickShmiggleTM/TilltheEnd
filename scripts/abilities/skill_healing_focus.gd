extends AbilityBase
## Healing Focus -- when the player is standing still, regenerates health
## gradually for 15 seconds. The healing effect cancels if the player moves.
## Recharges after 45 seconds.

# ── Tuning ────────────────────────────────────────────────────────────
var heal_per_second: float = 4.0
var heal_duration: float = 15.0
var cooldown: float = 45.0
var movement_threshold: float = 0.1  # how still the player must be

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0
var _is_healing: bool = false
var _heal_timer: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _heal_vfx: Node3D = null


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 5.0
	_is_healing = false


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	_stop_healing()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	if _is_healing:
		_process_healing(delta)
	else:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			# Check if player is roughly still
			var current_pos := player.global_position
			var moved := current_pos.distance_to(_last_player_pos)
			_last_player_pos = current_pos

			if moved < movement_threshold:
				# Check if health is not full
				var current_hp: float = GameManager.get_trait("max_health")
				var needs_heal := GameManager.player_stats.get("current_health", current_hp) < current_hp
				if needs_heal:
					_start_healing()
					_cooldown_timer = cooldown
			else:
				_cooldown_timer = 0.5  # re-check soon


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	heal_per_second = 4.0 + level * 1.5
	heal_duration = 15.0 + level * 2.0
	cooldown = maxf(45.0 - level * 3.0, 25.0)


func _start_healing() -> void:
	_is_healing = true
	_heal_timer = heal_duration
	_last_player_pos = player.global_position

	# Spawn healing VFX
	_heal_vfx = _create_heal_vfx()


func _stop_healing() -> void:
	_is_healing = false
	_heal_timer = 0.0
	if _heal_vfx and is_instance_valid(_heal_vfx):
		_heal_vfx.queue_free()
		_heal_vfx = null


func _process_healing(delta: float) -> void:
	_heal_timer -= delta

	# Check if player moved
	var current_pos := player.global_position
	var moved := current_pos.distance_to(_last_player_pos)

	if moved > movement_threshold or _heal_timer <= 0.0:
		_stop_healing()
		return

	# Apply healing
	var heal_amount := heal_per_second * delta
	if GameManager.player_stats.has("current_health"):
		var max_hp: float = GameManager.get_trait("max_health")
		GameManager.player_stats["current_health"] = minf(
			GameManager.player_stats["current_health"] + heal_amount,
			max_hp
		)
		EventBus.player_healed.emit(heal_amount)

	# Update VFX position
	if _heal_vfx and is_instance_valid(_heal_vfx):
		_heal_vfx.global_position = player.global_position + Vector3.UP * 0.5


func _create_heal_vfx() -> Node3D:
	var container := Node3D.new()
	container.name = "HealingFocus"

	# Glowing green aura ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.6
	ring.outer_radius = 1.0
	ring.sides = 12
	ring.ring_sides = 4
	ring.name = "HealRing"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	ring.rotation_degrees.x = 90.0
	container.add_child(ring)

	# Upward-flowing particles (small spheres)
	for i in 4:
		var particle := CSGSphere3D.new()
		particle.radius = 0.08
		particle.radial_segments = 4
		particle.rings = 3
		particle.name = "HealParticle_%d" % i

		var p_mat := StandardMaterial3D.new()
		p_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.7)
		p_mat.emission_enabled = true
		p_mat.emission = Color(0.2, 0.9, 0.4)
		p_mat.emission_energy_multiplier = 4.0
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle.material = p_mat

		var angle := TAU / 4.0 * i
		particle.position = Vector3(cos(angle) * 0.7, 0.0, sin(angle) * 0.7)
		container.add_child(particle)

		# Animate particles floating upward in a loop
		var tw := get_tree().create_tween()
		tw.set_loops()
		tw.tween_property(particle, "position:y", 2.0, 1.5 + i * 0.2)
		tw.tween_property(p_mat, "albedo_color:a", 0.0, 0.3)
		tw.tween_callback(func() -> void:
			particle.position.y = 0.0
			p_mat.albedo_color.a = 0.7
		)

	get_tree().current_scene.add_child(container)
	container.global_position = player.global_position + Vector3.UP * 0.5

	# Pulsing ring animation
	var ring_tw := get_tree().create_tween()
	ring_tw.set_loops()
	ring_tw.tween_property(mat, "emission_energy_multiplier", 5.0, 0.8)
	ring_tw.tween_property(mat, "emission_energy_multiplier", 3.0, 0.8)

	return container
