class_name EnemyMelee
extends EnemyBase
## Red demon-like melee rusher. Charges directly at the player and attacks
## with relentless melee strikes when in range.

# ---------------------------------------------------------------------------
# Overridden base stats
# ---------------------------------------------------------------------------

func _init() -> void:
	max_health = 30.0
	base_damage = 8.0
	speed = 4.5
	attack_range = 1.8
	attack_cooldown = 0.8
	base_exp_drop = 10.0

# ---------------------------------------------------------------------------
# Visual configuration
# ---------------------------------------------------------------------------

func _get_enemy_color() -> Color:
	return Color(0.9, 0.15, 0.1)  # Demonic red


func _create_mesh() -> Node3D:
	# Main body — slightly taller box
	var body := CSGBox3D.new()
	var scale_bonus := 1.0 + (wave_hp_mult - 1.0) * 0.05  # Gets slightly larger on higher waves
	body.size = Vector3(0.7, 1.1, 0.5) * scale_bonus
	body.position = Vector3(0.0, 0.55 * scale_bonus, 0.0)

	# Small horn-like protrusions for the demon look
	var horn_left := CSGBox3D.new()
	horn_left.size = Vector3(0.1, 0.3, 0.1)
	horn_left.position = Vector3(-0.2, 1.2 * scale_bonus, 0.0)
	horn_left.rotation_degrees = Vector3(0, 0, 15)
	body.add_child(horn_left)

	var horn_right := CSGBox3D.new()
	horn_right.size = Vector3(0.1, 0.3, 0.1)
	horn_right.position = Vector3(0.2, 1.2 * scale_bonus, 0.0)
	horn_right.rotation_degrees = Vector3(0, 0, -15)
	body.add_child(horn_right)

	return body


func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	var scale_bonus := 1.0 + (wave_hp_mult - 1.0) * 0.05
	box.size = Vector3(0.7, 1.1, 0.5) * scale_bonus
	return box


func _get_collision_offset() -> Vector3:
	var scale_bonus := 1.0 + (wave_hp_mult - 1.0) * 0.05
	return Vector3(0.0, 0.55 * scale_bonus, 0.0)

# ---------------------------------------------------------------------------
# Attack — simple melee hit
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
		_attack_timer = attack_cooldown

		# Lunge visual: brief scale punch
		if _mesh:
			var tw := create_tween()
			tw.tween_property(_mesh, "scale", Vector3(1.2, 0.9, 1.2), 0.05)
			tw.tween_property(_mesh, "scale", Vector3.ONE, 0.1)
