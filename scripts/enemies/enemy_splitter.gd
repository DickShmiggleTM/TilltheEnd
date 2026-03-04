class_name EnemySplitter
extends EnemyBase
## Fission Hulk (large) / Fission Spawn (small) — a bloated creature that
## bursts into 2-3 smaller, faster copies on death.
##
## Large form unique behaviours:
##   • Body slam: telegraphs by rearing back, then leaps forward to crush
##     the player, dealing high damage + heavy knockback.
##   • Sticky spit: hurls a slow-moving glob that, on hit, reduces the
##     player's move speed by 30 % for 3 s.
##   • On-death split: spawns 2-3 small Fission Spawns at scatter angles.
##
## Small form unique behaviours:
##   • Roll charge: curls into a ball and accelerates directly at the player
##     for 0.5 s, dealing knock-on-contact damage. 4 s cooldown.
##   • Skittish approach: erratic path (tight S-curves) makes small forms
##     harder to hit than their low HP suggests.
##   • No further split on death.
##
## Sprites:
##   Large: outcast_paletted.png
##   Small: hindring_paletted.png

# ---------------------------------------------------------------------------
# Configuration flag — set BEFORE add_child() to get small-form stats
# ---------------------------------------------------------------------------

var _is_small: bool = false      ## Set by parent on the spawned child node
var _split_count: int = 2        ## Large: how many children to spawn (2 or 3)

# ---------------------------------------------------------------------------
# Overridden base stats — configured in _ready() after _is_small is known
# ---------------------------------------------------------------------------

func _init() -> void:
	# Large-form defaults (may be overridden in _ready if _is_small = true)
	max_health   = 55.0
	base_damage  = 12.0
	speed        = 2.8
	attack_range = 2.0
	attack_cooldown = 1.4
	base_exp_drop = 25.0

# ---------------------------------------------------------------------------
# Sprite configuration
# ---------------------------------------------------------------------------

func _get_sprite_texture() -> Texture2D:
	var path: String
	if _is_small:
		path = "res://scenes/hindring_paletted.png"
	else:
		path = "res://scenes/outcast_paletted.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_sprite_num_directions() -> int:
	return 4

func _get_sprite_frames_per_dir() -> int:
	return 4

func _get_sprite_height() -> float:
	return 0.85 if not _is_small else 0.45

func _get_sprite_fps() -> float:
	return 6.0 if not _is_small else 10.0

func _get_sprite_use_mirror() -> bool:
	return true

func _get_sprite_pixel_size() -> float:
	return 0.007 if not _is_small else 0.004

func _get_enemy_color() -> Color:
	return Color(0.7, 0.4, 0.9) if not _is_small else Color(0.9, 0.5, 1.0)

# ---------------------------------------------------------------------------
# Collision shape — larger for big form
# ---------------------------------------------------------------------------

func _create_collision_shape() -> Shape3D:
	if _is_small:
		var s := SphereShape3D.new()
		s.radius = 0.28
		return s
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.4, 0.9)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.7, 0.0) if not _is_small else Vector3(0.0, 0.28, 0.0)

# ---------------------------------------------------------------------------
# Large-form constants
# ---------------------------------------------------------------------------

const SLAM_RANGE := 3.5           ## Distance to trigger body slam
const SLAM_COOLDOWN := 5.0
const SLAM_LEAP_SPEED := 9.0      ## Horizontal surge during slam
const SLAM_LEAP_DURATION := 0.4
const SLAM_DAMAGE_MULT := 1.8
const SLAM_KNOCKBACK := 12.0

const SPIT_RANGE := 10.0
const SPIT_COOLDOWN := 4.0
const SPIT_SLOW := 0.7            ## Speed multiplier applied to player (0.7 = 30 % slow)
const SPIT_SLOW_DURATION := 3.0
const SPIT_SPEED := 8.0

# Small-form constants
const ROLL_RANGE := 8.0           ## Trigger roll within this dist
const ROLL_COOLDOWN := 4.0
const ROLL_SPEED := 11.0
const ROLL_DURATION := 0.5
const ROLL_DAMAGE_MULT := 1.3

const SKITTER_FREQUENCY := 5.0
const SKITTER_AMPLITUDE := 0.55

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _slam_timer: float = 1.5
var _is_slamming: bool = false
var _slam_leap_timer: float = 0.0
var _slam_dir: Vector3 = Vector3.ZERO

var _spit_timer: float = 2.0
var _spit_used: bool = false       ## Small form doesn't spit

var _roll_timer: float = 2.0
var _is_rolling: bool = false
var _roll_countdown: float = 0.0
var _roll_dir: Vector3 = Vector3.ZERO

