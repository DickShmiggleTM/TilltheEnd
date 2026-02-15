extends AbilityBase
## Hyperfocus -- on dodge, slow time to 50% for 2 seconds using
## Engine.time_scale. Refreshes duration on repeated dodges.

# ── Tuning ────────────────────────────────────────────────────────────
var time_scale: float = 0.5
var slow_duration: float = 2.0

# ── Internal ──────────────────────────────────────────────────────────
var _active: bool = false
var _timer: float = 0.0
var _original_time_scale: float = 1.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	EventBus.player_dodged_attack.connect(_on_player_dodged)


func deactivate() -> void:
	if EventBus.player_dodged_attack.is_connected(_on_player_dodged):
		EventBus.player_dodged_attack.disconnect(_on_player_dodged)
	_restore_time()


func _on_upgrade() -> void:
	time_scale = maxf(0.5 - (level - 1) * 0.05, 0.2)
	slow_duration = 2.0 + (level - 1) * 0.5


# ── Process ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active:
		return

	# Use unscaled delta since time is slowed
	_timer -= delta / Engine.time_scale
	if _timer <= 0.0:
		_restore_time()


# ── Signal callbacks ─────────────────────────────────────────────────

func _on_player_dodged() -> void:
	if not _active:
		_original_time_scale = Engine.time_scale
		Engine.time_scale = time_scale
		_active = true
	# Always refresh timer
	_timer = slow_duration


# ── Private ──────────────────────────────────────────────────────────

func _restore_time() -> void:
	if not _active:
		return
	Engine.time_scale = _original_time_scale
	_active = false
	_timer = 0.0
