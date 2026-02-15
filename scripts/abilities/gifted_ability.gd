extends AbilityBase
## Gifted -- adds 1 extra ability slot and decreases ability cooldowns.
## Stores bonus_ability_slots and cooldown_reduction in player_traits for
## AbilityManager and other systems to query.

# ── Tuning ────────────────────────────────────────────────────────────
var bonus_slots: int = 1
var cooldown_reduction: float = 0.10  ## 10% cooldown reduction per level

# ── Internal ──────────────────────────────────────────────────────────
var _applied_slots: int = 0
var _applied_cooldown_reduction: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_apply_modifiers()


func _on_upgrade() -> void:
	_revert_modifiers()
	_apply_level_stats()
	_apply_modifiers()


func deactivate() -> void:
	_revert_modifiers()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	bonus_slots = 1
	cooldown_reduction = 0.10 * level


func _apply_modifiers() -> void:
	_applied_slots = bonus_slots
	_applied_cooldown_reduction = cooldown_reduction

	# Store bonus ability slots as a trait for capacity checks.
	if not GameManager.player_traits.has("bonus_ability_slots"):
		GameManager.player_traits["bonus_ability_slots"] = 0.0
	GameManager.player_traits["bonus_ability_slots"] += float(_applied_slots)

	# Store cooldown reduction for ability timers to read.
	if not GameManager.player_traits.has("cooldown_reduction"):
		GameManager.player_traits["cooldown_reduction"] = 0.0
	GameManager.player_traits["cooldown_reduction"] += _applied_cooldown_reduction


func _revert_modifiers() -> void:
	if GameManager.player_traits.has("bonus_ability_slots"):
		GameManager.player_traits["bonus_ability_slots"] -= float(_applied_slots)
	if GameManager.player_traits.has("cooldown_reduction"):
		GameManager.player_traits["cooldown_reduction"] -= _applied_cooldown_reduction
	_applied_slots = 0
	_applied_cooldown_reduction = 0.0
