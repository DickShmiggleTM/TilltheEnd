class_name BossTunnelHorror
extends EnemyBase
## THE BROODMOTHER — Level 3 Boss.
##
## A massive spider-like creature lurking in the tunnels.
##
## Phase 1 (100-65%): Rapid charges, web shot (slows player), spawns 3-4
##   small fast enemies.
## Phase 2 (65-30%): Ceiling hang (briefly invulnerable), drops for massive
##   AoE. Poison spit projectiles.
## Phase 3 (30-0%): Enraged — constant spawning of small enemies, rapid
##   multi-directional poison spray.
##
## Visual: Purple/dark CSGSphere3D body with 4 CSGCylinder3D legs extending out.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 1500.0
	base_damage = 20.0
	speed = 3.5
	attack_range = 3.0
	attack_cooldown = 1.5
	base_exp_drop = 600.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Broodmother"

const PHASE_2_THRESHOLD := 0.65
const PHASE_3_THRESHOLD := 0.30

const CHARGE_SPEED := 10.0
const CHARGE_DURATION := 0.5
const CHARGE_COOLDOWN := 5.0
const WEB_SHOT_COOLDOWN := 6.0
const WEB_SHOT_SPEED := 16.0
const WEB_SLOW_DURATION := 2.5
const BROOD_SPAWN_COOLDOWN := 8.0
const BROOD_COUNT_P1 := 3
const BROOD_COUNT_P3 := 5
const CEILING_DROP_COOLDOWN := 10.0
const CEILING_HANG_DURATION := 1.5
const CEILING_DROP_RADIUS := 6.0
const CEILING_DROP_DAMAGE_MULT := 2.0
const POISON_SPIT_COOLDOWN := 3.5
const POISON_SPIT_SPEED := 13.0
const POISON_SPRAY_COUNT := 8
const POISON_SPRAY_COOLDOWN := 4.0
const ENRAGE_SPEED_MULT := 1.3

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _charge_timer: float = CHARGE_COOLDOWN
var _web_timer: float = WEB_SHOT_COOLDOWN
var _brood_timer: float = BROOD_SPAWN_COOLDOWN
var _ceiling_timer: float = CEILING_DROP_COOLDOWN
var _poison_timer: float = POISON_SPIT_COOLDOWN
var _spray_timer: float = POISON_SPRAY_COOLDOWN
var _is_attacking: bool = false
var _is_charging: bool = false
var _is_hanging: bool = false
var _is_invulnerable: bool = false
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_elapsed: float = 0.0
var _hang_elapsed: float = 0.0
var _original_y: float = 0.0

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Leg references for animation
var _legs: Array[CSGCylinder3D] = []

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.3, 0.1, 0.35)  # Dark purple

func _create_mesh() -> Node3D:
	# Main body — large sphere
	var body := CSGSphere3D.new()
	body.radius = 1.5
	body.radial_segments = 16
	body.rings = 8
	body.position = Vector3(0.0, 1.8, 0.0)

	# Abdomen — elongated sphere behind
	var abdomen := CSGSphere3D.new()
	abdomen.radius = 1.2
	abdomen.radial_segments = 12
	abdomen.rings = 6
	abdomen.position = Vector3(0.0, -0.2, 1.2)
	var abd_mat := StandardMaterial3D.new()
	abd_mat.albedo_color = Color(0.25, 0.08, 0.3)
	abd_mat.emission_enabled = true
	abd_mat.emission = Color(0.2, 0.05, 0.25)
	abd_mat.emission_energy_multiplier = 0.5
	abdomen.material = abd_mat
	body.add_child(abdomen)

	# Eyes — cluster of small red spheres
	var eye_positions := [
		Vector3(-0.4, 0.3, -1.3),
		Vector3(0.4, 0.3, -1.3),
		Vector3(-0.2, 0.5, -1.35),
		Vector3(0.2, 0.5, -1.35),
	]
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.1, 0.1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.1, 0.1)
	eye_mat.emission_energy_multiplier = 3.0

	for pos in eye_positions:
		var eye := CSGSphere3D.new()
		eye.radius = 0.12
		eye.radial_segments = 6
		eye.rings = 4
		eye.position = pos
		eye.material = eye_mat
		body.add_child(eye)

	# Legs — 4 long cylinders
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.2, 0.08, 0.25)
	leg_mat.emission_enabled = true
	leg_mat.emission = Color(0.15, 0.05, 0.2)
	leg_mat.emission_energy_multiplier = 0.3

	var leg_angles := [-45.0, -135.0, 45.0, 135.0]
	var leg_rotations := [30.0, 30.0, -30.0, -30.0]

	for i in 4:
		var leg := CSGCylinder3D.new()
		leg.radius = 0.12
		leg.height = 2.5
		leg.sides = 6
		var angle_rad := deg_to_rad(leg_angles[i])
		leg.position = Vector3(cos(angle_rad) * 1.0, -0.5, sin(angle_rad) * 1.0)
		leg.rotation_degrees = Vector3(leg_rotations[i], leg_angles[i], 0)
		leg.material = leg_mat
		body.add_child(leg)
		_legs.append(leg)

	return body

