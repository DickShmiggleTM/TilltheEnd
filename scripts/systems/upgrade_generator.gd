extends Node
## Generates randomized upgrade choices for level-up rewards.
## Handles weapons, abilities, and traits with weighted selection.

const WEAPON_DATABASE := {
	"pistol": {
		"id": "pistol", "name": "Hellfire Pistol", "type": "weapon",
		"description": "Reliable sidearm. Fast firing, moderate damage.",
		"damage": 8.0, "fire_rate": 0.2, "spread": 2.0,
		"projectile_speed": 40.0, "ammo_type": "bullet",
		"color": Color(1.0, 0.8, 0.2), "level": 1,
		"upgrade_desc": "Damage +25%, Fire rate +10%"
	},
	"shotgun": {
		"id": "shotgun", "name": "Gore Cannon", "type": "weapon",
		"description": "Devastating spread. Obliterates at close range.",
		"damage": 5.0, "fire_rate": 0.7, "spread": 15.0,
		"projectile_speed": 35.0, "pellets": 8, "ammo_type": "shell",
		"color": Color(1.0, 0.3, 0.1), "level": 1,
		"upgrade_desc": "Pellets +2, Damage +15%"
	},
	"smg": {
		"id": "smg", "name": "Rip Shredder", "type": "weapon",
		"description": "Extremely fast firing. Sprays death everywhere.",
		"damage": 4.0, "fire_rate": 0.08, "spread": 8.0,
		"projectile_speed": 38.0, "ammo_type": "bullet",
		"color": Color(0.2, 0.8, 1.0), "level": 1,
		"upgrade_desc": "Fire rate +15%, Spread -10%"
	},
	"rocket_launcher": {
		"id": "rocket_launcher", "name": "Doom Bringer", "type": "weapon",
		"description": "Explosive rockets. Massive area damage.",
		"damage": 35.0, "fire_rate": 1.2, "spread": 1.0,
		"projectile_speed": 20.0, "explosion_radius": 4.0, "ammo_type": "rocket",
		"color": Color(1.0, 0.1, 0.1), "level": 1,
		"upgrade_desc": "Blast radius +20%, Damage +20%"
	},
	"plasma_rifle": {
		"id": "plasma_rifle", "name": "Void Scorcher", "type": "weapon",
		"description": "Searing plasma bolts. Burns through armor.",
		"damage": 12.0, "fire_rate": 0.15, "spread": 3.0,
		"projectile_speed": 30.0, "armor_pierce": 0.5, "ammo_type": "cell",
		"color": Color(0.3, 1.0, 0.3), "level": 1,
		"upgrade_desc": "Armor pierce +15%, Damage +20%"
	},
	"railgun": {
		"id": "railgun", "name": "Reaper Rail", "type": "weapon",
		"description": "Piercing beam. Hits everything in a line.",
		"damage": 45.0, "fire_rate": 1.5, "spread": 0.0,
		"projectile_speed": 100.0, "pierce": 5, "ammo_type": "cell",
		"color": Color(0.8, 0.2, 1.0), "level": 1,
		"upgrade_desc": "Pierce +2, Damage +25%"
	},
	"minigun": {
		"id": "minigun", "name": "Hellstorm", "type": "weapon",
		"description": "Spinning barrels of death. Ramps up fire rate.",
		"damage": 6.0, "fire_rate": 0.05, "spread": 10.0,
		"projectile_speed": 42.0, "spinup": true, "ammo_type": "bullet",
		"color": Color(0.9, 0.9, 0.2), "level": 1,
		"upgrade_desc": "Max fire rate +20%, Spread -15%"
	},
	"flamethrower": {
		"id": "flamethrower", "name": "Inferno Spewer", "type": "weapon",
		"description": "Continuous flame cone. Sets enemies ablaze.",
		"damage": 3.0, "fire_rate": 0.03, "spread": 20.0,
		"projectile_speed": 15.0, "burn_dps": 5.0, "ammo_type": "fuel",
		"color": Color(1.0, 0.5, 0.0), "level": 1,
		"upgrade_desc": "Burn DPS +30%, Range +15%"
	},
	"crossbow": {
		"id": "crossbow", "name": "Skull Piercer", "type": "weapon",
		"description": "Heavy bolt. Massive crit damage.",
		"damage": 25.0, "fire_rate": 0.9, "spread": 0.5,
		"projectile_speed": 45.0, "crit_bonus": 2.0, "ammo_type": "bolt",
		"color": Color(0.6, 0.3, 0.1), "level": 1,
		"upgrade_desc": "Crit multiplier +25%, Damage +15%"
	},
	"acid_gun": {
		"id": "acid_gun", "name": "Bile Launcher", "type": "weapon",
		"description": "Corrosive globs that leave damaging pools.",
		"damage": 10.0, "fire_rate": 0.5, "spread": 5.0,
		"projectile_speed": 22.0, "dot_damage": 4.0, "ammo_type": "acid",
		"color": Color(0.2, 1.0, 0.0), "level": 1,
		"upgrade_desc": "DoT duration +1s, Pool size +20%"
	},
}

