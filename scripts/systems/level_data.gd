class_name LevelData
extends RefCounted
## Defines all 7 levels of the campaign: themes, environments, enemy compositions,
## boss references, difficulty scaling, and story text.
##
## The story: A resurrected warrior uses a ritual to return from death,
## vowing to end a powerful elitist cult empowered by an ancient, unnamed God.
## Each death erases progress — true roguelike permadeath.

# ── Level theme enum ──────────────────────────────────────────────────────
enum Theme {
	FOREST,          # Level 1 - wide forest, two-story house, ritual sites
	INDUSTRIAL,      # Level 2 - industrial area, buildings, puzzles
	TUNNELS,         # Level 3 - maze-like tunnel system
	COURTYARD,       # Level 4 - occult temple courtyard & estate
	TEMPLE_FLOOR_1,  # Level 5 - first floor of the massive temple
	TEMPLE_FLOOR_2,  # Level 6 - second floor
	TEMPLE_FLOOR_3,  # Level 7 - third and final floor
}

# ── Level definitions ────────────────────────────────────────────────────
# Each level is a dictionary with all the data needed to generate and run it.

static var LEVELS: Array[Dictionary] = [
	# ── LEVEL 1: THE CURSED FOREST ──────────────────────────────────────
	{
		"level_number": 1,
		"name": "The Cursed Forest",
		"theme": Theme.FOREST,
		"description": "A once-peaceful woodland, now corrupted by dark rituals.",
		"map_script": "res://scripts/map/level_1_forest.gd",
		"boss_script": "res://scripts/enemies/boss_forest_guardian.gd",
		"boss_name": "The Blighted Warden",
		"waves": 8,
		"difficulty_mult": 1.0,
		"enemy_hp_mult": 1.0,
		"enemy_dmg_mult": 1.0,
		"enemy_speed_mult": 1.0,
		"enemy_count_mult": 1.0,
		"exp_mult": 1.0,
		"wall_height": 4.0,
		"ambient_color": Color(0.15, 0.25, 0.1),
		"fog_color": Color(0.08, 0.12, 0.05),
		"fog_density": 0.008,
		"light_color": Color(0.4, 0.5, 0.3),
		"light_energy": 0.5,
		"intro_text": "You awaken in the cold dirt, gasping. The resurrection ritual burns in your veins. Around you, the forest writhes — corrupted by the cult's rituals. Their sentinels patrol the treeline. The nearest safehouse lies beyond the clearing, but something ancient guards the path.",
		"boss_intro": "The trees groan and uproot. A massive figure of twisted wood and bone rises — the Blighted Warden, once a forest spirit, now enslaved by the cult's corruption.",
		"enemy_types": ["melee", "fast"],
		"enemy_weights": { "melee": 0.65, "fast": 0.35 },
		"environment": {
			"floor_color": Color(0.15, 0.1, 0.05),
			"wall_color": Color(0.12, 0.18, 0.08),
			"ceiling_color": Color(0.05, 0.08, 0.03),
			"accent_color": Color(0.3, 0.5, 0.15),
		},
	},
	# ── LEVEL 2: THE DEAD WORKS ─────────────────────────────────────────
	{
		"level_number": 2,
		"name": "The Dead Works",
		"theme": Theme.INDUSTRIAL,
		"description": "An abandoned industrial complex repurposed as a cult stronghold.",
		"map_script": "res://scripts/map/level_2_industrial.gd",
		"boss_script": "res://scripts/enemies/boss_overseer.gd",
		"boss_name": "The Forge Overseer",
		"waves": 10,
		"difficulty_mult": 1.4,
		"enemy_hp_mult": 1.3,
		"enemy_dmg_mult": 1.2,
		"enemy_speed_mult": 1.05,
		"enemy_count_mult": 1.2,
		"exp_mult": 1.15,
		"wall_height": 5.0,
		"ambient_color": Color(0.2, 0.15, 0.1),
		"fog_color": Color(0.1, 0.06, 0.03),
		"fog_density": 0.015,
		"light_color": Color(0.8, 0.5, 0.2),
		"light_energy": 0.45,
		"intro_text": "The cult's industrial heart — a sprawling factory of steel and smoke. Here they forge weapons and armor blessed by their nameless God. The buildings hide secrets behind locked doors and coded mechanisms. The Overseer watches everything.",
		"boss_intro": "Steam erupts from the foundry floor. A hulking figure encased in riveted iron and burning coal emerges — the Forge Overseer, the cult's weapons master.",
		"enemy_types": ["melee", "ranged", "fast"],
		"enemy_weights": { "melee": 0.4, "ranged": 0.35, "fast": 0.25 },
		"environment": {
			"floor_color": Color(0.12, 0.1, 0.1),
			"wall_color": Color(0.15, 0.13, 0.12),
			"ceiling_color": Color(0.08, 0.07, 0.06),
			"accent_color": Color(0.7, 0.4, 0.1),
		},
	},
	# ── LEVEL 3: THE DEEP WARRENS ───────────────────────────────────────
	{
		"level_number": 3,
		"name": "The Deep Warrens",
		"theme": Theme.TUNNELS,
		"description": "A sprawling labyrinth of tunnels beneath the earth, carved by the cult's faithful.",
		"map_script": "res://scripts/map/level_3_tunnels.gd",
		"boss_script": "res://scripts/enemies/boss_tunnel_horror.gd",
		"boss_name": "The Broodmother",
		"waves": 10,
		"difficulty_mult": 1.8,
		"enemy_hp_mult": 1.6,
		"enemy_dmg_mult": 1.4,
		"enemy_speed_mult": 1.1,
		"enemy_count_mult": 1.4,
		"exp_mult": 1.3,
		"wall_height": 3.5,
		"ambient_color": Color(0.08, 0.05, 0.12),
		"fog_color": Color(0.04, 0.02, 0.06),
		"fog_density": 0.025,
		"light_color": Color(0.4, 0.2, 0.6),
		"light_energy": 0.3,
		"intro_text": "The stairway descends into endless darkness. The tunnels twist and branch — a labyrinth designed to trap intruders. The walls are scratched with claw marks. Something bred down here, in the dark, fed on the cult's sacrifices.",
		"boss_intro": "The tunnel opens into a vast cavern. Hanging from the ceiling, a massive arachnid-like horror drops — the Broodmother, spawning endless young from her bloated form.",
		"enemy_types": ["melee", "fast", "exploder"],
		"enemy_weights": { "melee": 0.3, "fast": 0.45, "exploder": 0.25 },
		"environment": {
			"floor_color": Color(0.08, 0.06, 0.1),
			"wall_color": Color(0.1, 0.07, 0.12),
			"ceiling_color": Color(0.03, 0.02, 0.05),
			"accent_color": Color(0.4, 0.15, 0.6),
		},
	},
	# ── LEVEL 4: THE OUTER SANCTUM ──────────────────────────────────────
	{
		"level_number": 4,
		"name": "The Outer Sanctum",
		"theme": Theme.COURTYARD,
		"description": "The temple courtyard — adorned with symbols of the nameless God.",
		"map_script": "res://scripts/map/level_4_courtyard.gd",
		"boss_script": "res://scripts/enemies/boss_high_priest.gd",
		"boss_name": "The High Priest",
		"waves": 12,
		"difficulty_mult": 2.2,
		"enemy_hp_mult": 1.9,
		"enemy_dmg_mult": 1.6,
		"enemy_speed_mult": 1.15,
		"enemy_count_mult": 1.5,
		"exp_mult": 1.45,
		"wall_height": 6.0,
		"ambient_color": Color(0.2, 0.05, 0.08),
		"fog_color": Color(0.1, 0.02, 0.04),
		"fog_density": 0.01,
		"light_color": Color(0.8, 0.2, 0.1),
		"light_energy": 0.5,
		"intro_text": "The temple gates loom above. The courtyard is vast — marble pillars carved with blasphemous scripture, altars stained with centuries of blood. The cult's elite guard patrol these grounds. Their High Priest awaits within, channeling the God's power.",
		"boss_intro": "At the altar's peak, a robed figure turns. His eyes burn with unholy light. The High Priest raises his staff — reality bends around him. He speaks the God's name, and the ground shakes.",
		"enemy_types": ["melee", "ranged", "tank", "fast", "exploder"],
		"enemy_weights": { "melee": 0.2, "ranged": 0.25, "tank": 0.2, "fast": 0.2, "exploder": 0.15 },
		"environment": {
			"floor_color": Color(0.15, 0.05, 0.05),
			"wall_color": Color(0.2, 0.08, 0.06),
			"ceiling_color": Color(0.06, 0.02, 0.02),
			"accent_color": Color(0.8, 0.15, 0.1),
		},
	},
	# ── LEVEL 5: TEMPLE FLOOR 1 - HALL OF ECHOES ────────────────────────
	{
		"level_number": 5,
		"name": "Hall of Echoes",
		"theme": Theme.TEMPLE_FLOOR_1,
		"description": "The first floor of the God's temple — vast halls echoing with whispered prayers.",
		"map_script": "res://scripts/map/level_5_temple_f1.gd",
		"boss_script": "res://scripts/enemies/boss_temple_sentinel.gd",
		"boss_name": "The Sentinel of Echoes",
		"waves": 12,
		"difficulty_mult": 2.8,
		"enemy_hp_mult": 2.2,
		"enemy_dmg_mult": 1.8,
		"enemy_speed_mult": 1.2,
		"enemy_count_mult": 1.6,
		"exp_mult": 1.6,
		"wall_height": 8.0,
		"ambient_color": Color(0.15, 0.05, 0.15),
		"fog_color": Color(0.06, 0.02, 0.06),
		"fog_density": 0.012,
		"light_color": Color(0.5, 0.15, 0.5),
		"light_energy": 0.4,
		"intro_text": "The temple's interior dwarfs all expectations. Pillars stretch to impossible heights. The walls pulse with a faint, rhythmic glow — like a heartbeat. Whispered prayers echo from nowhere and everywhere. The God's presence grows stronger.",
		"boss_intro": "A statue at the hall's end cracks and moves. Stone and shadow merge into a towering armored figure — the Sentinel of Echoes, the temple's immortal guardian, sustained by ten thousand prayers.",
		"enemy_types": ["melee", "ranged", "tank", "fast", "exploder"],
		"enemy_weights": { "melee": 0.2, "ranged": 0.2, "tank": 0.25, "fast": 0.2, "exploder": 0.15 },
		"environment": {
			"floor_color": Color(0.1, 0.04, 0.1),
			"wall_color": Color(0.14, 0.05, 0.14),
			"ceiling_color": Color(0.04, 0.01, 0.04),
			"accent_color": Color(0.5, 0.1, 0.5),
		},
	},
	# ── LEVEL 6: TEMPLE FLOOR 2 - THE CRIMSON NAVE ──────────────────────
	{
		"level_number": 6,
		"name": "The Crimson Nave",
		"theme": Theme.TEMPLE_FLOOR_2,
		"description": "The second floor — where the cult performs its most terrible rituals.",
		"map_script": "res://scripts/map/level_6_temple_f2.gd",
		"boss_script": "res://scripts/enemies/boss_dark_apostle.gd",
		"boss_name": "The Dark Apostle",
		"waves": 14,
		"difficulty_mult": 3.5,
		"enemy_hp_mult": 2.6,
		"enemy_dmg_mult": 2.0,
		"enemy_speed_mult": 1.25,
		"enemy_count_mult": 1.7,
		"exp_mult": 1.8,
		"wall_height": 8.0,
		"ambient_color": Color(0.25, 0.02, 0.02),
		"fog_color": Color(0.12, 0.01, 0.01),
		"fog_density": 0.015,
		"light_color": Color(0.9, 0.1, 0.05),
		"light_energy": 0.45,
		"intro_text": "Blood runs in channels carved into the floor. The second floor is a cathedral of agony — every surface inscribed with the God's demands. Ritual circles glow with active power. The cult's most fanatical apostle commands from the inner sanctum.",
		"boss_intro": "He floats above a circle of blood, wreathed in dark flame. The Dark Apostle — voice of the nameless God, conduit of power that warps flesh and bone. He smiles. He's been waiting.",
		"enemy_types": ["melee", "ranged", "tank", "fast", "exploder"],
		"enemy_weights": { "melee": 0.15, "ranged": 0.2, "tank": 0.25, "fast": 0.2, "exploder": 0.2 },
		"environment": {
			"floor_color": Color(0.18, 0.03, 0.03),
			"wall_color": Color(0.2, 0.04, 0.04),
			"ceiling_color": Color(0.05, 0.01, 0.01),
			"accent_color": Color(0.9, 0.1, 0.05),
		},
	},
	# ── LEVEL 7: TEMPLE FLOOR 3 - THE THRONE OF THE NAMELESS ────────────
	{
		"level_number": 7,
		"name": "Throne of the Nameless",
		"theme": Theme.TEMPLE_FLOOR_3,
		"description": "The final floor. The God's throne room. The end of everything.",
		"map_script": "res://scripts/map/level_7_temple_f3.gd",
		"boss_script": "res://scripts/enemies/boss_ancient_god.gd",
		"boss_name": "The Nameless One",
		"waves": 16,
		"difficulty_mult": 4.5,
		"enemy_hp_mult": 3.2,
		"enemy_dmg_mult": 2.4,
		"enemy_speed_mult": 1.3,
		"enemy_count_mult": 1.8,
		"exp_mult": 2.0,
		"wall_height": 12.0,
		"ambient_color": Color(0.1, 0.0, 0.05),
		"fog_color": Color(0.05, 0.0, 0.02),
		"fog_density": 0.018,
		"light_color": Color(0.6, 0.05, 0.3),
		"light_energy": 0.35,
		"intro_text": "The final stairway. Beyond this door, the God waits on its throne of bone and shadow. Every death you've suffered, every resurrection, has led to this moment. There is no retreat. No more coming back. This is the end — for you, or for the nameless evil that rules the world.",
		"boss_intro": "The throne room is vast beyond comprehension. At its center, reality tears open. Something immense unfolds from between dimensions — the Nameless One, ancient beyond time, powerful beyond measure. It turns its impossible gaze upon you. THE FINAL BATTLE BEGINS.",
		"enemy_types": ["melee", "ranged", "tank", "fast", "exploder"],
		"enemy_weights": { "melee": 0.15, "ranged": 0.15, "tank": 0.25, "fast": 0.2, "exploder": 0.25 },
		"environment": {
			"floor_color": Color(0.06, 0.0, 0.04),
			"wall_color": Color(0.08, 0.01, 0.06),
			"ceiling_color": Color(0.02, 0.0, 0.01),
			"accent_color": Color(0.5, 0.05, 0.3),
		},
	},
]

## Get level data by 1-indexed level number.
static func get_level(level_number: int) -> Dictionary:
	var idx := level_number - 1
	if idx >= 0 and idx < LEVELS.size():
		return LEVELS[idx]
	return {}

## Total number of levels.
static func get_total_levels() -> int:
	return LEVELS.size()
