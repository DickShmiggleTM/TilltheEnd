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
│       ├── main_menu.tscn     # Entry point / title screen
│       ├── hud.tscn           # In-game heads-up display
│       ├── pause_menu.tscn
│       ├── level_intro_screen.tscn
│       ├── level_up_screen.tscn
│       ├── game_over_screen.tscn
│       └── touch_controls.tscn
└── scripts/
    ├── systems/               # Core game systems & autoloads
    │   ├── game_manager.gd    # Central state machine (autoload)
    │   ├── event_bus.gd       # Global signal dispatcher (autoload)
    │   ├── save_manager.gd    # Permadeath save system (autoload)
    │   ├── audio_manager.gd   # Audio system (autoload, placeholder)
    │   ├── game_scene.gd      # Main scene orchestrator
    │   ├── level_data.gd      # 7-level campaign definitions
    │   ├── wave_manager.gd    # Enemy wave spawning
    │   ├── upgrade_generator.gd # Loot/upgrade generation
    │   └── pickup.gd          # Collectible items (EXP, health, ammo)
    ├── player/
    │   └── player_controller.gd # FPS controller (movement, input, health, touch)
    ├── weapons/
    │   ├── weapon_manager.gd  # Weapon equipping, firing, hitscan/projectile
    │   └── projectile.gd      # Projectile physics & collision
    ├── abilities/
    │   ├── ability_base.gd    # Abstract base class for all abilities
    │   ├── ability_manager.gd # Ability lifecycle management
    │   ├── auto_turret.gd
    │   ├── bomb_ability.gd
    │   ├── chain_lightning.gd
    │   ├── fire_nova.gd
    │   ├── blood_scythe.gd
    │   ├── frost_aura.gd
    │   ├── shadow_clone.gd
    │   ├── venom_trail.gd
    │   ├── meteor_strike.gd
    │   └── death_skulls.gd
    ├── enemies/
    │   ├── enemy_base.gd      # Base enemy class (health, AI, drops)
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
        ├── main_menu.gd
        ├── hud.gd
        ├── pause_menu.gd
        ├── level_intro_screen.gd
        ├── level_up_screen.gd
        ├── game_over_screen.gd
        ├── touch_controls.gd
        └── damage_number.gd
```

## Architecture

### Autoloads (Global Singletons)

Four autoloads are registered in `project.godot` and are accessible everywhere:

| Autoload | Script | Purpose |
|----------|--------|---------|
| `GameManager` | `scripts/systems/game_manager.gd` | Central state machine, run progression, difficulty scaling |
| `EventBus` | `scripts/systems/event_bus.gd` | Global signal dispatcher for decoupled communication |
| `SaveManager` | `scripts/systems/save_manager.gd` | Permadeath save/load (binary file at `user://till_the_end_save.dat`) |
| `AudioManager` | `scripts/systems/audio_manager.gd` | Audio playback (currently procedural placeholders) |

### Game State Machine

`GameManager.state` drives the entire game flow:

```
MENU → PLAYING → PAUSED
                → LEVEL_UP (upgrade selection)
                → GAME_OVER / VICTORY
                → LEVEL_COMPLETE → TRANSITIONING → PLAYING (next level)
```

### Event Bus Pattern

All inter-system communication goes through `EventBus` signals. Systems never reference each other directly. Key signal categories:

- **Player events:** `player_damaged`, `player_healed`, `player_died`, `player_level_up`
- **Combat events:** `enemy_killed`, `enemy_damaged`, `boss_killed`, `damage_dealt`
- **Wave events:** `wave_started`, `wave_completed`, `all_waves_completed`, `boss_wave_started`
- **Pickup events:** `exp_collected`, `health_collected`, `ammo_collected`
- **Upgrade events:** `level_up_choices_ready`, `upgrade_selected`, `weapon_acquired`, `ability_acquired`
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
│   └── AbilityManager             [ability_manager.gd]
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

1. 7-level campaign with permadeath (death deletes save, restart from level 1)
2. Each level has 8-16 enemy waves followed by a boss wave
3. Killing enemies drops EXP, health, ammo
4. Level-ups offer 1-of-3 random upgrades (weapons, abilities, traits)
5. Save checkpoint after each boss defeat
6. Beat all 7 levels to win

### Difficulty Scaling

- **Per-wave:** 1.25x enemy count, 1.2x HP, 1.12x damage, 1.04x speed per wave
- **Per-level:** Multipliers range from 1.0x (Level 1) to 4.5x (Level 7)

### Content Inventory

- **10 weapons** (pistol, shotgun, SMG, rocket launcher, plasma rifle, railgun, minigun, flamethrower, crossbow, acid gun)
- **10 abilities** (auto turret, bomb, chain lightning, fire nova, blood scythe, frost aura, shadow clone, venom trail, meteor strike, death skulls)
- **13 traits** (max_health, defense, speed, fire_rate_mult, exp_mult, collect_range, damage_mult, crit_chance, crit_damage, dodge_chance, health_regen, armor, thorns, lifesteal)
- **5 enemy types** (melee, ranged, fast, tank, exploder)
- **7 unique bosses** (one per level)
- **7 procedural maps** (forest, industrial, tunnels, courtyard, temple floors 1-3)