const ABILITY_DATABASE := {
	"auto_turret": {
		"id": "auto_turret", "name": "Sentinel Turret", "type": "ability",
		"description": "Deploys an auto-turret that follows you and fires at nearby enemies.",
		"damage": 5.0, "fire_rate": 0.3, "range": 12.0, "duration": -1.0,
		"color": Color(0.2, 0.7, 1.0), "level": 1,
		"upgrade_desc": "Damage +30%, Fire rate +15%"
	},
	"bomb": {
		"id": "bomb", "name": "Frag Grenade", "type": "ability",
		"description": "Throwable explosive. Replenished by enemy drops. Devastating blast.",
		"damage": 40.0, "radius": 5.0, "max_charges": 3, "charges": 3,
		"color": Color(1.0, 0.6, 0.0), "level": 1,
		"upgrade_desc": "Max charges +1, Damage +25%, Radius +15%"
	},
	"death_skulls": {
		"id": "death_skulls", "name": "Death Orbit", "type": "ability",
		"description": "Spectral skulls orbit you, shredding any enemy they touch.",
		"damage": 8.0, "skull_count": 3, "radius": 3.0, "spin_speed": 2.0,
		"color": Color(0.8, 0.1, 0.8), "level": 1,
		"upgrade_desc": "Skulls +1, Damage +20%, Orbit speed +10%"
	},
	"chain_lightning": {
		"id": "chain_lightning", "name": "Storm Chain", "type": "ability",
		"description": "Lightning arcs from enemy to enemy. More chains at higher levels.",
		"damage": 12.0, "chains": 3, "range": 8.0, "cooldown": 2.5,
		"color": Color(0.3, 0.5, 1.0), "level": 1,
		"upgrade_desc": "Chains +1, Damage +20%"
	},
	"fire_nova": {
		"id": "fire_nova", "name": "Hellfire Nova", "type": "ability",
		"description": "Periodically erupts fire in all directions around you.",
		"damage": 15.0, "radius": 6.0, "cooldown": 4.0,
		"color": Color(1.0, 0.2, 0.0), "level": 1,
		"upgrade_desc": "Radius +1m, Cooldown -0.5s, Damage +15%"
	},
	"blood_scythe": {
		"id": "blood_scythe", "name": "Blood Scythe", "type": "ability",
		"description": "Spectral scythes fly outward, returning with lifesteal.",
		"damage": 10.0, "projectile_count": 4, "cooldown": 3.0, "lifesteal": 0.15,
		"color": Color(0.8, 0.0, 0.0), "level": 1,
		"upgrade_desc": "Projectiles +1, Lifesteal +5%"
	},
	"frost_aura": {
		"id": "frost_aura", "name": "Frost Aura", "type": "ability",
		"description": "Slows all nearby enemies. Frozen enemies take more damage.",
		"slow_amount": 0.3, "radius": 5.0, "damage_amp": 1.2,
		"color": Color(0.5, 0.8, 1.0), "level": 1,
		"upgrade_desc": "Slow +10%, Radius +1m, Damage amp +5%"
	},
	"shadow_clone": {
		"id": "shadow_clone", "name": "Shadow Clone", "type": "ability",
		"description": "Creates a decoy that attracts enemies and explodes after a delay.",
		"damage": 25.0, "health": 30.0, "duration": 5.0, "cooldown": 8.0,
		"color": Color(0.3, 0.0, 0.5), "level": 1,
		"upgrade_desc": "Explosion damage +30%, Duration +1s"
	},
	"venom_trail": {
		"id": "venom_trail", "name": "Venom Trail", "type": "ability",
		"description": "Leave a trail of poison behind you that damages enemies.",
		"damage": 3.0, "duration": 4.0, "width": 1.5,
		"color": Color(0.0, 0.8, 0.2), "level": 1,
		"upgrade_desc": "Damage +25%, Width +0.5m"
	},
	"meteor_strike": {
		"id": "meteor_strike", "name": "Meteor Strike", "type": "ability",
		"description": "Calls down a meteor on the densest cluster of enemies.",
		"damage": 60.0, "radius": 4.0, "cooldown": 10.0,
		"color": Color(1.0, 0.4, 0.0), "level": 1,
		"upgrade_desc": "Damage +25%, Cooldown -1.5s"
	},
}

