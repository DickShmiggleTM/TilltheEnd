class_name EnemyDigger
extends EnemyBase
## Burrower — an underground predator that tracks the player while invisible,
## then surfaces with a devastating ambush strike.
##
## State machine: SURFACE → BURROWING → UNDERGROUND → EMERGING → SURFACE
##
## Unique behaviours:
##   • Underground tracking: while burrowed the enemy teleports below the
##     floor and moves directly toward the player's XZ position, ignoring
##     walls. A pulsing ground-ripple indicator reveals its path.
##   • Emerge ambush: surfaces with a circular shockwave that damages and
##     knocks back the player. If the player is within 1.5 m of the emerge
##     point, a bonus ambush-damage multiplier applies.
##   • Feint pop: 25 % chance to burst halfway up, then immediately re-burrow
##     at a slightly different position before the true emerge — baiting
##     the player's fire.
##   • Surface attacks: once above ground, makes 2-3 quick melee strikes
##     before burrowing again. Does not stay on the surface indefinitely.
##
## Sprite: ratman_paletted.png

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health   = 40.0
	base_damage  = 18.0
	speed        = 4.5
	attack_range = 2.0
	attack_cooldown = 0.9
	base_exp_drop = 22.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path := "res://scenes/ratman_paletted.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 4

func _get_sprite_height() -> float:
	return 0.8

func _get_sprite_fps() -> float:
	return 8.0

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.006

func _get_enemy_color() -> Color:
	return Color(0.45, 0.3, 0.15)   # Earthy brown fallback

# ---------------------------------------------------------------------------
# Collision shape
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.1
	return cap

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.55, 0.0)

# ---------------------------------------------------------------------------
# Digger constants
# ---------------------------------------------------------------------------

# Surface phase
const SURFACE_ATTACKS_BEFORE_BURROW := 3     ## After this many attacks, burrow again
const SURFACE_MAX_DURATION := 5.0            ## Failsafe: burrow if still up this long

# Burrow / emerge transitions
const BURROW_SPEED_ANIM := 0.45             ## Seconds to sink into the ground
const EMERGE_SPEED_ANIM := 0.4             ## Seconds to rise from the ground

# Underground movement
const UNDERGROUND_Y_OFFSET := -0.6          ## How far below spawn_y to travel
const UNDERGROUND_SPEED := 7.0              ## XZ speed while burrowed (fast tracking)

# Trigger distances
const BURROW_TRIGGER_DIST_MIN := 6.0        ## Burrow if farther than this from player
const BURROW_TRIGGER_DIST_MAX := 14.0
const EMERGE_TRIGGER_DIST := 1.8            ## Emerge when within this dist of player XZ

# Emerge attack
const EMERGE_SHOCKWAVE_RADIUS := 2.8
const EMERGE_AMBUSH_RADIUS := 1.5
const EMERGE_AMBUSH_MULT := 2.0             ## Extra damage if player very close on emerge
const EMERGE_KNOCKBACK := 10.0

# Feint
const FEINT_CHANCE := 0.25                 ## Probability of feint on any emerge
const FEINT_RISE_HEIGHT := 0.8             ## Partial rise during feint
const FEINT_DURATION := 0.3               ## Brief visibility before re-burrowing

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

enum DigState { SURFACE, BURROWING, UNDERGROUND, EMERGING, FEINTING }
var _dig_state: DigState = DigState.SURFACE

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _spawn_y: float = 0.0           ## Floor Y captured on _ready
var _surface_attack_count: int = 0
var _surface_timer: float = 0.0

var _transition_timer: float = 0.0  ## Burrow / emerge animation timer

# Underground
var _underground_target: Vector3 = Vector3.ZERO
var _feint_pending: bool = false

# Ground indicator node (visible while burrowed, follows XZ position)
var _indicator: Node3D = null
var _indicator_material: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_spawn_y = global_position.y
	# Decide initial burrow delay
	_surface_timer = 0.5 + randf() * 1.0
	# Create ground indicator
	_create_indicator()

# ---------------------------------------------------------------------------
# Ground indicator (ripple that shows underground position to player)
# ---------------------------------------------------------------------------

