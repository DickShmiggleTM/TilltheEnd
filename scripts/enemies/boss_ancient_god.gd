class_name BossAncientGod
extends EnemyBase
## THE NAMELESS ONE — Level 7 FINAL BOSS.
##
## An enormous eldritch horror that defies comprehension. A towering mass of
## shifting dark matter, covered in watchful eyes and grasping tentacles.
##
## Phase 1 (100-70%): Reality-warping attacks — dimensional rift projectiles,
##   massive sweeping tentacle attacks, summons void orbs that chase the player.
## Phase 2 (70-40%): Summons waves of cultist enemies while attacking. Creates
##   void zones on the ground that damage and slow. Eye beams tracking player.
## Phase 3 (40-15%): All-out — tentacle slam combos, void explosions, gravity
##   pulses (knockback), constant enemy spawns.
## Phase 4 (15-0%): DESPERATION — fastest attacks, most damage, but becomes
##   briefly stunnable after each big attack (takes 2x damage during stun).
##
## On death: special dissolve effect — lingers for 2 seconds with scale down.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 5000.0
	base_damage = 50.0
	speed = 2.5
	attack_range = 5.0
	attack_cooldown = 2.0
	base_exp_drop = 2000.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Nameless One"

const PHASE_2_THRESHOLD := 0.70
const PHASE_3_THRESHOLD := 0.40
const PHASE_4_THRESHOLD := 0.15

const VOID_RIFT_COOLDOWN := 2.5
const VOID_RIFT_SPEED := 10.0
const VOID_RIFT_HOMING := 2.5
const TENTACLE_SWEEP_RANGE := 8.0
const TENTACLE_SWEEP_COOLDOWN := 4.0
const TENTACLE_SWEEP_DAMAGE_MULT := 1.3
const VOID_ORB_COOLDOWN := 6.0
const VOID_ORB_SPEED := 5.0
const VOID_ORB_HOMING := 4.0
const CULTIST_SPAWN_COOLDOWN := 8.0
const CULTIST_COUNT := 3
const VOID_ZONE_COOLDOWN := 5.0
const VOID_ZONE_RADIUS := 3.5
const VOID_ZONE_DURATION := 7.0
const EYE_BEAM_COOLDOWN := 5.0
const EYE_BEAM_RANGE := 20.0
const EYE_BEAM_DURATION := 2.0
const EYE_BEAM_DPS_MULT := 0.4
const TENTACLE_SLAM_COOLDOWN := 3.5
const TENTACLE_SLAM_RADIUS := 6.0
const TENTACLE_SLAM_DAMAGE_MULT := 1.5
const GRAVITY_PULSE_COOLDOWN := 7.0
const GRAVITY_PULSE_RADIUS := 10.0
const GRAVITY_PULSE_FORCE := 18.0
const DIMENSIONAL_TEAR_COOLDOWN := 10.0
const DIMENSIONAL_TEAR_RADIUS := 8.0
const DIMENSIONAL_TEAR_DAMAGE_MULT := 2.0
const STUN_DURATION := 1.5
const STUN_DAMAGE_MULT := 2.0

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE, FOUR }
var current_phase: Phase = Phase.ONE

var _rift_timer: float = VOID_RIFT_COOLDOWN
var _sweep_timer: float = TENTACLE_SWEEP_COOLDOWN
var _orb_timer: float = VOID_ORB_COOLDOWN
var _cultist_timer: float = CULTIST_SPAWN_COOLDOWN
var _zone_timer: float = VOID_ZONE_COOLDOWN
var _beam_timer: float = EYE_BEAM_COOLDOWN
var _slam_timer: float = TENTACLE_SLAM_COOLDOWN
var _gravity_timer: float = GRAVITY_PULSE_COOLDOWN
var _tear_timer: float = DIMENSIONAL_TEAR_COOLDOWN
var _is_attacking: bool = false
var _is_beaming: bool = false
var _beam_elapsed: float = 0.0
var _is_stunned: bool = false
var _stun_elapsed: float = 0.0
var _dissolve_started: bool = false

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Visual references
var _eye_nodes: Array[CSGSphere3D] = []
var _eye_mat: StandardMaterial3D = null
var _tentacles: Array[CSGCylinder3D] = []
var _body_mat: StandardMaterial3D = null
var _color_shift_time: float = 0.0

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.15, 0.02, 0.2)  # Dark eldritch purple