const TRAIT_DATABASE := {
	"max_health": {
		"trait_name": "max_health", "name": "Vitality", "type": "trait",
		"description": "Increases maximum health by 15.",
		"trait_value": 15.0, "color": Color(1.0, 0.2, 0.2),
	},
	"defense": {
		"trait_name": "defense", "name": "Iron Skin", "type": "trait",
		"description": "Reduces incoming damage by 3.",
		"trait_value": 3.0, "color": Color(0.5, 0.5, 0.6),
	},
	"speed": {
		"trait_name": "speed", "name": "Adrenaline Rush", "type": "trait",
		"description": "Increases movement speed by 0.8.",
		"trait_value": 0.8, "color": Color(0.2, 1.0, 0.5),
	},
	"fire_rate_mult": {
		"trait_name": "fire_rate_mult", "name": "Trigger Finger", "type": "trait",
		"description": "Increases firing speed by 10%.",
		"trait_value": 0.1, "color": Color(1.0, 1.0, 0.2),
	},
	"exp_mult": {
		"trait_name": "exp_mult", "name": "Soul Siphon", "type": "trait",
		"description": "Increases EXP gained from all sources by 15%.",
		"trait_value": 0.15, "color": Color(0.8, 0.4, 1.0),
	},
	"collect_range": {
		"trait_name": "collect_range", "name": "Magnetic Pull", "type": "trait",
		"description": "Increases pickup collection range by 1.5m.",
		"trait_value": 1.5, "color": Color(0.3, 0.6, 1.0),
	},
	"damage_mult": {
		"trait_name": "damage_mult", "name": "Brutality", "type": "trait",
		"description": "Increases all damage dealt by 8%.",
		"trait_value": 0.08, "color": Color(1.0, 0.0, 0.0),
	},
	"crit_chance": {
		"trait_name": "crit_chance", "name": "Precision", "type": "trait",
		"description": "Increases critical hit chance by 5%.",
		"trait_value": 0.05, "color": Color(1.0, 0.8, 0.0),
	},
	"crit_damage": {
		"trait_name": "crit_damage", "name": "Executioner", "type": "trait",
		"description": "Increases critical hit damage by 20%.",
		"trait_value": 0.2, "color": Color(0.9, 0.1, 0.3),
	},
	"dodge_chance": {
		"trait_name": "dodge_chance", "name": "Phantom Step", "type": "trait",
		"description": "Gain 4% chance to dodge incoming attacks.",
		"trait_value": 0.04, "color": Color(0.5, 0.5, 0.8),
	},
	"health_regen": {
		"trait_name": "health_regen", "name": "Regeneration", "type": "trait",
		"description": "Regenerate 1 HP per second.",
		"trait_value": 1.0, "color": Color(0.0, 1.0, 0.3),
	},
	"armor": {
		"trait_name": "armor", "name": "Plating", "type": "trait",
		"description": "Gain 5 armor that reduces damage by a percentage.",
		"trait_value": 5.0, "color": Color(0.7, 0.7, 0.8),
	},
	"thorns": {
		"trait_name": "thorns", "name": "Thorns", "type": "trait",
		"description": "Reflect 10% of damage taken back to attackers.",
		"trait_value": 0.1, "color": Color(0.6, 0.0, 0.3),
	},
	"lifesteal": {
		"trait_name": "lifesteal", "name": "Vampirism", "type": "trait",
		"description": "Heal for 3% of damage dealt.",
		"trait_value": 0.03, "color": Color(0.5, 0.0, 0.0),
	},
}

