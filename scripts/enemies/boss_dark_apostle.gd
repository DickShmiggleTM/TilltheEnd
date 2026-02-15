class_name BossDarkApostle
extends EnemyBase
## THE DARK APOSTLE — Level 6 Boss.
##
## A floating robed figure wreathed in dark fire, channeling abyssal power.
##
## Phase 1 (100-60%): Rapid dark fire projectiles, teleports frequently,
##   creates blood circles that heal him if he stands on them.
## Phase 2 (60-30%): Summons 2 shadow copies, dark nova periodically, life
##   drain beam on player.
## Phase 3 (30-0%): Transforms — grows larger, constant dark fire rain from
##   above, shadow copies permanent, devastating melee.
##
## Visual: Dark red/black CSGCylinder3D body wreathed in orbiting CSGSphere3D
## "flames". Floats above the ground.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 3500.0
	base_damage = 40.0
	speed = 4.0
	attack_range = 20.0
	attack_cooldown = 1.5
	base_exp_drop = 1300.0

# ---------------------------------------------------------------------------
# Boss-specific constants
# ---------------------------------------------------------------------------

const BOSS_NAME := "The Dark Apostle"

const PHASE_2_THRESHOLD := 0.6
const PHASE_3_THRESHOLD := 0.3

const FLOAT_HEIGHT := 2.0
const DARK_FIRE_COOLDOWN := 1.8
const DARK_FIRE_SPEED := 16.0
const TELEPORT_COOLDOWN := 4.0
const TELEPORT_RANGE := 14.0
const BLOOD_CIRCLE_COOLDOWN := 10.0
const BLOOD_CIRCLE_HEAL_RATE := 30.0
const BLOOD_CIRCLE_RADIUS := 3.0
const BLOOD_CIRCLE_DURATION := 8.0
const DARK_NOVA_RADIUS := 7.0
const DARK_NOVA_COOLDOWN := 6.0
const DARK_NOVA_DAMAGE_MULT := 1.2
const SHADOW_COPY_COOLDOWN := 12.0
const LIFE_DRAIN_COOLDOWN := 7.0
const LIFE_DRAIN_RANGE := 15.0
const LIFE_DRAIN_DURATION := 2.0
const LIFE_DRAIN_DPS := 15.0
const FIRE_RAIN_COOLDOWN := 3.0
const FIRE_RAIN_COUNT := 5
const MELEE_RANGE := 4.0
const MELEE_DAMAGE_MULT := 1.8
const TRANSFORM_SCALE := 1.3
const OPTIMAL_RANGE := 12.0

# ---------------------------------------------------------------------------
# Boss state
# ---------------------------------------------------------------------------

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

var _fire_timer: float = DARK_FIRE_COOLDOWN
var _teleport_timer: float = TELEPORT_COOLDOWN
var _blood_timer: float = BLOOD_CIRCLE_COOLDOWN
var _nova_timer: float = DARK_NOVA_COOLDOWN
var _shadow_timer: float = SHADOW_COPY_COOLDOWN
var _drain_timer: float = LIFE_DRAIN_COOLDOWN
var _rain_timer: float = FIRE_RAIN_COOLDOWN
var _is_attacking: bool = false
var _is_draining: bool = false
var _drain_elapsed: float = 0.0
var _blood_circles: Array = []  # Track active circles for healing

## Health bar
var _health_bar_bg: CSGBox3D = null
var _health_bar_fill: CSGBox3D = null
var _health_bar_mat: StandardMaterial3D = null

## Flame orb references
var _flame_orbs: Array[CSGSphere3D] = []
var _flame_orbit_angle: float = 0.0
var _flame_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.25, 0.02, 0.02)  # Very dark red/black

