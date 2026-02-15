extends AbilityBase
## Clairvoyant -- guarantees the next dodge when charged. After the dodge is
## consumed, recharges over 45 seconds. Listens to player_damaged to intercept
## incoming damage and emit a dodge event instead.

# ── Tuning ────────────────────────────────────────────────────────────
var recharge_time: float = 45.0

# ── Internal ──────────────────────────────────────────────────────────
var _charged: bool = false
var _recharge_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_charged = true
	_recharge_timer = 0.0
	# Boost dodge chance to 100% while charged -- the player's take_damage()
	# already checks dodge_chance. We inject a guaranteed dodge by increasing it.
	_apply_guaranteed_dodge()
	EventBus.player_damaged.connect(_on_player_damaged)


func _on_upgrade() -> void:
	_apply_level_stats()
	# If currently recharging, reduce remaining time proportionally
	if not _charged and _recharge_timer > recharge_time:
		_recharge_timer = recharge_time


func deactivate() -> void:
	_revert_guaranteed_dodge()
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	if not _charged:
		_recharge_timer -= delta
		if _recharge_timer <= 0.0:
			_charged = true
			_apply_guaranteed_dodge()


# ── Signal handler ────────────────────────────────────────────────────

func _on_player_damaged(_amount: float, _source: Node3D) -> void:
	# The damage already happened through the player's take_damage(), but
	# we use this signal to consume our charge. The actual dodge is handled
	# via the boosted dodge_chance trait set during _apply_guaranteed_dodge.
	# When the player dodges, dodge_chance was >= 1.0 so take_damage returns
	# early. If damage came through, it means dodge_chance was overridden or
	# the hit was unavoidable -- we still consume charge.
	if _charged:
		_charged = false
		_revert_guaranteed_dodge()
		_recharge_timer = recharge_time
		EventBus.player_dodged_attack.emit()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	recharge_time = 45.0 - (level - 1) * 3.0
	recharge_time = maxf(recharge_time, 15.0)


func _apply_guaranteed_dodge() -> void:
	# Temporarily set dodge_chance very high to guarantee the next dodge.
	if not has_meta("clairvoyant_dodge_applied"):
		GameManager.player_traits["dodge_chance"] += 100.0
		set_meta("clairvoyant_dodge_applied", true)


func _revert_guaranteed_dodge() -> void:
	if has_meta("clairvoyant_dodge_applied"):
		GameManager.player_traits["dodge_chance"] -= 100.0
		remove_meta("clairvoyant_dodge_applied")
