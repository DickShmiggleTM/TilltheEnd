class_name BossForestGuardian
extends EnemyBase
## THE BLIGHTED WARDEN — Level 1 Boss.
##
## A massive tree-like creature corrupted by blight.
##
## Phase 1 (100-50%): Charges player, melee swipe attacks. Summons 2 root
##   tendrils (small enemies spawned from ground).
## Phase 2 (50-0%): Becomes faster, fires "thorn" projectiles in a spread.
##   Ground slam that creates a damaging area around self.
##
## Visual: Large brown/green CSGCylinder3D trunk with CSGBox3D branch "arms".

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 800.0
	base_damage = 16.0
	speed = 3.0
	attack_range = 3.0
	attack_cooldown = 1.8
	base_exp_drop = 300.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Blighted Warden"

## Phase threshold
const PHASE_2_THRESHOLD := 0.5

## Attack parameters
const SWIPE_RANGE := 4.0
const SWIPE_DAMAGE_MULT := 1.2
const SWIPE_COOLDOWN := 2.0
const THORN_COUNT := 3
const THORN_SPEED := 14.0
const THORN_COOLDOWN := 3.0
const ROOT_SLAM_RADIUS := 5.5
const ROOT_SLAM_DAMAGE_MULT := 1.5
const ROOT_SLAM_COOLDOWN := 6.0
const TENDRIL_SPAWN_COOLDOWN := 10.0
const PHASE2_SPEED_MULT := 1.4

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO }
var current_phase: Phase = Phase.ONE

var _swipe_timer: float = SWIPE_COOLDOWN
var _thorn_timer: float = THORN_COOLDOWN
var _slam_timer: float = ROOT_SLAM_COOLDOWN
var _tendril_timer: float = TENDRIL_SPAWN_COOLDOWN
var _is_attacking: bool = false
var _telegraph_timer: float = 0.0

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Branch arm references for telegraph animation
var _left_arm: CSGBox3D = null
var _right_arm: CSGBox3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.35, 0.25, 0.1)  # Dark brown bark

func _create_mesh() -> Node3D:
	# Main trunk — tall cylinder
	var trunk := CSGCylinder3D.new()
	trunk.radius = 0.8
	trunk.height = 3.0
	trunk.sides = 12
	trunk.position = Vector3(0.0, 1.5, 0.0)

	# Crown / canopy — green sphere on top
	var canopy := CSGSphere3D.new()
	canopy.radius = 1.2
	canopy.radial_segments = 12
	canopy.rings = 6
	canopy.position = Vector3(0.0, 1.8, 0.0)
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.15, 0.4, 0.1)
	canopy_mat.emission_enabled = true
	canopy_mat.emission = Color(0.1, 0.3, 0.05)
	canopy_mat.emission_energy_multiplier = 0.4
	canopy.material = canopy_mat
	trunk.add_child(canopy)

	# Left branch arm
	_left_arm = CSGBox3D.new()
	_left_arm.size = Vector3(1.6, 0.3, 0.3)
	_left_arm.position = Vector3(-1.2, 1.0, 0.0)
	_left_arm.rotation_degrees = Vector3(0, 0, -20)
	var branch_mat := StandardMaterial3D.new()
	branch_mat.albedo_color = Color(0.3, 0.22, 0.08)
	branch_mat.emission_enabled = true
	branch_mat.emission = Color(0.2, 0.15, 0.05)
	branch_mat.emission_energy_multiplier = 0.3
	_left_arm.material = branch_mat
	trunk.add_child(_left_arm)

	# Right branch arm
	_right_arm = CSGBox3D.new()
	_right_arm.size = Vector3(1.6, 0.3, 0.3)
	_right_arm.position = Vector3(1.2, 1.0, 0.0)
	_right_arm.rotation_degrees = Vector3(0, 0, 20)
	_right_arm.material = branch_mat
	trunk.add_child(_right_arm)

	# Glowing eye knots on trunk
	var eye_l := CSGSphere3D.new()
	eye_l.radius = 0.15
	eye_l.radial_segments = 8
	eye_l.rings = 4
	eye_l.position = Vector3(-0.3, 1.5, -0.75)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.4, 1.0, 0.2)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.4, 1.0, 0.2)
	eye_mat.emission_energy_multiplier = 2.5
	eye_l.material = eye_mat
	trunk.add_child(eye_l)

	var eye_r := CSGSphere3D.new()
	eye_r.radius = 0.15
	eye_r.radial_segments = 8
	eye_r.rings = 4
	eye_r.position = Vector3(0.3, 1.5, -0.75)
	eye_r.material = eye_mat
	trunk.add_child(eye_r)

	return trunk

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 1.5, 0.0)

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
	_health_bar_bg.position = Vector3(0.0, 4.2, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 4.2, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.2, 0.8, 0.1)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.2, 0.8, 0.1)
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
		if ratio <= PHASE_2_THRESHOLD:
			_health_bar_mat.albedo_color = Color(0.8, 0.4, 0.1)
			_health_bar_mat.emission = Color(0.8, 0.4, 0.1)

