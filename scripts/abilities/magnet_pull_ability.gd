extends AbilityBase
## Magnet Pull -- passively increases the player's pickup collection range
## by modifying GameManager.player_traits["collect_range"].

# -- Tuning ------------------------------------------------------------------
## Fraction of base collect_range added per level.
var range_bonus_percent: float = 0.25

# -- Internal -----------------------------------------------------------------
## The absolute bonus currently applied, so we can cleanly remove it.
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
	# 25% per level (stacking additively).
	range_bonus_percent = 0.25 * level


func _add_bonus() -> void:
	var base_range: float = GameManager.player_traits.get("collect_range", 3.0)
	_applied_bonus = base_range * range_bonus_percent
	GameManager.player_traits["collect_range"] = base_range + _applied_bonus


func _remove_bonus() -> void:
	if _applied_bonus > 0.0:
		GameManager.player_traits["collect_range"] -= _applied_bonus
		_applied_bonus = 0.0
