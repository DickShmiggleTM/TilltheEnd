class_name EnemyRanged
extends EnemyBase
## Green ranged shooter enemy. Keeps distance from the player and fires
## projectiles while strafing sideways.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 20.0
	base_damage = 6.0
	speed = 3.0
	attack_range = 15.0
	attack_cooldown = 1.5
	base_exp_drop = 15.0

# ---------------------------------------------------------------------------
# Ranged-specific
# ---------------------------------------------------------------------------

const OPTIMAL_RANGE_MIN := 8.0
const OPTIMAL_RANGE_MAX := 12.0
const STRAFE_SPEED := 2.5
const PROJECTILE_SPEED := 15.0

var _strafe_direction: float = 1.0   # 1.0 = right, -1.0 = left
var _strafe_timer: float = 0.0
const STRAFE_SWITCH_TIME := 2.0

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.2, 0.85, 0.2)  # Green


func _create_mesh() -> Node3D:
	var cylinder := CSGCylinder3D.new()
	cylinder.radius = 0.35
	cylinder.height = 1.3
	cylinder.sides = 8
	cylinder.position = Vector3(0.0, 0.65, 0.0)
	return cylinder


func _create_collision_shape() -> Shape3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.3
	return capsule


func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.65, 0.0)

# ---------------------------------------------------------------------------
# Movement override — maintain optimal range + strafe
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

	# -- Knockback decay -------------------------------------------------
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Ranged positioning logic ----------------------------------------
	var move_dir := Vector3.ZERO
	var player := get_player()

	if player and is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var forward := to_player.normalized()

		# Move toward or away to maintain optimal range
		if dist > OPTIMAL_RANGE_MAX:
			move_dir += forward
		elif dist < OPTIMAL_RANGE_MIN:
			move_dir -= forward

		# Strafe perpendicular to player direction
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_direction *= -1.0
			_strafe_timer = STRAFE_SWITCH_TIME + randf() * 1.0

		var strafe := Vector3(-forward.z, 0.0, forward.x) * _strafe_direction
		move_dir += strafe * 0.6
		move_dir = move_dir.normalized()

		# Face player
		if to_player.length() > 0.1:
			var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
			look_at(look_target, Vector3.UP)

	# Apply movement
	var effective_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	# -- Attack logic ----------------------------------------------------
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Attack — fire a projectile at the player
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		_fire_projectile(player)
		_attack_timer = attack_cooldown


func _fire_projectile(target: Node3D) -> void:
	var projectile := _EnemyProjectile.new()
	var spawn_pos := global_position + Vector3(0.0, 0.8, 0.0)
	projectile.global_position = spawn_pos

	var dir := (target.global_position + Vector3(0, 0.9, 0) - spawn_pos).normalized()
	projectile.direction = dir
	projectile.projectile_speed = PROJECTILE_SPEED
	projectile.damage = base_damage * wave_dmg_mult

	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(projectile)

# ---------------------------------------------------------------------------
# Inner class: Enemy projectile
# ---------------------------------------------------------------------------

class _EnemyProjectile:
	extends Area3D

	var direction: Vector3 = Vector3.FORWARD
	var projectile_speed: float = 15.0
	var damage: float = 6.0
	var _lifetime: float = 5.0

	func _ready() -> void:
		# Collision: layer 4 (Projectiles bit 3 = value 8), mask layer 2 (Player)
		collision_layer = 8
		collision_mask = 2

		# Visual
		var sphere := CSGSphere3D.new()
		sphere.radius = 0.15
		sphere.radial_segments = 8
		sphere.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 1.0, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 1.0, 0.3)
		mat.emission_energy_multiplier = 2.0
		sphere.material = mat
		add_child(sphere)

		# Collision shape
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
