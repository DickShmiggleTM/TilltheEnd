extends AbilityBase
## Versatility -- adds extra ability slots to the player's loadout by
## increasing GameManager.MAX_ABILITIES.

# ── Tuning ────────────────────────────────────────────────────────────
var extra_slots: int = 2

# ── Internal ──────────────────────────────────────────────────────────
var _applied_slots: int = 0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_applied_slots = extra_slots
	GameManager.MAX_ABILITIES += _applied_slots


func deactivate() -> void:
	GameManager.MAX_ABILITIES -= _applied_slots
	_applied_slots = 0


func _on_upgrade() -> void:
	GameManager.MAX_ABILITIES -= _applied_slots
	extra_slots = 2 + (level - 1)
	_applied_slots = extra_slots
	GameManager.MAX_ABILITIES += _applied_slots