func _create_collision_shape() -> Shape3D:
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	return shape

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 1.8, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_create_health_bar()
	_original_y = global_position.y
	EventBus.boss_wave_started.emit()

# ---------------------------------------------------------------------------
# Health bar
# ---------------------------------------------------------------------------

func _create_health_bar() -> void:
	var bar_width := 3.0
	var bar_height := 0.15
	_health_bar_bg = CSGBox3D.new()
	_health_bar_bg.size = Vector3(bar_width, bar_height, 0.05)
	_health_bar_bg.position = Vector3(0.0, 4.5, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 4.5, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.6, 0.1, 0.7)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.6, 0.1, 0.7)
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
			_health_bar_mat.albedo_color = Color(0.8, 0.3, 0.1)
			_health_bar_mat.emission = Color(0.8, 0.3, 0.1)

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
# Override damage — invulnerable while hanging
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if _is_invulnerable:
		return
	super.take_damage(amount, knockback_dir * 0.2)

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

	# -- Gravity (when not hanging)
	if not _is_hanging:
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

	# -- Ceiling hang logic
	if _is_hanging:
		_hang_elapsed += delta
		velocity = Vector3.ZERO
		if _hang_elapsed >= CEILING_HANG_DURATION:
			_ceiling_drop()
		return

	# -- Charge movement
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
	_charge_timer -= delta
	_web_timer -= delta
	_brood_timer -= delta
	_ceiling_timer -= delta
	_poison_timer -= delta
	_spray_timer -= delta

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
	if _base_material:
		_base_material.emission_energy_multiplier = 1.5
		_base_material.emission = Color(0.4, 0.1, 0.5)

func _on_enter_phase_three() -> void:
	if _base_material:
		_base_material.emission_energy_multiplier = 3.0
		_base_material.emission = Color(0.6, 0.15, 0.7)
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
	var dist := global_position.distance_to(player.global_position)

	if _charge_timer <= 0.0 and dist > 4.0:
		_begin_charge(player)
	if _web_timer <= 0.0:
		_fire_web_shot(player)
	if _brood_timer <= 0.0:
		_spawn_brood(BROOD_COUNT_P1)

	# Melee bite
	if dist <= attack_range and _attack_timer <= 0.0:
		_bite_attack(player)

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _ceiling_timer <= 0.0:
		_begin_ceiling_hang()
	if _poison_timer <= 0.0:
		_fire_poison_spit(player)
	if _web_timer <= 0.0:
		_fire_web_shot(player)
	if _brood_timer <= 0.0:
		_spawn_brood(BROOD_COUNT_P1 + 1)

	if dist <= attack_range and _attack_timer <= 0.0:
		_bite_attack(player)

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _spray_timer <= 0.0:
		_poison_spray()
	if _brood_timer <= 0.0:
		_spawn_brood(BROOD_COUNT_P3)
	if _charge_timer <= 0.0 and dist > 3.0:
		_begin_charge(player)
	if _poison_timer <= 0.0:
		_fire_poison_spit(player)

	if dist <= attack_range and _attack_timer <= 0.0:
		_bite_attack(player, 1.3)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _bite_attack(player: Node3D, extra_mult: float = 1.0) -> void:
	_attack_timer = attack_cooldown
	var effective_damage := base_damage * wave_dmg_mult * extra_mult
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.15, 0.9, 1.15), 0.08)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.12)

func _begin_charge(target: Node3D) -> void:
	_charge_timer = CHARGE_COOLDOWN
	# Telegraph: rear up
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale:y", 1.3, 0.3)
		tw.tween_callback(func():
			var to_player := target.global_position - global_position
			to_player.y = 0.0
			_charge_dir = to_player.normalized()
			_charge_elapsed = 0.0
			_is_charging = true
		)
		tw.tween_property(_mesh, "scale:y", 1.0, 0.1)
	else:
		var to_player := target.global_position - global_position
		to_player.y = 0.0
		_charge_dir = to_player.normalized()
		_charge_elapsed = 0.0
		_is_charging = true

func _execute_charge_hit() -> void:
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= 3.5:
			var dmg := base_damage * wave_dmg_mult * 1.3
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 10.0

