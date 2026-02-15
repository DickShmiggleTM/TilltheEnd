extends AbilityBase
## Sage's Eye -- reveals hidden secrets by creating a detection area around
## the player. When nodes in the "secrets" group are nearby, visual
## indicators are spawned to guide the player.

# ── Tuning ────────────────────────────────────────────────────────────
var detection_radius: float = 10.0
const SCAN_INTERVAL := 0.5

# ── Internal ──────────────────────────────────────────────────────────
var _detection_area: Area3D = null
var _scan_timer: float = 0.0
var _active_indicators: Dictionary = {}  # secret instance_id -> MeshInstance3D


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_build_detection_area()


func deactivate() -> void:
	_clear_indicators()
	if _detection_area and is_instance_valid(_detection_area):
		_detection_area.queue_free()
		_detection_area = null


func _on_upgrade() -> void:
	_apply_level_stats()
	# Update detection area radius
	if _detection_area and is_instance_valid(_detection_area):
		var shape_node: CollisionShape3D = _detection_area.get_child(0)
		if shape_node and shape_node.shape is SphereShape3D:
			(shape_node.shape as SphereShape3D).radius = detection_radius


# ── Process ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Keep detection area on the player
	if _detection_area:
		_detection_area.global_position = player.global_position

	# Periodic scan for secrets
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_scan_for_secrets()


# ── Private ──────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	detection_radius = 10.0 + (level - 1) * 3.0


func _build_detection_area() -> void:
	_detection_area = _create_damage_area(detection_radius)
	_detection_area.name = "SagesEyeArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 0
	# We use manual distance checks against the "secrets" group instead of
	# collision, so the area serves as a positional anchor only.
	add_child(_detection_area)


func _scan_for_secrets() -> void:
	var origin := player.global_position
	var r_sq := detection_radius * detection_radius

	# Track which secrets are still in range
	var in_range: Dictionary = {}

	for secret in get_tree().get_nodes_in_group("secrets"):
		if not secret is Node3D or not is_instance_valid(secret):
			continue
		var sid := secret.get_instance_id()
		var dist_sq := (secret as Node3D).global_position.distance_squared_to(origin)
		if dist_sq <= r_sq:
			in_range[sid] = secret
			if not _active_indicators.has(sid):
				_spawn_indicator(secret as Node3D, sid)

	# Remove indicators for secrets that left range
	var to_remove: Array = []
	for sid in _active_indicators:
		if not in_range.has(sid):
			var indicator: Node3D = _active_indicators[sid]
			if is_instance_valid(indicator):
				indicator.queue_free()
			to_remove.append(sid)
	for sid in to_remove:
		_active_indicators.erase(sid)


func _spawn_indicator(secret: Node3D, sid: int) -> void:
	var indicator := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	indicator.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator.material_override = mat

	get_tree().current_scene.add_child(indicator)
	indicator.global_position = secret.global_position + Vector3.UP * 2.0

	# Gentle bobbing animation
	var tw := get_tree().create_tween().set_loops()
	tw.tween_property(indicator, "position:y", indicator.position.y + 0.3, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(indicator, "position:y", indicator.position.y, 0.8).set_trans(Tween.TRANS_SINE)

	_active_indicators[sid] = indicator


func _clear_indicators() -> void:
	for sid in _active_indicators:
		var indicator: Node3D = _active_indicators[sid]
		if is_instance_valid(indicator):
			indicator.queue_free()
	_active_indicators.clear()