func _create_mesh() -> Node3D:
	# Robed body — tall cylinder
	var body := CSGCylinder3D.new()
	body.radius = 0.8
	body.height = 3.5
	body.sides = 12
	body.position = Vector3(0.0, FLOAT_HEIGHT + 1.75, 0.0)

	# Hood — cone-like top
	var hood := CSGCylinder3D.new()
	hood.radius = 0.5
	hood.height = 0.8
	hood.sides = 8
	hood.position = Vector3(0.0, 1.9, 0.0)
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.1, 0.0, 0.0)
	hood_mat.emission_enabled = true
	hood_mat.emission = Color(0.15, 0.0, 0.0)
	hood_mat.emission_energy_multiplier = 0.5
	hood.material = hood_mat
	body.add_child(hood)

	# Glowing eyes beneath hood
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.2, 0.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.2, 0.0)
	eye_mat.emission_energy_multiplier = 4.0

	var eye_l := CSGSphere3D.new()
	eye_l.radius = 0.1
	eye_l.radial_segments = 6
	eye_l.rings = 4
	eye_l.position = Vector3(-0.2, 1.65, -0.45)
	eye_l.material = eye_mat
	body.add_child(eye_l)

	var eye_r := CSGSphere3D.new()
	eye_r.radius = 0.1
	eye_r.radial_segments = 6
	eye_r.rings = 4
	eye_r.position = Vector3(0.2, 1.65, -0.45)
	eye_r.material = eye_mat
	body.add_child(eye_r)

	# Robe base — wider at bottom
	var base := CSGCylinder3D.new()
	base.radius = 1.0
	base.height = 0.6
	base.sides = 12
	base.position = Vector3(0.0, -1.5, 0.0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.15, 0.0, 0.0)
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.1, 0.0, 0.0)
	base_mat.emission_energy_multiplier = 0.3
	base.material = base_mat
	body.add_child(base)

	# Orbiting flame orbs
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_color = Color(1.0, 0.3, 0.0)
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.2, 0.0)
	_flame_mat.emission_energy_multiplier = 3.0

	for i in 3:
		var orb := CSGSphere3D.new()
		orb.radius = 0.2
		orb.radial_segments = 8
		orb.rings = 4
		orb.material = _flame_mat
		body.add_child(orb)
		_flame_orbs.append(orb)

	return body

