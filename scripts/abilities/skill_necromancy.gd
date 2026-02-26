extends AbilityBase
## Necromancy -- resurrects the most recently killed enemy to fight as an
## ally for a duration. Recharges after the player kills 100 enemies.
## The resurrected minion attacks nearby enemies and despawns when its
## duration expires or it takes enough damage.

# ── Tuning ────────────────────────────────────────────────────────────
var kills_required: int = 100
var minion_duration: float = 30.0
var minion_damage: float = 10.0
var minion_health: float = 80.0
var minion_attack_interval: float = 1.5
var minion_range: float = 8.0

# ── Internal ──────────────────────────────────────────────────────────
var _kill_count: int = 0
var _last_killed_pos: Vector3 = Vector3.ZERO
var _active_minion: Node3D = null


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_kill_count = 0
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)
	if _active_minion and is_instance_valid(_active_minion):
		_active_minion.queue_free()
		_active_minion = null


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	kills_required = maxi(100 - (level - 1) * 10, 50)
	minion_duration = 30.0 + level * 5.0
	minion_damage = 10.0 * (1.0 + (level - 1) * 0.3)
	minion_health = 80.0 + level * 20.0
	minion_attack_interval = maxf(1.5 - level * 0.1, 0.8)


func _on_enemy_killed(enemy: Node3D, position: Vector3) -> void:
	_last_killed_pos = position
	_kill_count += 1

	if _kill_count >= kills_required:
		_kill_count = 0
		# Only summon if no active minion
		if _active_minion == null or not is_instance_valid(_active_minion):
			_active_minion = null
			_summon_minion(position)


func _summon_minion(pos: Vector3) -> void:
	var minion := Node3D.new()
	minion.name = "NecroMinion"

	# Visual: ghostly humanoid shape
	var body := CSGCylinder3D.new()
	body.radius = 0.45
	body.height = 1.8
	body.sides = 8
	body.name = "MinionBody"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.material = mat
	body.position = Vector3.UP * 0.9
	minion.add_child(body)

	# Skull head
	var head := CSGSphere3D.new()
	head.radius = 0.3
	head.radial_segments = 6
	head.rings = 4
	head.name = "MinionHead"

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.8, 0.9, 0.8, 0.7)
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.2, 0.8, 0.2)
	head_mat.emission_energy_multiplier = 3.0
	head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	head.material = head_mat
	head.position = Vector3.UP * 2.1
	minion.add_child(head)

	# Eye glow spheres
	for offset in [Vector3(-0.1, 2.15, 0.2), Vector3(0.1, 2.15, 0.2)]:
		var eye := CSGSphere3D.new()
		eye.radius = 0.06
		eye.radial_segments = 4
		eye.rings = 3

		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.0, 1.0, 0.0)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(0.0, 1.0, 0.0)
		eye_mat.emission_energy_multiplier = 8.0
		eye.material = eye_mat
		eye.position = offset
		minion.add_child(eye)

	get_tree().current_scene.add_child(minion)
	minion.global_position = pos
	_active_minion = minion

	# Summon VFX
	_spawn_summon_vfx(pos)

	# Minion AI: attack nearby enemies periodically
	var hp := minion_health
	var time_left := minion_duration
	var attack_timer := 0.0
	var dmg := get_scaled_damage(minion_damage)
	var atk_interval := minion_attack_interval
	var atk_range := minion_range
	var ability_ref := self

	# Use a process-like tween loop for minion behavior
	var loop_tw := get_tree().create_tween()
	loop_tw.set_loops()
	loop_tw.tween_callback(func() -> void:
		if not is_instance_valid(minion):
			loop_tw.kill()
			return

		var dt := get_process_delta_time()
		time_left -= dt
		attack_timer -= dt

		# Despawn when time is up
		if time_left <= 0.0:
			_despawn_minion(minion)
			loop_tw.kill()
			return

		# Fade visual as time runs low
		if time_left < 5.0:
			mat.albedo_color.a = 0.3 + 0.3 * abs(sin(time_left * 3.0))

		# Find and move toward nearest enemy
		var enemies := ability_ref._get_enemies_sorted(minion.global_position)
		if enemies.is_empty():
			return

		var target: Node3D = enemies[0]
		if not is_instance_valid(target):
			return

		var dist := minion.global_position.distance_to(target.global_position)

		# Move toward target
		if dist > 2.0:
			var dir := (target.global_position - minion.global_position).normalized()
			dir.y = 0.0
			minion.global_position += dir * 4.0 * dt

		# Attack when in range and timer ready
		if dist <= atk_range and attack_timer <= 0.0:
			attack_timer = atk_interval
			ability_ref._deal_damage(target, dmg)
			_spawn_attack_vfx(minion.global_position, target.global_position)
	).set_delay(0.0)


func _despawn_minion(minion: Node3D) -> void:
	if not is_instance_valid(minion):
		return

	var pos := minion.global_position

	# Fade-out death effect
	var ghost := CSGSphere3D.new()
	ghost.radius = 0.5
	ghost.radial_segments = 8
	ghost.rings = 4
	ghost.name = "MinionDeath"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.6, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material = mat

	get_tree().current_scene.add_child(ghost)
	ghost.global_position = pos + Vector3.UP * 1.0

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "radius", 0.05, 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.set_parallel(false)
	tw.tween_callback(ghost.queue_free)

	minion.queue_free()
	_active_minion = null


func _spawn_summon_vfx(pos: Vector3) -> void:
	# Green pillar of necromantic energy
	var pillar := CSGCylinder3D.new()
	pillar.radius = 0.8
	pillar.height = 6.0
	pillar.sides = 8
	pillar.name = "SummonPillar"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.8, 0.1, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 0.9, 0.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar.material = mat

	get_tree().current_scene.add_child(pillar)
	pillar.global_position = pos + Vector3.UP * 3.0

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(pillar, "radius", 0.1, 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.set_parallel(false)
	tw.tween_callback(pillar.queue_free)


func _spawn_attack_vfx(from_pos: Vector3, to_pos: Vector3) -> void:
	var mid := (from_pos + to_pos) * 0.5
	var dist := from_pos.distance_to(to_pos)

	var bolt := CSGBox3D.new()
	bolt.size = Vector3(0.04, 0.04, dist)
	bolt.name = "NecroAttack"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt.material = mat

	get_tree().current_scene.add_child(bolt)
	bolt.global_position = mid + Vector3.UP * 1.0
	if dist > 0.01:
		bolt.look_at(to_pos + Vector3.UP * 1.0, Vector3.UP)

	var tw := get_tree().create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(bolt.queue_free)