func _create_indicator() -> void:
	_indicator = Node3D.new()
	_indicator.visible = false

	# Outer ring
	var ring := CSGCylinder3D.new()
	ring.radius = 0.55
	ring.height = 0.06
	ring.sides = 16
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.albedo_color = Color(0.4, 0.25, 0.05, 0.65)
	_indicator_material.emission_enabled = true
	_indicator_material.emission = Color(0.6, 0.35, 0.1)
	_indicator_material.emission_energy_multiplier = 2.5
	_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = _indicator_material
	ring.position = Vector3(0, 0.04, 0)
	_indicator.add_child(ring)

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(_indicator)

# ---------------------------------------------------------------------------
# Main physics dispatch
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		if is_instance_valid(_indicator):
			_indicator.queue_free()
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)

	match _dig_state:
		DigState.SURFACE:
			_tick_surface(delta)
		DigState.BURROWING:
			_tick_burrowing(delta)
		DigState.UNDERGROUND:
			_tick_underground(delta)
		DigState.EMERGING:
			_tick_emerging(delta)
		DigState.FEINTING:
			_tick_feinting(delta)

	# Keep indicator above ground following XZ
	if is_instance_valid(_indicator):
		_indicator.global_position = Vector3(global_position.x, _spawn_y + 0.05, global_position.z)

# ---------------------------------------------------------------------------
# SURFACE: normal ground combat
# ---------------------------------------------------------------------------

func _tick_surface(delta: float) -> void:
	_surface_timer -= delta

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	var player := get_player()
	var move_dir := Vector3.ZERO

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var forward := to_player.normalized()

		if dist > 0.1:
			look_at(global_position + Vector3(to_player.x, 0.0, to_player.z), Vector3.UP)

		if dist > attack_range * 0.8:
			move_dir = forward

		if _sprite_billboard:
			_sprite_billboard.set_walking()

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

	# Burrow after enough attacks or time
	if (_surface_attack_count >= SURFACE_ATTACKS_BEFORE_BURROW
			or _surface_timer <= 0.0):
		_enter_burrowing()

# ---------------------------------------------------------------------------
# BURROWING: sink below ground
# ---------------------------------------------------------------------------

func _tick_burrowing(delta: float) -> void:
	_transition_timer -= delta
	var progress := 1.0 - clampf(_transition_timer / BURROW_SPEED_ANIM, 0.0, 1.0)
	global_position.y = lerpf(_spawn_y, _spawn_y + UNDERGROUND_Y_OFFSET, progress)

	# Fade out sprite as it sinks
	if _sprite_billboard:
		_sprite_billboard.modulate.a = 1.0 - progress

	if _transition_timer <= 0.0:
		_enter_underground()


func _enter_burrowing() -> void:
	_dig_state = DigState.BURROWING
	_transition_timer = BURROW_SPEED_ANIM
	_surface_attack_count = 0
	_surface_timer = SURFACE_MAX_DURATION

	# Disable collision so we can pass through walls underground
	collision_layer = 0
	collision_mask = 0

	if _sprite_billboard:
		_sprite_billboard.visible = true

	if is_instance_valid(_indicator):
		_indicator.visible = true
		_indicator_material.emission_energy_multiplier = 0.5

# ---------------------------------------------------------------------------
# UNDERGROUND: invisible tracking
# ---------------------------------------------------------------------------