func _create_mesh() -> Node3D:
	# Massive central body
	var body := CSGBox3D.new()
	body.size = Vector3(3.5, 5.0, 3.0)
	body.position = Vector3(0.0, 2.5, 0.0)

	# Store a reference to the body material for color shifting
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.15, 0.02, 0.2)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.1, 0.0, 0.15)
	_body_mat.emission_energy_multiplier = 0.5
	body.material = _body_mat

	# Crown / crest on top
	var crown := CSGBox3D.new()
	crown.size = Vector3(2.0, 1.2, 1.5)
	crown.position = Vector3(0.0, 3.0, 0.0)
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.1, 0.0, 0.15)
	crown_mat.emission_enabled = true
	crown_mat.emission = Color(0.15, 0.0, 0.2)
	crown_mat.emission_energy_multiplier = 0.8
	crown.material = crown_mat
	body.add_child(crown)

	# Multiple eye nodes scattered on the body
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.8, 0.0, 1.0)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.8, 0.0, 1.0)
	_eye_mat.emission_energy_multiplier = 4.0

	var eye_positions := [
		Vector3(0.0, 1.5, -1.51),      # Central eye (front)
		Vector3(-0.8, 1.0, -1.51),     # Lower left
		Vector3(0.8, 1.0, -1.51),      # Lower right
		Vector3(-0.5, 2.2, -1.51),     # Upper left
		Vector3(0.5, 2.2, -1.51),      # Upper right
		Vector3(0.0, 0.3, -1.51),      # Bottom center
		Vector3(-1.4, 1.5, -0.8),      # Side left
		Vector3(1.4, 1.5, -0.8),       # Side right
	]

	for pos in eye_positions:
		var eye := CSGSphere3D.new()
		eye.radius = 0.18
		eye.radial_segments = 8
		eye.rings = 4
		eye.position = pos
		eye.material = _eye_mat
		body.add_child(eye)
		_eye_nodes.append(eye)

	# Large central eye
	var main_eye := CSGSphere3D.new()
	main_eye.radius = 0.35
	main_eye.radial_segments = 12
	main_eye.rings = 6
	main_eye.position = Vector3(0.0, 1.5, -1.55)
	var main_eye_mat := StandardMaterial3D.new()
	main_eye_mat.albedo_color = Color(1.0, 0.0, 0.5)
	main_eye_mat.emission_enabled = true
	main_eye_mat.emission = Color(1.0, 0.0, 0.5)
	main_eye_mat.emission_energy_multiplier = 5.0
	main_eye.material = main_eye_mat
	body.add_child(main_eye)
	_eye_nodes.append(main_eye)

	# Tentacle arms — thick cylinders extending outward and downward
	var tentacle_mat := StandardMaterial3D.new()
	tentacle_mat.albedo_color = Color(0.12, 0.0, 0.18)
	tentacle_mat.emission_enabled = true
	tentacle_mat.emission = Color(0.1, 0.0, 0.15)
	tentacle_mat.emission_energy_multiplier = 0.4

	var tentacle_data := [
		{"pos": Vector3(-2.2, -0.5, 0.0), "rot": Vector3(0, 0, 40)},
		{"pos": Vector3(2.2, -0.5, 0.0), "rot": Vector3(0, 0, -40)},
		{"pos": Vector3(-1.5, -0.8, 1.0), "rot": Vector3(-30, 20, 35)},
		{"pos": Vector3(1.5, -0.8, 1.0), "rot": Vector3(-30, -20, -35)},
		{"pos": Vector3(-1.8, 0.5, -0.8), "rot": Vector3(20, 0, 50)},
		{"pos": Vector3(1.8, 0.5, -0.8), "rot": Vector3(20, 0, -50)},
	]

	for data in tentacle_data:
		var tentacle := CSGCylinder3D.new()
		tentacle.radius = 0.25
		tentacle.height = 3.0
		tentacle.sides = 8
		tentacle.position = data["pos"]
		tentacle.rotation_degrees = data["rot"]
		tentacle.material = tentacle_mat
		body.add_child(tentacle)
		_tentacles.append(tentacle)

	return body

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, 5.0, 3.0)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 2.5, 0.0)

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
	var bar_width := 4.0
	var bar_height := 0.18
	_health_bar_bg = CSGBox3D.new()
	_health_bar_bg.size = Vector3(bar_width, bar_height, 0.05)
	_health_bar_bg.position = Vector3(0.0, 7.0, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 7.0, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.6, 0.0, 0.8)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.6, 0.0, 0.8)
	_health_bar_mat.emission_energy_multiplier = 1.5
	_health_bar_fill.material = _health_bar_mat
	add_child(_health_bar_fill)

