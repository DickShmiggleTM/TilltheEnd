extends AbilityBase
## Soul Shield -- grants an absorb shield that blocks incoming damage.
## Killing enemies recharges the shield by a flat amount per kill.

# -- Tuning ------------------------------------------------------------------
var shield_max: float = 30.0
var recharge_per_kill: float = 5.0

# -- State --------------------------------------------------------------------
var shield_current: float = 0.0

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	shield_current = shield_max
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func deactivate() -> void:
	if EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)
	shield_current = 0.0


func _on_upgrade() -> void:
	_apply_level_stats()
	# Refill shield on upgrade as a small bonus.
	shield_current = shield_max


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Shield capacity and recharge scale with level.
	shield_max = 30.0 + (level - 1) * 15.0
	recharge_per_kill = 5.0 + (level - 1) * 2.0


func _on_player_damaged(amount: float, _source: Node3D) -> void:
	if shield_current <= 0.0:
		return

	# Absorb as much damage as possible with the shield.
	var absorbed: float = minf(amount, shield_current)
	shield_current -= absorbed

	# Heal back the absorbed portion so net damage is reduced.
	if absorbed > 0.0:
		EventBus.player_healed.emit(absorbed)


func _on_enemy_killed(_enemy: Node3D, _position: Vector3) -> void:
	shield_current = minf(shield_current + recharge_per_kill, shield_max)