func _tick_underground(delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	# Move toward player XZ at underground speed
	var target := Vector3(player.global_position.x, _spawn_y + UNDERGROUND_Y_OFFSET,
		player.global_position.z)
	var to_target := target - global_position
	if to_target.length() > 0.05:
		global_position += to_target.normalized() * UNDERGROUND_SPEED * wave_speed_mult * delta

	# Keep at underground depth
	global_position.y = _spawn_y + UNDERGROUND_Y_OFFSET

	# Pulse the indicator
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	if is_instance_valid(_indicator_material):
		_indicator_material.emission_energy_multiplier = 1.5 + pulse * 2.0

	# Emerge when close enough to player's XZ
	var xz_dist := Vector2(global_position.x, global_position.z).distance_to(
		Vector2(player.global_position.x, player.global_position.z))

	if xz_dist <= EMERGE_TRIGGER_DIST:
		_feint_pending = randf() < FEINT_CHANCE
		if _feint_pending:
			_enter_feinting()
		else:
			_enter_emerging()


func _enter_underground() -> void:
	_dig_state = DigState.UNDERGROUND
	if _sprite_billboard:
		_sprite_billboard.visible = false
		_sprite_billboard.modulate.a = 1.0   # Reset alpha

# ---------------------------------------------------------------------------
# EMERGING: rise from the ground with a shockwave
# ---------------------------------------------------------------------------

func _tick_emerging(delta: float) -> void:
	_transition_timer -= delta
	var progress := 1.0 - clampf(_transition_timer / EMERGE_SPEED_ANIM, 0.0, 1.0)
	global_position.y = lerpf(_spawn_y + UNDERGROUND_Y_OFFSET, _spawn_y, progress)

	if _sprite_billboard:
		_sprite_billboard.modulate.a = progress

	if _transition_timer <= 0.0:
		_finish_emerging()


func _enter_emerging() -> void:
	_dig_state = DigState.EMERGING
	_transition_timer = EMERGE_SPEED_ANIM

	# Restore collision
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 32

	if _sprite_billboard:
		_sprite_billboard.visible = true
		_sprite_billboard.modulate.a = 0.0
		_sprite_billboard.trigger_attack()

	if is_instance_valid(_indicator):
		_indicator.visible = false


func _finish_emerging() -> void:
	global_position.y = _spawn_y
	_dig_state = DigState.SURFACE
	_surface_attack_count = 0
	_surface_timer = SURFACE_MAX_DURATION

	# Emit shockwave and deal ambush damage
	_do_emerge_attack()
	_spawn_emerge_shockwave()

# ---------------------------------------------------------------------------
# FEINTING: partial rise, brief pause, re-burrow at a shifted position
# ---------------------------------------------------------------------------

func _tick_feinting(delta: float) -> void:
	_transition_timer -= delta
	if _transition_timer <= 0.0:
		# Shift position laterally then go back underground
		var offset := Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		global_position.x += offset.x
		global_position.z += offset.z
		global_position.y = _spawn_y + UNDERGROUND_Y_OFFSET
		if _sprite_billboard:
			_sprite_billboard.visible = false
		_enter_underground()


func _enter_feinting() -> void:
	_dig_state = DigState.FEINTING
	_transition_timer = FEINT_DURATION

	# Rise partway to tease the player
	global_position.y = _spawn_y + UNDERGROUND_Y_OFFSET + FEINT_RISE_HEIGHT
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 32

	if _sprite_billboard:
		_sprite_billboard.visible = true
		_sprite_billboard.modulate.a = 0.6

	if is_instance_valid(_indicator):
		_indicator.visible = false

# ---------------------------------------------------------------------------
# Emerge attack — shockwave + melee
# ---------------------------------------------------------------------------

func _do_emerge_attack() -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= EMERGE_SHOCKWAVE_RADIUS:
		var falloff := 1.0 - (dist / EMERGE_SHOCKWAVE_RADIUS)
		var dmg := base_damage * wave_dmg_mult * falloff

		# Ambush bonus if player was very close
		if dist <= EMERGE_AMBUSH_RADIUS:
			dmg *= EMERGE_AMBUSH_MULT

		if player.has_method("take_damage"):
			player.take_damage(dmg, self)

		if player is CharacterBody3D:
			var kb := (player.global_position - global_position).normalized()
			kb.y = 0.25
			player.velocity += kb * EMERGE_KNOCKBACK * falloff

	_attack_timer = attack_cooldown


func _spawn_emerge_shockwave() -> void:
	var ring := CSGCylinder3D.new()
	ring.radius = 0.2
	ring.height = 0.12
	ring.sides = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.35, 0.1, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.45, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	ring.global_position = global_position + Vector3(0, 0.06, 0)

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "radius", EMERGE_SHOCKWAVE_RADIUS, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)

# ---------------------------------------------------------------------------
# Standard melee (surface attacks)
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	if _dig_state != DigState.SURFACE:
		return
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		if player.has_method("take_damage"):
			player.take_damage(base_damage * wave_dmg_mult, self)
		_attack_timer = attack_cooldown
		_surface_attack_count += 1
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Burrow trigger from range (also burrowed if player walks away while surface)
# ---------------------------------------------------------------------------

func _physics_process_extra_check(delta: float) -> void:
	if _dig_state != DigState.SURFACE:
		return
	var player := get_player()
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist >= BURROW_TRIGGER_DIST_MAX:
		_enter_burrowing()

# ---------------------------------------------------------------------------
# Cleanup indicator on death
# ---------------------------------------------------------------------------

func _on_death_effects() -> void:
	if is_instance_valid(_indicator):
		_indicator.queue_free()
