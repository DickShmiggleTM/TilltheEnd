extends Node3D
class_name SkillBase
## Base class for all player skills. Skills are active abilities that require
## player input via a button press and recharge over time. Each skill has its
## own cooldown duration.

# ── Data ──────────────────────────────────────────────────────────────
var skill_data: Dictionary = {}
var level: int = 1
var player: Node3D = null

# Cooldown tracking
var cooldown: float = 10.0        # Total cooldown duration in seconds
var cooldown_remaining: float = 0.0
var is_ready: bool = true

# Cached scaling helpers
var _damage_mult: float = 1.0


# ── Lifecycle ─────────────────────────────────────────────────────────

func initialize(data: Dictionary, player_ref: Node3D) -> void:
	skill_data = data.duplicate(true)
	player = player_ref
	level = skill_data.get("level", 1)
	cooldown = skill_data.get("cooldown", 10.0)
	_recalculate_scaling()
	on_activate()


func upgrade(new_level: int) -> void:
	level = new_level
	skill_data["level"] = level
	_recalculate_scaling()
	_on_upgrade()


## Called once when skill is first acquired.
func on_activate() -> void:
	pass


## Called when the player presses the skill button. Only fires if ready.
func use_skill() -> void:
	if not is_ready:
		return
	is_ready = false
	cooldown_remaining = cooldown
	_execute()
	EventBus.skill_activated.emit(skill_data.get("id", ""))
	EventBus.skill_cooldown_started.emit(skill_data.get("id", ""), cooldown)


## Virtual -- override in subclasses to perform the skill action.
func _execute() -> void:
	pass


## Virtual -- override to clean up when the skill is removed.
func deactivate() -> void:
	pass


## Virtual -- override to react to level changes.
func _on_upgrade() -> void:
	pass


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_ready:
		cooldown_remaining -= delta
		if cooldown_remaining <= 0.0:
			cooldown_remaining = 0.0
			is_ready = true
			EventBus.skill_cooldown_finished.emit(skill_data.get("id", ""))


# ── Scaling ───────────────────────────────────────────────────────────

func _recalculate_scaling() -> void:
	_damage_mult = 1.0 + (level - 1) * 0.25


func get_scaled_damage(base_damage: float) -> float:
	var trait_mult: float = GameManager.get_trait("damage_mult")
	return base_damage * _damage_mult * trait_mult


func get_cooldown_progress() -> float:
	if is_ready:
		return 1.0
	return 1.0 - (cooldown_remaining / cooldown)


# ── Enemy helpers (same as AbilityBase) ───────────────────────────────

func _get_enemies() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and is_instance_valid(e):
			result.append(e)
	return result


func _get_enemies_in_range(origin: Vector3, radius: float) -> Array[Node3D]:
	var r_sq := radius * radius
	var result: Array[Node3D] = []
	for e in _get_enemies():
		if e.global_position.distance_squared_to(origin) <= r_sq:
			result.append(e)
	return result


func _get_nearest_enemy(origin: Vector3, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = max_range * max_range
	for e in _get_enemies():
		var d := e.global_position.distance_squared_to(origin)
		if d < best_dist_sq:
			best_dist_sq = d
			best = e
	return best


func _deal_damage(enemy: Node3D, amount: float) -> void:
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		enemy.take_damage(amount, player)
		EventBus.damage_dealt.emit(amount, enemy.global_position, false)
