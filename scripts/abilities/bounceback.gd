extends AbilityBase
## Bounceback -- whenever the player takes damage, deals the same amount of
## damage back to the attacker.

# -- Tuning ------------------------------------------------------------------
## Multiplier applied to the reflected damage (scales with level).
var reflect_mult: float = 1.0

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	EventBus.player_damaged.connect(_on_player_damaged)


func deactivate() -> void:
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)


func _on_upgrade() -> void:
	_apply_level_stats()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Level 1 = 100% reflect, +25% per additional level.
	reflect_mult = 1.0 + (level - 1) * 0.25


func _on_player_damaged(amount: float, source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	if not source.is_in_group("enemies"):
		return

	var reflect_damage: float = amount * reflect_mult
	_deal_damage(source, reflect_damage)
