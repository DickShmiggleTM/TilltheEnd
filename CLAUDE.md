# CLAUDE.md - AI Assistant Guide for Till The End

## Project Overview

**Till The End** is a roguelike 2.5D FPS mobile game built in **Godot 4.2 (Mobile renderer)** using **GDScript 2.0**. It targets Android in portrait orientation (1080x1920). The game features a 7-level campaign with permadeath, DOOM-inspired combat, and procedurally generated visuals (no external art/audio assets).

## Quick Reference

- **Engine:** Godot 4.2 (Mobile)
- **Language:** GDScript 2.0
- **Target:** Android (arm64-v8a), APK format
- **Package:** `com.tilltheend.game`
- **Entry Scene:** `res://scenes/ui/main_menu.tscn`
- **Orientation:** Portrait (1080x1920)
- **No external dependencies or plugins** -- pure Godot

## Repository Structure

```
TilltheEnd/
├── project.godot              # Project config (autoloads, input, physics layers, display)
├── export_presets.cfg         # Android export settings
├── icon.svg                   # App icon
├── .gitignore
├── .gdignore
├── scenes/
│   ├── game.tscn              # Main gameplay scene (root of in-game hierarchy)
│   └── ui/
│       ├── main_menu.tscn     # Entry point / title screen (with Shop access)
│       ├── hud.tscn           # In-game heads-up display (health, ammo, coins, skills)
│       ├── pause_menu.tscn
│       ├── level_intro_screen.tscn
│       ├── level_up_screen.tscn  # 3-4 upgrade choices (skills have 1/20 4th option)
│       ├── game_over_screen.tscn
│       └── touch_controls.tscn   # Joystick, skill, kick, jump, sprint buttons
└── scripts/
    ├── systems/               # Core game systems & autoloads
    │   ├── game_manager.gd    # Central state machine, run/coin/relic/voucher/ammo (autoload)
    │   ├── event_bus.gd       # Global signal dispatcher (autoload)
    │   ├── save_manager.gd    # Permadeath save + meta persistence (autoload)
    │   ├── audio_manager.gd   # Audio system (autoload, placeholder)
    │   ├── game_scene.gd      # Main scene orchestrator
    │   ├── level_data.gd      # 7-level campaign definitions
    │   ├── wave_manager.gd    # Enemy wave spawning
    │   ├── upgrade_generator.gd # Loot/upgrade/relic/skill generation
    │   └── pickup.gd          # Collectible items (EXP, health, ammo, coins)
    ├── player/
    │   └── player_controller.gd # FPS controller (movement, jump, sprint, kick, recoil)
    ├── weapons/
    │   ├── weapon_manager.gd  # Weapon equipping, firing, ammo, sway, recoil
    │   └── projectile.gd      # Projectile physics & collision
    ├── abilities/             # Three-tier system: Abilities, Skills, Traits
    │   ├── ability_base.gd    # Base class for passive/auto-activating abilities
    │   ├── ability_manager.gd # Passive ability lifecycle management
    │   ├── skill_base.gd      # Base class for button-activated skills with cooldowns
    │   ├── skill_manager.gd   # Manages 3 active skill slots
    │   ├── auto_turret.gd     # [Ability] Auto-targeting turret
    │   ├── chain_lightning.gd # [Ability] Lightning chains between enemies
    │   ├── fire_nova.gd       # [Ability] Periodic fire eruption
    │   ├── blood_scythe.gd    # [Ability] Spectral scythes with lifesteal
    │   ├── frost_aura.gd      # [Ability] Slows nearby enemies
    │   ├── venom_trail.gd     # [Ability] Poison trail behind player
    │   ├── death_skulls.gd    # [Ability] Orbiting damage skulls
    │   ├── lifesteal_aura.gd  # [Ability] Passive heal on damage dealt
    │   ├── thorns_aura.gd     # [Ability] Passive damage reflect
    │   ├── bomb_ability.gd    # [Skill] Throwable grenade with cooldown
    │   ├── shadow_clone.gd    # [Skill] Decoy that explodes on death
    │   └── meteor_strike.gd   # [Skill] Meteor drop on enemy clusters
    ├── enemies/
    │   ├── enemy_base.gd      # Base enemy class (health, AI, drops, coin drops)
    │   ├── enemy_boss.gd      # Boss base class (multi-phase)
    │   ├── enemy_melee.gd
    │   ├── enemy_ranged.gd
    │   ├── enemy_fast.gd
    │   ├── enemy_tank.gd
    │   ├── enemy_exploder.gd
    │   ├── boss_forest_guardian.gd   # Level 1 boss
    │   ├── boss_overseer.gd         # Level 2 boss
    │   ├── boss_tunnel_horror.gd    # Level 3 boss
    │   ├── boss_high_priest.gd      # Level 4 boss
    │   ├── boss_temple_sentinel.gd  # Level 5 boss
    │   ├── boss_dark_apostle.gd     # Level 6 boss
    │   └── boss_ancient_god.gd      # Level 7 boss
    ├── map/
    │   ├── map_generator.gd         # Base map generation
    │   ├── level_1_forest.gd
    │   ├── level_2_industrial.gd
    │   ├── level_3_tunnels.gd
    │   ├── level_4_courtyard.gd
    │   ├── level_5_temple_f1.gd
    │   ├── level_6_temple_f2.gd
    │   └── level_7_temple_f3.gd
    └── ui/
        ├── main_menu.gd          # Title screen with Shop button
        ├── hud.gd                # Health, EXP, ammo, coins, skill cooldowns
        ├── pause_menu.gd
        ├── level_intro_screen.gd
        ├── level_up_screen.gd    # 3-4 choice selection (skills color-coded)
        ├── game_over_screen.gd
        ├── touch_controls.gd     # Joystick, skill, kick, jump, sprint, weapon switch
        ├── shop_screen.gd        # Relic purchase & voucher redemption
        └── damage_number.gd
```

