extends AbilityBase
## Voidwalker -- adds 2 ability slots and halves cooldowns, but halves weapon
## damage (-50% damage_mult) and lowers defense by 20%. A high-risk trade-off
## that favours ability-heavy builds.

# ── Tuning ────────────────────────────────────────────────────────────
var bonus_slots: int = 2
var cooldown_reduction: float = 0.50  ## 50% cooldown reduction
var damage_penalty: float = 0.50      ## -50% damage_mult
var defense_penalty: float = 0.20     ## -20% defense

# ── Internal ──────────────────────────────────────────────────────────
var _applied_slots: int = 0
var _applied_cooldown: float = 0.0
var _applied_damage_penalty: float = 0.0
var _applied_defense_penalty: float = 0.0


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
	bonus_slots = 2
	cooldown_reduction = 0.50 + (level - 1) * 0.05
	damage_penalty = 0.50 - (level - 1) * 0.03  # Penalty lessens slightly per level
	defense_penalty = 0.20


func _apply_modifiers() -> void:
	_applied_slots = bonus_slots
	_applied_cooldown = cooldown_reduction
	_applied_damage_penalty = damage_penalty
	_applied_defense_penalty = defense_penalty

	# Bonus ability slots
	if not GameManager.player_traits.has("bonus_ability_slots"):
		GameManager.player_traits["bonus_ability_slots"] = 0.0
	GameManager.player_traits["bonus_ability_slots"] += float(_applied_slots)

	# Cooldown reduction
	if not GameManager.player_traits.has("cooldown_reduction"):
		GameManager.player_traits["cooldown_reduction"] = 0.0
	GameManager.player_traits["cooldown_reduction"] += _applied_cooldown

	# Damage penalty (subtract from damage_mult)
	GameManager.player_traits["damage_mult"] -= _applied_damage_penalty

	# Defense penalty (subtract flat defense)
	GameManager.player_traits["defense"] -= _applied_defense_penalty


func _revert_modifiers() -> void:
	if GameManager.player_traits.has("bonus_ability_slots"):
		GameManager.player_traits["bonus_ability_slots"] -= float(_applied_slots)
	if GameManager.player_traits.has("cooldown_reduction"):
		GameManager.player_traits["cooldown_reduction"] -= _applied_cooldown
	GameManager.player_traits["damage_mult"] += _applied_damage_penalty
	GameManager.player_traits["defense"] += _applied_defense_penalty

	_applied_slots = 0
	_applied_cooldown = 0.0
	_applied_damage_penalty = 0.0
	_applied_defense_penalty = 0.0
