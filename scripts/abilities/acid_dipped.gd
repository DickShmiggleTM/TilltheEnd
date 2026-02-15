extends AbilityBase
## Acid Dipped -- when any enemy takes damage, applies a damage-over-time
## effect (2 damage every 3 seconds for 12 seconds). Does not stack on the
## same enemy. Tracks active DoTs via a dictionary of enemy references.

# ── Tuning ────────────────────────────────────────────────────────────
var dot_damage: float = 2.0
var dot_interval: float = 3.0    ## seconds between ticks
var dot_duration: float = 12.0   ## total DoT lifetime

# ── Internal ──────────────────────────────────────────────────────────
## Maps enemy instance_id -> { "enemy": Node3D, "remaining": float, "tick": float }
var _active_dots: Dictionary = {}


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	EventBus.enemy_damaged.connect(_on_enemy_damaged)


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	if EventBus.enemy_damaged.is_connected(_on_enemy_damaged):
		EventBus.enemy_damaged.disconnect(_on_enemy_damaged)
	_active_dots.clear()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _active_dots.is_empty():
		return

	var to_remove: Array = []

	for eid in _active_dots:
		var data: Dictionary = _active_dots[eid]
		var enemy: Node3D = data["enemy"]

		# Clean up dead enemies
		if not is_instance_valid(enemy):
			to_remove.append(eid)
			continue

		data["remaining"] -= delta
		if data["remaining"] <= 0.0:
			to_remove.append(eid)
			continue

		data["tick"] -= delta
		if data["tick"] <= 0.0:
			data["tick"] = dot_interval
			_deal_damage(enemy, get_scaled_damage(dot_damage))

	for eid in to_remove:
		_active_dots.erase(eid)


# ── Signal handler ────────────────────────────────────────────────────

func _on_enemy_damaged(enemy: Node3D, _amount: float) -> void:
	if not is_instance_valid(enemy):
		return

	var eid := enemy.get_instance_id()

	# Don't stack -- only apply if not already active
	if _active_dots.has(eid):
		return

	_active_dots[eid] = {
		"enemy": enemy,
		"remaining": dot_duration,
		"tick": dot_interval,
	}


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	dot_damage = 2.0 + (level - 1) * 1.0
	dot_interval = 3.0
	dot_duration = 12.0 + (level - 1) * 2.0
