extends AbilityBase
## Revitalize -- instantly heals a portion of the player's health.
## Triggers automatically when health drops below 50%.
## Recharges after 3 minutes.

# ── Tuning ────────────────────────────────────────────────────────────
var heal_percent: float = 0.35   # heals 35% of max HP
var health_trigger: float = 0.50 # triggers when below 50% HP
var cooldown: float = 180.0      # 3 minutes

# ── Internal ──────────────────────────────────────────────────────────
var _cooldown_timer: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_cooldown_timer = 5.0


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
		var max_hp: float = GameManager.get_trait("max_health")
		var current_hp: float = GameManager.player_stats.get("current_health", max_hp)
		var hp_ratio := current_hp / max_hp if max_hp > 0.0 else 1.0

		if hp_ratio < health_trigger:
			_cooldown_timer = cooldown
			_heal_player()
		else:
			_cooldown_timer = 1.0  # re-check


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	heal_percent = 0.35 + (level - 1) * 0.05
	health_trigger = minf(0.50 + (level - 1) * 0.05, 0.70)
	cooldown = maxf(180.0 - level * 10.0, 90.0)


func _heal_player() -> void:
	var max_hp: float = GameManager.get_trait("max_health")
	var heal_amount := max_hp * heal_percent

	if GameManager.player_stats.has("current_health"):
		GameManager.player_stats["current_health"] = minf(
			GameManager.player_stats["current_health"] + heal_amount,
			max_hp
		)
	EventBus.player_healed.emit(heal_amount)

	_spawn_heal_vfx()


func _spawn_heal_vfx() -> void:
	var origin := player.global_position

	# Bright green flash
	var flash := CSGSphere3D.new()
	flash.radius = 0.5
	flash.radial_segments = 8
	flash.rings = 6
	flash.name = "RevitalizeFlash"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.2)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material = mat

	get_tree().current_scene.add_child(flash)
	flash.global_position = origin + Vector3.UP * 1.0

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "radius", 2.5, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.set_parallel(false)
	tw.tween_callback(flash.queue_free)

	# Rising cross / plus symbol
	var cross_h := CSGBox3D.new()
	cross_h.size = Vector3(1.2, 0.2, 0.1)
	cross_h.name = "HealCrossH"

	var cross_v := CSGBox3D.new()
	cross_v.size = Vector3(0.2, 1.2, 0.1)
	cross_v.name = "HealCrossV"

	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(0.5, 1.0, 0.5, 0.9)
	cross_mat.emission_enabled = true
	cross_mat.emission = Color(0.3, 1.0, 0.3)
	cross_mat.emission_energy_multiplier = 6.0
	cross_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cross_h.material = cross_mat
	cross_v.material = cross_mat

	var cross_container := Node3D.new()
	cross_container.name = "HealCross"
	cross_container.add_child(cross_h)
	cross_container.add_child(cross_v)

	get_tree().current_scene.add_child(cross_container)
	cross_container.global_position = origin + Vector3.UP * 2.5

	var tw2 := get_tree().create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(cross_container, "global_position:y", origin.y + 4.5, 1.0).set_ease(Tween.EASE_OUT)
	tw2.tween_property(cross_mat, "albedo_color:a", 0.0, 1.0).set_ease(Tween.EASE_IN)
	tw2.set_parallel(false)
	tw2.tween_callback(cross_container.queue_free)