var _skitter_time: float = 0.0
var _skitter_offset: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Apply small-form stat overrides BEFORE super._ready builds everything
	if _is_small:
		max_health   = 14.0 * wave_hp_mult
		base_damage  = 6.0
		speed        = 5.5
		attack_range = 1.5
		attack_cooldown = 0.6
		base_exp_drop = 8.0

	super._ready()

	_split_count = 2 + randi() % 2   # 2 or 3 children
	_skitter_offset = randf() * TAU

	if _is_small and _sprite_billboard:
		_sprite_billboard.set_tint(Color(1.1, 0.7, 1.3))  # Lighter tint for children

# ---------------------------------------------------------------------------
# Physics override
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	if _is_small:
		_tick_small(delta)
	else:
		_tick_large(delta)

# ---------------------------------------------------------------------------
# Large-form physics
# ---------------------------------------------------------------------------

func _tick_large(delta: float) -> void:
	# During slam leap
	if _is_slamming:
		_slam_leap_timer -= delta
		if _slam_leap_timer <= 0.0:
			_is_slamming = false
			_slam_timer = SLAM_COOLDOWN
		else:
			var eff := SLAM_LEAP_SPEED * slow_mult
			velocity.x = _slam_dir.x * eff
			velocity.z = _slam_dir.z * eff
			move_and_slide()
			# Check if we've reached the player during leap
			_check_slam_hit()
		_attack_timer -= delta
		return

	_slam_timer -= delta
	_spit_timer -= delta

	var player := get_player()
	var move_dir := Vector3.ZERO
	var dist := INF

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		var forward := to_player.normalized()

		if dist > 0.1:
			look_at(global_position + Vector3(to_player.x, 0.0, to_player.z), Vector3.UP)

		if dist > attack_range * 0.9:
			move_dir = forward

		if _sprite_billboard:
			_sprite_billboard.set_walking()

		# Body slam trigger
		if _slam_timer <= 0.0 and dist <= SLAM_RANGE:
			_start_slam(forward)
			_attack_timer -= delta
			return

		# Spit trigger
		if _spit_timer <= 0.0 and dist <= SPIT_RANGE:
			_fire_spit(player)
			_spit_timer = SPIT_COOLDOWN

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Small-form physics — skittish S-curve approach + roll charge
# ---------------------------------------------------------------------------

func _tick_small(delta: float) -> void:
	# Roll charge state
	if _is_rolling:
		_roll_countdown -= delta
		if _roll_countdown <= 0.0:
			_is_rolling = false
			_roll_timer = ROLL_COOLDOWN
			if _sprite_billboard:
				_sprite_billboard.reset_tint()
		else:
			velocity.x = _roll_dir.x * ROLL_SPEED
			velocity.z = _roll_dir.z * ROLL_SPEED
			move_and_slide()
			_check_roll_hit()
		_attack_timer -= delta
		return

	_roll_timer -= delta

	var player := get_player()
	var move_dir := Vector3.ZERO
	var dist := INF

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		var forward := to_player.normalized()

		# Skittish S-curve
		var right := Vector3(-forward.z, 0.0, forward.x)
		_skitter_time += delta
		var offset := sin(_skitter_time * SKITTER_FREQUENCY + _skitter_offset) * SKITTER_AMPLITUDE
		move_dir = (forward + right * offset).normalized()

		if move_dir.length() > 0.1:
			look_at(global_position + Vector3(move_dir.x, 0.0, move_dir.z), Vector3.UP)

		if _sprite_billboard:
			_sprite_billboard.set_walking()

		# Roll trigger
		if _roll_timer <= 0.0 and dist <= ROLL_RANGE and dist > attack_range:
			_start_roll(forward)
			_attack_timer -= delta
			return

	var eff_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * eff_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Standard melee attack
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		if player.has_method("take_damage"):
			player.take_damage(base_damage * wave_dmg_mult, self)
		_attack_timer = attack_cooldown
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Body slam (large form)
# ---------------------------------------------------------------------------

func _start_slam(direction: Vector3) -> void:
	_is_slamming = true
	_slam_leap_timer = SLAM_LEAP_DURATION
	_slam_dir = direction
	if _sprite_billboard:
		_sprite_billboard.trigger_attack()


func _check_slam_hit() -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range * 1.3 and _attack_timer <= 0.0:
		var dmg := base_damage * wave_dmg_mult * SLAM_DAMAGE_MULT
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)
		if player is CharacterBody3D:
			var kb := (player.global_position - global_position).normalized()
			player.velocity += kb * SLAM_KNOCKBACK
		_attack_timer = attack_cooldown
		_is_slamming = false
		_slam_timer = SLAM_COOLDOWN

