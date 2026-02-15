class_name BossTempleSentinel
extends EnemyBase
## THE SENTINEL OF ECHOES — Level 5 Boss.
##
## A massive armored stone golem inscribed with ancient runes.
##
## Phase 1 (100-65%): Slow powerful melee, ground pounds that send shockwaves
##   (expanding ring damage).
## Phase 2 (65-30%): Summons echo clones (2 weaker copies), rune beams from
##   hands.
## Phase 3 (30-0%): Goes berserk — much faster, chains ground pound into
##   charge, echoes become permanent.
##
## Visual: Gray/purple CSGBox3D body with glowing purple rune accent strips.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 2800.0
	base_damage = 35.0
	speed = 2.0
	attack_range = 4.0
	attack_cooldown = 2.5
	base_exp_drop = 1000.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Sentinel of Echoes"

const PHASE_2_THRESHOLD := 0.65
const PHASE_3_THRESHOLD := 0.30

const CRUSH_RANGE := 4.5
const CRUSH_COOLDOWN := 3.0
const CRUSH_DAMAGE_MULT := 1.3
const SHOCKWAVE_RADIUS := 8.0
const SHOCKWAVE_COOLDOWN := 6.0
const SHOCKWAVE_DAMAGE_MULT := 1.0
const ECHO_SPAWN_COOLDOWN := 15.0
const ECHO_COUNT := 2
const RUNE_BEAM_COOLDOWN := 5.0
const RUNE_BEAM_RANGE := 16.0
const RUNE_BEAM_DAMAGE_MULT := 0.4
const RUNE_BEAM_DURATION := 1.5
const BERSERK_SPEED_MULT := 2.5
const BERSERK_DAMAGE_MULT := 1.3
const CHARGE_COOLDOWN := 5.0
const CHARGE_SPEED := 14.0
const CHARGE_DURATION := 0.5

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _crush_timer: float = CRUSH_COOLDOWN
var _shockwave_timer: float = SHOCKWAVE_COOLDOWN
var _echo_timer: float = ECHO_SPAWN_COOLDOWN
var _beam_timer: float = RUNE_BEAM_COOLDOWN
var _charge_timer: float = CHARGE_COOLDOWN
var _is_attacking: bool = false
var _is_beaming: bool = false
var _beam_elapsed: float = 0.0
var _is_charging: bool = false
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_elapsed: float = 0.0

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Rune accent references
var _rune_strips: Array[CSGBox3D] = []
var _rune_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.35, 0.32, 0.38)  # Stone gray with purple tint

func _create_mesh() -> Node3D:
	# Massive stone body
	var body := CSGBox3D.new()
	body.size = Vector3(2.8, 4.0, 2.2)
	body.position = Vector3(0.0, 2.0, 0.0)

	# Head — smaller box on top
	var head := CSGBox3D.new()
	head.size = Vector3(1.2, 1.0, 1.0)
	head.position = Vector3(0.0, 2.3, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.3, 0.28, 0.35)
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.2, 0.15, 0.25)
	head_mat.emission_energy_multiplier = 0.3
	head.material = head_mat
	body.add_child(head)

	# Glowing rune eye visor
	var visor := CSGBox3D.new()
	visor.size = Vector3(0.8, 0.15, 0.05)
	visor.position = Vector3(0.0, 0.15, -0.51)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.6, 0.2, 1.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.6, 0.2, 1.0)
	visor_mat.emission_energy_multiplier = 4.0
	visor.material = visor_mat
	head.add_child(visor)

	# Shoulder armor
	var shoulder_l := CSGBox3D.new()
	shoulder_l.size = Vector3(0.8, 0.8, 1.5)
	shoulder_l.position = Vector3(-1.6, 1.4, 0.0)
	body.add_child(shoulder_l)

	var shoulder_r := CSGBox3D.new()
	shoulder_r.size = Vector3(0.8, 0.8, 1.5)
	shoulder_r.position = Vector3(1.6, 1.4, 0.0)
	body.add_child(shoulder_r)

	# Arms — thick cylinders
	var arm_l := CSGCylinder3D.new()
	arm_l.radius = 0.35
	arm_l.height = 2.2
	arm_l.sides = 8
	arm_l.position = Vector3(-1.6, 0.0, 0.0)
	arm_l.rotation_degrees = Vector3(0, 0, 10)
	body.add_child(arm_l)

	var arm_r := CSGCylinder3D.new()
	arm_r.radius = 0.35
	arm_r.height = 2.2
	arm_r.sides = 8
	arm_r.position = Vector3(1.6, 0.0, 0.0)
	arm_r.rotation_degrees = Vector3(0, 0, -10)
	body.add_child(arm_r)

	# Rune accent strips (vertical purple glowing lines on body)
	_rune_mat = StandardMaterial3D.new()
	_rune_mat.albedo_color = Color(0.5, 0.15, 0.8)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.5, 0.15, 0.8)
	_rune_mat.emission_energy_multiplier = 2.0

	var strip_positions := [-0.8, 0.0, 0.8]
	for x_pos in strip_positions:
		var strip := CSGBox3D.new()
		strip.size = Vector3(0.1, 3.5, 0.05)
		strip.position = Vector3(x_pos, 0.0, -1.11)
		strip.material = _rune_mat
		body.add_child(strip)
		_rune_strips.append(strip)

	# Horizontal rune strip
	var h_strip := CSGBox3D.new()
	h_strip.size = Vector3(2.5, 0.1, 0.05)
	h_strip.position = Vector3(0.0, 0.5, -1.11)
	h_strip.material = _rune_mat
	body.add_child(h_strip)
	_rune_strips.append(h_strip)

	return body

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 4.0, 2.2)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 2.0, 0.0)

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
	var bar_width := 3.5
	var bar_height := 0.15
	_health_bar_bg = CSGBox3D.new()
	_health_bar_bg.size = Vector3(bar_width, bar_height, 0.05)
	_health_bar_bg.position = Vector3(0.0, 6.0, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, 6.0, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.5, 0.15, 0.8)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.5, 0.15, 0.8)
	_health_bar_mat.emission_energy_multiplier = 1.0
	_health_bar_fill.material = _health_bar_mat
	add_child(_health_bar_fill)