func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	var ratio := get_health_ratio()
	var full_width := 3.95
	_health_bar_fill.size.x = full_width * ratio
	var offset := (full_width - _health_bar_fill.size.x) * 0.5
	_health_bar_fill.position.x = -offset
	if _health_bar_mat:
		if ratio <= PHASE_4_THRESHOLD:
			_health_bar_mat.albedo_color = Color(1.0, 0.0, 0.0)
			_health_bar_mat.emission = Color(1.0, 0.0, 0.0)
		elif ratio <= PHASE_3_THRESHOLD:
			_health_bar_mat.albedo_color = Color(0.8, 0.2, 0.0)
			_health_bar_mat.emission = Color(0.8, 0.2, 0.0)

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
# Override damage — stunned takes 2x damage
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	var final_amount := amount
	if _is_stunned:
		final_amount *= STUN_DAMAGE_MULT
	super.take_damage(final_amount, knockback_dir * 0.1)

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

	# -- Knockback decay (massive boss barely moves)
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 3.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	_update_phase()
	_update_health_bar()
	_face_health_bar_to_camera()
	_animate_color_shift(delta)
	_animate_tentacles(delta)

	# -- Stun check
	if _is_stunned:
		_stun_elapsed += delta
		if _stun_elapsed >= STUN_DURATION:
			_is_stunned = false
			if _body_mat:
				_body_mat.emission_energy_multiplier = maxf(_body_mat.emission_energy_multiplier, 0.5)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# -- Eye beam
	if _is_beaming:
		_beam_elapsed += delta
		if _beam_elapsed >= EYE_BEAM_DURATION:
			_is_beaming = false
			if _eye_mat:
				_eye_mat.emission_energy_multiplier = 4.0
		else:
			_execute_beam_tick(delta)

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

	var effective_speed := speed * wave_speed_mult * slow_mult
	if current_phase == Phase.FOUR:
		effective_speed *= 1.4

	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Timers
	_rift_timer -= delta
	_sweep_timer -= delta
	_orb_timer -= delta
	_cultist_timer -= delta
	_zone_timer -= delta
	_beam_timer -= delta
	_slam_timer -= delta
	_gravity_timer -= delta
	_tear_timer -= delta

	match current_phase:
		Phase.ONE:
			_phase_one_logic(delta)
		Phase.TWO:
			_phase_two_logic(delta)
		Phase.THREE:
			_phase_three_logic(delta)
		Phase.FOUR:
			_phase_four_logic(delta)

# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

func _animate_color_shift(delta: float) -> void:
	_color_shift_time += delta
	if _body_mat:
		var t := (sin(_color_shift_time * 0.8) + 1.0) * 0.5
		var color_a := Color(0.15, 0.02, 0.2)
		var color_b := Color(0.05, 0.0, 0.05)
		_body_mat.albedo_color = color_a.lerp(color_b, t)

