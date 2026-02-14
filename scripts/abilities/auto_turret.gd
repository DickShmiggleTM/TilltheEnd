extends AbilityBase
## Sentinel Turret -- a small floating turret that auto-targets and shoots
## the nearest enemy within range. Follows the player with a slight offset.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 5.0
var fire_rate: float = 0.3       # seconds between shots (gets faster with level)
var attack_range: float = 12.0

# ── Internal ──────────────────────────────────────────────────────────
var _fire_timer: float = 0.0
var _turret_body: CSGBox3D = null
var _turret_barrel: CSGBox3D = null
var _turret_material: StandardMaterial3D = null
var _current_target: Node3D = null
var _offset := Vector3(1.5, 1.8, 0.0)  # hover position relative to player


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_build_turret_visual()


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if _turret_body:
		_turret_body.queue_free()
		_turret_body = null


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null or _turret_body == null:
		return

	# Follow the player with smooth interpolation
	var target_pos := player.global_position + _offset
	_turret_body.global_position = _turret_body.global_position.lerp(target_pos, 8.0 * delta)

	# Spin idle animation
	_turret_body.rotation.y += delta * 1.5

	# Targeting and firing
	_fire_timer -= delta
	_current_target = _get_nearest_enemy(_turret_body.global_position, attack_range)

	if _current_target and is_instance_valid(_current_target):
		# Face target
		var dir := (_current_target.global_position - _turret_body.global_position).normalized()
		if dir.length() > 0.01:
			_turret_body.look_at(_turret_body.global_position + dir, Vector3.UP)

		# Fire
		if _fire_timer <= 0.0:
			_fire_timer = fire_rate
			_fire_at_target(_current_target)


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 5.0 * level
	fire_rate = 0.3 / (1.0 + level * 0.1)
	attack_range = 12.0 + level * 2.0


func _build_turret_visual() -> void:
	if _turret_body:
		_turret_body.queue_free()

	# Main body
	_turret_body = CSGBox3D.new()
	_turret_body.size = Vector3(0.4, 0.3, 0.4)
	_turret_body.name = "TurretBody"

	_turret_material = StandardMaterial3D.new()
	_turret_material.albedo_color = Color(0.15, 0.5, 0.9)
	_turret_material.emission_enabled = true
	_turret_material.emission = Color(0.2, 0.6, 1.0)
	_turret_material.emission_energy_multiplier = 2.0
	_turret_body.material = _turret_material

	# Barrel
	_turret_barrel = CSGBox3D.new()
	_turret_barrel.size = Vector3(0.1, 0.1, 0.5)
	_turret_barrel.position = Vector3(0.0, 0.0, 0.35)
	_turret_barrel.name = "Barrel"

	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.3, 0.3, 0.4)
	_turret_barrel.material = barrel_mat
	_turret_body.add_child(_turret_barrel)

	# Place in world (not as child of player so it doesn't inherit rotation)
	get_tree().current_scene.add_child.call_deferred(_turret_body)
	if player:
		_turret_body.global_position = player.global_position + _offset


func _fire_at_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	var damage := get_scaled_damage(base_damage)

	# --- Hitscan: instant hit with a brief visual tracer ---
	_deal_damage(target, damage)
	_spawn_tracer(target.global_position)


func _spawn_tracer(target_pos: Vector3) -> void:
	if _turret_body == null:
		return

	# Quick line visual using a thin CSGBox stretched between turret and target
	var origin := _turret_body.global_position
	var midpoint := (origin + target_pos) * 0.5
	var dist := origin.distance_to(target_pos)

	var tracer := CSGBox3D.new()
	tracer.size = Vector3(0.03, 0.03, dist)
	tracer.name = "Tracer"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.8
	tracer.material = mat

	get_tree().current_scene.add_child(tracer)
	tracer.global_position = midpoint
	tracer.look_at(target_pos, Vector3.UP)

	# Auto-remove after a brief flash
	var tw := get_tree().create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(tracer.queue_free)
