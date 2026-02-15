class_name BossOverseer
extends EnemyBase
## THE FORGE OVERSEER — Level 2 Boss.
##
## A hulking iron-clad figure fueled by an internal furnace.
##
## Phase 1 (100-60%): Heavy melee attacks, throws slag bombs that leave fire
##   pools on the ground.
## Phase 2 (60-30%): Deploys turret nodes (stationary shooting enemies),
##   charges with knockback.
## Phase 3 (30-0%): Overheats — glows brighter, faster attacks, continuous
##   flame burst AoE around self.
##
## Visual: Dark gray CSGBox3D body with orange glowing furnace core (CSGSphere3D).

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 1200.0
	base_damage = 23.0
	speed = 2.5
	attack_range = 3.5
	attack_cooldown = 2.2
	base_exp_drop = 450.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Forge Overseer"

const PHASE_2_THRESHOLD := 0.6
const PHASE_3_THRESHOLD := 0.3

const HAMMER_SLAM_RANGE := 4.0
const HAMMER_SLAM_COOLDOWN := 2.5
const HAMMER_SLAM_DAMAGE_MULT := 1.4
const SLAG_BOMB_COOLDOWN := 5.0
const SLAG_BOMB_SPEED := 10.0
const SLAG_BOMB_RADIUS := 3.0
const TURRET_DEPLOY_COOLDOWN := 12.0
const CHARGE_COOLDOWN := 7.0
const CHARGE_SPEED := 12.0
const CHARGE_DURATION := 0.6
const FLAME_BURST_RADIUS := 5.0
const FLAME_BURST_COOLDOWN := 3.0
const FLAME_BURST_DAMAGE_MULT := 0.8
const ENRAGE_SPEED_MULT := 1.5
const ENRAGE_ATTACK_MULT := 1.4

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _hammer_timer: float = HAMMER_SLAM_COOLDOWN
var _slag_timer: float = SLAG_BOMB_COOLDOWN
var _turret_timer: float = TURRET_DEPLOY_COOLDOWN
var _charge_timer: float = CHARGE_COOLDOWN
var _flame_timer: float = FLAME_BURST_COOLDOWN
var _is_attacking: bool = false
var _is_charging: bool = false
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_elapsed: float = 0.0

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Core reference for visual effects
var _furnace_core: CSGSphere3D = null
var _core_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.25, 0.25, 0.28)  # Dark iron gray

func _create_mesh() -> Node3D:
	# Main body — massive box
	var body := CSGBox3D.new()
	body.size = Vector3(2.2, 3.2, 1.8)
	body.position = Vector3(0.0, 1.6, 0.0)

	# Furnace core (glowing orange sphere in center)
	_furnace_core = CSGSphere3D.new()
	_furnace_core.radius = 0.6
	_furnace_core.radial_segments = 12
	_furnace_core.rings = 6
	_furnace_core.position = Vector3(0.0, 0.0, -0.7)
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color(1.0, 0.5, 0.05)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.4, 0.0)
	_core_mat.emission_energy_multiplier = 3.0
	_furnace_core.material = _core_mat
	body.add_child(_furnace_core)

	# Shoulder plates
	var shoulder_l := CSGBox3D.new()
	shoulder_l.size = Vector3(0.7, 0.5, 1.0)
	shoulder_l.position = Vector3(-1.3, 1.2, 0.0)
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.3, 0.28, 0.25)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.15, 0.12, 0.1)
	plate_mat.emission_energy_multiplier = 0.3
	shoulder_l.material = plate_mat
	body.add_child(shoulder_l)

	var shoulder_r := CSGBox3D.new()
	shoulder_r.size = Vector3(0.7, 0.5, 1.0)
	shoulder_r.position = Vector3(1.3, 1.2, 0.0)
	shoulder_r.material = plate_mat
	body.add_child(shoulder_r)

	# Head — small dark box on top
	var head := CSGBox3D.new()
	head.size = Vector3(0.8, 0.6, 0.7)
	head.position = Vector3(0.0, 2.0, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.2, 0.2, 0.22)
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.4, 0.2, 0.0)
	head_mat.emission_energy_multiplier = 0.5
	head.material = head_mat
	body.add_child(head)

	# Visor (glowing slit)
	var visor := CSGBox3D.new()
	visor.size = Vector3(0.6, 0.1, 0.05)
	visor.position = Vector3(0.0, 0.1, -0.36)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(1.0, 0.4, 0.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(1.0, 0.4, 0.0)
	visor_mat.emission_energy_multiplier = 3.0
	visor.material = visor_mat
	head.add_child(visor)

	return body

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 3.2, 1.8)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 1.6, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_create_health_bar()
	EventBus.boss_wave_started.emit()

