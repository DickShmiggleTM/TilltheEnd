class_name EnemyTank
extends EnemyBase
## Heavy dark-gray tank enemy. Slow, massive health pool, deals heavy damage
## and knockback. Takes only 80% of incoming damage (damage resistance).
## Starts appearing at wave 3+.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 120.0
	base_damage = 20.0
	speed = 2.0
	attack_range = 2.5
	attack_cooldown = 1.5
	base_exp_drop = 30.0

# ---------------------------------------------------------------------------
# Tank-specific
# ---------------------------------------------------------------------------

const DAMAGE_RESISTANCE := 0.8   ## Takes 80% of incoming damage
const PLAYER_KNOCKBACK := 8.0    ## Extra knockback force on player hit

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.3, 0.3, 0.35)  # Dark gray


func _create_mesh() -> Node3D:
	var body := CSGBox3D.new()
	body.size = Vector3(1.2, 1.6, 1.0)
	body.position = Vector3(0.0, 0.8, 0.0)

	# Shoulder plates
	var shoulder_l := CSGBox3D.new()
	shoulder_l.size = Vector3(0.4, 0.3, 1.0)
	shoulder_l.position = Vector3(-0.8, 1.3, 0.0)
	body.add_child(shoulder_l)

	var shoulder_r := CSGBox3D.new()
	shoulder_r.size = Vector3(0.4, 0.3, 1.0)
	shoulder_r.position = Vector3(0.8, 1.3, 0.0)
	body.add_child(shoulder_r)

	return body


func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.6, 1.0)
	return box


func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.8, 0.0)

# ---------------------------------------------------------------------------
# Damage resistance override
# ---------------------------------------------------------------------------

func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	# Apply damage resistance before passing to base
	var reduced := amount * DAMAGE_RESISTANCE
	super.take_damage(reduced, knockback_dir * 0.5)  # Also resist knockback

# ---------------------------------------------------------------------------
# Attack — heavy melee with knockback
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	var player := get_player()
	if player == null or not is_instance_valid(player):
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= attack_range:
		var effective_damage := base_damage * wave_dmg_mult
		if player.has_method("take_damage"):
			player.take_damage(effective_damage, self)

		# Heavy knockback on the player
		if player is CharacterBody3D:
			var kb_dir := (player.global_position - global_position).normalized()
			player.velocity += kb_dir * PLAYER_KNOCKBACK

		_attack_timer = attack_cooldown

		# Ground-pound visual
		if _mesh:
			var tw := create_tween()
			tw.tween_property(_mesh, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
			tw.tween_property(_mesh, "scale", Vector3.ONE, 0.15)