## Architecture

### Autoloads (Global Singletons)

Four autoloads are registered in `project.godot` and are accessible everywhere:

| Autoload | Script | Purpose |
|----------|--------|---------|
| `GameManager` | `scripts/systems/game_manager.gd` | Central state machine, run progression, ammo, coins, relics, vouchers, difficulty scaling |
| `EventBus` | `scripts/systems/event_bus.gd` | Global signal dispatcher for decoupled communication |
| `SaveManager` | `scripts/systems/save_manager.gd` | Permadeath run save + persistent meta save (coins/relics/vouchers) |
| `AudioManager` | `scripts/systems/audio_manager.gd` | Audio playback (currently procedural placeholders) |

### Game State Machine

`GameManager.state` drives the entire game flow:

```
MENU → PLAYING → PAUSED
                → LEVEL_UP (upgrade selection, 3-4 choices)
                → GAME_OVER / VICTORY
                → LEVEL_COMPLETE → TRANSITIONING → PLAYING (next level)
```

### Three-Tier Player Progression System

| Tier | Description | Player Input | Manager | Persistence |
|------|-------------|-------------|---------|-------------|
| **Traits** | Permanent starting stats (max_health, speed, crit_chance, etc.) | None -- always active | `GameManager.player_traits` | Reset on death |
| **Abilities** | Passive/auto-activating effects (fire nova, frost aura, lifesteal, thorns, etc.) | None -- fire automatically | `AbilityManager` | Reset on death |
| **Skills** | Button-activated specials with cooldowns (bomb, shadow clone, meteor strike) | Button press required | `SkillManager` (3 slots max) | Reset on death |

**Key distinction:** Traits are raw stat numbers. Abilities are passive scripts that trigger themselves. Skills require player input and have cooldown timers.

### Ammo System

Each weapon has an `ammo_type` field (bullet, shell, rocket, cell, fuel, bolt, acid). Ammo is:
- Tracked in `GameManager.weapon_ammo` dictionary
- Consumed on each shot via `GameManager.consume_ammo()`
- Gained from enemy drops (`Pickup.create_ammo_drop()`)
- Reset to defaults at run start

### Coin Economy (Persists Across Deaths)

- Enemies drop coins (25% chance, 1-3 coins)
- Coins persist across deaths (stored in meta save)
- Used to buy relics in the Shop

### Relic System (Persists Across Deaths)

- **Relics** are purchasable perks from the Shop (accessible from main menu)
- Up to **5 equipped relic slots** (modifiable by vouchers)
- Each relic provides permanent stat bonuses applied at run start
- 8 relics available: Blood Chalice, Iron Boots, Swift Cloak, Marksman's Eye, Soul Magnet, War Drum, Ghost Ring, Phoenix Feather

### Voucher System (Persists Across Deaths)

- **Vouchers** are earned through special tasks and discovering secrets
- Max **20 vouchers** of any kind
- Redeemable at the Shop for one-time effects on the next run
- Discarded after use

### Event Bus Pattern

