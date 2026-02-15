extends Node
## Generates randomized upgrade choices for level-up rewards.
## Handles weapons, abilities, and traits with weighted selection
## based on rarity tiers (Common, Rare, Mythic) modified by player luck.

# ── Rarity system ──────────────────────────────────────────────────────────
enum Rarity { COMMON, RARE, MYTHIC }

const RARITY_BASE_CHANCES := {
	Rarity.COMMON: 0.50,
	Rarity.RARE: 0.20,
	Rarity.MYTHIC: 0.10,
}

const RARITY_NAMES := {
	Rarity.COMMON: "Common",
	Rarity.RARE: "Rare",
	Rarity.MYTHIC: "Mythic",
}

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.8, 0.8, 0.8),       # Silver-white
	Rarity.RARE: Color(0.3, 0.5, 1.0),          # Blue
	Rarity.MYTHIC: Color(1.0, 0.3, 0.8),        # Pink-magenta
}

## Luck bonus per luck level: +5% added to both Rare and Mythic chances.
const LUCK_RARITY_BONUS := 0.05


# ══════════════════════════════════════════════════════════════════════════════
# Weapon Database
# ══════════════════════════════════════════════════════════════════════════════

const WEAPON_DATABASE := {
	"pistol": {
		"id": "pistol", "name": "Hellfire Pistol", "type": "weapon",
		"rarity": Rarity.COMMON,
		"description": "Reliable sidearm. Fast firing, moderate damage.",
		"damage": 8.0, "fire_rate": 0.2, "spread": 2.0,
		"projectile_speed": 40.0, "ammo_type": "bullet",
		"color": Color(1.0, 0.8, 0.2), "level": 1,
		"upgrade_desc": "Damage +25%, Fire rate +10%"
	},
	"shotgun": {
		"id": "shotgun", "name": "Gore Cannon", "type": "weapon",
		"rarity": Rarity.COMMON,
		"description": "Devastating spread. Obliterates at close range.",
		"damage": 5.0, "fire_rate": 0.7, "spread": 15.0,
		"projectile_speed": 35.0, "pellets": 8, "ammo_type": "shell",
		"color": Color(1.0, 0.3, 0.1), "level": 1,
		"upgrade_desc": "Pellets +2, Damage +15%"
	},
	"smg": {
		"id": "smg", "name": "Rip Shredder", "type": "weapon",
		"rarity": Rarity.COMMON,
		"description": "Extremely fast firing. Sprays death everywhere.",
		"damage": 4.0, "fire_rate": 0.08, "spread": 8.0,
		"projectile_speed": 38.0, "ammo_type": "bullet",
		"color": Color(0.2, 0.8, 1.0), "level": 1,
		"upgrade_desc": "Fire rate +15%, Spread -10%"
	},
	"rocket_launcher": {
		"id": "rocket_launcher", "name": "Doom Bringer", "type": "weapon",
		"rarity": Rarity.RARE,
		"description": "Explosive rockets. Massive area damage.",
		"damage": 35.0, "fire_rate": 1.2, "spread": 1.0,
		"projectile_speed": 20.0, "explosion_radius": 4.0, "ammo_type": "rocket",
		"color": Color(1.0, 0.1, 0.1), "level": 1,
		"upgrade_desc": "Blast radius +20%, Damage +20%"
	},
	"plasma_rifle": {
		"id": "plasma_rifle", "name": "Void Scorcher", "type": "weapon",
		"rarity": Rarity.RARE,
		"description": "Searing plasma bolts. Burns through armor.",
		"damage": 12.0, "fire_rate": 0.15, "spread": 3.0,
		"projectile_speed": 30.0, "armor_pierce": 0.5, "ammo_type": "cell",
		"color": Color(0.3, 1.0, 0.3), "level": 1,
		"upgrade_desc": "Armor pierce +15%, Damage +20%"
	},
	"railgun": {
		"id": "railgun", "name": "Reaper Rail", "type": "weapon",
		"rarity": Rarity.MYTHIC,
		"description": "Piercing beam. Hits everything in a line.",
		"damage": 45.0, "fire_rate": 1.5, "spread": 0.0,
		"projectile_speed": 100.0, "pierce": 5, "ammo_type": "cell",
		"color": Color(0.8, 0.2, 1.0), "level": 1,
		"upgrade_desc": "Pierce +2, Damage +25%"
	},
	"minigun": {
		"id": "minigun", "name": "Hellstorm", "type": "weapon",
		"rarity": Rarity.RARE,
		"description": "Spinning barrels of death. Ramps up fire rate.",
		"damage": 6.0, "fire_rate": 0.05, "spread": 10.0,
		"projectile_speed": 42.0, "spinup": true, "ammo_type": "bullet",
		"color": Color(0.9, 0.9, 0.2), "level": 1,
		"upgrade_desc": "Max fire rate +20%, Spread -15%"
	},
	"flamethrower": {
		"id": "flamethrower", "name": "Inferno Spewer", "type": "weapon",
		"rarity": Rarity.COMMON,
		"description": "Continuous flame cone. Sets enemies ablaze.",
		"damage": 3.0, "fire_rate": 0.03, "spread": 20.0,
		"projectile_speed": 15.0, "burn_dps": 5.0, "ammo_type": "fuel",
		"color": Color(1.0, 0.5, 0.0), "level": 1,
		"upgrade_desc": "Burn DPS +30%, Range +15%"
	},
	"crossbow": {
		"id": "crossbow", "name": "Skull Piercer", "type": "weapon",
		"rarity": Rarity.RARE,
		"description": "Heavy bolt. Massive crit damage.",
		"damage": 25.0, "fire_rate": 0.9, "spread": 0.5,
		"projectile_speed": 45.0, "crit_bonus": 2.0, "ammo_type": "bolt",
		"color": Color(0.6, 0.3, 0.1), "level": 1,
		"upgrade_desc": "Crit multiplier +25%, Damage +15%"
	},
	"acid_gun": {
		"id": "acid_gun", "name": "Bile Launcher", "type": "weapon",
		"rarity": Rarity.COMMON,
		"description": "Corrosive globs that leave damaging pools.",
		"damage": 10.0, "fire_rate": 0.5, "spread": 5.0,
		"projectile_speed": 22.0, "dot_damage": 4.0, "ammo_type": "acid",
		"color": Color(0.2, 1.0, 0.0), "level": 1,
		"upgrade_desc": "DoT duration +1s, Pool size +20%"
	},
}


