extends AbilityBase
## Tough Skin -- increases defense by 20% per level.

# ── Tuning ────────────────────────────────────────────────────────────
var defense_bonus_pct: float = 0.20

# ── Internal ──────────────────────────────────────────────────────────
var _applied_bonus: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_defense_bonus()


func deactivate() -> void:
	GameManager.player_traits["defense"] -= _applied_bonus
	_applied_bonus = 0.0


func _on_upgrade() -> void:
	GameManager.player_traits["defense"] -= _applied_bonus
	defense_bonus_pct = 0.20 + (level - 1) * 0.05
	_apply_defense_bonus()


# ── Private ──────────────────────────────────────────────────────────

func _apply_defense_bonus() -> void:
	var base_defense: float = GameManager.player_traits["defense"]
	# Use max_health as reference when defense is 0 so the bonus is meaningful
	if base_defense == 0.0:
		_applied_bonus = GameManager.get_trait("max_health") * defense_bonus_pct
	else:
		_applied_bonus = base_defense * defense_bonus_pct
	GameManager.player_traits["defense"] += _applied_bonus