func generate_level_up_choices(player_level: int) -> Array:
	var choices: Array = []
	var weapons_full := GameManager.player_weapons.size() >= GameManager.MAX_WEAPONS
	var abilities_full := GameManager.player_abilities.size() >= GameManager.MAX_ABILITIES

	# Generate 3 choices
	for i in 3:
		var choice: Dictionary
		var roll := randf()

		if roll < 0.35:
			# Weapon choice
			if weapons_full and not GameManager.player_weapons.is_empty():
				choice = _generate_weapon_upgrade()
			else:
				choice = _generate_new_weapon()
		elif roll < 0.65:
			# Ability choice
			if abilities_full and not GameManager.player_abilities.is_empty():
				choice = _generate_ability_upgrade()
			else:
				choice = _generate_new_ability()
		else:
			# Trait choice
			choice = _generate_trait_upgrade(player_level)

		# Avoid duplicate choices
		var attempts := 0
		while _has_duplicate(choices, choice) and attempts < 10:
			choice = _generate_trait_upgrade(player_level) if randf() > 0.5 else _generate_new_weapon()
			attempts += 1

		choices.append(choice)

	return choices

func _generate_new_weapon() -> Dictionary:
	var available_ids := WEAPON_DATABASE.keys()
	# Filter out weapons player already has
	var owned_ids: Array[String] = []
	for w in GameManager.player_weapons:
		owned_ids.append(w.get("id", ""))
	var candidates: Array = []
	for wid in available_ids:
		if wid not in owned_ids:
			candidates.append(wid)
	if candidates.is_empty():
		return _generate_weapon_upgrade()
	var chosen_id: String = candidates[randi() % candidates.size()]
	return WEAPON_DATABASE[chosen_id].duplicate(true)

func _generate_weapon_upgrade() -> Dictionary:
	if GameManager.player_weapons.is_empty():
		return _generate_trait_upgrade(1)
	var idx := randi() % GameManager.player_weapons.size()
	var weapon: Dictionary = GameManager.player_weapons[idx]
	return {
		"type": "weapon_upgrade",
		"weapon_index": idx,
		"id": weapon.get("id", ""),
		"name": weapon.get("name", "Unknown") + " UP",
		"description": weapon.get("upgrade_desc", "Upgrade this weapon."),
		"current_level": weapon.get("level", 1),
		"color": weapon.get("color", Color.WHITE),
	}

func _generate_new_ability() -> Dictionary:
	var available_ids := ABILITY_DATABASE.keys()
	var owned_ids: Array[String] = []
	for a in GameManager.player_abilities:
		owned_ids.append(a.get("id", ""))
	var candidates: Array = []
	for aid in available_ids:
		if aid not in owned_ids:
			candidates.append(aid)
	if candidates.is_empty():
		return _generate_ability_upgrade()
	var chosen_id: String = candidates[randi() % candidates.size()]
	return ABILITY_DATABASE[chosen_id].duplicate(true)

func _generate_ability_upgrade() -> Dictionary:
	if GameManager.player_abilities.is_empty():
		return _generate_trait_upgrade(1)
	var idx := randi() % GameManager.player_abilities.size()
	var ability: Dictionary = GameManager.player_abilities[idx]
	return {
		"type": "ability_upgrade",
		"ability_index": idx,
		"id": ability.get("id", ""),
		"name": ability.get("name", "Unknown") + " UP",
		"description": ability.get("upgrade_desc", "Upgrade this ability."),
		"current_level": ability.get("level", 1),
		"color": ability.get("color", Color.WHITE),
	}

func _generate_trait_upgrade(_player_level: int) -> Dictionary:
	var trait_keys := TRAIT_DATABASE.keys()
	var chosen_key: String = trait_keys[randi() % trait_keys.size()]
	return TRAIT_DATABASE[chosen_key].duplicate(true)

func _has_duplicate(choices: Array, new_choice: Dictionary) -> bool:
	for c in choices:
		if c.get("id", "") == new_choice.get("id", "") and c.get("trait_name", "") == new_choice.get("trait_name", ""):
			return true
	return false