func _face_health_bar_to_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for bar in [_health_bar_bg, _health_bar_fill]:
		if bar:
			var dir: Vector3 = cam.global_position - bar.global_position
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

	# -- Knockback decay (boss resists knockback)
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 2.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Update phase
	_update_phase()
	_update_health_bar()
	_face_health_bar_to_camera()

	# -- Movement
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
	if current_phase == Phase.TWO:
		speed_mult = PHASE2_SPEED_MULT

	var effective_speed := speed * wave_speed_mult * slow_mult * speed_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Attack timers
	_swipe_timer -= delta
	_thorn_timer -= delta
	_slam_timer -= delta
	_tendril_timer -= delta

	match current_phase:
		Phase.ONE:
			_phase_one_logic(delta)
		Phase.TWO:
			_phase_two_logic(delta)

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

func _update_phase() -> void:
	var ratio := get_health_ratio()
	if ratio <= PHASE_2_THRESHOLD and current_phase == Phase.ONE:
		current_phase = Phase.TWO
		_on_enter_phase_two()

func _on_enter_phase_two() -> void:
	# Glow green — thorn mode activated
	if _base_material:
		_base_material.emission_energy_multiplier = 1.8
		_base_material.emission = Color(0.3, 0.7, 0.1)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.1, 1.15, 1.1), 0.4)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	# Melee swipe
	if dist <= SWIPE_RANGE and _swipe_timer <= 0.0:
		_melee_swipe(player)

	# Spawn root tendrils
	if _tendril_timer <= 0.0:
		_spawn_root_tendrils(2)
		_tendril_timer = TENDRIL_SPAWN_COOLDOWN

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)

	# Thorn barrage
	if _thorn_timer <= 0.0:
		_fire_thorn_barrage(player)

	# Root slam AoE
	if dist <= ROOT_SLAM_RADIUS and _slam_timer <= 0.0:
		_root_slam()

	# Still does melee
	if dist <= SWIPE_RANGE and _swipe_timer <= 0.0:
		_melee_swipe(player)

	# Faster tendril spawns in phase 2
	if _tendril_timer <= 0.0:
		_spawn_root_tendrils(3)
		_tendril_timer = TENDRIL_SPAWN_COOLDOWN * 0.7

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _melee_swipe(player: Node3D) -> void:
	_is_attacking = true
	_swipe_timer = SWIPE_COOLDOWN

	# Telegraph: grow taller for 0.5s, then strike
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale:y", 1.3, 0.5)
		tw.tween_callback(_execute_swipe.bind(player))
		tw.tween_property(_mesh, "scale:y", 1.0, 0.2)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_swipe(player)
		_is_attacking = false

func _execute_swipe(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > SWIPE_RANGE * 1.3:
		return
	var effective_damage := base_damage * wave_dmg_mult * SWIPE_DAMAGE_MULT
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)

