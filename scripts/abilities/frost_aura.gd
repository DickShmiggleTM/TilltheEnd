extends AbilityBase
## Frost Aura -- passive aura that slows all enemies within radius and
## amplifies damage they take from all sources.

# ── Tuning ────────────────────────────────────────────────────────────
var slow_amount: float = 0.3      # 0-1 fraction of speed reduction
var aura_radius: float = 5.0
var damage_amp: float = 1.2       # damage multiplier applied to affected enemies

# ── Internal ──────────────────────────────────────────────────────────
var _aura_area: Area3D = null
var _aura_visual: CSGTorus3D = null
var _affected_enemies: Dictionary = {}  # instance_id -> original_speed (or null if unknown)
var _tick_timer: float = 0.0
const TICK_INTERVAL := 0.25  # how often we refresh slow status


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_build_aura()


func _on_upgrade() -> void:
	_apply_level_stats()
	_rebuild_aura()


func deactivate() -> void:
	# Restore all enemy speeds before removing
	_restore_all_enemies()
	if _aura_visual and is_instance_valid(_aura_visual):
		_aura_visual.queue_free()
	if _aura_area and is_instance_valid(_aura_area):
		_aura_area.queue_free()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Follow player
	if _aura_visual:
		_aura_visual.global_position = player.global_position + Vector3.UP * 0.1
	if _aura_area:
		_aura_area.global_position = player.global_position

	# Periodically refresh enemy slow effects
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_refresh_slow_effects()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	slow_amount = 0.3 + level * 0.05
	aura_radius = 5.0 + level * 0.5
	damage_amp = 1.2 + level * 0.05


func _build_aura() -> void:
	# Visual: subtle blue torus lying flat around the player
	_aura_visual = CSGTorus3D.new()
	_aura_visual.inner_radius = aura_radius * 0.85
	_aura_visual.outer_radius = aura_radius
	_aura_visual.sides = 24
	_aura_visual.ring_sides = 4
	_aura_visual.name = "FrostAuraVisual"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.8, 1.0, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_visual.material = mat
	_aura_visual.rotation_degrees.x = 90.0

	get_tree().current_scene.add_child.call_deferred(_aura_visual)

	# Detection area
	_aura_area = _create_damage_area(aura_radius)
	_aura_area.name = "FrostAuraArea"
	# We only need monitoring, not damage layer — but keeping layer 6
	# allows consistency with other abilities.
	add_child(_aura_area)


func _rebuild_aura() -> void:
	if _aura_visual and is_instance_valid(_aura_visual):
		_aura_visual.inner_radius = aura_radius * 0.85
		_aura_visual.outer_radius = aura_radius
	if _aura_area and is_instance_valid(_aura_area):
		var shape_node: CollisionShape3D = _aura_area.get_child(0)
		if shape_node and shape_node.shape is SphereShape3D:
			(shape_node.shape as SphereShape3D).radius = aura_radius


func _refresh_slow_effects() -> void:
	if _aura_area == null:
		return

	var current_in_range: Dictionary = {}

	# Apply slow to enemies inside the aura
	for body in _aura_area.get_overlapping_bodies():
		if not body.is_in_group("enemies") or not is_instance_valid(body):
			continue
		var eid := body.get_instance_id()
		current_in_range[eid] = true

		if not _affected_enemies.has(eid):
			# New enemy entering aura -- slow it
			_apply_slow(body)
			_affected_enemies[eid] = body

		# Apply damage amplification metadata
		if body.has_method("set_damage_multiplier"):
			body.set_damage_multiplier(damage_amp)

	# Restore enemies that left the aura
	var to_remove: Array = []
	for eid in _affected_enemies:
		if not current_in_range.has(eid):
			var enemy = _affected_enemies[eid]
			if is_instance_valid(enemy):
				_remove_slow(enemy)
			to_remove.append(eid)
	for eid in to_remove:
		_affected_enemies.erase(eid)


func _apply_slow(enemy: Node3D) -> void:
	if enemy.has_method("apply_slow"):
		enemy.apply_slow(slow_amount)
	elif "speed_multiplier" in enemy:
		enemy.speed_multiplier = 1.0 - slow_amount
	elif "move_speed" in enemy:
		# Fallback: store original and reduce
		if not enemy.has_meta("frost_original_speed"):
			enemy.set_meta("frost_original_speed", enemy.move_speed)
		enemy.move_speed = enemy.get_meta("frost_original_speed") * (1.0 - slow_amount)


func _remove_slow(enemy: Node3D) -> void:
	if enemy.has_method("remove_slow"):
		enemy.remove_slow()
	elif "speed_multiplier" in enemy:
		enemy.speed_multiplier = 1.0
	elif "move_speed" in enemy and enemy.has_meta("frost_original_speed"):
		enemy.move_speed = enemy.get_meta("frost_original_speed")
		enemy.remove_meta("frost_original_speed")

	if enemy.has_method("set_damage_multiplier"):
		enemy.set_damage_multiplier(1.0)


func _restore_all_enemies() -> void:
	for eid in _affected_enemies:
		var enemy = _affected_enemies[eid]
		if is_instance_valid(enemy):
			_remove_slow(enemy)
	_affected_enemies.clear()
