extends AbilityBase
## Vengeful Rage -- when the player takes damage, attack and defense are
## buffed by 15% for 5 seconds. Stacks refresh the timer, not the buff.

# ── Tuning ────────────────────────────────────────────────────────────
var buff_pct: float = 0.15
var buff_duration: float = 5.0

# ── Internal ──────────────────────────────────────────────────────────
var _buff_active: bool = false
var _buff_timer: float = 0.0
var _attack_bonus: float = 0.0
var _defense_bonus: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	EventBus.player_damaged.connect(_on_player_damaged)


func deactivate() -> void:
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)
	_remove_buff()


func _on_upgrade() -> void:
	buff_pct = 0.15 + (level - 1) * 0.05
	buff_duration = 5.0 + (level - 1) * 0.5
	# If buff is active, refresh it with new values
	if _buff_active:
		_remove_buff()
		_apply_buff()
		_buff_timer = buff_duration


# ── Process ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _buff_active:
		return

	_buff_timer -= delta
	if _buff_timer <= 0.0:
		_remove_buff()


# ── Signal callbacks ─────────────────────────────────────────────────

func _on_player_damaged(_amount: float, _source: Node3D) -> void:
	if _buff_active:
		# Refresh timer only
		_buff_timer = buff_duration
	else:
		_apply_buff()
		_buff_timer = buff_duration


# ── Private ──────────────────────────────────────────────────────────

func _apply_buff() -> void:
	_attack_bonus = GameManager.player_traits["damage_mult"] * buff_pct
	_defense_bonus = GameManager.get_trait("max_health") * buff_pct  # Flat defense from max HP
	if GameManager.player_traits["defense"] > 0.0:
		_defense_bonus = GameManager.player_traits["defense"] * buff_pct

	GameManager.player_traits["damage_mult"] += _attack_bonus
	GameManager.player_traits["defense"] += _defense_bonus
	_buff_active = true


func _remove_buff() -> void:
	if not _buff_active:
		return
	GameManager.player_traits["damage_mult"] -= _attack_bonus
	GameManager.player_traits["defense"] -= _defense_bonus
	_attack_bonus = 0.0
	_defense_bonus = 0.0
	_buff_active = false
