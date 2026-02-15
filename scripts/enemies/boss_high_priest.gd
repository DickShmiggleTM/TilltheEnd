class_name BossHighPriest
extends EnemyBase
## THE HIGH PRIEST — Level 4 Boss.
##
## A tall robed figure channeling forbidden magic from an ancient tome.
##
## Phase 1 (100-60%): Ranged magic — fires homing dark orbs, summons
##   temporary barrier walls.
## Phase 2 (60-30%): Teleports to random positions, creates sigil traps on
##   the ground, summons cultist enemies.
## Phase 3 (30-0%): Channels the God's power — massive beam sweeps, near-
##   constant cultist spawns, and a protective shield.
##
## Visual: Dark red CSGCylinder3D body, CSGSphere3D glowing head, floating
## CSGBox3D tome orbiting.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 2000.0
	base_damage = 28.0
	speed = 3.0
	attack_range = 18.0
	attack_cooldown = 2.0
	base_exp_drop = 800.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The High Priest"

const PHASE_2_THRESHOLD := 0.6
const PHASE_3_THRESHOLD := 0.3

const DARK_ORB_COOLDOWN := 2.5
const DARK_ORB_SPEED := 8.0
const DARK_ORB_HOMING := 3.0
const BARRIER_COOLDOWN := 8.0
const TELEPORT_COOLDOWN := 5.0
const TELEPORT_RANGE := 12.0
const SIGIL_TRAP_COOLDOWN := 4.0
const SIGIL_DAMAGE_MULT := 0.8
const SIGIL_RADIUS := 2.0
const SIGIL_DURATION := 6.0
const CULTIST_SPAWN_COOLDOWN := 8.0
const CULTIST_COUNT := 2
const BEAM_SWEEP_COOLDOWN := 7.0
const BEAM_SWEEP_DURATION := 2.0
const BEAM_DAMAGE_MULT := 0.3
const SHIELD_MAX_HP := 300.0
const SHIELD_REGEN_COOLDOWN := 15.0
const OPTIMAL_RANGE := 10.0

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _orb_timer: float = DARK_ORB_COOLDOWN
var _barrier_timer: float = BARRIER_COOLDOWN
var _teleport_timer: float = TELEPORT_COOLDOWN
var _sigil_timer: float = SIGIL_TRAP_COOLDOWN
var _cultist_timer: float = CULTIST_SPAWN_COOLDOWN
var _beam_timer: float = BEAM_SWEEP_COOLDOWN
var _shield_timer: float = SHIELD_REGEN_COOLDOWN
var _is_attacking: bool = false
var _is_beaming: bool = false
var _beam_elapsed: float = 0.0
var _beam_angle: float = 0.0
var _shield_hp: float = 0.0
var _has_shield: bool = false

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Tome reference
var _tome: CSGBox3D = null
var _tome_orbit_angle: float = 0.0
var _head_sphere: CSGSphere3D = null
var _head_mat: StandardMaterial3D = null

## Shield visual
var _shield_mesh: CSGSphere3D = null
var _shield_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.4, 0.05, 0.05)  # Dark blood red