func _animate_tentacles(delta: float) -> void:
	for i in _tentacles.size():
		var tentacle := _tentacles[i]
		if tentacle and is_instance_valid(tentacle):
			var sway := sin(_color_shift_time * 1.5 + float(i) * 1.2) * 3.0
			tentacle.rotation_degrees.x += sway * delta

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

func _update_phase() -> void:
	var ratio := get_health_ratio()
	if ratio <= PHASE_4_THRESHOLD and current_phase != Phase.FOUR:
		current_phase = Phase.FOUR
		_on_enter_phase_four()
	elif ratio <= PHASE_3_THRESHOLD and current_phase in [Phase.ONE, Phase.TWO]:
		current_phase = Phase.THREE
		_on_enter_phase_three()
	elif ratio <= PHASE_2_THRESHOLD and current_phase == Phase.ONE:
		current_phase = Phase.TWO
		_on_enter_phase_two()

func _on_enter_phase_two() -> void:
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = 6.0
	if _body_mat:
		_body_mat.emission_energy_multiplier = 1.0

func _on_enter_phase_three() -> void:
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = 8.0
		_eye_mat.emission = Color(1.0, 0.0, 0.3)
	if _body_mat:
		_body_mat.emission_energy_multiplier = 2.0
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.5)

func _on_enter_phase_four() -> void:
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = 12.0
		_eye_mat.emission = Color(1.0, 0.0, 0.0)
	if _body_mat:
		_body_mat.emission_energy_multiplier = 4.0
		_body_mat.emission = Color(0.4, 0.0, 0.0)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.6)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _rift_timer <= 0.0:
		_fire_void_rift(player)
	if dist <= TENTACLE_SWEEP_RANGE and _sweep_timer <= 0.0:
		_tentacle_sweep()
	if _orb_timer <= 0.0:
		_spawn_void_orb(player)

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _rift_timer <= 0.0:
		_fire_void_rift(player)
	if dist <= TENTACLE_SWEEP_RANGE and _sweep_timer <= 0.0:
		_tentacle_sweep()
	if _cultist_timer <= 0.0:
		_spawn_cultists(CULTIST_COUNT)
	if _zone_timer <= 0.0:
		_create_void_zone(player)
	if _beam_timer <= 0.0:
		_begin_eye_beam()

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _slam_timer <= 0.0 and dist <= TENTACLE_SLAM_RADIUS:
		_tentacle_slam()
	if _rift_timer <= 0.0:
		_fire_void_rift(player)
	if _zone_timer <= 0.0:
		_create_void_zone(player)
	if _gravity_timer <= 0.0:
		_gravity_pulse()
	if _cultist_timer <= 0.0:
		_spawn_cultists(CULTIST_COUNT + 2)
	if _beam_timer <= 0.0:
		_begin_eye_beam()
	if dist <= TENTACLE_SWEEP_RANGE and _sweep_timer <= 0.0:
		_tentacle_sweep()

func _phase_four_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	# Fastest attack rate
	if _tear_timer <= 0.0:
		_dimensional_tear()
	if _slam_timer <= 0.0 and dist <= TENTACLE_SLAM_RADIUS:
		_tentacle_slam()
	if _rift_timer <= 0.0:
		_fire_void_rift(player)
	if _gravity_timer <= 0.0:
		_gravity_pulse()
	if _cultist_timer <= 0.0:
		_spawn_cultists(CULTIST_COUNT + 3)
	if dist <= TENTACLE_SWEEP_RANGE and _sweep_timer <= 0.0:
		_tentacle_sweep()
	if _beam_timer <= 0.0:
		_begin_eye_beam()

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _fire_void_rift(target: Node3D) -> void:
	_rift_timer = VOID_RIFT_COOLDOWN
	if current_phase == Phase.FOUR:
		_rift_timer *= 0.5

	var spawn_pos := global_position + Vector3(0, 3.0, 0)
	var proj := _VoidRiftProjectile.new()
	proj.global_position = spawn_pos
	proj.target = target
	proj.damage = base_damage * wave_dmg_mult * 0.5
	proj.homing_strength = VOID_RIFT_HOMING
	proj.projectile_speed = VOID_RIFT_SPEED
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _tentacle_sweep() -> void:
	_is_attacking = true
	_sweep_timer = TENTACLE_SWEEP_COOLDOWN
	if current_phase == Phase.FOUR:
		_sweep_timer *= 0.6

	# Telegraph: tentacles rear back
	if _mesh and _tentacles.size() > 0:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale:x", 1.3, 0.3)
		tw.tween_callback(_execute_tentacle_sweep)
		tw.tween_property(_mesh, "scale:x", _mesh.scale.x, 0.2)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_tentacle_sweep()
		_is_attacking = false

