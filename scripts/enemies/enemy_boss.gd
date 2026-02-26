class_name EnemyBoss
extends EnemyBase
## ABYSSAL OVERLORD — the final boss appearing on wave 13.
##
## Three attack phases based on remaining health percentage:
##   Phase 1 (100-60%): Charges and melee attacks, periodically spawns minions.
##   Phase 2 (60-30%):  Fires projectile barrages, ground-slam AoE.
##   Phase 3 (30-0%):   Enraged — faster, more damage, continuous minion spawns.
##
## Very large (3x scale), dark red body with horn decorations.
## Has a visible health bar and telegraphs attacks with scale wind-ups.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 2000.0
	base_damage = 25.0
	speed = 3.0
	attack_range = 3.5
	attack_cooldown = 2.0
	base_exp_drop = 500.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "Abyssal Overlord"

## Phase thresholds (fraction of max HP)
const PHASE_2_THRESHOLD := 0.6
const PHASE_3_THRESHOLD := 0.3

## Attack parameters
const SLAM_RADIUS := 6.0
const SLAM_DAMAGE_MULT := 1.5
const SLAM_COOLDOWN := 5.0
const BARRAGE_COUNT := 8
const BARRAGE_COOLDOWN := 3.5
const BARRAGE_PROJECTILE_SPEED := 12.0
const MINION_SPAWN_COOLDOWN_P1 := 10.0
const MINION_SPAWN_COOLDOWN_P3 := 5.0
const MINION_COUNT := 3
const ENRAGE_SPEED_MULT := 1.5
const ENRAGE_DAMAGE_MULT := 1.6

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _slam_timer: float = SLAM_COOLDOWN
var _barrage_timer: float = BARRAGE_COOLDOWN
var _minion_timer: float = MINION_SPAWN_COOLDOWN_P1
var _is_attacking: bool = false
var _telegraph_timer: float = 0.0

## Health bar nodes
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.5, 0.05, 0.05)  # Dark red


func _create_mesh() -> Node3D:
	# Main body — massive box
	var body := CSGBox3D.new()
	body.size = Vector3(2.4, 3.0, 2.0)
	body.position = Vector3(0.0, 1.5, 0.0)

	# Left horn
	var horn_l := CSGBox3D.new()
	horn_l.size = Vector3(0.25, 1.0, 0.25)
	horn_l.position = Vector3(-0.7, 2.8, 0.0)
	horn_l.rotation_degrees = Vector3(0, 0, 25)

	var horn_l_mat := StandardMaterial3D.new()
	horn_l_mat.albedo_color = Color(0.2, 0.0, 0.0)
	horn_l_mat.emission_enabled = true
	horn_l_mat.emission = Color(0.4, 0.0, 0.0)
	horn_l_mat.emission_energy_multiplier = 0.5
	horn_l.material = horn_l_mat
	body.add_child(horn_l)

	# Right horn
	var horn_r := CSGBox3D.new()
	horn_r.size = Vector3(0.25, 1.0, 0.25)
	horn_r.position = Vector3(0.7, 2.8, 0.0)
	horn_r.rotation_degrees = Vector3(0, 0, -25)

	var horn_r_mat := StandardMaterial3D.new()
	horn_r_mat.albedo_color = Color(0.2, 0.0, 0.0)
	horn_r_mat.emission_enabled = true
	horn_r_mat.emission = Color(0.4, 0.0, 0.0)
	horn_r_mat.emission_energy_multiplier = 0.5
	horn_r.material = horn_r_mat
	body.add_child(horn_r)

	# Center horn (larger, on top)
	var horn_c := CSGBox3D.new()
	horn_c.size = Vector3(0.2, 1.4, 0.2)
	horn_c.position = Vector3(0.0, 3.2, 0.0)

	var horn_c_mat := StandardMaterial3D.new()
	horn_c_mat.albedo_color = Color(0.3, 0.0, 0.0)
	horn_c_mat.emission_enabled = true
	horn_c_mat.emission = Color(0.6, 0.1, 0.0)
	horn_c_mat.emission_energy_multiplier = 1.0
	horn_c.material = horn_c_mat
	body.add_child(horn_c)

	# Eyes (two small glowing boxes)
	var eye_l := CSGBox3D.new()
	eye_l.size = Vector3(0.2, 0.15, 0.1)
	eye_l.position = Vector3(-0.4, 2.5, -1.01)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.2, 0.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.3, 0.0)
	eye_mat.emission_energy_multiplier = 3.0
	eye_l.material = eye_mat
	body.add_child(eye_l)

	var eye_r := CSGBox3D.new()
	eye_r.size = Vector3(0.2, 0.15, 0.1)
	eye_r.position = Vector3(0.4, 2.5, -1.01)
	eye_r.material = eye_mat
	body.add_child(eye_r)

	return body


