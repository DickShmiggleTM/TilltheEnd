extends AbilityBase
## Spiritually Aligned -- adds 25 base health per level and passively heals
## 2 HP every 20 seconds via an internal timer.

# ── Tuning ────────────────────────────────────────────────────────────
var bonus_health: float = 25.0
var heal_amount: float = 2.0
var heal_interval: float = 20.0  ## seconds between heals

# ── Internal ──────────────────────────────────────────────────────────
var _applied_health: float = 0.0
var _heal_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_apply_modifiers()
	_heal_timer = heal_interval


func _on_upgrade() -> void:
	_revert_modifiers()
	_apply_level_stats()
	_apply_modifiers()


func deactivate() -> void:
	_revert_modifiers()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	_heal_timer -= delta
	if _heal_timer <= 0.0:
		_heal_timer = heal_interval
		if is_instance_valid(player) and player.has_method("heal"):
			player.heal(heal_amount)


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	bonus_health = 25.0 * level
	heal_amount = 2.0 + (level - 1) * 1.0


func _apply_modifiers() -> void:
	_applied_health = bonus_health
	GameManager.player_traits["max_health"] += _applied_health


func _revert_modifiers() -> void:
	GameManager.player_traits["max_health"] -= _applied_health
	_applied_health = 0.0
