extends Area3D
## Projectile behavior for non-hitscan weapons.
## Created at runtime by WeaponManager -- no .tscn scene file required.
## Supports: explosion on impact, piercing, burn DoT, and acid pools.

# ── Configuration (set by WeaponManager before _ready) ─────────────────────
var direction: Vector3 = Vector3.FORWARD
var speed: float = 30.0
var damage: float = 10.0
var is_crit: bool = false
var weapon_data: Dictionary = {}
var weapon_color: Color = Color.WHITE

# ── Constants ──────────────────────────────────────────────────────────────────
const LIFETIME := 3.0
const EXPLOSION_DURATION := 0.25
const BURN_TICK_INTERVAL := 0.5
const ACID_POOL_DURATION := 4.0
const ACID_POOL_TICK := 0.5
const ACID_POOL_RADIUS := 1.5

# ── Runtime state ──────────────────────────────────────────────────────────────
var _age: float = 0.0
var _pierce_remaining: int = 0
var _enemies_hit: Array[Node3D] = []  # Track pierced enemies to avoid double-hit
var _visual: Node3D = null


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Set collision (should already be set by WeaponManager, but ensure correctness)
	collision_layer = 32  # Layer 6: PlayerProjectiles
	collision_mask = 0b000101  # Layer 1 (Environment) + Layer 3 (Enemies)

	# Parse weapon-specific properties
	_pierce_remaining = weapon_data.get("pierce", 0)

	# Build visual
	_build_visual()

	# Build collision shape
	_build_collision()

	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Orient to face movement direction
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)


func _process(delta: float) -> void:
	_age += delta

	# Self-destruct after lifetime
	if _age >= LIFETIME:
		_destroy()
		return

	# Move forward
	global_position += direction * speed * delta

	# Rotate visual for some weapon types (rockets spin slowly, plasma pulses)
	if _visual and weapon_data.get("id", "") == "rocket_launcher":
		_visual.rotate_z(delta * 3.0)


# ══════════════════════════════════════════════════════════════════════════════
# Collision handling
# ══════════════════════════════════════════════════════════════════════════════