func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 3.0, 2.0)
	return box


func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 1.5, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_create_health_bar()
	# Boss announces itself
	EventBus.boss_wave_started.emit()


func _create_health_bar() -> void:
	# Floating health bar above the boss
	var bar_width := 3.0
	var bar_height := 0.15

	# Background (dark)
	_health_bar_bg = CSGBox3D.new()
	_health_bar_bg.size = Vector3(bar_width, bar_height, 0.05)
	_health_bar_bg.position = Vector3(0.0, 4.5, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	# Fill (red)
	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 4.5, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.9, 0.1, 0.1)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.9, 0.1, 0.1)
	_health_bar_mat.emission_energy_multiplier = 1.0
	_health_bar_fill.material = _health_bar_mat
	add_child(_health_bar_fill)

# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# -- Flash timer -----------------------------------------------------
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and _mesh is CSGPrimitive3D:
			(_mesh as CSGPrimitive3D).material = _base_material

	# -- Gravity ---------------------------------------------------------
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# -- Knockback decay (boss resists most knockback) -------------------
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 2.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Update phase ----------------------------------------------------
	_update_phase()

	# -- Update health bar -----------------------------------------------
	_update_health_bar()

	# -- Make health bar face camera -------------------------------------
	_face_health_bar_to_camera()

	# -- Movement --------------------------------------------------------
	var move_dir := Vector3.ZERO
	var player := get_player()

	if player and is_instance_valid(player) and not _is_attacking:
		var to_player := player.global_position - global_position
		to_player.y = 0.0

		if to_player.length() > attack_range * 0.7:
			move_dir = to_player.normalized()

		if to_player.length() > 0.1:
			var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
			look_at(look_target, Vector3.UP)

	var speed_mult := 1.0
	if current_phase == Phase.THREE:
		speed_mult = ENRAGE_SPEED_MULT

	var effective_speed := speed * wave_speed_mult * slow_mult * speed_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Phase-specific attack timers ------------------------------------
	_attack_timer -= delta
	_slam_timer -= delta
	_barrage_timer -= delta
	_minion_timer -= delta

	match current_phase:
		Phase.ONE:
			_phase_one_logic(delta)
		Phase.TWO:
			_phase_two_logic(delta)
		Phase.THREE:
			_phase_three_logic(delta)

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

func _update_phase() -> void:
	var ratio := get_health_ratio()
	if ratio <= PHASE_3_THRESHOLD and current_phase != Phase.THREE:
		current_phase = Phase.THREE
		_on_enter_phase_three()
	elif ratio <= PHASE_2_THRESHOLD and current_phase == Phase.ONE:
		current_phase = Phase.TWO
		_on_enter_phase_two()


func _on_enter_phase_two() -> void:
	# Visual feedback — flash body
	if _base_material:
		_base_material.emission_energy_multiplier = 1.5
		_base_material.emission = Color(0.7, 0.1, 0.0)