func _create_mesh() -> Node3D:
	# Robed body — tall cylinder
	var body := CSGCylinder3D.new()
	body.radius = 0.7
	body.height = 3.0
	body.sides = 12
	body.position = Vector3(0.0, 1.5, 0.0)

	# Glowing head
	_head_sphere = CSGSphere3D.new()
	_head_sphere.radius = 0.4
	_head_sphere.radial_segments = 12
	_head_sphere.rings = 6
	_head_sphere.position = Vector3(0.0, 1.8, 0.0)
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(0.8, 0.2, 0.8)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(0.8, 0.2, 0.8)
	_head_mat.emission_energy_multiplier = 3.0
	_head_sphere.material = _head_mat
	body.add_child(_head_sphere)

	# Hood
	var hood := CSGCylinder3D.new()
	hood.radius = 0.5
	hood.height = 0.6
	hood.sides = 8
	hood.position = Vector3(0.0, 1.6, 0.0)
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.15, 0.02, 0.02)
	hood_mat.emission_enabled = true
	hood_mat.emission = Color(0.1, 0.0, 0.0)
	hood_mat.emission_energy_multiplier = 0.3
	hood.material = hood_mat
	body.add_child(hood)

	# Floating tome — orbits around body
	_tome = CSGBox3D.new()
	_tome.size = Vector3(0.5, 0.6, 0.08)
	_tome.position = Vector3(1.5, 1.0, 0.0)
	var tome_mat := StandardMaterial3D.new()
	tome_mat.albedo_color = Color(0.6, 0.5, 0.2)
	tome_mat.emission_enabled = true
	tome_mat.emission = Color(0.8, 0.3, 0.1)
	tome_mat.emission_energy_multiplier = 2.0
	_tome.material = tome_mat
	body.add_child(_tome)

	# Robe trim
	var trim := CSGCylinder3D.new()
	trim.radius = 0.85
	trim.height = 0.3
	trim.sides = 12
	trim.position = Vector3(0.0, -1.35, 0.0)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.5, 0.15, 0.0)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.4, 0.1, 0.0)
	trim_mat.emission_energy_multiplier = 0.5
	trim.material = trim_mat
	body.add_child(trim)

	return body

func _create_collision_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7
	capsule.height = 3.0
	return capsule

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
	_health_bar_mat.albedo_color = Color(0.7, 0.1, 0.1)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.7, 0.1, 0.1)
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
			_health_bar_mat.albedo_color = Color(0.5, 0.0, 0.5)
			_health_bar_mat.emission = Color(0.5, 0.0, 0.5)

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
# Shield (Phase 3)
# ---------------------------------------------------------------------------

func _create_shield() -> void:
	_shield_hp = SHIELD_MAX_HP
	_has_shield = true
	_shield_mesh = CSGSphere3D.new()
	_shield_mesh.radius = 2.0
	_shield_mesh.radial_segments = 16
	_shield_mesh.rings = 8
	_shield_mesh.position = Vector3(0.0, 1.5, 0.0)
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.albedo_color = Color(0.5, 0.1, 0.5, 0.3)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.6, 0.1, 0.6)
	_shield_mat.emission_energy_multiplier = 2.0
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mesh.material = _shield_mat
	add_child(_shield_mesh)

func _break_shield() -> void:
	_has_shield = false
	_shield_hp = 0.0
	if _shield_mesh:
		_shield_mesh.queue_free()
		_shield_mesh = null

# ---------------------------------------------------------------------------
# Override damage — shield absorbs in phase 3
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if _has_shield:
		_shield_hp -= amount
		if _shield_hp <= 0.0:
			_break_shield()
			# Remaining damage passes through
			var remainder := absf(_shield_hp)
			if remainder > 0.0:
				super.take_damage(remainder, knockback_dir * 0.15)
		return
	super.take_damage(amount, knockback_dir * 0.15)

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

	# -- Orbit the tome
	_tome_orbit_angle += delta * 1.5
	if _tome:
		var orbit_r := 1.5
		_tome.position = Vector3(
			cos(_tome_orbit_angle) * orbit_r,
			1.0 + sin(_tome_orbit_angle * 2.0) * 0.2,
			sin(_tome_orbit_angle) * orbit_r
		)

	# -- Beam sweep
	if _is_beaming:
		_beam_elapsed += delta
		if _beam_elapsed >= BEAM_SWEEP_DURATION:
			_is_beaming = false
		else:
			_execute_beam_tick(delta)
		return

	# -- Movement — maintain optimal range
	var move_dir := Vector3.ZERO
	var player := get_player()
	if player and is_instance_valid(player) and not _is_attacking:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if dist > OPTIMAL_RANGE + 2.0:
			move_dir = to_player.normalized()
		elif dist < OPTIMAL_RANGE - 2.0:
			move_dir = -to_player.normalized()
		if to_player.length() > 0.1:
			var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
			look_at(look_target, Vector3.UP)

	var effective_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# -- Timers
	_orb_timer -= delta
	_barrier_timer -= delta
	_teleport_timer -= delta
	_sigil_timer -= delta
	_cultist_timer -= delta
	_beam_timer -= delta
	_shield_timer -= delta

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
	if _head_mat:
		_head_mat.emission_energy_multiplier = 5.0
	# Tome spins faster (visual cue)

