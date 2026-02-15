extends AbilityBase
## Quick Reflexes -- doubles the player's dodge chance. Multiplier grows
## with each upgrade level.

# ── Tuning ────────────────────────────────────────────────────────────
var dodge_multiplier: float = 2.0

# ── Internal ──────────────────────────────────────────────────────────
var _original_dodge: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_original_dodge = GameManager.player_traits["dodge_chance"]
	GameManager.player_traits["dodge_chance"] = _original_dodge * dodge_multiplier


func deactivate() -> void:
	GameManager.player_traits["dodge_chance"] = _original_dodge


func _on_upgrade() -> void:
	# Restore, recalculate multiplier, reapply
	GameManager.player_traits["dodge_chance"] = _original_dodge
	dodge_multiplier = 2.0 + (level - 1) * 0.5
	GameManager.player_traits["dodge_chance"] = _original_dodge * dodge_multiplier
