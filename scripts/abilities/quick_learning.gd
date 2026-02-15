extends AbilityBase
## Quick Learning -- passively multiplies all EXP gain by modifying the
## GameManager exp_mult trait.

# -- Tuning ------------------------------------------------------------------
## The multiplier applied to the current exp_mult trait.
var exp_multiplier: float = 2.0

# -- Internal -----------------------------------------------------------------
## Tracks how much we added so we can cleanly revert.
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
	exp_multiplier = 2.0 + (level - 1) * 0.5


func _add_bonus() -> void:
	# We store the additive portion we inject so removal is precise.
	# exp_mult trait is multiplicative (default 1.0).
	# We want final exp_mult = original * exp_multiplier, so the additive
	# portion we inject is original * (exp_multiplier - 1).
	var current: float = GameManager.player_traits.get("exp_mult", 1.0)
	_applied_bonus = current * (exp_multiplier - 1.0)
	GameManager.player_traits["exp_mult"] = current + _applied_bonus


func _remove_bonus() -> void:
	if _applied_bonus != 0.0:
		GameManager.player_traits["exp_mult"] -= _applied_bonus
		_applied_bonus = 0.0
