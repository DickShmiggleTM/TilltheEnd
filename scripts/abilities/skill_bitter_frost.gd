extends AbilityBase
## Bitter Frost -- freezes all enemies within sight range for 20 seconds,
## immobilizing them completely. Frozen enemies take 20% more damage.
## Recharges after 2 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var freeze_duration: float = 20.0
var freeze_range: float = 20.0
var damage_amp: float = 0.20  # frozen enemies take 20% more damage
var cooldown: float = 120.0   # 2 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0
var _frozen_enemies: Dictionary = {}  # enemy_id -> { enemy, original_speed, timer, vfx }


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 5.0


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	_unfreeze_all()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Update frozen enemy timers
	var expired: Array = []
	for eid in _frozen_enemies.keys():
		var data: Dictionary = _frozen_enemies[eid]
		var enemy: Node3D = data.get("enemy")
		if enemy == null or not is_instance_valid(enemy):
			expired.append(eid)
			continue

		data["timer"] -= delta
		if data["timer"] <= 0.0:
			_unfreeze_enemy(eid, data)
			expired.append(eid)

	for eid in expired:
		_frozen_enemies.erase(eid)

	# Cooldown for next freeze
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		var enemies := _get_enemies_in_range(player.global_position, freeze_range)
		if enemies.size() >= 2:
			_cooldown_timer = cooldown
			_freeze_enemies(enemies)
		else:
			_cooldown_timer = 2.0


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	freeze_duration = 20.0 + level * 3.0
	freeze_range = 20.0 + level * 2.0
	damage_amp = 0.20 + (level - 1) * 0.05
	cooldown = maxf(120.0 - level * 8.0, 60.0)


func _freeze_enemies(enemies: Array[Node3D]) -> void:
	# Central frost burst VFX
	_spawn_frost_burst(player.global_position)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var eid := enemy.get_instance_id()
		if _frozen_enemies.has(eid):
			continue  # already frozen

		# Store original speed and stop the enemy
		var original_speed: float = 0.0
		if enemy.has_method("get_speed"):
			original_speed = enemy.get_speed()
		if enemy.has_method("set_speed"):
			enemy.set_speed(0.0)

		# Frost VFX on enemy
		var frost_vfx := _create_frost_vfx(enemy)

		_frozen_enemies[eid] = {
			"enemy": enemy,
			"original_speed": original_speed,
			"timer": freeze_duration,
			"vfx": frost_vfx,
		}


func _unfreeze_enemy(eid: int, data: Dictionary) -> void:
	var enemy: Node3D = data.get("enemy")
	if enemy != null and is_instance_valid(enemy):
		if enemy.has_method("set_speed"):
			enemy.set_speed(data.get("original_speed", 0.0))

	var vfx: Node3D = data.get("vfx")
	if vfx != null and is_instance_valid(vfx):
		vfx.queue_free()


func _unfreeze_all() -> void:
	for eid in _frozen_enemies.keys():
		_unfreeze_enemy(eid, _frozen_enemies[eid])
	_frozen_enemies.clear()


func _create_frost_vfx(enemy: Node3D) -> Node3D:
	var frost := CSGSphere3D.new()
	frost.radius = 0.8
	frost.radial_segments = 6
	frost.rings = 4
	frost.name = "FrostIce"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frost.material = mat

	enemy.add_child(frost)
	frost.position = Vector3.UP * 1.0

	# Gentle pulsing
	var tw := get_tree().create_tween()
	tw.set_loops()
	tw.tween_property(mat, "emission_energy_multiplier", 4.0, 1.0)
	tw.tween_property(mat, "emission_energy_multiplier", 2.0, 1.0)

	return frost


func _spawn_frost_burst(origin: Vector3) -> void:
	var burst := CSGSphere3D.new()
	burst.radius = 1.0
	burst.radial_segments = 10
	burst.rings = 6
	burst.name = "FrostBurst"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.8, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst.material = mat

	get_tree().current_scene.add_child(burst)
	burst.global_position = origin + Vector3.UP * 1.0

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "radius", freeze_range * 0.4, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.set_parallel(false)
	tw.tween_callback(burst.queue_free)
