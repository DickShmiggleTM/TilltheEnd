extends AbilityBase
## Vampiric Aura -- passive ability that heals the player for a percentage
## of all damage dealt. Automatically triggers on every damage event.

# ── Tuning ────────────────────────────────────────────────────────────
var lifesteal_percent: float = 0.03  # 3% base


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if EventBus.damage_dealt.is_connected(_on_damage_dealt):
		EventBus.damage_dealt.disconnect(_on_damage_dealt)


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	lifesteal_percent = 0.03 + (level - 1) * 0.02  # +2% per level


func _on_damage_dealt(amount: float, _position: Vector3, _is_crit: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var heal_amount := amount * lifesteal_percent
	if heal_amount > 0.0:
		EventBus.player_healed.emit(heal_amount)