func _create_collision_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.8
	capsule.height = 3.5
	return capsule

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, FLOAT_HEIGHT + 1.75, 0.0)

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
	_health_bar_bg.position = Vector3(0.0, FLOAT_HEIGHT + 5.5, 0.0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_bar_bg.material = bg_mat
	add_child(_health_bar_bg)

	_health_bar_fill = CSGBox3D.new()
	_health_bar_fill.size = Vector3(bar_width - 0.05, bar_height - 0.02, 0.06)
	_health_bar_fill.position = Vector3(0.0, FLOAT_HEIGHT + 5.5, 0.0)
	_health_bar_mat = StandardMaterial3D.new()
	_health_bar_mat.albedo_color = Color(0.8, 0.1, 0.0)
	_health_bar_mat.emission_enabled = true
	_health_bar_mat.emission = Color(0.8, 0.1, 0.0)
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
			_health_bar_mat.albedo_color = Color(1.0, 0.0, 0.0)
			_health_bar_mat.emission = Color(1.0, 0.0, 0.0)

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

	# -- Floating: maintain height (no gravity)
	velocity.y = (FLOAT_HEIGHT - (global_position.y)) * 2.0

	# -- Knockback decay
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * 2.0 * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	_update_phase()
	_update_health_bar()
	_face_health_bar_to_camera()
	_animate_flame_orbs(delta)
	_check_blood_circle_healing(delta)

	# -- Life drain beam
	if _is_draining:
		_drain_elapsed += delta
		if _drain_elapsed >= LIFE_DRAIN_DURATION:
			_is_draining = false
		else:
			_execute_drain_tick(delta)

	# -- Movement — maintain optimal range
	var move_dir := Vector3.ZERO
	var player := get_player()
	if player and is_instance_valid(player) and not _is_attacking:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if dist > OPTIMAL_RANGE + 3.0:
			move_dir = to_player.normalized()
		elif dist < OPTIMAL_RANGE - 3.0:
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
	_fire_timer -= delta
	_teleport_timer -= delta
	_blood_timer -= delta
	_nova_timer -= delta
	_shadow_timer -= delta
	_drain_timer -= delta
	_rain_timer -= delta

	match current_phase:
		Phase.ONE:
			_phase_one_logic(delta)
		Phase.TWO:
			_phase_two_logic(delta)
		Phase.THREE:
			_phase_three_logic(delta)

# ---------------------------------------------------------------------------
# Flame orb animation
# ---------------------------------------------------------------------------

func _animate_flame_orbs(delta: float) -> void:
	_flame_orbit_angle += delta * 2.5
	for i in _flame_orbs.size():
		var orb := _flame_orbs[i]
		if orb and is_instance_valid(orb):
			var angle := _flame_orbit_angle + (TAU / float(_flame_orbs.size())) * float(i)
			var orbit_r := 1.3
			orb.position = Vector3(
				cos(angle) * orbit_r,
				0.5 + sin(angle * 1.5) * 0.3,
				sin(angle) * orbit_r
			)

# ---------------------------------------------------------------------------
# Blood circle healing
# ---------------------------------------------------------------------------

func _check_blood_circle_healing(delta: float) -> void:
	# Check if boss is standing on any blood circle
	var cleaned := []
	for circle_data in _blood_circles:
		if is_instance_valid(circle_data["node"]):
			var circle_pos: Vector3 = circle_data["node"].global_position
			var dist := Vector2(global_position.x, global_position.z).distance_to(
				Vector2(circle_pos.x, circle_pos.z))
			if dist <= BLOOD_CIRCLE_RADIUS:
				health = minf(health + BLOOD_CIRCLE_HEAL_RATE * delta, max_health * wave_hp_mult)
			cleaned.append(circle_data)
	_blood_circles = cleaned

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
	if _flame_mat:
		_flame_mat.emission_energy_multiplier = 5.0
	if _base_material:
		_base_material.emission_energy_multiplier = 1.5

func _on_enter_phase_three() -> void:
	# Transform — grow larger and more menacing
	if _flame_mat:
		_flame_mat.emission_energy_multiplier = 8.0
		_flame_mat.emission = Color(1.0, 0.0, 0.0)
	if _base_material:
		_base_material.emission_energy_multiplier = 3.0
		_base_material.emission = Color(0.5, 0.0, 0.0)
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3.ONE * TRANSFORM_SCALE, 0.6)

# ---------------------------------------------------------------------------
# Phase logic
# ---------------------------------------------------------------------------

func _phase_one_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	if _fire_timer <= 0.0:
		_fire_dark_bolt(player)
	if _teleport_timer <= 0.0:
		_teleport()
	if _blood_timer <= 0.0:
		_create_blood_circle()

func _phase_two_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	if _fire_timer <= 0.0:
		_fire_dark_bolt(player)
	if _teleport_timer <= 0.0:
		_teleport()
	if _nova_timer <= 0.0:
		_dark_nova()
	if _shadow_timer <= 0.0:
		_summon_shadow_copies()
	if _drain_timer <= 0.0:
		_begin_life_drain()
	if _blood_timer <= 0.0:
		_create_blood_circle()

func _phase_three_logic(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)

	if _fire_timer <= 0.0:
		_fire_dark_bolt(player)
	if _rain_timer <= 0.0:
		_fire_rain()
	if _nova_timer <= 0.0:
		_dark_nova()
	if _shadow_timer <= 0.0:
		_summon_shadow_copies()
	if _teleport_timer <= 0.0:
		_teleport()
	# Devastating melee if player gets close
	if dist <= MELEE_RANGE and _attack_timer <= 0.0:
		_melee_strike(player)

# ---------------------------------------------------------------------------
# Attacks
# ---------------------------------------------------------------------------