func _on_body_entered(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return

	# Check if this is an enemy (layer 3)
	if _is_enemy(body):
		_hit_enemy(body)
	else:
		# Hit environment -- explode or destroy
		_on_hit_environment(body)


func _on_area_entered(area: Area3D) -> void:
	# In case enemies use Area3D instead of PhysicsBody3D
	if area == null or not is_instance_valid(area):
		return
	if area.is_in_group("enemies") or (area.collision_layer & 4 != 0):
		var enemy := area
		_hit_enemy(enemy)


func _hit_enemy(enemy: Node3D) -> void:
	# Skip if already hit this enemy (piercing)
	if enemy in _enemies_hit:
		return
	_enemies_hit.append(enemy)

	# Calculate final damage with crit
	var final_damage := damage
	if is_crit:
		var crit_mult: float = GameManager.player_traits.get("crit_damage", 1.5)
		crit_mult += weapon_data.get("crit_bonus", 0.0)
		final_damage *= crit_mult

	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(final_damage)

	# Lifesteal
	var lifesteal: float = GameManager.player_traits.get("lifesteal", 0.0)
	if lifesteal > 0.0:
		EventBus.player_healed.emit(final_damage * lifesteal)

	# Emit combat events
	EventBus.enemy_damaged.emit(enemy, final_damage)
	EventBus.damage_dealt.emit(final_damage, global_position, is_crit)

	# Apply armor pierce
	var armor_pierce: float = weapon_data.get("armor_pierce", 0.0)
	if armor_pierce > 0.0 and enemy.has_method("reduce_armor"):
		enemy.reduce_armor(armor_pierce)

	# Apply burn DoT
	var burn_dps: float = weapon_data.get("burn_dps", 0.0)
	if burn_dps > 0.0:
		_apply_burn(enemy, burn_dps)

	# Apply acid / DoT damage pool
	var dot_damage: float = weapon_data.get("dot_damage", 0.0)
	if dot_damage > 0.0:
		_spawn_acid_pool(global_position, dot_damage)

	# Check explosion
	var explosion_radius: float = weapon_data.get("explosion_radius", 0.0)
	if explosion_radius > 0.0:
		_explode(global_position, explosion_radius)
		_destroy()
		return

	# Piercing logic
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		# Continue through -- do not destroy
		return

	# Non-piercing, non-explosive: destroy on first hit
	_destroy()


func _on_hit_environment(_body: Node3D) -> void:
	# Explosion on environment hit
	var explosion_radius: float = weapon_data.get("explosion_radius", 0.0)
	if explosion_radius > 0.0:
		_explode(global_position, explosion_radius)

	# Acid pool on environment hit
	var dot_damage: float = weapon_data.get("dot_damage", 0.0)
	if dot_damage > 0.0:
		_spawn_acid_pool(global_position, dot_damage)

	_destroy()


# ══════════════════════════════════════════════════════════════════════════════
# Explosion
# ══════════════════════════════════════════════════════════════════════════════

func _explode(pos: Vector3, radius: float) -> void:
	# Create an Area3D sphere to detect all enemies in blast radius
	var explosion_area := Area3D.new()
	explosion_area.name = "Explosion"
	explosion_area.global_position = pos
	explosion_area.collision_layer = 0
	explosion_area.collision_mask = 4  # Layer 3: Enemies

	var shape := SphereShape3D.new()
	shape.radius = radius
	var collision := CollisionShape3D.new()
	collision.shape = shape
	explosion_area.add_child(collision)

	# Explosion visual -- expanding sphere
	var visual := CSGSphere3D.new()
	visual.radius = radius * 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material = mat
	explosion_area.add_child(visual)

	# Explosion light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.0)
	light.light_energy = 5.0
	light.omni_range = radius * 2.0
	explosion_area.add_child(light)

	get_tree().current_scene.add_child(explosion_area)

	# Use deferred overlap check -- need one physics frame for the area to register
	explosion_area.set_deferred("monitoring", true)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Damage all enemies in the explosion
	if is_instance_valid(explosion_area):
		var bodies := explosion_area.get_overlapping_bodies()
		var areas := explosion_area.get_overlapping_areas()

		for body in bodies:
			if _is_enemy(body) and body not in _enemies_hit:
				var dist := pos.distance_to(body.global_position)
				var falloff := clampf(1.0 - (dist / radius) * 0.5, 0.3, 1.0)
				var explosion_damage := damage * falloff
				if body.has_method("take_damage"):
					body.take_damage(explosion_damage)
				EventBus.enemy_damaged.emit(body, explosion_damage)
				EventBus.damage_dealt.emit(explosion_damage, body.global_position, false)

		for area in areas:
			if (area.is_in_group("enemies") or area.collision_layer & 4 != 0) and area not in _enemies_hit:
				var dist := pos.distance_to(area.global_position)
				var falloff := clampf(1.0 - (dist / radius) * 0.5, 0.3, 1.0)
				var explosion_damage := damage * falloff
				if area.has_method("take_damage"):
					area.take_damage(explosion_damage)
				EventBus.enemy_damaged.emit(area, explosion_damage)
				EventBus.damage_dealt.emit(explosion_damage, area.global_position, false)

	# Animate and clean up
	if is_instance_valid(explosion_area) and is_instance_valid(visual):
		var tween := get_tree().create_tween()
		tween.set_parallel(true)
		tween.tween_property(visual, "radius", radius, EXPLOSION_DURATION)
		tween.tween_property(mat, "albedo_color:a", 0.0, EXPLOSION_DURATION)
		tween.tween_property(light, "light_energy", 0.0, EXPLOSION_DURATION)
		tween.set_parallel(false)
		tween.tween_callback(explosion_area.queue_free)


# ══════════════════════════════════════════════════════════════════════════════
# Burn DoT
# ══════════════════════════════════════════════════════════════════════════════

func _apply_burn(enemy: Node3D, burn_dps: float) -> void:
	# Apply burn as repeated ticks over 3 seconds
	var total_ticks: int = int(3.0 / BURN_TICK_INTERVAL)
	var tick_damage: float = burn_dps * BURN_TICK_INTERVAL
	var level: int = weapon_data.get("level", 1)
	var level_mult: float = 1.0 + (level - 1) * 0.25
	tick_damage *= level_mult

	# Use a timer-based approach on the scene tree
	var burn_timer := Timer.new()
	burn_timer.wait_time = BURN_TICK_INTERVAL
	burn_timer.one_shot = false
	burn_timer.name = "BurnTimer"
	get_tree().current_scene.add_child(burn_timer)

	var ticks_left := total_ticks
	burn_timer.timeout.connect(func() -> void:
		if not is_instance_valid(enemy):
			burn_timer.queue_free()
			return
		if ticks_left <= 0:
			burn_timer.queue_free()
			return
		ticks_left -= 1
		if enemy.has_method("take_damage"):
			enemy.take_damage(tick_damage)
		EventBus.enemy_damaged.emit(enemy, tick_damage)
		EventBus.damage_dealt.emit(tick_damage, enemy.global_position, false)
	)
	burn_timer.start()


# ══════════════════════════════════════════════════════════════════════════════
# Acid pool
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_acid_pool(pos: Vector3, dot_dmg: float) -> void:
	var level: int = weapon_data.get("level", 1)
	var level_mult: float = 1.0 + (level - 1) * 0.25
	var pool_damage: float = dot_dmg * ACID_POOL_TICK * level_mult

	# Create pool area
	var pool := Area3D.new()
	pool.name = "AcidPool"
	pool.global_position = Vector3(pos.x, 0.05, pos.z)  # Slightly above ground
	pool.collision_layer = 0
	pool.collision_mask = 4  # Layer 3: Enemies

	var shape := CylinderShape3D.new()
	shape.radius = ACID_POOL_RADIUS
	shape.height = 0.3
	var collision := CollisionShape3D.new()
	collision.shape = shape
	pool.add_child(collision)

	# Pool visual -- flat green disc
	var visual := CSGCylinder3D.new()
	visual.radius = ACID_POOL_RADIUS
	visual.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.8, 0.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material = mat
	pool.add_child(visual)

	get_tree().current_scene.add_child(pool)

	# Tick damage to enemies standing in the pool
	var pool_timer := Timer.new()
	pool_timer.wait_time = ACID_POOL_TICK
	pool_timer.one_shot = false
	pool.add_child(pool_timer)

	pool_timer.timeout.connect(func() -> void:
		if not is_instance_valid(pool):
			return
		var bodies := pool.get_overlapping_bodies()
		for body in bodies:
			if _is_enemy(body):
				if body.has_method("take_damage"):
					body.take_damage(pool_damage)
				EventBus.enemy_damaged.emit(body, pool_damage)
				EventBus.damage_dealt.emit(pool_damage, body.global_position, false)
		var areas := pool.get_overlapping_areas()
		for area in areas:
			if area.is_in_group("enemies") or (area.collision_layer & 4 != 0):
				if area.has_method("take_damage"):
					area.take_damage(pool_damage)
				EventBus.enemy_damaged.emit(area, pool_damage)
				EventBus.damage_dealt.emit(pool_damage, area.global_position, false)
	)
	pool_timer.start()

	# Fade out and destroy after duration
	var lifetime_timer := get_tree().create_timer(ACID_POOL_DURATION)
	lifetime_timer.timeout.connect(func() -> void:
		if is_instance_valid(pool) and is_instance_valid(mat):
			var tween := get_tree().create_tween()
			tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
			tween.tween_callback(pool.queue_free)
	)


# ══════════════════════════════════════════════════════════════════════════════
# Visual construction
# ══════════════════════════════════════════════════════════════════════════════

func _build_visual() -> void:
	var weapon_id: String = weapon_data.get("id", "")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = weapon_color
	mat.emission_enabled = true
	mat.emission = weapon_color
	mat.emission_energy_multiplier = 2.0

	match weapon_id:
		"rocket_launcher":
			# Cylindrical rocket
			var rocket := CSGCylinder3D.new()
			rocket.radius = 0.08
			rocket.height = 0.25
			rocket.rotation_degrees.x = 90.0
			rocket.material = mat
			add_child(rocket)
			# Nose cone
			var nose := CSGCylinder3D.new()
			nose.radius = 0.08
			nose.height = 0.1
			nose.cone = true
			nose.rotation_degrees.x = 90.0
			nose.position.z = -0.15
			nose.material = mat
			add_child(nose)
			_visual = rocket
		"acid_gun":
			# Blob-like sphere
			var blob := CSGSphere3D.new()
			blob.radius = 0.1
			mat.albedo_color = Color(0.2, 1.0, 0.0, 0.8)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			blob.material = mat
			add_child(blob)
			_visual = blob
		"flamethrower":
			# Flame particle -- small stretched sphere
			var flame := CSGSphere3D.new()
			flame.radius = 0.08
			mat.albedo_color = Color(1.0, 0.5, 0.0, 0.9)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			flame.material = mat
			add_child(flame)
			_visual = flame
		"crossbow":
			# Bolt shape
			var bolt := CSGBox3D.new()
			bolt.size = Vector3(0.02, 0.02, 0.2)
			bolt.material = mat
			add_child(bolt)
			_visual = bolt
		_:
			# Default: small glowing sphere
			var sphere := CSGSphere3D.new()
			sphere.radius = 0.06
			sphere.material = mat
			add_child(sphere)
			_visual = sphere

	# Add a small point light to make projectiles visible
	var light := OmniLight3D.new()
	light.light_color = weapon_color
	light.light_energy = 1.0
	light.omni_range = 2.0
	add_child(light)


func _build_collision() -> void:
	var shape := SphereShape3D.new()
	shape.radius = 0.1
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


# ══════════════════════════════════════════════════════════════════════════════
# Utility
# ══════════════════════════════════════════════════════════════════════════════

func _is_enemy(node: Node3D) -> bool:
	if node is PhysicsBody3D:
		return (node as PhysicsBody3D).collision_layer & 4 != 0  # Layer 3
	return node.is_in_group("enemies")


func _destroy() -> void:
	set_process(false)
	set_physics_process(false)
	# Disable collision immediately
	collision_layer = 0
	collision_mask = 0
	queue_free()