## Coding Conventions

### Naming

- **Classes/Nodes:** `PascalCase` (e.g., `EnemyBase`, `AbilityManager`)
- **Variables/Properties:** `snake_case` (e.g., `current_health`, `wave_hp_mult`)
- **Constants:** `UPPER_SNAKE_CASE` (e.g., `MAX_WEAPONS`, `ACCELERATION`)
- **Private methods:** prefix `_` (e.g., `_on_player_died()`, `_spawn_wave()`)
- **Signals:** `snake_case` (e.g., `player_damaged`, `wave_completed`)
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
| **Factory** | `Pickup.create_exp_drop()`, `WeaponManager._create_projectile_node()`, `UpgradeGenerator` |
| **State Machine** | `GameManager.state` enum controls game phases |
| **Strategy** | Enemy subclasses, ability subclasses, per-level map generators |
| **Runtime Instantiation** | All visuals (CSG meshes), projectiles, and pickups built in code, no prefab scenes |

### Key Architectural Principles

- **All visuals are procedural.** CSG meshes and `AudioStreamGenerator` are used instead of asset files. No `.png`, `.wav`, `.glb`, or `.tres` files exist.
- **Loose coupling via EventBus.** Systems never hold direct references to each other. All communication goes through signals on the EventBus autoload.
- **Data-driven upgrades.** Weapons, abilities, and traits are defined as dictionaries in `UpgradeGenerator`. Level definitions live in `LevelData`.
- **Trait-based progression.** Player stats are modified through a trait dictionary on `GameManager`. Gameplay systems read traits at runtime (e.g., `GameManager.get_trait("damage_mult")`).
- **Mobile-first input.** Touch controls (virtual joystick, look drag, tap buttons) are primary. Keyboard/mouse input is also supported for desktop testing.

## Development Workflow

### Running the Project

Open the project in Godot 4.2 and run from the editor. The entry scene is `scenes/ui/main_menu.tscn`.

- **Desktop testing:** WASD + mouse look + left-click to shoot + mouse wheel to switch weapons
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
2. The weapon system handles firing, projectiles, and visuals generically based on weapon data properties (`damage`, `fire_rate`, `spread`, `projectile_speed`, `pellets`, `pierce`, etc.)

### Adding a New Ability

1. Create a new script extending `AbilityBase` in `scripts/abilities/`
2. Implement `_ready()`, `activate()`, `deactivate()`, and `upgrade()` methods
3. Register the ability in `ABILITY_DATABASE` in `scripts/systems/upgrade_generator.gd`
4. Add the script path to the ability data entry

### Adding a New Enemy Type

1. Create a new script extending `EnemyBase` in `scripts/enemies/`
2. Override `_ready()` to set stats and `_physics_process()` for custom AI
3. Add the enemy type to the appropriate level data entries in `scripts/systems/level_data.gd`

### Adding a New Level

1. Create a new map generator script extending `MapGenerator` in `scripts/map/`
2. Add a complete level data entry in `scripts/systems/level_data.gd` with: map script path, boss script path, wave count, difficulty multipliers, environment colors, lighting, enemy composition, and story text
3. Create a corresponding boss script extending `EnemyBoss` in `scripts/enemies/`
4. Update `GameManager` if the total level count changes

### Adding a New Trait

1. Add the trait with a default value to `GameManager.traits` dictionary
2. Reference it from gameplay code via `GameManager.get_trait("trait_name")`
3. Add upgrade entries in `UpgradeGenerator.TRAIT_UPGRADES`

## Important Notes for AI Assistants

- **No asset files exist.** All meshes are CSG, all audio is procedural. Do not assume or reference `.png`, `.wav`, `.obj`, `.glb`, or `.tres` resource files.
- **Godot 4.2 GDScript only.** Do not use Godot 3.x syntax (e.g., `onready` instead of `@onready`, `export` instead of `@export`).
- **EventBus is mandatory for cross-system communication.** Never add direct node references between systems. Emit and connect signals on `EventBus`.
- **GameManager owns all game state.** Player progression (level, traits, weapons, abilities), game phase, and difficulty data live on `GameManager`. Do not duplicate state elsewhere.
- **Runtime instantiation pattern.** New nodes (enemies, projectiles, pickups, visual effects) are created in code and added to `EntityContainer`. Do not create separate `.tscn` files for simple game objects.
- **Mobile-first UI.** All UI must work in portrait 1080x1920. Touch targets should be large enough for finger input. Test both touch and keyboard/mouse paths.
- **Permadeath is a core mechanic.** The save file is deleted on death. Do not add autosave during levels or undo-death features without explicit approval.