func _on_enter_phase_three() -> void:
	# Enrage visual — glow intensely
	if _base_material:
		_base_material.emission_energy_multiplier = 3.0
		_base_material.emission = Color(1.0, 0.2, 0.0)

	# Scale up slightly to look more menacing
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.15, 1.15, 1.15), 0.5)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	# Melee attack
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range and _attack_timer <= 0.0:
		_melee_attack(player)

	# Spawn minions periodically
	if _minion_timer <= 0.0:
		_spawn_minions(MINION_COUNT)
		_minion_timer = MINION_SPAWN_COOLDOWN_P1


func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	# Ground slam when close
	if dist <= SLAM_RADIUS and _slam_timer <= 0.0:
		_ground_slam()

	# Projectile barrage at range
	if _barrage_timer <= 0.0:
		_fire_barrage(player)

	# Still does melee if very close
	if dist <= attack_range and _attack_timer <= 0.0:
		_melee_attack(player)

	# Occasional minion spawns
	if _minion_timer <= 0.0:
		_spawn_minions(2)
		_minion_timer = MINION_SPAWN_COOLDOWN_P1


func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	# Slam more frequently
	if dist <= SLAM_RADIUS and _slam_timer <= 0.0:
		_ground_slam()

	# Barrage more frequently
	if _barrage_timer <= 0.0:
		_fire_barrage(player)

	# Enraged melee
	if dist <= attack_range and _attack_timer <= 0.0:
		_melee_attack(player, ENRAGE_DAMAGE_MULT)

	# Continuous minion spawns
	if _minion_timer <= 0.0:
		_spawn_minions(MINION_COUNT + 2)
		_minion_timer = MINION_SPAWN_COOLDOWN_P3

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _melee_attack(player: Node3D, extra_mult: float = 1.0) -> void:
	# Telegraph: wind-up scale
	_is_attacking = true
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.2, 0.85, 1.2), 0.15)
		tw.tween_callback(_execute_melee.bind(player, extra_mult))
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.2)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_melee(player, extra_mult)
		_is_attacking = false
	_attack_timer = attack_cooldown


func _execute_melee(player: Node3D, extra_mult: float) -> void:
	if not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > attack_range * 1.5:
		return  # Player moved away during telegraph
	var effective_damage := base_damage * wave_dmg_mult * extra_mult
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)


func _ground_slam() -> void:
	_is_attacking = true
	_slam_timer = SLAM_COOLDOWN

	# Telegraph: rise up then slam down
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "position:y", _mesh.position.y + 0.6, 0.3)
		tw.tween_callback(_execute_slam)
		tw.tween_property(_mesh, "position:y", _mesh.position.y, 0.15)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_slam()
		_is_attacking = false


