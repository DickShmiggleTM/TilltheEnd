extends Node3D
class_name AbilityBase
## Base class for all player abilities. Provides common interface and
## level-scaling logic. Concrete abilities override activate/deactivate
## and implement their own _process / _physics_process behaviour.

# ── Data ──────────────────────────────────────────────────────────────
var ability_data: Dictionary = {}
var level: int = 1
var player: Node3D = null

# Cached scaling helpers recalculated on upgrade
var _damage_mult: float = 1.0


# ── Lifecycle ─────────────────────────────────────────────────────────

func initialize(data: Dictionary, player_ref: Node3D) -> void:
	ability_data = data.duplicate(true)
	player = player_ref
	level = ability_data.get("level", 1)
	_recalculate_scaling()
	activate()


func upgrade(new_level: int) -> void:
	level = new_level
	ability_data["level"] = level
	_recalculate_scaling()
	_on_upgrade()


## Virtual -- override in subclasses to set up visuals, timers, areas, etc.
func activate() -> void:
	pass


## Virtual -- override to clean up when the ability is removed.
func deactivate() -> void:
	pass


## Virtual -- override to react to level changes (e.g. add more skulls).
func _on_upgrade() -> void:
	pass


# ── Scaling ───────────────────────────────────────────────────────────

## Recalculate the multiplier applied to base values each level.
## Default rule: +25 % per level (tuneable per-ability by overriding).
func _recalculate_scaling() -> void:
	_damage_mult = 1.0 + (level - 1) * 0.25


## Convenience: returns base_damage * level scaling * global damage_mult trait.
func get_scaled_damage(base_damage: float) -> float:
	var trait_mult: float = GameManager.get_trait("damage_mult")
	return base_damage * _damage_mult * trait_mult


# ── Enemy helpers ─────────────────────────────────────────────────────

## Return all living enemies in the "enemies" group.
func _get_enemies() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and is_instance_valid(e):
			result.append(e)
	return result


## Return enemies sorted by distance to `origin`, closest first.
func _get_enemies_sorted(origin: Vector3) -> Array[Node3D]:
	var enemies := _get_enemies()
	enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin)
	)
	return enemies


## Return the single nearest enemy within `max_range` of `origin`, or null.
func _get_nearest_enemy(origin: Vector3, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = max_range * max_range
	for e in _get_enemies():
		var d := e.global_position.distance_squared_to(origin)
		if d < best_dist_sq:
			best_dist_sq = d
			best = e
	return best


## Return all enemies within `radius` of `origin`.
func _get_enemies_in_range(origin: Vector3, radius: float) -> Array[Node3D]:
	var r_sq := radius * radius
	var result: Array[Node3D] = []
	for e in _get_enemies():
		if e.global_position.distance_squared_to(origin) <= r_sq:
			result.append(e)
	return result


# ── Damage helpers ────────────────────────────────────────────────────

## Apply damage to an enemy node. Enemies are expected to have a
## `take_damage(amount: float, source: Node3D)` method.
func _deal_damage(enemy: Node3D, amount: float) -> void:
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		enemy.take_damage(amount, player)
		EventBus.damage_dealt.emit(amount, enemy.global_position, false)


## Create an Area3D with a SphereShape3D on layer 6 / mask 3 and return it.
## Caller is responsible for adding it to the tree and connecting signals.
func _create_damage_area(radius: float) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 32   # Layer 6  (1 << 5)
	area.collision_mask  = 4    # Mask  3  (1 << 2)
	area.monitorable = true
	area.monitoring = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	return area