func _on_enter_phase_three() -> void:
	if _head_mat:
		_head_mat.emission_energy_multiplier = 8.0
		_head_mat.emission = Color(1.0, 0.3, 1.0)
	if _base_material:
		_base_material.emission_energy_multiplier = 2.0
		_base_material.emission = Color(0.5, 0.05, 0.5)
	_create_shield()
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.1, 1.15, 1.1), 0.5)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	if _orb_timer <= 0.0:
		_fire_dark_orb(player)
	if _barrier_timer <= 0.0:
		_summon_barrier()

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	if _orb_timer <= 0.0:
		_fire_dark_orb(player)
	if _teleport_timer <= 0.0:
		_teleport()
	if _sigil_timer <= 0.0:
		_create_sigil_trap(player)
	if _cultist_timer <= 0.0:
		_spawn_cultists(CULTIST_COUNT)

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	if _beam_timer <= 0.0:
		_begin_beam_sweep()
	if _orb_timer <= 0.0:
		_fire_dark_orb(player)
	if _cultist_timer <= 0.0:
		_spawn_cultists(CULTIST_COUNT + 1)
	if _shield_timer <= 0.0 and not _has_shield:
		_create_shield()
		_shield_timer = SHIELD_REGEN_COOLDOWN
	if _teleport_timer <= 0.0:
		_teleport()

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _fire_dark_orb(target: Node3D) -> void:
	_orb_timer = DARK_ORB_COOLDOWN
	if current_phase == Phase.THREE:
		_orb_timer *= 0.6

	# Telegraph: head glows brighter
	if _head_mat:
		var orig := _head_mat.emission_energy_multiplier
		_head_mat.emission_energy_multiplier = orig + 4.0
		get_tree().create_timer(0.3).timeout.connect(func():
			if _head_mat:
				_head_mat.emission_energy_multiplier = orig
		)

	var spawn_pos := global_position + Vector3(0, 2.5, 0)
	var proj := _DarkOrb.new()
	proj.global_position = spawn_pos
	proj.target = target
	proj.damage = base_damage * wave_dmg_mult * 0.7
	proj.homing_strength = DARK_ORB_HOMING
	proj.projectile_speed = DARK_ORB_SPEED
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _summon_barrier() -> void:
	_barrier_timer = BARRIER_COOLDOWN
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	# Place wall between boss and player
	var mid := (global_position + player.global_position) * 0.5
	mid.y = 0.5
	var wall := CSGBox3D.new()
	wall.size = Vector3(4.0, 3.0, 0.5)
	wall.global_position = mid
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.3, 0.05, 0.3, 0.7)
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.4, 0.05, 0.4)
	wall_mat.emission_energy_multiplier = 2.0
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall.material = wall_mat
	# Face toward player
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.1:
		wall.look_at(wall.global_position + dir, Vector3.UP)
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(wall)
		var tw := wall.create_tween()
		tw.tween_interval(4.0)
		tw.tween_property(wall_mat, "albedo_color:a", 0.0, 1.0)
		tw.tween_callback(wall.queue_free)