func _execute_slam() -> void:
	var slam_damage := base_damage * wave_dmg_mult * SLAM_DAMAGE_MULT

	# Damage player if in radius
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= SLAM_RADIUS:
			var falloff := 1.0 - (dist / SLAM_RADIUS) * 0.5
			if player.has_method("take_damage"):
				player.take_damage(slam_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 10.0

	# Spawn expanding ring visual
	_spawn_slam_ring()


func _spawn_slam_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.1
	ring.sides = 24
	ring.global_position = global_position + Vector3(0, 0.1, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", SLAM_RADIUS, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)


func _fire_barrage(target: Node3D) -> void:
	_barrage_timer = BARRAGE_COOLDOWN
	if current_phase == Phase.THREE:
		_barrage_timer *= 0.6  # Faster in phase 3

	var target_pos := target.global_position + Vector3(0, 0.9, 0)
	var spawn_pos := global_position + Vector3(0, 2.5, 0)

	# Fire projectiles in a spread pattern
	var base_dir := (target_pos - spawn_pos).normalized()
	var count := BARRAGE_COUNT
	if current_phase == Phase.THREE:
		count += 4  # More projectiles in phase 3

	for i in count:
		# Spread angle
		var angle_offset := deg_to_rad(-30.0 + (60.0 / float(count)) * float(i))
		var rotated_dir := base_dir.rotated(Vector3.UP, angle_offset)

		# Slight delay for dramatic effect
		get_tree().create_timer(i * 0.08).timeout.connect(
			_spawn_boss_projectile.bind(spawn_pos, rotated_dir)
		)


func _spawn_boss_projectile(pos: Vector3, dir: Vector3) -> void:
	if not is_alive:
		return
	var proj := _BossProjectile.new()
	proj.global_position = pos
	proj.direction = dir
	proj.projectile_speed = BARRAGE_PROJECTILE_SPEED
	proj.damage = base_damage * wave_dmg_mult * 0.6

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

# ---------------------------------------------------------------------------
# Minion spawning
# ---------------------------------------------------------------------------

func _spawn_minions(count: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	for i in count:
		var minion := EnemyMelee.new()
		# Place around the boss
		var angle := (TAU / float(count)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y

		minion.initialize(wave_hp_mult * 0.5, wave_dmg_mult * 0.5, wave_speed_mult)
		scene_root.add_child(minion)
		minion.global_position = spawn_pos

		# Register with GameManager so wave tracking stays correct
		GameManager.register_enemies(1)

# ---------------------------------------------------------------------------
# Health bar
# ---------------------------------------------------------------------------

func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	var ratio := get_health_ratio()
	var full_width := 2.95
	_health_bar_fill.size.x = full_width * ratio

	# Shift fill position to keep it left-aligned
	var offset := (full_width - _health_bar_fill.size.x) * 0.5
	_health_bar_fill.position.x = -offset

	# Color shifts with health
	if _health_bar_mat:
		if ratio <= PHASE_3_THRESHOLD:
			_health_bar_mat.albedo_color = Color(1.0, 0.1, 0.1)
			_health_bar_mat.emission = Color(1.0, 0.1, 0.1)
		elif ratio <= PHASE_2_THRESHOLD:
			_health_bar_mat.albedo_color = Color(1.0, 0.5, 0.0)
			_health_bar_mat.emission = Color(1.0, 0.5, 0.0)


func _face_health_bar_to_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _health_bar_bg:
		var dir := cam.global_position - _health_bar_bg.global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			_health_bar_bg.look_at(_health_bar_bg.global_position + dir, Vector3.UP)
	if _health_bar_fill:
		var dir := cam.global_position - _health_bar_fill.global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			_health_bar_fill.look_at(_health_bar_fill.global_position + dir, Vector3.UP)

# ---------------------------------------------------------------------------
# Override damage — boss resists knockback
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir * 0.2)

# ---------------------------------------------------------------------------
# Override die — emit boss_killed instead
# ---------------------------------------------------------------------------

func die() -> void:
	if not is_alive:
		return
	is_alive = false

	# Drop massive EXP
	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)

	# Guaranteed drops
	_drop_health()
	_drop_health()
	_drop_ammo()
	_drop_ammo()
	_drop_bomb_ammo()

	# Signals
	EventBus.enemy_killed.emit(self, global_position)
	EventBus.boss_killed.emit()

	# Death effect — dramatic
	_boss_death_effect()
	queue_free()


func _boss_death_effect() -> void:
	# Multiple expanding rings
	for i in 3:
		get_tree().create_timer(i * 0.3).timeout.connect(
			_spawn_death_ring.bind(i)
		)


func _spawn_death_ring(index: int) -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.3
	ring.height = 0.15
	ring.sides = 32
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.5, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", 8.0, 0.6).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Inner class: Boss projectile
# ---------------------------------------------------------------------------

class _BossProjectile extends Area3D:

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 12.0
	var damage: float = 15.0
	var _lifetime: float = 6.0

	func _ready() -> void:
		collision_layer = 8   # Layer 4 (Projectiles)
		collision_mask = 2    # Layer 2 (Player)

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.25
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.0)
		mat.emission_energy_multiplier = 3.0
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.25
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		global_position += direction * projectile_speed * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(damage, self)
		queue_free()
