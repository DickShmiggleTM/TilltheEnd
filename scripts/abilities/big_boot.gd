extends AbilityBase
## Big Boot -- an active kick ability with AoE damage, double knockback, and a
## short charge-up cooldown. Press the kick input to stomp enemies in front of
## the player within a cone radius.

# -- Tuning ------------------------------------------------------------------
var base_damage: float = 25.0
var kick_radius: float = 3.0
var knockback_force: float = 20.0
var cooldown: float = 4.0

# -- Internal -----------------------------------------------------------------
var _cooldown_timer: float = 0.0
var _is_ready: bool = true

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 0.0
	_is_ready = true


func deactivate() -> void:
	_is_ready = false


func _on_upgrade() -> void:
	_apply_level_stats()


# -- Process ------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return

	if not _is_ready:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_is_ready = true

	# Check for kick input.
	if _is_ready and Input.is_action_just_pressed("kick"):
		_perform_kick()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	base_damage = 25.0 * (1.0 + (level - 1) * 0.20)
	kick_radius = 3.0 + level * 0.5
	knockback_force = 20.0 + level * 5.0
	cooldown = maxf(4.0 - level * 0.3, 1.5)


func _perform_kick() -> void:
	_is_ready = false
	_cooldown_timer = cooldown

	var origin := player.global_position
	var forward := -player.global_transform.basis.z.normalized()
	var damage := get_scaled_damage(base_damage)

	# Hit all enemies in front of the player within kick_radius.
	for enemy in _get_enemies_in_range(origin, kick_radius):
		var to_enemy := (enemy.global_position - origin).normalized()
		# Only hit enemies roughly in front (within ~120-degree cone).
		if forward.dot(to_enemy) >= 0.0:
			_deal_damage(enemy, damage)
			# Apply knockback away from the player.
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(to_enemy * knockback_force)
			elif "velocity" in enemy:
				enemy.velocity += to_enemy * knockback_force