All inter-system communication goes through `EventBus` signals. Key signal categories:

- **Player events:** `player_damaged`, `player_healed`, `player_died`, `player_level_up`, `player_kicked`
- **Combat events:** `enemy_killed`, `enemy_damaged`, `boss_killed`, `damage_dealt`
- **Wave events:** `wave_started`, `wave_completed`, `all_waves_completed`, `boss_wave_started`
- **Pickup events:** `exp_collected`, `health_collected`, `ammo_collected`, `coin_collected`
- **Upgrade events:** `upgrade_selected`, `weapon_acquired`, `ability_acquired`, `skill_acquired`, `trait_upgraded`, `weapon_upgraded`, `ability_upgraded`, `skill_upgraded`
- **Skill events:** `skill_activated`, `skill_cooldown_started`, `skill_cooldown_finished`
- **Shop events:** `relic_equipped`, `relic_unequipped`, `voucher_redeemed`, `coins_changed`, `shop_opened`, `shop_closed`
- **Game state events:** `game_started`, `game_over`, `game_won`, `level_started`, `level_complete`

### Scene Hierarchy (In-Game)

```
Game (Node3D)                      [game_scene.gd]
├── MapGenerator                   [dynamically loads level-specific script]
├── Player (CharacterBody3D)       [player_controller.gd]
│   ├── CollisionShape3D
│   ├── Camera3D (FOV 90)
│   ├── RayCast3D (aim, 100m)
│   ├── Marker3D (fire point)
│   ├── WeaponManager              [weapon_manager.gd]
│   ├── AbilityManager             [ability_manager.gd]
│   └── SkillManager               [skill_manager.gd]
├── EntityContainer                [spawned enemies/pickups go here]
├── WaveManager                    [wave_manager.gd]
├── UpgradeGenerator               [upgrade_generator.gd]
└── UI Layers
    ├── HUD
    ├── TouchControls
    ├── LevelUpScreen
    ├── GameOverScreen
    ├── PauseMenu
    └── LevelIntroScreen
```

### Physics Layers

| Layer | Name |
|-------|------|
| 1 | Environment |
| 2 | Player |
| 3 | Enemies |
| 4 | Projectiles |
| 5 | Pickups |
| 6 | PlayerProjectiles |

## Game Design Summary

### Core Loop

1. 7-level campaign with permadeath (death deletes run save, restart from level 1)
2. Each level has 8-16 enemy waves followed by a boss wave
3. Killing enemies drops EXP, health, ammo, and coins
4. Level-ups offer 1-of-3 random upgrades (weapons, abilities, skills, traits) with 1/20 chance of a 4th skill upgrade option
5. Save checkpoint after each boss defeat
6. Beat all 7 levels to win
7. Coins/relics/vouchers persist across deaths for meta-progression

### Player Mechanics

- **Movement:** WASD + virtual joystick, acceleration-based with friction
- **Look/Aim:** Mouse or touch drag on right half of screen
- **Firing:** Auto-fire when touching right side (mobile) or LMB (desktop)
- **Jumping:** Space bar or touch jump button
- **Sprinting:** Shift toggle or touch sprint button (1.6x speed)
- **Kick:** F key or touch kick button (knockback + small damage to nearby enemies)
- **Weapon Switch:** Arrow buttons or mouse wheel
- **Skill Use:** Q key or touch skill button (activates current skill slot)
- **Camera bob/sway:** Position-based bob + rotational sway while moving
- **Weapon sway:** Weapon model follows look input with smooth return
- **Recoil:** Camera kick on fire, recovers smoothly

### Difficulty Scaling

- **Per-wave:** 1.25x enemy count, 1.2x HP, 1.12x damage, 1.04x speed per wave
- **Per-level:** Multipliers range from 1.0x (Level 1) to 4.5x (Level 7)

### Content Inventory