func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	var ratio := get_health_ratio()
	var full_width := 3.45
	_health_bar_fill.size.x = full_width * ratio
	var offset := (full_width - _health_bar_fill.size.x) * 0.5
	_health_bar_fill.position.x = -offset
	if _health_bar_mat:
		if ratio <= PHASE_3_THRESHOLD:
			_health_bar_mat.albedo_color = Color(1.0, 0.2, 0.2)
			_health_bar_mat.emission = Color(1.0, 0.2, 0.2)

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

	# -- Knockback decay (golem barely moves)
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 3.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	_update_phase()
	_update_health_bar()
	_face_health_bar_to_camera()

	# -- Charge
	if _is_charging:
		_charge_elapsed += delta
		velocity.x = _charge_dir.x * CHARGE_SPEED
		velocity.z = _charge_dir.z * CHARGE_SPEED
		move_and_slide()
		if _charge_elapsed >= CHARGE_DURATION:
			_is_charging = false
			_execute_charge_impact()
		return

	# -- Beam
	if _is_beaming:
		_beam_elapsed += delta
		if _beam_elapsed >= RUNE_BEAM_DURATION:
			_is_beaming = false
			if _rune_mat:
				_rune_mat.emission_energy_multiplier = 2.0
		else:
			_execute_beam_tick(delta)
		# Stand still during beam
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
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
		speed_mult = BERSERK_SPEED_MULT

	var effective_speed := speed * wave_speed_mult * slow_mult * speed_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Timers
	_crush_timer -= delta
	_shockwave_timer -= delta
	_echo_timer -= delta
	_beam_timer -= delta
	_charge_timer -= delta

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
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 3.5
	if _base_material:
		_base_material.emission_energy_multiplier = 1.0

func _on_enter_phase_three() -> void:
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 6.0
		_rune_mat.emission = Color(1.0, 0.3, 0.3)
	if _base_material:
		_base_material.emission_energy_multiplier = 2.5
		_base_material.emission = Color(0.5, 0.1, 0.1)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.12, 1.12, 1.12), 0.6)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= CRUSH_RANGE and _crush_timer <= 0.0:
		_crushing_blow(player)
	if _shockwave_timer <= 0.0:
		_ground_pound_shockwave()

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= CRUSH_RANGE and _crush_timer <= 0.0:
		_crushing_blow(player)
	if _shockwave_timer <= 0.0:
		_ground_pound_shockwave()
	if _echo_timer <= 0.0:
		_summon_echoes()
	if _beam_timer <= 0.0 and dist <= RUNE_BEAM_RANGE:
		_begin_rune_beam()

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if dist <= CRUSH_RANGE and _crush_timer <= 0.0:
		_crushing_blow(player, BERSERK_DAMAGE_MULT)
	if _shockwave_timer <= 0.0:
		# Chain ground pound into charge
		_ground_pound_shockwave()
		_charge_timer = 0.5  # Quick follow-up charge
	if _charge_timer <= 0.0 and dist > 3.0:
		_begin_charge(player)
	if _echo_timer <= 0.0:
		_summon_echoes()
	if _beam_timer <= 0.0 and dist <= RUNE_BEAM_RANGE:
		_begin_rune_beam()

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _crushing_blow(player: Node3D, extra_mult: float = 1.0) -> void:
	_is_attacking = true
	_crush_timer = CRUSH_COOLDOWN

	if _mesh:
		var tw := create_tween()
		# Telegraph: raise fists high
		tw.tween_property(_mesh, "scale:y", 1.2, 0.4)
		tw.tween_callback(_execute_crush.bind(player, extra_mult))
		tw.tween_property(_mesh, "scale:y", 1.0, 0.15)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_crush(player, extra_mult)
		_is_attacking = false