func _teleport() -> void:
	_teleport_timer = TELEPORT_COOLDOWN

	# Telegraph: tome spins faster (visual brief flash)
	if _head_mat:
		_head_mat.emission_energy_multiplier += 3.0

	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var angle := randf() * TAU
	var dist := TELEPORT_RANGE * (0.6 + randf() * 0.4)
	var new_pos := player.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	new_pos.y = global_position.y
	global_position = new_pos

	if _head_mat:
		_head_mat.emission_energy_multiplier -= 3.0

func _create_sigil_trap(target: Node3D) -> void:
	_sigil_timer = SIGIL_TRAP_COOLDOWN
	var trap_pos := target.global_position
	trap_pos.y = 0.05

	var sigil := CSGCylinder3D.new()
	sigil.radius = SIGIL_RADIUS
	sigil.height = 0.05
	sigil.sides = 16
	sigil.global_position = trap_pos
	var sigil_mat := StandardMaterial3D.new()
	sigil_mat.albedo_color = Color(0.7, 0.0, 0.0, 0.5)
	sigil_mat.emission_enabled = true
	sigil_mat.emission = Color(0.8, 0.0, 0.0)
	sigil_mat.emission_energy_multiplier = 2.0
	sigil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sigil.material = sigil_mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(sigil)
		# Sigil damages over its lifetime
		var sigil_ref := sigil
		var dmg := base_damage * wave_dmg_mult * SIGIL_DAMAGE_MULT
		var elapsed := 0.0
		var timer_cb: Callable
		timer_cb = func():
			if not is_instance_valid(sigil_ref):
				return
			elapsed += 0.5
			if elapsed > SIGIL_DURATION:
				sigil_ref.queue_free()
				return
			# Damage player if on sigil
			var p := get_player()
			if p and is_instance_valid(p):
				var d := p.global_position.distance_to(sigil_ref.global_position)
				if d <= SIGIL_RADIUS and p.has_method("take_damage"):
					p.take_damage(dmg * 0.3, self)
			get_tree().create_timer(0.5).timeout.connect(timer_cb)
		get_tree().create_timer(0.5).timeout.connect(timer_cb)

func _begin_beam_sweep() -> void:
	_beam_timer = BEAM_SWEEP_COOLDOWN
	_is_beaming = true
	_beam_elapsed = 0.0
	var player := get_player()
	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		_beam_angle = atan2(to_player.z, to_player.x)

	# Telegraph: intense glow
	if _head_mat:
		_head_mat.emission_energy_multiplier = 12.0

func _execute_beam_tick(delta: float) -> void:
	# Sweep beam direction
	_beam_angle += delta * 1.5
	var beam_dir := Vector3(cos(_beam_angle), 0, sin(_beam_angle))

	var player := get_player()
	if player and is_instance_valid(player):
		var to_player := (player.global_position - global_position)
		to_player.y = 0.0
		var player_dir := to_player.normalized()
		var dot := beam_dir.dot(player_dir)
		if dot > 0.85 and to_player.length() < 20.0:
			var dmg := base_damage * wave_dmg_mult * BEAM_DAMAGE_MULT * delta
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)

func _spawn_cultists(count: int) -> void:
	_cultist_timer = CULTIST_SPAWN_COOLDOWN
	if current_phase == Phase.THREE:
		_cultist_timer *= 0.5
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in count:
		var minion := EnemyMelee.new()
		var angle := (TAU / float(count)) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 4.0, 0.0, sin(angle) * 4.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = global_position.y
		minion.initialize(wave_hp_mult * 0.4, wave_dmg_mult * 0.5, wave_speed_mult)
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
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.0, 0.6, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.1, 0.7)
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
# Inner class: Homing dark orb
# ---------------------------------------------------------------------------

class _DarkOrb:
	extends Area3D

	var target: Node3D = null
	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 8.0
	var damage: float = 15.0
	var homing_strength: float = 3.0
	var _lifetime: float = 7.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.25
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.0, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.1, 0.6)
		mat.emission_energy_multiplier = 3.5
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.25
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		# Homing toward target
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
