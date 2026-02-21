extends AbilityBase
## Earth Spikes -- erupts a ring of stone spikes from the ground around the
## player, damaging all enemies standing on top of the spike area.
## Recharges after 20 seconds.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 25.0
var spike_radius: float = 5.0
var spike_count: int = 8
var cooldown: float = 20.0

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
		var enemies := _get_enemies_in_range(player.global_position, spike_radius + 2.0)
		if enemies.size() >= 1:
			_cooldown_timer = cooldown
			_erupt_spikes()
		else:
			_cooldown_timer = 1.0


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 25.0 * (1.0 + (level - 1) * 0.25)
	spike_radius = 5.0 + level * 0.5
	spike_count = 8 + level * 2
	cooldown = maxf(20.0 - level * 1.5, 10.0)


func _erupt_spikes() -> void:
	var origin := player.global_position
	var damage := get_scaled_damage(base_damage)

	# Damage enemies in the spike radius
	for enemy in _get_enemies_in_range(origin, spike_radius):
		_deal_damage(enemy, damage)

	# Spawn spike visuals in a ring pattern
	for i in spike_count:
		var angle := (TAU / spike_count) * i
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * spike_radius * randf_range(0.3, 1.0)
		var spike_pos := origin + offset
		spike_pos.y = origin.y  # ground level

		_spawn_spike(spike_pos, i)

	# Ground crack visual at center
	_spawn_ground_crack(origin)


func _spawn_spike(pos: Vector3, index: int) -> void:
	var spike := CSGCylinder3D.new()
	spike.radius = 0.15 + randf_range(0.0, 0.1)
	spike.height = 0.1  # starts small, grows
	spike.sides = 5     # jagged look
	spike.name = "EarthSpike_%d" % index

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.25, 0.1)
	mat.emission_energy_multiplier = 1.5
	spike.material = mat

	# Slight random tilt for organic look
	spike.rotation_degrees.x = randf_range(-10, 10)
	spike.rotation_degrees.z = randf_range(-10, 10)

	get_tree().current_scene.add_child(spike)
	spike.global_position = pos

	# Animate spike eruption with staggered delay
	var delay := index * 0.02
	var target_height := randf_range(1.5, 3.0)

	var tw := get_tree().create_tween()
	tw.tween_interval(delay)
	# Erupt upward
	tw.tween_property(spike, "height", target_height, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(spike, "global_position:y", pos.y + target_height * 0.5, 0.15).set_ease(Tween.EASE_OUT)
	# Hold briefly
	tw.tween_interval(0.8)
	# Retract
	tw.tween_property(spike, "height", 0.05, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(spike, "global_position:y", pos.y, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(spike.queue_free)


func _spawn_ground_crack(origin: Vector3) -> void:
	var crack := CSGCylinder3D.new()
	crack.radius = 0.5
	crack.height = 0.05
	crack.sides = 8
	crack.name = "GroundCrack"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.3, 0.1, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.25, 0.05)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack.material = mat

	get_tree().current_scene.add_child(crack)
	crack.global_position = origin + Vector3.UP * 0.02

	var tw := get_tree().create_tween()
	tw.tween_property(crack, "radius", spike_radius * 0.8, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(crack.queue_free)