func _execute_crush(player: Node3D, extra_mult: float) -> void:
	if not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > CRUSH_RANGE * 1.3:
		return
	var effective_damage := base_damage * wave_dmg_mult * CRUSH_DAMAGE_MULT * extra_mult
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)

func _ground_pound_shockwave() -> void:
	_is_attacking = true
	_shockwave_timer = SHOCKWAVE_COOLDOWN
	if current_phase == Phase.THREE:
		_shockwave_timer *= 0.6

	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "position:y", _mesh.position.y + 0.8, 0.4)
		tw.tween_callback(_execute_shockwave)
		tw.tween_property(_mesh, "position:y", _mesh.position.y, 0.15)
		tw.tween_callback(func(): _is_attacking = false)
	else:
		_execute_shockwave()
		_is_attacking = false

func _execute_shockwave() -> void:
	var shockwave_damage := base_damage * wave_dmg_mult * SHOCKWAVE_DAMAGE_MULT
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= SHOCKWAVE_RADIUS:
			var falloff := 1.0 - (dist / SHOCKWAVE_RADIUS) * 0.6
			if player.has_method("take_damage"):
				player.take_damage(shockwave_damage * falloff, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 12.0
	_spawn_shockwave_ring()

func _spawn_shockwave_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.15
	ring.sides = 28
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.15, 0.8, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.15, 0.8)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", SHOCKWAVE_RADIUS, 0.5).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

func _begin_rune_beam() -> void:
	_beam_timer = RUNE_BEAM_COOLDOWN
	if current_phase == Phase.THREE:
		_beam_timer *= 0.7
	_is_beaming = true
	_beam_elapsed = 0.0

	# Telegraph: runes glow intensely
	if _rune_mat:
		_rune_mat.emission_energy_multiplier = 10.0

func _execute_beam_tick(delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	# Face the player during beam
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.1:
		var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
		look_at(look_target, Vector3.UP)

	var dist := global_position.distance_to(player.global_position)
	if dist <= RUNE_BEAM_RANGE:
		var dmg := base_damage * wave_dmg_mult * RUNE_BEAM_DAMAGE_MULT * delta
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)

func _begin_charge(target: Node3D) -> void:
	_charge_timer = CHARGE_COOLDOWN
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	_charge_dir = to_player.normalized()
	_charge_elapsed = 0.0
	_is_charging = true

func _execute_charge_impact() -> void:
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= 4.5:
			var dmg := base_damage * wave_dmg_mult * 1.5
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 16.0
	# Immediately shockwave after charge in phase 3
	if current_phase == Phase.THREE and _shockwave_timer <= 1.0:
		_shockwave_timer = 0.0

func _summon_echoes() -> void:
	_echo_timer = ECHO_SPAWN_COOLDOWN
	if current_phase == Phase.THREE:
		_echo_timer *= 0.6

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in ECHO_COUNT:
		var echo := EnemyMelee.new()
		var angle := (TAU / float(ECHO_COUNT)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 4.0, 0.0, sin(angle) * 4.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y
		# Echoes are weaker copies
		echo.initialize(wave_hp_mult * 0.4, wave_dmg_mult * 0.5, wave_speed_mult * 0.8)
		scene_root.add_child(echo)
		echo.global_position = spawn_pos
		GameManager.register_enemies(1)

# ---------------------------------------------------------------------------
# Damage / Death
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir * 0.1)  # Barely moves

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
	for i in 5:
		get_tree().create_timer(i * 0.2).timeout.connect(
			_spawn_death_ring.bind(i)
		)

func _spawn_death_ring(index: int) -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.4
	ring.height = 0.15
	ring.sides = 32
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.6, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.15, 0.8, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.2, 0.9)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", 10.0, 0.6).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)
