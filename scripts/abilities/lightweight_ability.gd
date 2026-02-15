extends AbilityBase
## Lightweight -- increases movement speed by 10% per level.

# ── Tuning ────────────────────────────────────────────────────────────
var speed_bonus_pct: float = 0.10

# ── Internal ──────────────────────────────────────────────────────────
var _applied_bonus: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_speed_bonus()


func deactivate() -> void:
	GameManager.player_traits["speed"] -= _applied_bonus
	_applied_bonus = 0.0


func _on_upgrade() -> void:
	# Remove old bonus, recalculate, reapply
	GameManager.player_traits["speed"] -= _applied_bonus
	speed_bonus_pct = 0.10 + (level - 1) * 0.05
	_apply_speed_bonus()


# ── Private ──────────────────────────────────────────────────────────

func _apply_speed_bonus() -> void:
	var base_speed: float = GameManager.player_traits["speed"]
	_applied_bonus = base_speed * speed_bonus_pct
	GameManager.player_traits["speed"] += _applied_bonus