# ---------------------------------------------------------------------------
# Health bar
# ---------------------------------------------------------------------------

func _create_health_bar() -> void:
	var bar_width := 3.0
	var bar_height := 0.15
	_health_bar_bg = CSGBox3D.new()
	_health_bar_bg.size = Vector3(bar_width, bar_height, 0.05)
	_health_bar_bg.position = Vector3(0.0, 5.0, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 5.0, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(1.0, 0.5, 0.0)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(1.0, 0.5, 0.0)
	_health_bar_mat.emission_energy_multiplier = 1.0
	_health_bar_fill.material = _health_bar_mat
	add_child(_health_bar_fill)

func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	var ratio := get_health_ratio()
	var full_width := 2.95
	_health_bar_fill.size.x = full_width * ratio
	var offset := (full_width - _health_bar_fill.size.x) * 0.5
	_health_bar_fill.position.x = -offset
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
	for bar in [_health_bar_bg, _health_bar_fill]:
		if bar:
			var dir := cam.global_position - bar.global_position
			dir.y = 0.0
			if dir.length() > 0.01:
				bar.look_at(bar.global_position + dir, Vector3.UP)

# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# -- Flash timer
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and _mesh is CSGPrimitive3D:
			(_mesh as CSGPrimitive3D).material = _base_material

	# -- Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# -- Knockback decay
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 2.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	_update_phase()
	_update_health_bar()
	_face_health_bar_to_camera()

	# -- Charge movement override
	if _is_charging:
		_charge_elapsed += delta
		velocity.x = _charge_dir.x * CHARGE_SPEED
		velocity.z = _charge_dir.z * CHARGE_SPEED
		move_and_slide()
		if _charge_elapsed >= CHARGE_DURATION:
			_is_charging = false
			_execute_charge_hit()
		return

	# -- Normal movement
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

	# -- Timers
	_hammer_timer -= delta
	_slag_timer -= delta
	_turret_timer -= delta
	_charge_timer -= delta
	_flame_timer -= delta

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
	if _core_mat:
		_core_mat.emission_energy_multiplier = 4.0

func _on_enter_phase_three() -> void:
	# Overheat — glow intensely
	if _core_mat:
		_core_mat.emission_energy_multiplier = 8.0
		_core_mat.emission = Color(1.0, 0.7, 0.1)
	if _base_material:
		_base_material.emission_energy_multiplier = 2.0
		_base_material.emission = Color(0.6, 0.25, 0.0)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.4)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= HAMMER_SLAM_RANGE and _hammer_timer <= 0.0:
		_hammer_slam(player)
	if _slag_timer <= 0.0:
		_throw_slag_bomb(player)

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= HAMMER_SLAM_RANGE and _hammer_timer <= 0.0:
		_hammer_slam(player)
	if _slag_timer <= 0.0:
		_throw_slag_bomb(player)
	if _turret_timer <= 0.0:
		_deploy_turret()
	if _charge_timer <= 0.0 and dist > 5.0:
		_begin_charge(player)

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= HAMMER_SLAM_RANGE and _hammer_timer <= 0.0:
		_hammer_slam(player, ENRAGE_ATTACK_MULT)
	if _slag_timer <= 0.0:
		_throw_slag_bomb(player)
	if _flame_timer <= 0.0:
		_flame_burst()
	if _charge_timer <= 0.0 and dist > 4.0:
		_begin_charge(player)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _hammer_slam(player: Node3D, extra_mult: float = 1.0) -> void:
	_is_attacking = true
	_hammer_timer = HAMMER_SLAM_COOLDOWN

	# Telegraph: raise arms (mesh scale Y)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale:y", 1.25, 0.4)
		tw.tween_callback(_execute_hammer.bind(player, extra_mult))
		tw.tween_property(_mesh, "scale:y", 1.0, 0.15)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_hammer(player, extra_mult)
		_is_attacking = false

func _execute_hammer(player: Node3D, extra_mult: float) -> void:
	if not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > HAMMER_SLAM_RANGE * 1.3:
		return
	var effective_damage := base_damage * wave_dmg_mult * HAMMER_SLAM_DAMAGE_MULT * extra_mult
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)

