extends AbilityBase
## Flaming Aura -- deals fire damage to all enemies within range of the
## player on a repeating timer.

# -- Tuning ------------------------------------------------------------------
var base_damage: float = 8.0
var aura_radius: float = 4.0
var tick_interval: float = 2.0

# -- Internal -----------------------------------------------------------------
var _tick_timer: float = 0.0

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	_tick_timer = tick_interval


func deactivate() -> void:
	_tick_timer = 0.0


func _on_upgrade() -> void:
	_apply_level_stats()


# -- Process ------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = tick_interval
		_pulse_damage()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	base_damage = 8.0 * (1.0 + (level - 1) * 0.20)
	aura_radius = 4.0 + level * 0.5
	tick_interval = maxf(2.0 - level * 0.1, 1.0)


func _pulse_damage() -> void:
	var origin := player.global_position
	var damage := get_scaled_damage(base_damage)

	for enemy in _get_enemies_in_range(origin, aura_radius):
		_deal_damage(enemy, damage)
