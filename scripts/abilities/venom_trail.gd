extends AbilityBase
## Venom Trail -- leaves poisonous damage zones behind the player as they
## move. Each zone persists for a set duration and damages enemies standing
## in it every second.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 3.0       # damage per second
var zone_duration: float = 4.0
var zone_width: float = 1.5        # radius of each zone
var drop_interval: float = 0.5     # seconds between zone drops
var min_move_speed: float = 0.5    # player must be moving faster than this

# ── Internal ──────────────────────────────────────────────────────────
var _drop_timer: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _active_zones: Array[Dictionary] = []  # { node, timer, area }


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	if player:
		_last_player_pos = player.global_position


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	for zone_data in _active_zones:
		if is_instance_valid(zone_data["node"]):
			zone_data["node"].queue_free()
	_active_zones.clear()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Determine movement speed
	var current_pos := player.global_position
	var move_dist := current_pos.distance_to(_last_player_pos)
	var move_speed := move_dist / maxf(delta, 0.001)
	_last_player_pos = current_pos

	# Drop zones while moving
	_drop_timer -= delta
	if move_speed > min_move_speed and _drop_timer <= 0.0:
		_drop_timer = drop_interval
		_spawn_zone(current_pos)

	# Tick zone lifetimes and damage
	_tick_zones(delta)


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 3.0 * (1.0 + (level - 1) * 0.25)
	zone_duration = 4.0 + level * 0.5
	zone_width = 1.5 + level * 0.3


func _spawn_zone(pos: Vector3) -> void:
	var zone := Node3D.new()
	zone.name = "VenomZone"

	# Visual: flat green disc on the ground
	var mesh := CSGCylinder3D.new()
	mesh.radius = zone_width
	mesh.height = 0.08
	mesh.sides = 12
	mesh.name = "ZoneMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.75, 0.2, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.6, 0.15)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	zone.add_child(mesh)

	# Damage area
	var area := Area3D.new()
	area.name = "ZoneArea"
	area.collision_layer = 32  # Layer 6
	area.collision_mask  = 4   # Mask  3
	area.monitorable = true
	area.monitoring = true

	var col := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = zone_width
	cyl_shape.height = 2.0  # tall enough to catch enemies walking through
	col.shape = cyl_shape
	area.add_child(col)
	zone.add_child(area)

	get_tree().current_scene.add_child(zone)
	zone.global_position = Vector3(pos.x, 0.05, pos.z)

	_active_zones.append({
		"node": zone,
		"area": area,
		"mat": mat,
		"timer": zone_duration,
		"dmg_tick": 0.0,
	})


func _tick_zones(delta: float) -> void:
	var damage_per_tick := get_scaled_damage(base_damage) * delta
	var to_remove: Array[int] = []

	for i in _active_zones.size():
		var zd: Dictionary = _active_zones[i]
		zd["timer"] -= delta

		if zd["timer"] <= 0.0 or not is_instance_valid(zd["node"]):
			if is_instance_valid(zd["node"]):
				zd["node"].queue_free()
			to_remove.append(i)
			continue

		# Fade out near end of life
		var mat: StandardMaterial3D = zd["mat"]
		if zd["timer"] < 1.5:
			mat.albedo_color.a = lerpf(0.0, 0.55, zd["timer"] / 1.5)

		# Damage enemies inside zone (once per second, accumulated)
		zd["dmg_tick"] += delta
		if zd["dmg_tick"] >= 1.0:
			zd["dmg_tick"] -= 1.0
			var area: Area3D = zd["area"]
			if area and is_instance_valid(area):
				for body in area.get_overlapping_bodies():
					if body.is_in_group("enemies") and is_instance_valid(body):
						_deal_damage(body, get_scaled_damage(base_damage))

	# Remove expired zones (reverse order to keep indices valid)
	to_remove.reverse()
	for idx in to_remove:
		_active_zones.remove_at(idx)
