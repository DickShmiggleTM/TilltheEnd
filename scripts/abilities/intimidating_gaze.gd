extends AbilityBase
## Intimidating Gaze -- halves attack and defense of enemies within line of
## sight. Every 0.5 seconds, finds enemies in range and applies a damage_amp
## debuff and a metadata flag so other systems can check debuff status.

# ── Tuning ────────────────────────────────────────────────────────────
var gaze_range: float = 12.0
var damage_amp_mult: float = 2.0   ## Enemy takes 2x damage (halved defense)
var attack_reduction: float = 0.5  ## Enemy deals half damage

# ── Internal ──────────────────────────────────────────────────────────
const TICK_INTERVAL := 0.5
var _tick_timer: float = 0.0
var _affected_enemies: Dictionary = {}  ## instance_id -> enemy Node3D


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_tick_timer = 0.0


func _on_upgrade() -> void:
	_restore_all()
	_apply_level_stats()


func deactivate() -> void:
	_restore_all()


# ── Process ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player == null:
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_refresh_debuffs()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	gaze_range = 12.0 + level * 2.0
	damage_amp_mult = 2.0 + (level - 1) * 0.2
	attack_reduction = 0.5


func _refresh_debuffs() -> void:
	var in_range := _get_enemies_in_range(player.global_position, gaze_range)
	var current_ids: Dictionary = {}

	for enemy in in_range:
		if not is_instance_valid(enemy):
			continue
		var eid := enemy.get_instance_id()
		current_ids[eid] = true

		if not _affected_enemies.has(eid):
			_apply_debuff(enemy)
			_affected_enemies[eid] = enemy

	# Restore enemies that left range
	var to_remove: Array = []
	for eid in _affected_enemies:
		if not current_ids.has(eid):
			var enemy = _affected_enemies[eid]
			if is_instance_valid(enemy):
				_remove_debuff(enemy)
			to_remove.append(eid)
	for eid in to_remove:
		_affected_enemies.erase(eid)

	# Clean up dead enemies
	var dead: Array = []
	for eid in _affected_enemies:
		var enemy = _affected_enemies[eid]
		if not is_instance_valid(enemy):
			dead.append(eid)
	for eid in dead:
		_affected_enemies.erase(eid)


func _apply_debuff(enemy: Node3D) -> void:
	# Amplify damage taken (halves effective defense)
	if "damage_amp" in enemy:
		if not enemy.has_meta("gaze_original_damage_amp"):
			enemy.set_meta("gaze_original_damage_amp", enemy.damage_amp)
		enemy.damage_amp = enemy.get_meta("gaze_original_damage_amp") * damage_amp_mult

	# Halve attack damage via wave_dmg_mult
	if "wave_dmg_mult" in enemy:
		if not enemy.has_meta("gaze_original_dmg_mult"):
			enemy.set_meta("gaze_original_dmg_mult", enemy.wave_dmg_mult)
		enemy.wave_dmg_mult = enemy.get_meta("gaze_original_dmg_mult") * attack_reduction

	enemy.set_meta("intimidating_gaze_debuff", true)


func _remove_debuff(enemy: Node3D) -> void:
	if "damage_amp" in enemy and enemy.has_meta("gaze_original_damage_amp"):
		enemy.damage_amp = enemy.get_meta("gaze_original_damage_amp")
		enemy.remove_meta("gaze_original_damage_amp")

	if "wave_dmg_mult" in enemy and enemy.has_meta("gaze_original_dmg_mult"):
		enemy.wave_dmg_mult = enemy.get_meta("gaze_original_dmg_mult")
		enemy.remove_meta("gaze_original_dmg_mult")

	if enemy.has_meta("intimidating_gaze_debuff"):
		enemy.remove_meta("intimidating_gaze_debuff")


func _restore_all() -> void:
	for eid in _affected_enemies:
		var enemy = _affected_enemies[eid]
		if is_instance_valid(enemy):
			_remove_debuff(enemy)
	_affected_enemies.clear()
