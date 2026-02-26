extends AbilityBase
## Electric Burst -- emits a burst of lightning from the player that chains
## between nearby enemies, dealing damage over a short period.
## Recharges after 3 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 18.0
var chain_count: int = 6
var chain_range: float = 8.0
var burst_radius: float = 12.0
var chain_interval: float = 0.15  # seconds between each chain jump
var cooldown: float = 180.0       # 3 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 5.0


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
		var enemies := _get_enemies_in_range(player.global_position, burst_radius)
		if enemies.size() >= 2:
			_cooldown_timer = cooldown
			_fire_burst(enemies)
		else:
			_cooldown_timer = 2.0


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 18.0 * (1.0 + (level - 1) * 0.2)
	chain_count = 6 + level * 2
	chain_range = 8.0 + level * 1.0
	burst_radius = 12.0 + level * 1.0
	cooldown = maxf(180.0 - level * 12.0, 90.0)


func _fire_burst(nearby_enemies: Array[Node3D]) -> void:
	var origin := player.global_position + Vector3.UP * 1.0
	var damage := get_scaled_damage(base_damage)

	# Initial burst VFX at player
	_spawn_burst_origin_vfx(origin)

	# Start chain from player to nearest enemy, then chain outward
	var sorted := nearby_enemies.duplicate()
	sorted.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)

	# Build chain path
	var chain_targets: Array[Node3D] = []
	var hit_set: Dictionary = {}

	for enemy in sorted:
		if chain_targets.size() >= chain_count:
			break
		if not is_instance_valid(enemy):
			continue
		chain_targets.append(enemy)
		hit_set[enemy.get_instance_id()] = true

	# If we haven't filled the chain, try chaining from the last hit to other enemies
	if chain_targets.size() < chain_count and not chain_targets.is_empty():
		var last_pos: Vector3 = chain_targets.back().global_position
		for enemy in _get_enemies():
			if chain_targets.size() >= chain_count:
				break
			if hit_set.has(enemy.get_instance_id()):
				continue
			if enemy.global_position.distance_to(last_pos) <= chain_range:
				chain_targets.append(enemy)
				hit_set[enemy.get_instance_id()] = true
				last_pos = enemy.global_position

	# Animate the chain sequentially using tweens
	var prev_pos := origin
	for i in chain_targets.size():
		var target := chain_targets[i]
		var delay := chain_interval * i

		# Schedule damage and visual for each chain link
		var tw := get_tree().create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void:
			if not is_instance_valid(target):
				return
			# Each chain does slightly less damage
			var chain_damage := damage * pow(0.85, i)
			_deal_damage(target, chain_damage)

			# Draw lightning bolt from previous position
			_draw_lightning_bolt(prev_pos, target.global_position + Vector3.UP * 1.0)
			_spawn_chain_hit_vfx(target.global_position + Vector3.UP * 1.0)
		)

		if is_instance_valid(target):
			prev_pos = target.global_position + Vector3.UP * 1.0


func _spawn_burst_origin_vfx(origin: Vector3) -> void:
	# Electric sphere at player
	var sphere := CSGSphere3D.new()
	sphere.radius = 0.5
	sphere.radial_segments = 8
	sphere.rings = 6
	sphere.name = "ElectricBurstOrigin"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat

	get_tree().current_scene.add_child(sphere)
	sphere.global_position = origin

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(sphere, "radius", 2.0, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.set_parallel(false)
	tw.tween_callback(sphere.queue_free)


func _draw_lightning_bolt(from: Vector3, to: Vector3) -> void:
	var midpoint := (from + to) * 0.5
	var dist := from.distance_to(to)

	# Main bolt
	var bolt := CSGBox3D.new()
	bolt.size = Vector3(0.08, 0.08, dist)
	bolt.name = "ElectricBolt"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.7, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt.material = mat

	get_tree().current_scene.add_child(bolt)
	bolt.global_position = midpoint
	if dist > 0.01:
		bolt.look_at(to, Vector3.UP)

	# Jagged secondary bolt
	var jag := CSGBox3D.new()
	jag.size = Vector3(0.05, 0.05, dist * 0.5)
	jag.position = Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), 0.0)
	jag.material = mat
	bolt.add_child(jag)

	# Fade out
	var tw := get_tree().create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(bolt.queue_free)


func _spawn_chain_hit_vfx(pos: Vector3) -> void:
	var spark := CSGSphere3D.new()
	spark.radius = 0.2
	spark.radial_segments = 6
	spark.rings = 4
	spark.name = "ElectricSpark"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.7, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.8, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material = mat

	get_tree().current_scene.add_child(spark)
	spark.global_position = pos

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(spark, "radius", 0.6, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.set_parallel(false)
	tw.tween_callback(spark.queue_free)
