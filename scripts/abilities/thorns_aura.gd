extends AbilityBase
## Thorns Aura -- passive ability that reflects a percentage of damage taken
## back to the attacker. Automatically triggers when the player is damaged.

# ── Tuning ────────────────────────────────────────────────────────────
var thorns_percent: float = 0.10  # 10% reflected


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	EventBus.player_damaged.connect(_on_player_damaged)


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	thorns_percent = 0.10 + (level - 1) * 0.05  # +5% per level


func _on_player_damaged(amount: float, source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	var reflect_amount := amount * thorns_percent
	if reflect_amount > 0.0 and source.has_method("take_damage"):
		source.take_damage(reflect_amount)
		EventBus.damage_dealt.emit(reflect_amount, source.global_position, false)