# ══════════════════════════════════════════════════════════════════════════════
# Ability Database
# ══════════════════════════════════════════════════════════════════════════════

const ABILITY_DATABASE := {
	# ── Existing abilities ─────────────────────────────────────────────────
	"auto_turret": {
		"id": "auto_turret", "name": "Auto Turret", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Deploys an auto-turret that follows you and fires at nearby enemies.",
		"damage": 5.0, "fire_rate": 0.3, "range": 12.0, "duration": -1.0,
		"color": Color(0.2, 0.7, 1.0), "level": 1,
		"upgrade_desc": "Damage +30%, Fire rate +15%"
	},
	"bomb": {
		"id": "bomb", "name": "Frag Grenade", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Throwable explosive. Replenished by enemy drops. Devastating blast.",
		"damage": 40.0, "radius": 5.0, "max_charges": 3, "charges": 3,
		"color": Color(1.0, 0.6, 0.0), "level": 1,
		"upgrade_desc": "Max charges +1, Damage +25%, Radius +15%"
	},
	"death_skulls": {
		"id": "death_skulls", "name": "Spirit Skulls", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Spectral skulls orbit you, shredding any enemy they touch.",
		"damage": 8.0, "skull_count": 3, "radius": 3.0, "spin_speed": 2.0,
		"color": Color(0.8, 0.1, 0.8), "level": 1,
		"upgrade_desc": "Skulls +1, Damage +20%, Orbit speed +10%"
	},
	"chain_lightning": {
		"id": "chain_lightning", "name": "Chain Lightning", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Auto-fires lightning at a random nearby enemy. Chains to 2 adjacent enemies.",
		"damage": 12.0, "chains": 2, "range": 8.0, "cooldown": 2.5,
		"color": Color(0.3, 0.5, 1.0), "level": 1,
		"upgrade_desc": "Chains +1, Damage +20%"
	},
	"fire_nova": {
		"id": "fire_nova", "name": "Firestarter", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Sets one enemy close to you on fire, causing 3 damage every second for 3 seconds.",
		"damage": 3.0, "burn_duration": 3.0, "cooldown": 4.0, "range": 6.0,
		"color": Color(1.0, 0.2, 0.0), "level": 1,
		"upgrade_desc": "Burn damage +25%, Cooldown -0.5s"
	},
	"blood_scythe": {
		"id": "blood_scythe", "name": "Lifeleech", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Gradually regain 1 health every 20 seconds. Recover 3 health for every 10 enemies killed.",
		"heal_passive": 1.0, "heal_interval": 20.0, "heal_per_kills": 3.0, "kills_needed": 10,
		"color": Color(0.8, 0.0, 0.0), "level": 1,
		"upgrade_desc": "Heal amounts +25%, Interval -2s"
	},
	"frost_aura": {
		"id": "frost_aura", "name": "Icy Presence", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Slows enemies within close range for 5 secs. Stacks every 2 secs up to 3 times.",
		"slow_amount": 0.3, "radius": 5.0, "stack_interval": 2.0, "max_stacks": 3,
		"color": Color(0.5, 0.8, 1.0), "level": 1,
		"upgrade_desc": "Slow +10%, Radius +1m, Max stacks +1"
	},
	"shadow_clone": {
		"id": "shadow_clone", "name": "Shadow Clone", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Creates a decoy that attracts enemies and explodes after a delay.",
		"damage": 25.0, "health": 30.0, "duration": 5.0, "cooldown": 8.0,
		"color": Color(0.3, 0.0, 0.5), "level": 1,
		"upgrade_desc": "Explosion damage +30%, Duration +1s"
	},
	"meteor_strike": {
		"id": "meteor_strike", "name": "Meteor Strike", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Calls down a meteor on the densest cluster of enemies.",
		"damage": 60.0, "radius": 4.0, "cooldown": 10.0,
		"color": Color(1.0, 0.4, 0.0), "level": 1,
		"upgrade_desc": "Damage +25%, Cooldown -1.5s"
	},

	# ── Existing (clarified) abilities ────────────────────────────────────
	"thornflesh": {
		"id": "thornflesh", "name": "Thornflesh", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Enemies that damage you with melee attacks take damage equal to 20% of their base health.",
		"reflect_percent": 0.20,
		"color": Color(0.6, 0.2, 0.4), "level": 1,
		"upgrade_desc": "Reflect +5%"
	},
	"magnet_pull": {
		"id": "magnet_pull", "name": "Magnet Pull", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Increases pickup collection range by 25%.",
		"range_bonus": 0.25,
		"color": Color(0.3, 0.6, 1.0), "level": 1,
		"upgrade_desc": "Range bonus +10%"
	},

	# ── New abilities ─────────────────────────────────────────────────────
	"soul_shield": {
		"id": "soul_shield", "name": "Soul Shield", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Adds a shield bar that absorbs damage. Recharges gradually with enemies killed.",
		"shield_amount": 30.0, "recharge_per_kill": 3.0,
		"color": Color(0.4, 0.7, 1.0), "level": 1,
		"upgrade_desc": "Shield +10, Recharge per kill +1"
	},
	"flaming_aura": {
		"id": "flaming_aura", "name": "Flaming Aura", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Deals damage to enemies within an area around you every 2 seconds.",
		"damage": 5.0, "radius": 4.0, "tick_interval": 2.0,
		"color": Color(1.0, 0.4, 0.0), "level": 1,
		"upgrade_desc": "Damage +25%, Radius +0.5m"
	},
	"quick_learning": {
		"id": "quick_learning", "name": "Quick Learning", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Adds a 2x multiplier for EXP picked up.",
		"exp_multiplier": 2.0,
		"color": Color(0.9, 0.9, 0.3), "level": 1,
		"upgrade_desc": "EXP multiplier +0.5x"
	},
	"bounceback": {
		"id": "bounceback", "name": "Bounceback", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Deals damage equal to the damage you take from an attack back to the attacker.",
		"reflect_mult": 1.0,
		"color": Color(0.7, 0.7, 0.3), "level": 1,
		"upgrade_desc": "Reflected damage +25%"
	},
	"telekinesis": {
		"id": "telekinesis", "name": "Telekinesis", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Doubles pushback force on all bullets. Enemies are pushed back when hit.",
		"pushback_mult": 2.0,
		"color": Color(0.6, 0.3, 1.0), "level": 1,
		"upgrade_desc": "Pushback force +50%"
	},
	"big_boot": {
		"id": "big_boot", "name": "Big Boot", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Powers up your kick with double knockback, AoE effect, and a charge ability that triples force and damage.",
		"knockback_mult": 2.0, "kick_damage": 15.0, "kick_radius": 2.5,
		"charge_mult": 3.0, "charge_time": 1.5,
		"color": Color(0.6, 0.4, 0.2), "level": 1,
		"upgrade_desc": "Kick damage +30%, Knockback +25%"
	},
	"rubber_rounds": {
		"id": "rubber_rounds", "name": "Rubber Rounds", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "All shots bounce once off enemies or walls. Bounces increase by 1 per upgrade level.",
		"bounce_count": 1,
		"color": Color(0.9, 0.7, 0.2), "level": 1,
		"upgrade_desc": "Bounces +1"
	},
	"spirit_shot": {
		"id": "spirit_shot", "name": "Spirit Shot", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Shots pierce through one enemy. Pierce count increases by 1 per upgrade level.",
		"pierce_count": 1,
		"color": Color(0.5, 0.8, 0.9), "level": 1,
		"upgrade_desc": "Pierce +1"
	},
	"gods_tear": {
		"id": "gods_tear", "name": "God's Tear", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Revive on death if you've killed 75+ enemies since acquiring. Kill requirement doubles with each use.",
		"kills_required": 75, "uses": 0,
		"color": Color(1.0, 0.9, 0.4), "level": 1,
		"upgrade_desc": "Base kills required -15"
	},
	"quick_reflexes": {
		"id": "quick_reflexes", "name": "Quick Reflexes", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Doubles the percentage chance of dodging an attack.",
		"dodge_mult": 2.0,
		"color": Color(0.5, 0.8, 0.5), "level": 1,
		"upgrade_desc": "Dodge multiplier +0.5x"
	},
	"lightweight": {
		"id": "lightweight", "name": "Lightweight", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Movement speed is increased by 10%.",
		"speed_bonus": 0.10,
		"color": Color(0.7, 1.0, 0.7), "level": 1,
		"upgrade_desc": "Speed bonus +5%"
	},
	"tough_skin": {
		"id": "tough_skin", "name": "Tough Skin", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Increases defense by 20%.",
		"defense_bonus": 0.20,
		"color": Color(0.6, 0.6, 0.7), "level": 1,
		"upgrade_desc": "Defense bonus +10%"
	},
	"vengeful_rage": {
		"id": "vengeful_rage", "name": "Vengeful Rage", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Increases defense and attack by 15% for 5 seconds every time you take damage.",
		"buff_amount": 0.15, "buff_duration": 5.0,
		"color": Color(1.0, 0.2, 0.2), "level": 1,
		"upgrade_desc": "Buff amount +5%, Duration +1s"
	},
	"hyperfocus": {
		"id": "hyperfocus", "name": "Hyperfocus", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Every time you dodge an attack, time slows by 50% for 2 seconds.",
		"slow_amount": 0.5, "slow_duration": 2.0,
		"color": Color(0.4, 0.4, 0.9), "level": 1,
		"upgrade_desc": "Slow duration +0.5s"
	},
	"toxic_emission": {
		"id": "toxic_emission", "name": "Toxic Emission", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Applies poison to nearby enemies for 3 seconds. Poison reapplied every second while in range.",
		"damage": 4.0, "radius": 4.0, "poison_duration": 3.0, "apply_interval": 1.0,
		"color": Color(0.2, 0.8, 0.1), "level": 1,
		"upgrade_desc": "Poison damage +25%, Radius +0.5m"
	},
	"uplift": {
		"id": "uplift", "name": "Uplift", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Allows an extra jump mid-air.",
		"extra_jumps": 1,
		"color": Color(0.6, 0.9, 1.0), "level": 1,
		"upgrade_desc": "Extra jumps +1"
	},
	"sages_eye": {
		"id": "sages_eye", "name": "Sage's Eye", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Reveals secrets by highlighting important areas or objects when nearby.",
		"reveal_range": 10.0,
		"color": Color(0.9, 0.7, 1.0), "level": 1,
		"upgrade_desc": "Reveal range +3m"
	},
	"versatility": {
		"id": "versatility", "name": "Versatility", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Adds 2 more ability slots for this run.",
		"extra_slots": 2,
		"color": Color(0.8, 0.6, 0.3), "level": 1,
		"upgrade_desc": "Extra slots +1"
	},
	"triggerhappy": {
		"id": "triggerhappy", "name": "Triggerhappy", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Increases attack rate by 15% but decreases accuracy by 5%.",
		"fire_rate_bonus": 0.15, "accuracy_penalty": 0.05,
		"color": Color(1.0, 0.5, 0.2), "level": 1,
		"upgrade_desc": "Attack rate +10%, Accuracy -3%"
	},
	"gifted": {
		"id": "gifted", "name": "Gifted", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Adds an ability slot and decreases all ability cooldowns by 10%.",
		"extra_slots": 1, "cooldown_reduction": 0.10,
		"color": Color(1.0, 0.8, 0.3), "level": 1,
		"upgrade_desc": "Cooldown reduction +5%"
	},
	"spiritually_aligned": {
		"id": "spiritually_aligned", "name": "Spiritually Aligned", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Adds 25 to base health and recovers 2 HP every 20 seconds.",
		"health_bonus": 25.0, "heal_amount": 2.0, "heal_interval": 20.0,
		"color": Color(0.5, 0.9, 0.8), "level": 1,
		"upgrade_desc": "Health bonus +10, Heal amount +1"
	},
	"intimidating_gaze": {
		"id": "intimidating_gaze", "name": "Intimidating Gaze", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Halves the attack and defense of enemies currently within your line of sight.",
		"debuff_amount": 0.5, "range": 15.0,
		"color": Color(0.9, 0.2, 0.2), "level": 1,
		"upgrade_desc": "Debuff range +3m"
	},
	"bullet_time": {
		"id": "bullet_time", "name": "Bullet Time", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Doubles the projectiles of each shot fired with all weapons.",
		"projectile_mult": 2,
		"color": Color(0.9, 0.3, 0.1), "level": 1,
		"upgrade_desc": "Projectile multiplier +1"
	},
	"voidwalker": {
		"id": "voidwalker", "name": "Voidwalker", "type": "ability",
		"rarity": Rarity.MYTHIC,
		"description": "Adds 2 ability slots and halves cooldowns, but halves weapon damage and lowers defense by 20%.",
		"extra_slots": 2, "cooldown_reduction": 0.50,
		"damage_penalty": 0.50, "defense_penalty": 0.20,
		"color": Color(0.2, 0.0, 0.4), "level": 1,
		"upgrade_desc": "Cooldown reduction +10%"
	},
	"clairvoyant": {
		"id": "clairvoyant", "name": "Clairvoyant", "type": "ability",
		"rarity": Rarity.RARE,
		"description": "Guarantees the next attack is dodged when charged. Recharges 45 seconds after dodging.",
		"recharge_time": 45.0,
		"color": Color(0.7, 0.5, 1.0), "level": 1,
		"upgrade_desc": "Recharge time -5s"
	},
	"acid_dipped": {
		"id": "acid_dipped", "name": "Acid Dipped", "type": "ability",
		"rarity": Rarity.COMMON,
		"description": "Applies 2 damage every 3 secs for 12 secs on hit. Does not stack; reapplied only when expired.",
		"dot_damage": 2.0, "dot_interval": 3.0, "dot_duration": 12.0,
		"color": Color(0.4, 0.9, 0.1), "level": 1,
		"upgrade_desc": "DoT damage +1, Duration +3s"
	},
}


