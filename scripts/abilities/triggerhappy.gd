extends AbilityBase
## Trigger Happy -- increases fire rate by 15% per level but reduces accuracy
## by 5% per level. Modifies the global fire_rate_mult trait and stores an
## accuracy penalty for the weapon system to query.

# ── Tuning ────────────────────────────────────────────────────────────
var fire_rate_bonus: float = 0.15
var accuracy_penalty: float = 0.05  ## Extra spread degrees added to weapons

# ── Internal ──────────────────────────────────────────────────────────
var _applied_fire_rate: float = 0.0
var _applied_accuracy_penalty: float = 0.0


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
	fire_rate_bonus = 0.15 * level
	accuracy_penalty = 0.05 * level


func _apply_modifiers() -> void:
	_applied_fire_rate = fire_rate_bonus
	_applied_accuracy_penalty = accuracy_penalty
	GameManager.player_traits["fire_rate_mult"] += _applied_fire_rate
	# Store accuracy penalty so the weapon system can read it.
	if not GameManager.player_traits.has("accuracy_penalty"):
		GameManager.player_traits["accuracy_penalty"] = 0.0
	GameManager.player_traits["accuracy_penalty"] += _applied_accuracy_penalty


func _revert_modifiers() -> void:
	GameManager.player_traits["fire_rate_mult"] -= _applied_fire_rate
	if GameManager.player_traits.has("accuracy_penalty"):
		GameManager.player_traits["accuracy_penalty"] -= _applied_accuracy_penalty
	_applied_fire_rate = 0.0
	_applied_accuracy_penalty = 0.0
