extends AbilityBase
## Telekinesis -- passive ability that doubles (or more) pushback/knockback
## force applied by the player's weapons. Stores a multiplier in
## GameManager.player_traits["pushback_mult"] for the weapon system to read.

# -- Tuning ------------------------------------------------------------------
var pushback_multiplier: float = 2.0

# -- Internal -----------------------------------------------------------------
var _applied_bonus: float = 0.0

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	_add_bonus()


func deactivate() -> void:
	_remove_bonus()


func _on_upgrade() -> void:
	_remove_bonus()
	_apply_level_stats()
	_add_bonus()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Level 1 = 2x, level 2 = 2.5x, level 3 = 3x, etc.
	pushback_multiplier = 2.0 + (level - 1) * 0.5


func _add_bonus() -> void:
	# Ensure the trait key exists.
	if not GameManager.player_traits.has("pushback_mult"):
		GameManager.player_traits["pushback_mult"] = 1.0
	var current: float = GameManager.player_traits["pushback_mult"]
	_applied_bonus = current * (pushback_multiplier - 1.0)
	GameManager.player_traits["pushback_mult"] = current + _applied_bonus


func _remove_bonus() -> void:
	if _applied_bonus != 0.0:
		GameManager.player_traits["pushback_mult"] -= _applied_bonus
		_applied_bonus = 0.0
