extends AbilityBase
## Storm Chain -- periodically fires a lightning bolt at the nearest enemy
## that arcs (chains) to additional nearby targets.

# ── Tuning ────────────────────────────────────────────────────────────
var base_damage: float = 12.0
var chain_count: int = 3
var chain_range: float = 8.0
var cooldown: float = 2.5

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = cooldown * 0.5  # first strike comes quickly


func _on_upgrade() -> void:
	_apply_level_stats()


func deactivate() -> void:
	pass


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = cooldown
		_fire_lightning()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	base_damage = 12.0 * (1.0 + (level - 1) * 0.2)
	chain_count = 3 + level - 1
	chain_range = 8.0 + level
	cooldown = maxf(2.5 - level * 0.2, 0.8)


func _fire_lightning() -> void:
	var origin := player.global_position + Vector3.UP * 1.0
	var first_target := _get_nearest_enemy(origin, chain_range)
	if first_target == null:
		return

	var damage := get_scaled_damage(base_damage)
	var chain_targets: Array[Node3D] = []
	var hit_set: Dictionary = {}  # instance_id -> true

	# First target
	chain_targets.append(first_target)
	hit_set[first_target.get_instance_id()] = true
	_deal_damage(first_target, damage)

	# Chain to additional targets
	var current_pos := first_target.global_position
	for _i in chain_count - 1:
		var next := _find_next_chain_target(current_pos, hit_set)
		if next == null:
			break
		chain_targets.append(next)
		hit_set[next.get_instance_id()] = true
		# Each chain does slightly less damage
		damage *= 0.85
		_deal_damage(next, damage)
		current_pos = next.global_position

	# Draw lightning visual
	_draw_lightning_chain(origin, chain_targets)


func _find_next_chain_target(from_pos: Vector3, hit_set: Dictionary) -> Node3D:
	var best: Node3D = null
	var best_dist_sq: float = chain_range * chain_range
	for e in _get_enemies():
		if hit_set.has(e.get_instance_id()):
			continue
		var d := e.global_position.distance_squared_to(from_pos)
		if d < best_dist_sq:
			best_dist_sq = d
			best = e
	return best


func _draw_lightning_chain(start: Vector3, targets: Array[Node3D]) -> void:
	# Build a chain of thin beam segments: start -> target1 -> target2 -> ...
	var points: Array[Vector3] = [start]
	for t in targets:
		points.append(t.global_position + Vector3.UP * 0.5)

	for i in points.size() - 1:
		_draw_bolt_segment(points[i], points[i + 1])


func _draw_bolt_segment(from: Vector3, to: Vector3) -> void:
	var midpoint := (from + to) * 0.5
	var dist := from.distance_to(to)

	var beam := CSGBox3D.new()
	beam.size = Vector3(0.06, 0.06, dist)
	beam.name = "LightningBolt"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.7, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material = mat

	get_tree().current_scene.add_child(beam)
	beam.global_position = midpoint
	if dist > 0.01:
		beam.look_at(to, Vector3.UP)

	# Also draw a slightly offset second beam for a jagged look
	var jag := CSGBox3D.new()
	jag.size = Vector3(0.04, 0.04, dist * 0.6)
	var jag_offset := Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1), 0.0)
	jag.position = jag_offset
	jag.material = mat
	beam.add_child(jag)

	# Fade out quickly
	var tw := get_tree().create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(beam.queue_free)
