extends AbilityBase
## Thornflesh -- enemies that melee-attack the player take damage equal to
## a percentage of their base health as reflected thorn damage.

# -- Tuning ------------------------------------------------------------------
## Fraction of the attacker's max health dealt back as reflect damage.
var reflect_percent: float = 0.20

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	EventBus.player_damaged.connect(_on_player_hit)


func deactivate() -> void:
	if EventBus.player_damaged.is_connected(_on_player_hit):
		EventBus.player_damaged.disconnect(_on_player_hit)


func _on_upgrade() -> void:
	_apply_level_stats()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Base 20%, +5% per additional level.
	reflect_percent = 0.20 + (level - 1) * 0.05


func _on_player_hit(_amount: float, source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	# Only reflect against melee enemies (must be in "enemies" group).
	if not source.is_in_group("enemies"):
		return

	# Calculate reflect damage based on the attacker's max health.
	var enemy_max_hp: float = 0.0
	if "max_health" in source:
		enemy_max_hp = source.max_health
	elif "health" in source:
		enemy_max_hp = source.health  # fallback if max_health unavailable
	else:
		return  # cannot determine health -- skip

	var reflect_damage: float = enemy_max_hp * reflect_percent * _damage_mult
	_deal_damage(source, reflect_damage)
