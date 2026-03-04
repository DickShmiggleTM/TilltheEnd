extends Node
## Global event bus for decoupled communication between game systems.

# Player events
signal player_damaged(amount: float, source: Node3D)
signal player_healed(amount: float)
signal player_died
signal player_level_up(new_level: int)
signal player_exp_gained(amount: float, total: float, needed: float)

# Combat events
signal enemy_killed(enemy: Node3D, position: Vector3)
signal enemy_damaged(enemy: Node3D, amount: float)
signal boss_killed
signal damage_dealt(amount: float, position: Vector3, is_crit: bool)

# Wave events
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal all_waves_completed
signal boss_wave_started
signal enemies_remaining_changed(count: int)

# Pickup events
signal exp_dropped(position: Vector3, amount: float)
signal exp_collected(amount: float)
signal ammo_dropped(position: Vector3, ammo_type: String)
signal ammo_collected(ammo_type: String, amount: int)
signal health_dropped(position: Vector3, amount: float)
signal health_collected(amount: float)
signal bomb_ammo_collected(amount: int)
signal gold_dropped(position: Vector3, amount: int)
signal gold_collected(amount: int)

# Player combat ability events
signal player_dodged_attack
signal player_revived

# Upgrade events
signal level_up_choices_ready(choices: Array)
signal upgrade_selected(upgrade: Dictionary)
signal weapon_acquired(weapon_data: Dictionary)
signal ability_acquired(ability_data: Dictionary)
signal trait_upgraded(trait_name: String, new_value: float)
signal weapon_upgraded(weapon_id: String, new_level: int)
signal ability_upgraded(ability_id: String, new_level: int)

# Game state events
signal game_started
signal game_over(survived_waves: int, kills: int)
signal game_won
signal game_paused
signal game_resumed
signal run_started

# Level / campaign events
signal level_complete(level_number: int)
signal level_started(level_number: int, level_data: Dictionary)
signal level_intro_finished
signal boss_intro_started(boss_name: String, boss_intro: String)

# Hub world events
signal hub_world_entered
signal hub_door_unlocked(level_number: int)
signal hub_all_doors_reset
signal relic_purchased(relic_id: String, cost: int)
signal hub_interaction_changed(target_name: String)  # empty string = no target