func _execute_tentacle_sweep() -> void:
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= TENTACLE_SWEEP_RANGE:
			var dmg := base_damage * wave_dmg_mult * TENTACLE_SWEEP_DAMAGE_MULT
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 10.0

func _spawn_void_orb(target: Node3D) -> void:
	_orb_timer = VOID_ORB_COOLDOWN

	var spawn_pos := global_position + Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2))
	var orb := _VoidOrbChaser.new()
	orb.global_position = spawn_pos
	orb.target = target
	orb.damage = base_damage * wave_dmg_mult * 0.7
	orb.homing_strength = VOID_ORB_HOMING
	orb.projectile_speed = VOID_ORB_SPEED
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(orb)

func _begin_eye_beam() -> void:
	_beam_timer = EYE_BEAM_COOLDOWN
	if current_phase == Phase.FOUR:
		_beam_timer *= 0.6
	_is_beaming = true
	_beam_elapsed = 0.0

	# Telegraph: eyes glow intensely
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = 15.0

func _execute_beam_tick(delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.1:
		var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
		look_at(look_target, Vector3.UP)
	var dist := global_position.distance_to(player.global_position)
	if dist <= EYE_BEAM_RANGE:
		var dmg := base_damage * wave_dmg_mult * EYE_BEAM_DPS_MULT * delta
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)

func _create_void_zone(target: Node3D) -> void:
	_zone_timer = VOID_ZONE_COOLDOWN
	if current_phase in [Phase.THREE, Phase.FOUR]:
		_zone_timer *= 0.6

	var zone_pos := target.global_position
	zone_pos.y = 0.05
	var zone := CSGCylinder3D.new()
	zone.radius = VOID_ZONE_RADIUS
	zone.height = 0.06
	zone.sides = 16
	zone.global_position = zone_pos
	var zone_mat := StandardMaterial3D.new()
	zone_mat.albedo_color = Color(0.2, 0.0, 0.3, 0.5)
	zone_mat.emission_enabled = true
	zone_mat.emission = Color(0.3, 0.0, 0.4)
	zone_mat.emission_energy_multiplier = 2.0
	zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zone.material = zone_mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(zone)
		var zone_ref := zone
		var elapsed := 0.0
		var zone_dmg := base_damage * wave_dmg_mult * 0.25
		var tick_cb: Callable
		tick_cb = func():
			if not is_instance_valid(zone_ref):
				return
			elapsed += 0.5
			if elapsed > VOID_ZONE_DURATION:
				zone_ref.queue_free()
				return
			var p := get_player()
			if p and is_instance_valid(p):
				var d := Vector2(p.global_position.x, p.global_position.z).distance_to(
					Vector2(zone_ref.global_position.x, zone_ref.global_position.z))
				if d <= VOID_ZONE_RADIUS:
					if p.has_method("take_damage"):
						p.take_damage(zone_dmg, self)
					if p.has_method("apply_slow"):
						p.apply_slow(0.5, 0.6)
			get_tree().create_timer(0.5).timeout.connect(tick_cb)
		get_tree().create_timer(0.5).timeout.connect(tick_cb)