# ══════════════════════════════════════════════════════════════════════════════
# Trait Database
# ══════════════════════════════════════════════════════════════════════════════

const TRAIT_DATABASE := {
	"max_health": {
		"trait_name": "max_health", "name": "Vitality", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Increases maximum health by 15.",
		"trait_value": 15.0, "color": Color(1.0, 0.2, 0.2),
	},
	"defense": {
		"trait_name": "defense", "name": "Iron Skin", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Reduces incoming damage by 3.",
		"trait_value": 3.0, "color": Color(0.5, 0.5, 0.6),
	},
	"speed": {
		"trait_name": "speed", "name": "Adrenaline Rush", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Increases movement speed by 0.8.",
		"trait_value": 0.8, "color": Color(0.2, 1.0, 0.5),
	},
	"fire_rate_mult": {
		"trait_name": "fire_rate_mult", "name": "Trigger Finger", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Increases firing speed by 10%.",
		"trait_value": 0.1, "color": Color(1.0, 1.0, 0.2),
	},
	"exp_mult": {
		"trait_name": "exp_mult", "name": "Soul Siphon", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Increases EXP gained from all sources by 15%.",
		"trait_value": 0.15, "color": Color(0.8, 0.4, 1.0),
	},
	"collect_range": {
		"trait_name": "collect_range", "name": "Magnetic Pull", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Increases pickup collection range by 1.5m.",
		"trait_value": 1.5, "color": Color(0.3, 0.6, 1.0),
	},
	"damage_mult": {
		"trait_name": "damage_mult", "name": "Brutality", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Increases all damage dealt by 8%.",
		"trait_value": 0.08, "color": Color(1.0, 0.0, 0.0),
	},
	"crit_chance": {
		"trait_name": "crit_chance", "name": "Precision", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Increases critical hit chance by 5%.",
		"trait_value": 0.05, "color": Color(1.0, 0.8, 0.0),
	},
	"crit_damage": {
		"trait_name": "crit_damage", "name": "Executioner", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Increases critical hit damage by 20%.",
		"trait_value": 0.2, "color": Color(0.9, 0.1, 0.3),
	},
	"dodge_chance": {
		"trait_name": "dodge_chance", "name": "Phantom Step", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Gain 4% chance to dodge incoming attacks.",
		"trait_value": 0.04, "color": Color(0.5, 0.5, 0.8),
	},
	"health_regen": {
		"trait_name": "health_regen", "name": "Regeneration", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Regenerate 1 HP per second.",
		"trait_value": 1.0, "color": Color(0.0, 1.0, 0.3),
	},
	"armor": {
		"trait_name": "armor", "name": "Plating", "type": "trait",
		"rarity": Rarity.COMMON,
		"description": "Gain 5 armor that reduces damage by a percentage.",
		"trait_value": 5.0, "color": Color(0.7, 0.7, 0.8),
	},
	"thorns": {
		"trait_name": "thorns", "name": "Thorns", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Reflect 10% of damage taken back to attackers.",
		"trait_value": 0.1, "color": Color(0.6, 0.0, 0.3),
	},
	"lifesteal": {
		"trait_name": "lifesteal", "name": "Vampirism", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Heal for 3% of damage dealt.",
		"trait_value": 0.03, "color": Color(0.5, 0.0, 0.0),
	},
	"luck": {
		"trait_name": "luck", "name": "Fortune", "type": "trait",
		"rarity": Rarity.RARE,
		"description": "Increases gold drops and boosts Rare/Mythic appearance chances by 5%.",
		"trait_value": 1.0, "color": Color(1.0, 0.85, 0.0),
	},
}


