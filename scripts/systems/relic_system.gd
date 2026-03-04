class_name RelicSystem
extends RefCounted
## Defines all relics available in the hub world shop.
## Relics are persistent passive upgrades that persist across ALL levels in a run.
## They are purchased with gold collected during levels.
##
## When a level starts, call RelicSystem.apply_relics() to apply all
## purchased relic effects to the player's traits.

# ── Relic definitions ─────────────────────────────────────────────────────
## Each relic is a Dictionary:
##   id         : String  — unique relic identifier
##   name       : String  — display name
##   description: String  — effect description
##   cost       : int     — gold cost in the shop
##   max_stack  : int     — how many times it can be purchased (default 1)
##   effect     : Dictionary — trait changes to apply per stack

static var RELICS: Array[Dictionary] = [
	# ── Common Relics ─────────────────────────────────────────────────────
	{
		"id": "iron_heart",
		"name": "Iron Heart",
		"description": "+25 max health per stack.",
		"cost": 60,
		"max_stack": 4,
		"effect": { "max_health": 25.0 },
	},
	{
		"id": "swiftfoot",
		"name": "Swiftfoot Charm",
		"description": "+0.8 movement speed.",
		"cost": 50,
		"max_stack": 3,
		"effect": { "speed": 0.8 },
	},
	{
		"id": "gunslingers_sigil",
		"name": "Gunslinger's Sigil",
		"description": "+10% fire rate.",
		"cost": 75,
		"max_stack": 3,
		"effect": { "fire_rate_mult": 0.10 },
	},
	{
		"id": "scholars_lens",
		"name": "Scholar's Lens",
		"description": "+20% EXP gain.",
		"cost": 55,
		"max_stack": 3,
		"effect": { "exp_mult": 0.20 },
	},
	{
		"id": "lodestone",
		"name": "Lodestone Fragment",
		"description": "+2.0 pickup collect range.",
		"cost": 45,
		"max_stack": 3,
		"effect": { "collect_range": 2.0 },
	},
	# ── Rare Relics ───────────────────────────────────────────────────────
	{
		"id": "blood_sigil",
		"name": "Blood Sigil",
		"description": "+8% damage multiplier.",
		"cost": 100,
		"max_stack": 4,
		"effect": { "damage_mult": 0.08 },
	},
	{
		"id": "cursed_eye",
		"name": "Cursed Eye",
		"description": "+5% crit chance, +0.25 crit damage.",
		"cost": 120,
		"max_stack": 3,
		"effect": { "crit_chance": 0.05, "crit_damage": 0.25 },
	},
	{
		"id": "iron_skin",
		"name": "Iron Skin",
		"description": "+5 armor and +3 defense.",
		"cost": 90,
		"max_stack": 3,
		"effect": { "armor": 5.0, "defense": 3.0 },
	},
	{
		"id": "vampiric_fang",
		"name": "Vampiric Fang",
		"description": "+3% lifesteal.",
		"cost": 130,
		"max_stack": 2,
		"effect": { "lifesteal": 0.03 },
	},
	{
		"id": "thorned_cloak",
		"name": "Thorned Cloak",
		"description": "+10% thorns damage reflected.",
		"cost": 110,
		"max_stack": 3,
		"effect": { "thorns": 0.10 },
	},
	# ── Mythic Relics ─────────────────────────────────────────────────────
	{
		"id": "phoenix_ember",
		"name": "Phoenix Ember",
		"description": "+1 HP/s regen and +20 max health.",
		"cost": 200,
		"max_stack": 2,
		"effect": { "health_regen": 1.0, "max_health": 20.0 },
	},
	{
		"id": "void_crystal",
		"name": "Void Crystal",
		"description": "+4% dodge chance and +8% damage.",
		"cost": 220,
		"max_stack": 2,
		"effect": { "dodge_chance": 0.04, "damage_mult": 0.08 },
	},
	{
		"id": "luck_coin",
		"name": "Fortune's Coin",
		"description": "+2 luck (improves upgrade rarity).",
		"cost": 180,
		"max_stack": 3,
		"effect": { "luck": 2.0 },
	},
]


## Get relic data by ID.
static func get_relic(relic_id: String) -> Dictionary:
	for relic: Dictionary in RELICS:
		if relic.get("id", "") == relic_id:
			return relic
	return {}


## Get all relic definitions (for shop display).
static func get_all_relics() -> Array[Dictionary]:
	return RELICS


## Apply all purchased relics from GameManager to the player's traits.
## Call this at the start of every level.
static func apply_relics() -> void:
	for relic_id: String in GameManager.player_relics.keys():
		var count: int = GameManager.player_relics[relic_id]
		if count <= 0:
			continue
		var relic := get_relic(relic_id)
		if relic.is_empty():
			continue
		var effect: Dictionary = relic.get("effect", {})
		for trait_name: String in effect.keys():
			var amount: float = float(effect[trait_name]) * count
			if GameManager.player_traits.has(trait_name):
				GameManager.player_traits[trait_name] += amount


## Check if a relic can be purchased (enough gold, below max stack).
static func can_purchase(relic_id: String) -> bool:
	var relic := get_relic(relic_id)
	if relic.is_empty():
		return false
	var cost: int = relic.get("cost", 999)
	if GameManager.player_gold < cost:
		return false
	var max_stack: int = relic.get("max_stack", 1)
	var current_count: int = GameManager.player_relics.get(relic_id, 0)
	return current_count < max_stack


## Get the rarity label for display
static func get_rarity(relic_id: String) -> String:
	var relic := get_relic(relic_id)
	var cost: int = relic.get("cost", 0)
	if cost >= 200:
		return "MYTHIC"
	elif cost >= 90:
		return "RARE"
	return "COMMON"