func _fire_thorn_barrage(target: Node3D) -> void:
	_thorn_timer = THORN_COOLDOWN

	# Telegraph: glow green briefly
	if _base_material:
		var orig_emission := _base_material.emission_energy_multiplier
		_base_material.emission_energy_multiplier = 4.0
		get_tree().create_timer(0.3).timeout.connect(func():
			if _base_material:
				_base_material.emission_energy_multiplier = orig_emission
		)

	var target_pos := target.global_position + Vector3(0, 0.9, 0)
	var spawn_pos := global_position + Vector3(0, 2.0, 0)
	var base_dir := (target_pos - spawn_pos).normalized()

	for i in THORN_COUNT:
		var angle_offset := deg_to_rad(-15.0 + (30.0 / float(THORN_COUNT)) * float(i))
		var rotated_dir := base_dir.rotated(Vector3.UP, angle_offset)
		get_tree().create_timer(i * 0.1).timeout.connect(
			_spawn_thorn_projectile.bind(spawn_pos, rotated_dir)
		)

func _spawn_thorn_projectile(pos: Vector3, dir: Vector3) -> void:
	if not is_alive:
		return
	var proj := _ThornProjectile.new()
	proj.global_position = pos
	proj.direction = dir
	proj.projectile_speed = THORN_SPEED
	proj.damage = base_damage * wave_dmg_mult * 0.7
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _root_slam() -> void:
	_is_attacking = true
	_slam_timer = ROOT_SLAM_COOLDOWN

	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "position:y", _mesh.position.y + 0.5, 0.35)
		tw.tween_callback(_execute_root_slam)
		tw.tween_property(_mesh, "position:y", _mesh.position.y, 0.15)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_root_slam()
		_is_attacking = false

func _execute_root_slam() -> void:
	var slam_damage := base_damage * wave_dmg_mult * ROOT_SLAM_DAMAGE_MULT
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= ROOT_SLAM_RADIUS:
			var falloff := 1.0 - (dist / ROOT_SLAM_RADIUS) * 0.5
			if player.has_method("take_damage"):
				player.take_damage(slam_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 8.0
	_spawn_slam_ring()

func _spawn_slam_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.1
	ring.sides = 24
	ring.global_position = global_position + Vector3(0, 0.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.1, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", ROOT_SLAM_RADIUS, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Minion spawning
# ---------------------------------------------------------------------------

func _spawn_root_tendrils(count: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in count:
		var minion := EnemyMelee.new()
		var angle := (TAU / float(count)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 3.5, 0.0, sin(angle) * 3.5)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y
		minion.initialize(wave_hp_mult * 0.3, wave_dmg_mult * 0.4, wave_speed_mult)
		scene_root.add_child(minion)
		minion.global_position = spawn_pos
		GameManager.register_enemies(1)

# ---------------------------------------------------------------------------
# Damage override — boss resists knockback
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir * 0.3)

# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------

func die() -> void:
	if not is_alive:
		return
	is_alive = false

	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)
	_drop_health()
	_drop_ammo()
	_drop_ammo()

	EventBus.enemy_killed.emit(self, global_position)
	EventBus.boss_killed.emit()

	_boss_death_effect()
	queue_free()

func _boss_death_effect() -> void:
	for i in 3:
		get_tree().create_timer(i * 0.25).timeout.connect(
			_spawn_death_ring.bind(i)
		)

func _spawn_death_ring(index: int) -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.3
	ring.height = 0.12
	ring.sides = 28
	ring.global_position = global_position + Vector3(0, 0.4 + index * 0.4, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", 7.0, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Inner class: Thorn projectile
# ---------------------------------------------------------------------------

class _ThornProjectile extends Area3D:

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 14.0
	var damage: float = 10.0
	var _lifetime: float = 5.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var thorn := CSGBox3D.new()
		thorn.size = Vector3(0.1, 0.1, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.8, 0.1)
		mat.emission_energy_multiplier = 2.0
		thorn.material = mat
		add_child(thorn)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.15
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