# ══════════════════════════════════════════════════════════════════════════════
# Level-up choice generation
# ══════════════════════════════════════════════════════════════════════════════

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


# ── Rarity-weighted selection ──────────────────────────────────────────────

## Check if an item passes its rarity appearance check, modified by player luck.
func _passes_rarity_check(rarity: int) -> bool:
	var luck_level: float = GameManager.get_trait("luck")
	var base_chance: float = RARITY_BASE_CHANCES.get(rarity, 0.50)
	var luck_bonus: float = luck_level * LUCK_RARITY_BONUS
	var final_chance: float = base_chance + luck_bonus
	return randf() < final_chance


## Pick a random item from a dictionary database, respecting rarity weights.
## Tries up to max_attempts to find an item that passes the rarity check.
## Falls back to any item if none pass.
func _pick_rarity_weighted(database: Dictionary, exclude_ids: Array = [], max_attempts: int = 30) -> String:
	var all_ids: Array = []
	for key in database.keys():
		if key not in exclude_ids:
			all_ids.append(key)

	if all_ids.is_empty():
		return ""

	# Try to find an item that passes the rarity check
	for _attempt in max_attempts:
		var candidate_id: String = all_ids[randi() % all_ids.size()]
		var item: Dictionary = database[candidate_id]
		var rarity: int = item.get("rarity", Rarity.COMMON)
		if _passes_rarity_check(rarity):
			return candidate_id

	# Fallback: just pick a random one
	return all_ids[randi() % all_ids.size()]


