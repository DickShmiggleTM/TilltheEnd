extends AbilityBase
## Blood Scythe -- fires spinning projectiles outward in a circle that
## boomerang back to the player, dealing damage and healing via lifesteal.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 10.0
var projectile_count: int = 4
var cooldown: float = 3.0
var lifesteal: float = 0.15
var flight_range: float = 7.0  # how far out projectiles travel before returning

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = cooldown * 0.4


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
		_cooldown_timer = cooldown
		_launch_scythes()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 10.0 * (1.0 + (level - 1) * 0.2)
	projectile_count = 4 + level - 1
	cooldown = maxf(3.0 - level * 0.2, 1.0)
	lifesteal = 0.15 + level * 0.03
	flight_range = 7.0 + level * 0.5


func _launch_scythes() -> void:
	var origin := player.global_position + Vector3.UP * 1.0

	for i in projectile_count:
		var angle := (TAU / projectile_count) * i
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_spawn_scythe(origin, direction)


func _spawn_scythe(origin: Vector3, direction: Vector3) -> void:
	var scythe := Node3D.new()
	scythe.name = "BloodScythe"

	# Visual: red spinning sphere
	var mesh := CSGSphere3D.new()
	mesh.radius = 0.2
	mesh.radial_segments = 6
	mesh.rings = 4
	mesh.name = "ScytheMesh"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.05, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.1, 0.1)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	scythe.add_child(mesh)

	# Damage area
	var area := Area3D.new()
	area.name = "HitArea"
	area.collision_layer = 32  # Layer 6
	area.collision_mask  = 4   # Mask  3
	area.monitorable = true
	area.monitoring = true

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	col.shape = sphere
	area.add_child(col)
	scythe.add_child(area)

	get_tree().current_scene.add_child(scythe)
	scythe.global_position = origin

	# Track which enemies this scythe already hit (to avoid multi-hit per pass)
	var hit_enemies: Dictionary = {}
	var damage := get_scaled_damage(base_damage)
	var ls := lifesteal

	area.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("enemies") and is_instance_valid(body):
			var eid := body.get_instance_id()
			if not hit_enemies.has(eid):
				hit_enemies[eid] = true
				_deal_damage(body, damage)
				# Lifesteal heal
				var heal_amount := damage * ls
				if heal_amount > 0.0 and player and is_instance_valid(player):
					EventBus.player_healed.emit(heal_amount)
	)

	# Animate: fly outward, then return to player
	_animate_boomerang(scythe, mesh, origin, direction, damage)


func _animate_boomerang(scythe: Node3D, mesh: CSGSphere3D, origin: Vector3, direction: Vector3, _damage: float) -> void:
	var outward_target := origin + direction * flight_range
	var flight_time := 0.4
	var return_time := 0.5

	# Spin the visual mesh continuously
	var spin_tw := get_tree().create_tween()
	spin_tw.set_loops()
	spin_tw.tween_property(mesh, "rotation:y", TAU, 0.2).as_relative()

	# Phase 1: fly outward
	var tw := get_tree().create_tween()
	tw.tween_property(scythe, "global_position", outward_target, flight_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Phase 2: return to player
	tw.tween_callback(func() -> void:
		if player == null or not is_instance_valid(player):
			scythe.queue_free()
			spin_tw.kill()
			return
		var return_tw := get_tree().create_tween()
		return_tw.tween_method(func(t: float) -> void:
			if not is_instance_valid(scythe) or player == null or not is_instance_valid(player):
				return
			var target_pos := player.global_position + Vector3.UP * 1.0
			scythe.global_position = scythe.global_position.lerp(target_pos, t)
		, 0.0, 1.0, return_time)
		return_tw.tween_callback(func() -> void:
			spin_tw.kill()
			if is_instance_valid(scythe):
				scythe.queue_free()
		)
	)