# ---------------------------------------------------------------------------
# Sticky spit (large form)
# ---------------------------------------------------------------------------

func _fire_spit(target: Node3D) -> void:
	var proj := _SpitGlob.new()
	var spawn_pos := global_position + Vector3(0.0, 1.0, 0.0)
	proj.global_position = spawn_pos
	proj.direction = (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()
	proj.speed = SPIT_SPEED
	proj.slow_mult = SPIT_SLOW
	proj.slow_duration = SPIT_SLOW_DURATION

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(proj)
	if _sprite_billboard:
		_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Roll charge (small form)
# ---------------------------------------------------------------------------

func _start_roll(direction: Vector3) -> void:
	_is_rolling = true
	_roll_countdown = ROLL_DURATION
	_roll_dir = direction
	if _sprite_billboard:
		_sprite_billboard.set_tint(Color(1.4, 0.4, 1.6))   # Bright magenta roll
		_sprite_billboard.trigger_attack()


func _check_roll_hit() -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range * 1.2 and _attack_timer <= 0.0:
		var dmg := base_damage * wave_dmg_mult * ROLL_DAMAGE_MULT
		if player.has_method("take_damage"):
			player.take_damage(dmg, self)
		_attack_timer = attack_cooldown
		_is_rolling = false
		_roll_timer = ROLL_COOLDOWN
		if _sprite_billboard:
			_sprite_billboard.reset_tint()

# ---------------------------------------------------------------------------
# Death — spawn children (large form only)
# ---------------------------------------------------------------------------

func die() -> void:
	if not _is_small:
		_spawn_children()
	super.die()


func _spawn_children() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	for i in _split_count:
		var child := EnemySplitter.new()
		child._is_small = true

		# Scatter angle so children fan out
		var angle := (TAU / float(_split_count)) * i + randf_range(-0.3, 0.3)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.8
		child.global_position = global_position + offset + Vector3(0, 0.1, 0)

		# Pass wave scaling to children (softer HP mult)
		child.wave_hp_mult = wave_hp_mult * 0.5
		child.wave_dmg_mult = wave_dmg_mult
		child.wave_speed_mult = wave_speed_mult

		scene_root.add_child(child)
		# Register with GameManager so wave tracking stays accurate
		GameManager.register_enemies(1)

	# Burst visual
	_spawn_split_visual()


func _spawn_split_visual() -> void:
	for i in _split_count:
		var angle := (TAU / float(_split_count)) * i
		var shard := CSGSphere3D.new()
		shard.radius = 0.15
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.4, 1.0, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.2, 0.9)
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shard.material = mat
		var scene_root := get_tree().current_scene
		if scene_root:
			shard.global_position = global_position + Vector3(0, 0.6, 0)
			scene_root.add_child(shard)
			var tw := shard.create_tween()
			var target := shard.global_position + Vector3(cos(angle), 0.3, sin(angle)) * 1.2
			tw.set_parallel(true)
			tw.tween_property(shard, "global_position", target, 0.35).set_ease(Tween.EASE_OUT)
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
			tw.set_parallel(false)
			tw.tween_callback(shard.queue_free)

# ---------------------------------------------------------------------------
# Inner class: sticky spit projectile
# ---------------------------------------------------------------------------

class _SpitGlob extends Area3D:

	var direction: Vector3 = Vector3.FORWARD
	var speed: float = 8.0
	var slow_mult: float = 0.7
	var slow_duration: float = 3.0
	var _lifetime: float = 4.0

	func _ready() -> void:
		collision_layer = 8
		collision_mask = 2

		var sphere := CSGSphere3D.new()
		sphere.radius = 0.22
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.8, 0.1, 0.85)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.7, 0.05)
		mat.emission_energy_multiplier = 1.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sphere.material = mat
		add_child(sphere)

		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.22
		col.shape = shape
		add_child(col)

		body_entered.connect(_on_body_entered)

	func _physics_process(delta: float) -> void:
		# Arc downward slightly (gravity)
		direction.y -= 2.0 * delta
		global_position += direction * speed * delta
		_lifetime -= delta
		if _lifetime <= 0.0:
			queue_free()

	func _on_body_entered(body: Node3D) -> void:
		if body.has_method("apply_slow"):
			body.apply_slow(slow_mult, slow_duration)
		elif body is CharacterBody3D and "slow_mult" in body:
			# Fallback: direct slow field
			body.slow_mult = minf(body.slow_mult, slow_mult)
			var t := body.get_tree().create_timer(slow_duration)
			t.timeout.connect(func():
				if is_instance_valid(body) and "slow_mult" in body:
					body.slow_mult = 1.0)
		queue_free()