# ── Weapon generation ──────────────────────────────────────────────────────

func _generate_new_weapon() -> Dictionary:
	var owned_ids: Array[String] = []
	for w in GameManager.player_weapons:
		owned_ids.append(w.get("id", ""))

	var chosen_id := _pick_rarity_weighted(WEAPON_DATABASE, owned_ids)
	if chosen_id.is_empty():
		return _generate_weapon_upgrade()
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
		"rarity": weapon.get("rarity", Rarity.COMMON),
	}


# ── Ability generation ─────────────────────────────────────────────────────

func _generate_new_ability() -> Dictionary:
	var owned_ids: Array[String] = []
	for a in GameManager.player_abilities:
		owned_ids.append(a.get("id", ""))

	var chosen_id := _pick_rarity_weighted(ABILITY_DATABASE, owned_ids)
	if chosen_id.is_empty():
		return _generate_ability_upgrade()
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
		"rarity": ability.get("rarity", Rarity.COMMON),
	}


# ── Trait generation ───────────────────────────────────────────────────────

func _generate_trait_upgrade(_player_level: int) -> Dictionary:
	var chosen_key := _pick_rarity_weighted(TRAIT_DATABASE)
	if chosen_key.is_empty():
		var trait_keys := TRAIT_DATABASE.keys()
		chosen_key = trait_keys[randi() % trait_keys.size()]
	return TRAIT_DATABASE[chosen_key].duplicate(true)


# ── Utilities ──────────────────────────────────────────────────────────────

func _has_duplicate(choices: Array, new_choice: Dictionary) -> bool:
	for c in choices:
		if c.get("id", "") == new_choice.get("id", "") and c.get("trait_name", "") == new_choice.get("trait_name", ""):
			return true
	return false