func _fire_web_shot(target: Node3D) -> void:
	_web_timer = WEB_SHOT_COOLDOWN
	var spawn_pos := global_position + Vector3(0, 1.5, 0)
	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()

	var proj := _WebProjectile.new()
	proj.global_position = spawn_pos
	proj.direction = dir
	proj.projectile_speed = WEB_SHOT_SPEED
	proj.slow_duration = WEB_SLOW_DURATION
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _fire_poison_spit(target: Node3D) -> void:
	_poison_timer = POISON_SPIT_COOLDOWN
	var spawn_pos := global_position + Vector3(0, 1.5, 0)
	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()

	var proj := _PoisonProjectile.new()
	proj.global_position = spawn_pos
	proj.direction = dir
	proj.projectile_speed = POISON_SPIT_SPEED
	proj.damage = base_damage * wave_dmg_mult * 0.6
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _poison_spray() -> void:
	_spray_timer = POISON_SPRAY_COOLDOWN

	# Telegraph: abdomen pulses
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.2)
		tw.tween_callback(_execute_poison_spray)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.15)
	else:
		_execute_poison_spray()

func _execute_poison_spray() -> void:
	if not is_alive:
		return
	var spawn_pos := global_position + Vector3(0, 1.5, 0)
	for i in POISON_SPRAY_COUNT:
		var angle := (TAU / float(POISON_SPRAY_COUNT)) * float(i)
		var dir := Vector3(cos(angle), 0.1, sin(angle)).normalized()
		var proj := _PoisonProjectile.new()
		proj.global_position = spawn_pos
		proj.direction = dir
		proj.projectile_speed = POISON_SPIT_SPEED * 0.8
		proj.damage = base_damage * wave_dmg_mult * 0.4
		var scene_root := get_tree().current_scene
		if scene_root:
			scene_root.add_child(proj)

func _begin_ceiling_hang() -> void:
	_ceiling_timer = CEILING_DROP_COOLDOWN
	_is_hanging = true
	_is_invulnerable = true
	_hang_elapsed = 0.0
	_original_y = global_position.y

	# Ascend quickly
	if _mesh:
		var tw := create_tween()
		tw.tween_property(self, "global_position:y", _original_y + 8.0, 0.4).set_ease(Tween.EASE_IN)
		# Fade mesh to indicate invulnerability
		if _base_material:
			_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tw.tween_property(_base_material, "albedo_color:a", 0.4, 0.3)

func _ceiling_drop() -> void:
	_is_hanging = false
	_is_invulnerable = false

	if _base_material:
		_base_material.albedo_color.a = 1.0
		_base_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	# Target the player's current position
	var player := get_player()
	var drop_target := global_position
	drop_target.y = _original_y
	if player and is_instance_valid(player):
		drop_target = player.global_position
		drop_target.y = _original_y

	# Teleport above target, then slam down
	global_position.x = drop_target.x
	global_position.z = drop_target.z

	var tw := create_tween()
	tw.tween_property(self, "global_position:y", _original_y, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(_execute_ceiling_drop)

func _execute_ceiling_drop() -> void:
	var drop_damage := base_damage * wave_dmg_mult * CEILING_DROP_DAMAGE_MULT
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= CEILING_DROP_RADIUS:
			var falloff := 1.0 - (dist / CEILING_DROP_RADIUS) * 0.6
			if player.has_method("take_damage"):
				player.take_damage(drop_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 12.0
	_spawn_drop_ring()

func _spawn_drop_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.1
	ring.sides = 24
	ring.global_position = global_position + Vector3(0, 0.1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.1, 0.6, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.6)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", CEILING_DROP_RADIUS, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Minion spawning
# ---------------------------------------------------------------------------

func _spawn_brood(count: int) -> void:
	_brood_timer = BROOD_SPAWN_COOLDOWN
	if current_phase == Phase.THREE:
		_brood_timer *= 0.5

	# Telegraph: abdomen pulses
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.15)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.1)

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in count:
		var minion := EnemyFast.new()
		var angle := (TAU / float(count)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y
		minion.initialize(wave_hp_mult * 0.3, wave_dmg_mult * 0.4, wave_speed_mult * 1.2)
		scene_root.add_child(minion)
		minion.global_position = spawn_pos
		GameManager.register_enemies(1)

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
	ring.height = 0.12
	ring.sides = 28
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.4, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.1, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.6)
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
# Inner class: Web projectile (slows player)
# ---------------------------------------------------------------------------

class _WebProjectile:
	extends Area3D

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 16.0
	var slow_duration: float = 2.5
	var _lifetime: float = 5.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var mesh := CSGSphere3D.new()
		mesh.radius = 0.2
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 0.9, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.8, 0.8)
		mat.emission_energy_multiplier = 1.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		add_child(mesh)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.2
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
			# Apply slow effect if player has the property
			if body.has_method("apply_slow"):
				body.apply_slow(0.4, slow_duration)
			body.take_damage(3.0, self)
		queue_free()

# ---------------------------------------------------------------------------
# Inner class: Poison projectile
# ---------------------------------------------------------------------------

class _PoisonProjectile:
	extends Area3D

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 13.0
	var damage: float = 10.0
	var _lifetime: float = 5.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.18
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.9, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.9, 0.1)
		mat.emission_energy_multiplier = 2.5
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.18
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