func _tentacle_slam() -> void:
	_is_attacking = true
	_slam_timer = TENTACLE_SLAM_COOLDOWN
	if current_phase == Phase.FOUR:
		_slam_timer *= 0.5

	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "position:y", _mesh.position.y + 0.8, 0.35)
		tw.tween_callback(_execute_tentacle_slam)
		tw.tween_property(_mesh, "position:y", _mesh.position.y, 0.15)
		tw.tween_callback(func():
			_is_attacking = false
			if current_phase == Phase.FOUR:
				_apply_stun()
		)
	else:
		_execute_tentacle_slam()
		_is_attacking = false
		if current_phase == Phase.FOUR:
			_apply_stun()

func _execute_tentacle_slam() -> void:
	var slam_damage := base_damage * wave_dmg_mult * TENTACLE_SLAM_DAMAGE_MULT
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= TENTACLE_SLAM_RADIUS:
			var falloff := 1.0 - (dist / TENTACLE_SLAM_RADIUS) * 0.5
			if player.has_method("take_damage"):
				player.take_damage(slam_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 14.0
	_spawn_slam_ring()

func _spawn_slam_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.15
	ring.sides = 32
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.0, 0.6, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.0, 0.7)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", TENTACLE_SLAM_RADIUS, 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

func _gravity_pulse() -> void:
	_gravity_timer = GRAVITY_PULSE_COOLDOWN
	if current_phase == Phase.FOUR:
		_gravity_timer *= 0.6

	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= GRAVITY_PULSE_RADIUS and player is CharacterBody3D:
			var kb := (player.global_position - global_position).normalized()
			player.velocity += kb * GRAVITY_PULSE_FORCE + Vector3(0, 8.0, 0)
	_spawn_gravity_ring()

func _spawn_gravity_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.1
	ring.sides = 24
	ring.global_position = global_position + Vector3(0, 2.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.0, 0.4, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.0, 0.5)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", GRAVITY_PULSE_RADIUS, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

func _dimensional_tear() -> void:
	_tear_timer = DIMENSIONAL_TEAR_COOLDOWN

	# Telegraph: reality flickers (brief scale pulse)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", _mesh.scale * 1.15, 0.15)
		tw.tween_property(_mesh, "scale", _mesh.scale, 0.15)
		tw.tween_callback(_execute_dimensional_tear)
	else:
		get_tree().create_timer(0.3).timeout.connect(_execute_dimensional_tear)

