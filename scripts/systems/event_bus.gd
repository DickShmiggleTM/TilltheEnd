extends Node
## Global event bus for decoupled communication between game systems.

# Player events
signal player_damaged(amount: float, source: Node3D)
signal player_healed(amount: float)
signal player_died
signal player_level_up(new_level: int)
signal player_exp_gained(amount: float, total: float, needed: float)
signal player_kicked(direction: Vector3)

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
signal coin_collected(amount: int)

# Upgrade events
signal level_up_choices_ready(choices: Array)
signal upgrade_selected(upgrade: Dictionary)
signal weapon_acquired(weapon_data: Dictionary)
signal ability_acquired(ability_data: Dictionary)
signal skill_acquired(skill_data: Dictionary)
signal trait_upgraded(trait_name: String, new_value: float)
signal weapon_upgraded(weapon_id: String, new_level: int)
signal ability_upgraded(ability_id: String, new_level: int)
signal skill_upgraded(skill_id: String, new_level: int)

# Skill events
signal skill_activated(skill_id: String)
signal skill_cooldown_started(skill_id: String, cooldown: float)
signal skill_cooldown_finished(skill_id: String)

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

# Shop / Relic / Voucher events
signal relic_equipped(relic_data: Dictionary)
signal relic_unequipped(relic_id: String)
signal voucher_redeemed(voucher_data: Dictionary)
signal coins_changed(new_total: int)
signal shop_opened
signal shop_closed