func _throw_slag_bomb(target: Node3D) -> void:
	_slag_timer = SLAG_BOMB_COOLDOWN
	if current_phase == Phase.THREE:
		_slag_timer *= 0.6

	var spawn_pos := global_position + Vector3(0, 2.5, 0)
	var target_pos := target.global_position
	var dir := (target_pos - spawn_pos).normalized()

	var proj := _SlagBombProjectile.new()
	proj.global_position = spawn_pos
	proj.direction = dir
	proj.projectile_speed = SLAG_BOMB_SPEED
	proj.damage = base_damage * wave_dmg_mult * 0.6
	proj.fire_pool_damage = base_damage * wave_dmg_mult * 0.3
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _deploy_turret() -> void:
	_turret_timer = TURRET_DEPLOY_COOLDOWN
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var minion := EnemyRanged.new()
	var angle := randf() * TAU
	var offset := Vector3(cos(angle) * 4.0, 0.0, sin(angle) * 4.0)
	var spawn_pos := global_position + offset
	spawn_pos.y = global_position.y
	minion.initialize(wave_hp_mult * 0.3, wave_dmg_mult * 0.5, 0.0)  # speed 0 = stationary
	scene_root.add_child(minion)
	minion.global_position = spawn_pos
	GameManager.register_enemies(1)

func _begin_charge(target: Node3D) -> void:
	_charge_timer = CHARGE_COOLDOWN
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	_charge_dir = to_player.normalized()
	_charge_elapsed = 0.0
	_is_charging = true

	# Telegraph: core flares bright
	if _core_mat:
		_core_mat.emission_energy_multiplier += 4.0

func _execute_charge_hit() -> void:
	if _core_mat:
		_core_mat.emission_energy_multiplier = maxf(_core_mat.emission_energy_multiplier - 4.0, 3.0)
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= 4.0:
			var effective_damage := base_damage * wave_dmg_mult * 1.2
			if player.has_method("take_damage"):
				player.take_damage(effective_damage, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 14.0

func _flame_burst() -> void:
	_flame_timer = FLAME_BURST_COOLDOWN

	# Telegraph: core glows bright before burst
	if _core_mat:
		var orig := _core_mat.emission_energy_multiplier
		_core_mat.emission_energy_multiplier = 12.0
		get_tree().create_timer(0.4).timeout.connect(func():
			if _core_mat:
				_core_mat.emission_energy_multiplier = orig
		)

	# Delayed burst
	get_tree().create_timer(0.4).timeout.connect(_execute_flame_burst)

func _execute_flame_burst() -> void:
	if not is_alive:
		return
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= FLAME_BURST_RADIUS:
			var falloff := 1.0 - (dist / FLAME_BURST_RADIUS) * 0.5
			var dmg := base_damage * wave_dmg_mult * FLAME_BURST_DAMAGE_MULT * falloff
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
	_spawn_flame_ring()

func _spawn_flame_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.15
	ring.sides = 24
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", FLAME_BURST_RADIUS, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Damage / Death
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir * 0.2)

func die() -> void:
	if not is_alive:
		return
	is_alive = false

	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)
	_drop_health()
	_drop_health()
	_drop_ammo()
	_drop_ammo()
	_drop_bomb_ammo()

	EventBus.enemy_killed.emit(self, global_position)
	EventBus.boss_killed.emit()

	_boss_death_effect()
	queue_free()

func _boss_death_effect() -> void:
	for i in 4:
		get_tree().create_timer(i * 0.2).timeout.connect(
			_spawn_death_ring.bind(i)
		)

func _spawn_death_ring(index: int) -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.3
	ring.height = 0.15
	ring.sides = 28
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.9)
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
		tw.tween_property(ring, "radius", 8.0, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Inner class: Slag bomb projectile (arcs and leaves fire pool)
# ---------------------------------------------------------------------------

class _SlagBombProjectile:
	extends Area3D

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 10.0
	var damage: float = 12.0
	var fire_pool_damage: float = 5.0
	var _lifetime: float = 4.0
	var _arc_time: float = 0.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2 | 1  # Player + Environment

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.25
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.4, 0.0)
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
		_arc_time += delta
		# Arc upward then downward
		var arc_y := 4.0 * _arc_time - 5.0 * _arc_time * _arc_time
		global_position += direction * projectile_speed * delta
		global_position.y += arc_y * delta
		_lifetime -= delta
		if _lifetime <= 0.0 or global_position.y < -5.0:
			_spawn_fire_pool()
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(damage, self)
		_spawn_fire_pool()
		queue_free()

	func _spawn_fire_pool() -> void:
		var pool := CSGCylinder3D.new()
		pool.radius = 2.0
		pool.height = 0.08
		pool.sides = 16
		pool.global_position = global_position
		pool.global_position.y = 0.05
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.0, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.0)
		mat.emission_energy_multiplier = 2.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pool.material = mat
		var scene_root := Engine.get_main_loop().current_scene if Engine.get_main_loop() else null
		if scene_root:
			scene_root.add_child(pool)
			# Pool fades out after 4 seconds
			var tw := pool.create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, 4.0)
			tw.tween_callback(pool.queue_free)
