extends AbilityBase
## Death Orbit -- spectral skulls orbit the player, damaging enemies on contact.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 8.0
var skull_count: int = 3
var orbit_radius: float = 3.0
var spin_speed: float = 2.0
var damage_cooldown: float = 0.25  # time between hits per-enemy

# ── Internal ──────────────────────────────────────────────────────────
var _skulls: Array[Node3D] = []
var _orbit_angle: float = 0.0
var _hit_timers: Dictionary = {}  # enemy instance_id -> cooldown remaining


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_rebuild_skulls()


func _on_upgrade() -> void:
	_apply_level_stats()
	_rebuild_skulls()


func deactivate() -> void:
	_clear_skulls()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	_orbit_angle += spin_speed * delta

	# Tick per-enemy hit cooldowns
	var expired: Array = []
	for eid in _hit_timers:
		_hit_timers[eid] -= delta
		if _hit_timers[eid] <= 0.0:
			expired.append(eid)
	for eid in expired:
		_hit_timers.erase(eid)

	# Position each skull around the player
	var count := _skulls.size()
	for i in count:
		var angle := _orbit_angle + (TAU / count) * i
		var offset := Vector3(cos(angle) * orbit_radius, 1.0, sin(angle) * orbit_radius)
		_skulls[i].global_position = player.global_position + offset

		# Rotate skull itself for visual flair
		_skulls[i].rotation.y += delta * 4.0


func _physics_process(_delta: float) -> void:
	# Check for enemy overlaps on each skull Area3D
	for skull in _skulls:
		var area: Area3D = skull.get_node_or_null("DamageArea")
		if area == null:
			continue
		for body in area.get_overlapping_bodies():
			if body.is_in_group("enemies") and is_instance_valid(body):
				var eid := body.get_instance_id()
				if not _hit_timers.has(eid):
					var dmg := get_scaled_damage(base_damage)
					_deal_damage(body, dmg)
					_hit_timers[eid] = damage_cooldown


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 8.0 * (1.0 + (level - 1) * 0.2)
	skull_count = 3 + (level - 1)
	orbit_radius = 3.0 + level * 0.3
	spin_speed = 2.0 + level * 0.1


func _clear_skulls() -> void:
	for s in _skulls:
		if is_instance_valid(s):
			s.queue_free()
	_skulls.clear()


func _rebuild_skulls() -> void:
	_clear_skulls()

	for i in skull_count:
		var skull := _create_skull()
		add_child(skull)
		_skulls.append(skull)


func _create_skull() -> Node3D:
	var root := Node3D.new()
	root.name = "Skull"

	# Visual: small glowing magenta sphere
	var mesh := CSGSphere3D.new()
	mesh.radius = 0.25
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.name = "SkullMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.1, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.15, 0.9)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	root.add_child(mesh)

	# Damage area
	var area := Area3D.new()
	area.name = "DamageArea"
	area.collision_layer = 32  # Layer 6
	area.collision_mask  = 4   # Mask  3
	area.monitorable = true
	area.monitoring = true

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	col.shape = sphere
	area.add_child(col)
	root.add_child(area)

	return root