func _fire_dark_bolt(target: Node3D) -> void:
	_fire_timer = DARK_FIRE_COOLDOWN
	if current_phase == Phase.THREE:
		_fire_timer *= 0.5

	var spawn_pos := global_position + Vector3(0, FLOAT_HEIGHT + 1.5, 0)
	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()

	var proj := _DarkFireProjectile.new()
	proj.global_position = spawn_pos
	proj.direction = dir
	proj.projectile_speed = DARK_FIRE_SPEED
	proj.damage = base_damage * wave_dmg_mult * 0.5
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)

func _teleport() -> void:
	_teleport_timer = TELEPORT_COOLDOWN
	if current_phase != Phase.ONE:
		_teleport_timer *= 0.7

	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var angle := randf() * TAU
	var dist := TELEPORT_RANGE * (0.5 + randf() * 0.5)
	var new_pos := player.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	new_pos.y = FLOAT_HEIGHT
	global_position = new_pos

func _create_blood_circle() -> void:
	_blood_timer = BLOOD_CIRCLE_COOLDOWN
	var circle_pos := global_position
	circle_pos.y = 0.05

	var circle := CSGCylinder3D.new()
	circle.radius = BLOOD_CIRCLE_RADIUS
	circle.height = 0.05
	circle.sides = 20
	circle.global_position = circle_pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.0, 0.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.0, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	circle.material = mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(circle)
		_blood_circles.append({"node": circle})
		var tw := circle.create_tween()
		tw.tween_interval(BLOOD_CIRCLE_DURATION)
		tw.tween_property(mat, "albedo_color:a", 0.0, 1.0)
		tw.tween_callback(circle.queue_free)

func _dark_nova() -> void:
	_nova_timer = DARK_NOVA_COOLDOWN
	if current_phase == Phase.THREE:
		_nova_timer *= 0.6

	# Telegraph: fire intensifies
	if _flame_mat:
		var orig := _flame_mat.emission_energy_multiplier
		_flame_mat.emission_energy_multiplier = 12.0
		get_tree().create_timer(0.4).timeout.connect(func():
			if _flame_mat:
				_flame_mat.emission_energy_multiplier = orig
		)

	get_tree().create_timer(0.4).timeout.connect(_execute_dark_nova)

func _execute_dark_nova() -> void:
	if not is_alive:
		return
	var player := get_player()
	if player and is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist <= DARK_NOVA_RADIUS:
			var falloff := 1.0 - (dist / DARK_NOVA_RADIUS) * 0.5
			var dmg := base_damage * wave_dmg_mult * DARK_NOVA_DAMAGE_MULT * falloff
			if player.has_method("take_damage"):
				player.take_damage(dmg, self)
			if player is CharacterBody3D:
				var kb := (player.global_position - global_position).normalized()
				player.velocity += kb * 10.0
	_spawn_nova_ring()

func _spawn_nova_ring() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.5
	ring.height = 0.15
	ring.sides = 24
	ring.global_position = global_position
	ring.global_position.y = 0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.0, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.1, 0.0)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", DARK_NOVA_RADIUS, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

func _summon_shadow_copies() -> void:
	_shadow_timer = SHADOW_COPY_COOLDOWN
	if current_phase == Phase.THREE:
		_shadow_timer *= 0.6

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in 2:
		var shadow := EnemyRanged.new()
		var angle := (TAU / 2.0) * float(i) + randf() * 0.5
		var offset := Vector3(cos(angle) * 5.0, 0.0, sin(angle) * 5.0)
		var spawn_pos := global_position + offset
		spawn_pos.y = 0.0
		shadow.initialize(wave_hp_mult * 0.3, wave_dmg_mult * 0.5, wave_speed_mult)
		scene_root.add_child(shadow)
		shadow.global_position = spawn_pos
		GameManager.register_enemies(1)

func _begin_life_drain() -> void:
	_drain_timer = LIFE_DRAIN_COOLDOWN
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > LIFE_DRAIN_RANGE:
		return
	_is_draining = true
	_drain_elapsed = 0.0