func _execute_dimensional_tear() -> void:
	if not is_alive:
		return
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= DIMENSIONAL_TEAR_RADIUS:
			var dmg := base_damage * wave_dmg_mult * DIMENSIONAL_TEAR_DAMAGE_MULT
			var falloff := 1.0 - (dist / DIMENSIONAL_TEAR_RADIUS) * 0.4
			if player.has_method("take_damage"):
				player.take_damage(dmg * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 16.0
	_spawn_tear_explosion()

	# Phase 4: self-stun after dimensional tear
	if current_phase == Phase.FOUR:
		_apply_stun()

func _spawn_tear_explosion() -> void:
	# Multiple expanding rings for dramatic effect
	for i in 3:
		var ring := CSGCylinder3D.new()
		ring.radius = 0.5
		ring.height = 0.2
		ring.sides = 32
		ring.global_position = global_position + Vector3(0, 0.5 + i * 1.0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.0, 0.8, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.0, 1.0)
		mat.emission_energy_multiplier = 6.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material = mat
		var scene_root := get_tree().current_scene
		if scene_root:
			scene_root.add_child(ring)
			var tw := ring.create_tween()
			tw.set_parallel(true)
			tw.tween_property(ring, "radius", DIMENSIONAL_TEAR_RADIUS, 0.5).set_ease(Tween.EASE_OUT)
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
			tw.set_parallel(false)
			tw.tween_callback(ring.queue_free)

func _apply_stun() -> void:
	_is_stunned = true
	_stun_elapsed = 0.0
	# Visual indicator: dim emission
	if _body_mat:
		_body_mat.emission_energy_multiplier = 0.1

# ---------------------------------------------------------------------------
# Minion spawning
# ---------------------------------------------------------------------------

func _spawn_cultists(count: int) -> void:
	_cultist_timer = CULTIST_SPAWN_COOLDOWN
	if current_phase in [Phase.THREE, Phase.FOUR]:
		_cultist_timer *= 0.5

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in count:
		var minion := EnemyMelee.new()
		var angle := (TAU / float(count)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 5.0, 0.0, sin(angle) * 5.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y
		minion.initialize(wave_hp_mult * 0.4, wave_dmg_mult * 0.5, wave_speed_mult)
		scene_root.add_child(minion)
		minion.global_position = spawn_pos
		GameManager.register_enemies(1)

# ---------------------------------------------------------------------------
# Death — special dramatic dissolve
# ---------------------------------------------------------------------------

func die() -> void:
	if not is_alive:
		return
	is_alive = false

	# Drop massive rewards
	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)
	_drop_health()
	_drop_health()
	_drop_health()
	_drop_ammo()
	_drop_ammo()
	_drop_ammo()
	_drop_bomb_ammo()
	_drop_bomb_ammo()

	# Signals
	EventBus.enemy_killed.emit(self, global_position)
	EventBus.boss_killed.emit()

	# Dramatic dissolve — linger for 2 seconds
	_begin_dissolve()

func _begin_dissolve() -> void:
	_dissolve_started = true

	# Make mesh transparent
	if _base_material:
		_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _body_mat:
		_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Scale down + fade + death rings
	if _mesh:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_mesh, "scale", Vector3(0.01, 0.01, 0.01), 2.0).set_ease(Tween.EASE_IN)
		if _body_mat:
			tw.tween_property(_body_mat, "albedo_color:a", 0.0, 2.0)
		tw.set_parallel(false)
		tw.tween_callback(queue_free)
	else:
		queue_free()

	# Spawn death explosion rings during dissolve
	for i in 6:
		get_tree().create_timer(i * 0.3).timeout.connect(
			_spawn_death_ring.bind(i)
		)

	# Hide health bar
	if _health_bar_bg:
		_health_bar_bg.visible = false
	if _health_bar_fill:
		_health_bar_fill.visible = false

func _spawn_death_ring(index: int) -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.2
	ring.sides = 32
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.8, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.0, 0.8, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.1, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", 12.0, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Inner class: Void rift projectile (homing)
# ---------------------------------------------------------------------------

class _VoidRiftProjectile extends Area3D:

	var target: Node3D = null
	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 10.0
	var damage: float = 25.0
	var homing_strength: float = 2.5
	var _lifetime: float = 7.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.3
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.0, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.0, 0.6)
		mat.emission_energy_multiplier = 4.0
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		if target and is_instance_valid(target):
			var desired := (target.global_position + Vector3(0, 0.9, 0) - global_position).normalized()
			direction = direction.move_toward(desired, homing_strength * delta)
			direction = direction.normalized()
		global_position += direction * projectile_speed * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(damage, self)
		queue_free()

# ---------------------------------------------------------------------------
# Inner class: Void orb chaser (slower, stronger homing)
# ---------------------------------------------------------------------------

class _VoidOrbChaser extends Area3D:

	var target: Node3D = null
	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 5.0
	var damage: float = 30.0
	var homing_strength: float = 4.0
	var _lifetime: float = 10.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.4
		sphere.radial_segments = 10
		sphere.rings = 5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.0, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.0, 0.5)
		mat.emission_energy_multiplier = 5.0
		sphere.material = mat
		add_child(sphere)

		# Outer glow ring
		var glow := CSGCylinder3D.new()
		glow.radius = 0.5
		glow.height = 0.05
		glow.sides = 12
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.4, 0.0, 0.6, 0.4)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(0.5, 0.0, 0.8)
		glow_mat.emission_energy_multiplier = 3.0
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.material = glow_mat
		add_child(glow)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.4
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		if target and is_instance_valid(target):
			var desired := (target.global_position + Vector3(0, 0.9, 0) - global_position).normalized()
			direction = direction.move_toward(desired, homing_strength * delta)
			direction = direction.normalized()
		global_position += direction * projectile_speed * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("take_damage"):
			body.take_damage(damage, self)
		queue_free()
