extends AbilityBase
## Toxic Emission -- periodically poisons enemies in close range. Poisoned
## enemies take damage per second for a set duration.

# ── Tuning ────────────────────────────────────────────────────────────
var apply_interval: float = 1.0
var poison_radius: float = 4.0
var poison_duration: float = 3.0
var poison_dps: float = 5.0

# ── Internal ──────────────────────────────────────────────────────────
var _apply_timer: float = 0.0
var _tick_timer: float = 0.0
const TICK_INTERVAL := 0.5

# Tracks poisoned enemies: instance_id -> { "node": Node3D, "remaining": float }
var _poisoned: Dictionary = {}


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_apply_timer = apply_interval


func deactivate() -> void:
	_poisoned.clear()


func _on_upgrade() -> void:
	_apply_level_stats()


# ── Process ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	# Apply poison to nearby enemies periodically
	_apply_timer -= delta
	if _apply_timer <= 0.0:
		_apply_timer = apply_interval
		_apply_poison_nearby()

	# Tick poison damage
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_tick_poison(TICK_INTERVAL)


# ── Private ──────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	poison_dps = 5.0 + (level - 1) * 2.0
	poison_radius = 4.0 + (level - 1) * 0.5
	poison_duration = 3.0 + (level - 1) * 0.5
	apply_interval = maxf(1.0 - (level - 1) * 0.1, 0.4)


func _apply_poison_nearby() -> void:
	var origin := player.global_position
	for enemy in _get_enemies_in_range(origin, poison_radius):
		var eid := enemy.get_instance_id()
		# Refresh or add poison
		_poisoned[eid] = { "node": enemy, "remaining": poison_duration }


func _tick_poison(tick_delta: float) -> void:
	var damage := get_scaled_damage(poison_dps) * tick_delta
	var to_remove: Array = []

	for eid in _poisoned:
		var data: Dictionary = _poisoned[eid]
		var enemy: Node3D = data["node"]

		if not is_instance_valid(enemy):
			to_remove.append(eid)
			continue

		data["remaining"] -= tick_delta
		if data["remaining"] <= 0.0:
			to_remove.append(eid)
			continue

		_deal_damage(enemy, damage)

	for eid in to_remove:
		_poisoned.erase(eid)
