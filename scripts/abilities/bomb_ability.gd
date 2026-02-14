extends AbilityBase
## Frag Grenade -- throwable explosive with limited charges. Charges are
## replenished by enemy drops via EventBus.bomb_ammo_collected.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 40.0
var explosion_radius: float = 5.0
var max_charges: int = 3
var current_charges: int = 3
var throw_force: float = 14.0
var fuse_time: float = 2.0  # explode after this many seconds if no collision

# ── Internal ──────────────────────────────────────────────────────────
var _can_throw: bool = true
var _throw_cooldown: float = 0.3  # minimum time between throws
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	current_charges = max_charges


func _on_upgrade() -> void:
	var old_max := max_charges
	_apply_level_stats()
	# Grant any new charges from the upgrade
	current_charges += max_charges - old_max
	current_charges = mini(current_charges, max_charges)


func deactivate() -> void:
	pass


# ── Public ────────────────────────────────────────────────────────────

## Called by input handler / ability manager when the player presses the bomb button.
func throw_bomb() -> void:
	if current_charges <= 0 or not _can_throw:
		return
	current_charges -= 1
	_can_throw = false
	_cooldown_timer = _throw_cooldown
	_spawn_grenade()


## Called by AbilityManager when bomb ammo is collected.
func add_charges(amount: int) -> void:
	current_charges = mini(current_charges + amount, max_charges)


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _can_throw:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_can_throw = true


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 40.0 * (1.0 + (level - 1) * 0.25)
	explosion_radius = 5.0 + level * 0.5
	max_charges = 3 + level - 1


func _spawn_grenade() -> void:
	if player == null:
		return

	var grenade := Node3D.new()
	grenade.name = "Grenade"

	# Visual: small dark sphere
	var mesh := CSGSphere3D.new()
	mesh.radius = 0.2
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.12, 0.1)
	mesh.material = mat
	grenade.add_child(mesh)

	# Collision area for enemy contact detonation
	var area := Area3D.new()
	area.name = "ContactArea"
	area.collision_layer = 32  # Layer 6
	area.collision_mask  = 4   # Mask  3
	area.monitorable = true
	area.monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	area.add_child(col)
	grenade.add_child(area)

	get_tree().current_scene.add_child(grenade)

	# Launch position: slightly in front and above the player
	var cam_basis: Basis = player.global_transform.basis
	var forward := -cam_basis.z.normalized()
	grenade.global_position = player.global_position + Vector3.UP * 1.5 + forward * 0.5

	# Parabolic arc: we simulate manually
	var velocity := forward * throw_force + Vector3.UP * throw_force * 0.45
	var gravity := 9.8
	var elapsed := 0.0
	var exploded := false

	# Contact detonation
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("enemies") and not exploded:
			exploded = true
			_explode(grenade)
	)

	# Simulate trajectory in a coroutine-like tween update
	var tw := get_tree().create_tween()
	tw.set_loops()
	tw.tween_callback(func() -> void:
		if exploded or not is_instance_valid(grenade):
			tw.kill()
			return
		var dt := get_process_delta_time()
		elapsed += dt
		velocity.y -= gravity * dt
		grenade.global_position += velocity * dt

		# Floor collision
		if grenade.global_position.y <= 0.1:
			grenade.global_position.y = 0.1
			exploded = true
			_explode(grenade)
			tw.kill()
			return

		# Fuse timer
		if elapsed >= fuse_time:
			exploded = true
			_explode(grenade)
			tw.kill()
	).set_delay(0.0)  # run every frame


func _explode(grenade: Node3D) -> void:
	if not is_instance_valid(grenade):
		return

	var pos := grenade.global_position
	var damage := get_scaled_damage(base_damage)

	# Deal area damage
	for enemy in _get_enemies_in_range(pos, explosion_radius):
		var dist := enemy.global_position.distance_to(pos)
		var falloff := 1.0 - (dist / explosion_radius) * 0.5  # 50-100% damage
		_deal_damage(enemy, damage * falloff)

	# Explosion visual
	_spawn_explosion_visual(pos)

	grenade.queue_free()


func _spawn_explosion_visual(pos: Vector3) -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 0.5
	explosion.radial_segments = 8
	explosion.rings = 4
	explosion.name = "Explosion"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = pos

	# Expand and fade
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(explosion, "radius", explosion_radius * 0.6, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(explosion.queue_free)