func _execute_drain_tick(delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		_is_draining = false
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > LIFE_DRAIN_RANGE:
		_is_draining = false
		return
	var dmg := LIFE_DRAIN_DPS * delta * wave_dmg_mult
	if player.has_method("take_damage"):
		player.take_damage(dmg, self)
	# Heal self
	health = minf(health + dmg * 0.5, max_health * wave_hp_mult)

func _fire_rain() -> void:
	_rain_timer = FIRE_RAIN_COOLDOWN

	# Telegraph: raised hands (mesh scale briefly)
	if _flame_mat:
		_flame_mat.emission_energy_multiplier += 4.0
		get_tree().create_timer(0.5).timeout.connect(func():
			if _flame_mat:
				_flame_mat.emission_energy_multiplier -= 4.0
		)

	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	# Spawn fire rain around player position
	for i in FIRE_RAIN_COUNT:
		var offset := Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
		var target_pos := player.global_position + offset
		get_tree().create_timer(i * 0.3).timeout.connect(
			_spawn_fire_rain_impact.bind(target_pos)
		)

func _spawn_fire_rain_impact(target_pos: Vector3) -> void:
	if not is_alive:
		return
	# Warning indicator on ground
	var indicator := CSGCylinder3D.new()
	indicator.radius = 1.5
	indicator.height = 0.05
	indicator.sides = 12
	indicator.global_position = target_pos
	indicator.global_position.y = 0.05
	var ind_mat := StandardMaterial3D.new()
	ind_mat.albedo_color = Color(1.0, 0.2, 0.0, 0.4)
	ind_mat.emission_enabled = true
	ind_mat.emission = Color(1.0, 0.1, 0.0)
	ind_mat.emission_energy_multiplier = 2.0
	ind_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator.material = ind_mat

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(indicator)
		# After brief delay, deal damage at impact
		get_tree().create_timer(0.5).timeout.connect(func():
			if not is_alive:
				if is_instance_valid(indicator):
					indicator.queue_free()
				return
			var player := get_player()
			if player and is_instance_valid(player):
				var dist := player.global_position.distance_to(target_pos)
				if dist <= 2.0:
					var dmg := base_damage * wave_dmg_mult * 0.6
					if player.has_method("take_damage"):
						player.take_damage(dmg, self)
			if is_instance_valid(indicator):
				var tw := indicator.create_tween()
				tw.tween_property(ind_mat, "albedo_color:a", 0.0, 0.5)
				tw.tween_callback(indicator.queue_free)
		)

func _melee_strike(player: Node3D) -> void:
	_attack_timer = attack_cooldown
	var effective_damage := base_damage * wave_dmg_mult * MELEE_DAMAGE_MULT
	if player.has_method("take_damage"):
		player.take_damage(effective_damage, self)
	if player is CharacterBody3D:
		var kb := (player.global_position - global_position).normalized()
		player.velocity += kb * 12.0
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.2, 0.9, 1.2), 0.08)
		tw.tween_property(_mesh, "scale", Vector3.ONE * (TRANSFORM_SCALE if current_phase == Phase.THREE else 1.0), 0.12)

# ---------------------------------------------------------------------------
# Damage / Death
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	super.take_damage(amount, knockback_dir * 0.15)

func die() -> void:
	if not is_alive:
		return
	is_alive = false

	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)
	_drop_health()
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
	ring.global_position = global_position + Vector3(0, 0.5 + index * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.0)
	mat.emission_energy_multiplier = 6.0
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

# ---------------------------------------------------------------------------
# Inner class: Dark fire projectile
# ---------------------------------------------------------------------------

class _DarkFireProjectile:
	extends Area3D

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 16.0
	var damage: float = 18.0
	var _lifetime: float = 5.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.2
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.1, 0.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.0)
		mat.emission_energy_multiplier = 3.0
		sphere.material = mat
		add_child(sphere)

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
			body.take_damage(damage, self)
		queue_free()