- **10 weapons** (pistol, shotgun, SMG, rocket launcher, plasma rifle, railgun, minigun, flamethrower, crossbow, acid gun)
- **9 passive abilities** (auto turret, chain lightning, fire nova, blood scythe, frost aura, venom trail, death skulls, lifesteal aura, thorns aura)
- **3 active skills** (frag grenade, shadow clone, meteor strike)
- **12 traits** (max_health, defense, speed, fire_rate_mult, exp_mult, collect_range, damage_mult, crit_chance, crit_damage, dodge_chance, health_regen, armor)
- **8 relics** (blood chalice, iron boots, swift cloak, marksman's eye, soul magnet, war drum, ghost ring, phoenix feather)
- **5 enemy types** (melee, ranged, fast, tank, exploder)
- **7 unique bosses** (one per level)
- **7 procedural maps** (forest, industrial, tunnels, courtyard, temple floors 1-3)

### Save System

Two separate save files:
- **Run save** (`user://till_the_end_save.dat`): Current run state (level, weapons, abilities, skills, traits, ammo). **Deleted on death.**
- **Meta save** (`user://till_the_end_meta.dat`): Coins, owned relics, equipped relics, vouchers. **Persists across deaths.**

## Coding Conventions

### Naming

- **Classes/Nodes:** `PascalCase` (e.g., `EnemyBase`, `AbilityManager`, `SkillBase`)
- **Variables/Properties:** `snake_case` (e.g., `current_health`, `wave_hp_mult`)
- **Constants:** `UPPER_SNAKE_CASE` (e.g., `MAX_WEAPONS`, `KICK_COOLDOWN`)
- **Private methods:** prefix `_` (e.g., `_on_player_died()`, `_spawn_wave()`)
- **Signals:** `snake_case` (e.g., `player_damaged`, `skill_cooldown_finished`)
- **Enums:** `PascalCase` values (e.g., `GameState.PLAYING`)

### Code Structure

Scripts follow this section order:

```gdscript
extends BaseClass

# ═══════════════════════════════════════
# Section dividers use box-drawing chars
# ═══════════════════════════════════════

# Constants
const MAX_VALUE := 100

# Enums
enum State { IDLE, ACTIVE }

# Exported properties
@export var speed: float = 5.0

# Member variables
var current_state: State = State.IDLE

# Lifecycle methods
func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

func _physics_process(delta: float) -> void:
    pass

# Public API methods
func take_damage(amount: float) -> void:
    pass

# Private helper methods
func _apply_knockback(direction: Vector3) -> void:
    pass

# Signal callbacks
func _on_event_name() -> void:
    pass
```

### Design Patterns in Use

| Pattern | Where Used |
|---------|------------|
| **Autoload Singletons** | GameManager, EventBus, SaveManager, AudioManager |
| **Observer (Event Bus)** | All inter-system communication via EventBus signals |
| **Factory** | `Pickup.create_exp_drop()`, `Pickup.create_coin_drop()`, `WeaponManager._create_projectile_node()` |
| **State Machine** | `GameManager.state` enum controls game phases |
| **Strategy** | Enemy subclasses, ability subclasses, skill subclasses, per-level map generators |
| **Three-tier system** | Traits (stats) → Abilities (passive) → Skills (active with cooldowns) |
| **Runtime Instantiation** | All visuals (CSG meshes), projectiles, and pickups built in code, no prefab scenes |
| **Dual persistence** | Run save (deleted on death) + Meta save (coins/relics/vouchers persist) |

### Key Architectural Principles

- **All visuals are procedural.** CSG meshes and `AudioStreamGenerator` are used instead of asset files. No `.png`, `.wav`, `.glb`, or `.tres` files exist.
- **Loose coupling via EventBus.** Systems never hold direct references to each other. All communication goes through signals on the EventBus autoload.
- **Data-driven upgrades.** Weapons, abilities, skills, traits, and relics are defined as dictionaries in `UpgradeGenerator`. Level definitions live in `LevelData`.
- **Three-tier player progression.** Traits = raw stats (always active). Abilities = passive auto-effects (no input). Skills = button-activated with cooldowns (3 slots).
- **Dual persistence.** Run progress resets on death. Meta-progression (coins, relics, vouchers) persists forever.
- **Mobile-first input.** Touch controls (virtual joystick, look drag, tap buttons for kick/jump/sprint/skill) are primary. Keyboard/mouse input is also supported for desktop testing.
- **Ammo economy.** Each weapon type consumes ammo from a shared pool. Ammo drops from enemies. Runs start with default ammo amounts.

## Development Workflow

### Running the Project

Open the project in Godot 4.2 and run from the editor. The entry scene is `scenes/ui/main_menu.tscn`.

- **Desktop testing:** WASD + mouse look + left-click to shoot + mouse wheel to switch weapons + Space to jump + Shift to sprint + F to kick + Q to use skill
- **Mobile testing:** Build APK via Export > Android preset, deploy to device

### Input Map

Defined in `project.godot`:

| Action | Key | Purpose |
|--------|-----|---------|
| `move_forward` | W | Move forward |
| `move_backward` | S | Move backward |
| `move_left` | A | Strafe left |
| `move_right` | D | Strafe right |
| `shoot` | Left Mouse Button | Fire weapon |
| `jump` | Space | Jump |
| `kick` | F | Kick (knockback) |
| `sprint` | Left Shift | Toggle sprint |
| `use_skill` | Q | Activate current skill |

Touch controls are handled programmatically in `touch_controls.gd` and `player_controller.gd`.

### Export Configuration

- **Platform:** Android
- **Architecture:** arm64-v8a only
- **Format:** APK
- **Package name:** `com.tilltheend.game`
- **Version:** 0.1.0
- **Permissions:** Vibrate only
- **Immersive mode:** Enabled
- **Note:** Keystore not yet configured for signed release builds

### Testing

No automated test framework is currently configured. Testing is manual via the Godot editor (desktop) or APK deployment (Android).

## Common Modification Tasks

### Adding a New Weapon

1. Add weapon data dictionary to `WEAPON_DATABASE` in `scripts/systems/upgrade_generator.gd`
2. Include `ammo_type` field matching a key in `GameManager.DEFAULT_AMMO`
3. The weapon system handles firing, projectiles, ammo consumption, and visuals generically based on weapon data properties

### Adding a New Ability (Passive/Auto)

1. Create a new script extending `AbilityBase` in `scripts/abilities/`
2. Implement `activate()`, `deactivate()`, and `_on_upgrade()` methods
3. Register the script path in `AbilityManager.ABILITY_SCRIPTS`
4. Add the ability data to `ABILITY_DATABASE` in `upgrade_generator.gd`

### Adding a New Skill (Button-Activated)

1. Create a new script extending `SkillBase` in `scripts/abilities/`
2. Implement `on_activate()`, `_execute()`, `deactivate()`, and `_on_upgrade()` methods
3. Register the script path in `SkillManager.SKILL_SCRIPTS`
4. Add the skill data to `SKILL_DATABASE` in `upgrade_generator.gd`

### Adding a New Relic

1. Add relic data to `RELIC_DATABASE` in `upgrade_generator.gd`
2. Include `cost`, `bonuses` (trait name -> value mapping), and `color`
3. The shop UI and relic system handle everything else automatically

### Adding a New Enemy Type

1. Create a new script extending `EnemyBase` in `scripts/enemies/`
2. Override `_ready()` to set stats and `_physics_process()` for custom AI
3. Add the enemy type to the appropriate level data entries in `scripts/systems/level_data.gd`

### Adding a New Level

1. Create a new map generator script extending `MapGenerator` in `scripts/map/`
2. Add a complete level data entry in `scripts/systems/level_data.gd`
3. Create a corresponding boss script extending `EnemyBoss` in `scripts/enemies/`
4. Update `GameManager.TOTAL_LEVELS` if the total level count changes

## Important Notes for AI Assistants

- **No asset files exist.** All meshes are CSG, all audio is procedural. Do not assume or reference `.png`, `.wav`, `.obj`, `.glb`, or `.tres` resource files.
- **Godot 4.2 GDScript only.** Do not use Godot 3.x syntax (e.g., `onready` instead of `@onready`, `export` instead of `@export`).
- **EventBus is mandatory for cross-system communication.** Never add direct node references between systems. Emit and connect signals on `EventBus`.
- **GameManager owns all game state.** Player progression (level, traits, weapons, abilities, skills), ammo, coins, relics, vouchers, and game phase all live on `GameManager`. Do not duplicate state elsewhere.
- **Three-tier system: Traits → Abilities → Skills.** Traits are stat numbers (no code). Abilities are passive (auto-fire, no input). Skills require button press and have cooldowns. Do not mix these tiers.
- **Dual persistence model.** Run state resets on death. Meta state (coins, relics, vouchers) persists forever. Understand which data belongs to which save file.
- **Runtime instantiation pattern.** New nodes (enemies, projectiles, pickups, visual effects) are created in code and added to `EntityContainer`. Do not create separate `.tscn` files for simple game objects.
- **Mobile-first UI.** All UI must work in portrait 1080x1920. Touch targets should be large enough for finger input. Test both touch and keyboard/mouse paths.
- **Permadeath is a core mechanic.** The run save file is deleted on death. Do not add autosave during levels or undo-death features without explicit approval.
- **Ammo matters.** Weapons consume ammo from `GameManager.weapon_ammo`. Players get ammo from enemy drops. Don't bypass the ammo system.
