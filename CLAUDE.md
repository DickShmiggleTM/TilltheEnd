# CLAUDE.md — Till The End

Comprehensive guide for AI assistants working on this codebase.

---

## Project Overview

**Till The End** is a mobile-first 2.5D roguelike FPS built in **Godot 4.2**. It is DOOM-inspired with procedural dungeon generation, permadeath, and a 7-level campaign. The game targets Android (ARM64) at 1080×1920 portrait resolution.

- **Engine:** Godot 4.2 (mobile rendering backend)
- **Language:** GDScript exclusively
- **Platform:** Android (ARM64-v8a), package `com.tilltheend.game`, version 0.1.0
- **No external package managers** — pure Godot project

---

## Repository Layout

```
TilltheEnd/
├── project.godot          # Engine config: input maps, autoloads, physics layers, rendering
├── export_presets.cfg     # Android APK export settings
├── icon.svg               # App icon
├── .gitignore             # Godot-standard ignores
├── scenes/
│   ├── ui/                # Scene files (.tscn) for each screen
│   │   ├── game.tscn
│   │   ├── main_menu.tscn
│   │   ├── hud.tscn
│   │   ├── game_over_screen.tscn
│   │   ├── level_up_screen.tscn
│   │   ├── level_intro_screen.tscn
│   │   ├── pause_menu.tscn
│   │   └── touch_controls.tscn
│   └── *.png / *.gif      # Sprite sheets and character art (60+)
└── scripts/
    ├── systems/           # Core singleton/manager systems
    ├── player/            # Player controller
    ├── enemies/           # Enemy and boss implementations
    ├── abilities/         # 39 ability implementations + base class
    ├── weapons/           # Weapon manager and projectile logic
    ├── map/               # BSP dungeon generator + 7 level-specific generators
    └── ui/                # UI scene controllers
```

---

## Architecture

### Autoloaded Singletons

Defined in `project.godot` — these persist across all scenes:

| Singleton | File | Role |
|-----------|------|------|
| `EventBus` | `scripts/systems/event_bus.gd` | Global signal dispatcher (40+ signals). All inter-system communication goes through here — **do not create direct script-to-script references between systems** |
| `GameManager` | `scripts/systems/game_manager.gd` | Campaign state, player stats, leveling, level progression, run management |
| `SaveManager` | `scripts/systems/save_manager.gd` | Permadeath save/load. Saves to `user://till_the_end_save.dat` (binary). Deletes file on death |
| `AudioManager` | `scripts/systems/audio_manager.gd` | 16 SFX channels, procedurally-generated placeholder sounds |

### Key Non-Singleton Systems

| File | Role |
|------|------|
| `scripts/systems/game_scene.gd` | Main orchestrator: instantiates all gameplay subsystems, manages level transitions, UI layers |
| `scripts/systems/wave_manager.gd` | Enemy wave spawning, BSP-determined spawn points, difficulty scaling |
| `scripts/systems/level_data.gd` | Static definitions for all 7 levels (themes, enemies, boss scripts, multipliers, story text) |
| `scripts/systems/upgrade_generator.gd` | Rarity-based loot: weapon DB, ability DB, trait definitions, luck scaling |
| `scripts/systems/pickup.gd` | Collectibles (EXP, health, ammo, gold): magnetic attraction, bobbing, auto-despawn |

### Design Patterns

- **EventBus pattern:** All cross-system communication uses `EventBus.emit_signal(...)` and `EventBus.connect(...)`. Never couple managers directly.
- **Manager pattern:** Singletons own their domain; other code queries them, never owns them.
- **Inheritance with virtual methods:** `ability_base.gd` and `enemy_base.gd` define virtual methods (`_on_upgrade`, `_process`) overridden by subtypes.
- **Dynamic composition:** Systems are instantiated in `game_scene.gd` at runtime, not placed in the editor scene tree.
- **State machine:** `GameState` enum in `GameManager` controls game flow.

---

## Physics Layers

Defined in `project.godot`:

| Layer | Name |
|-------|------|
| 1 | Environment (walls, floors) |
| 2 | Player |
| 3 | Enemies |
| 4 | Projectiles (unused currently) |
| 5 | Pickups |
| 6 | PlayerProjectiles |

When adding collision, always use the named layers — never hardcode layer numbers in scripts.

---

## Game Systems Reference

### Campaign Structure

- **7 levels:** forest → industrial → tunnels → temple (3 floors)
- **8 waves per level;** wave 8 is always the boss fight
- **Difficulty per wave:** HP ×1.2, damage ×1.12, enemy count ×1.25, speed ×1.04
- **Permadeath:** death deletes save, forces restart from Level 1

### Player Progression

- EXP-based leveling: base 100 XP, ×1.35 growth per level
- On level-up: choose 1 of 3 random upgrades (weapon / ability / trait)
- **6 weapon slots**, **6 ability slots**
- Resources: Health, Ammunition (5 types), Experience, Gold

### Rarity System (7 tiers)

Managed by `upgrade_generator.gd`. Base rates: Common 50%, Rare 20%, Mythic 10%, etc. Luck stat shifts probability toward higher tiers (+5% per luck level).

### Map Generation

`scripts/map/map_generator.gd` — BSP dungeon, 60×60 grid, procedural rooms and corridors. Each level has a dedicated generator (`level_1_forest.gd` through `level_7_temple_f3.gd`) with custom theming.

### Save Format

Single binary file `user://till_the_end_save.dat` written with Godot's `FileAccess.store_var`. Contents: campaign level, player XP, weapons array, abilities array, traits dict, kill count, playtime. **Do not change the field order** without migrating existing saves.

---

## Code Conventions

### Naming

| Construct | Convention | Example |
|-----------|-----------|---------|
| Variables / functions | `snake_case` | `current_health`, `apply_damage()` |
| Classes | `PascalCase` via `class_name` | `class_name EnemyBase` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_WAVE_COUNT = 8` |
| Signals | `snake_case` past-tense verb | `player_died`, `wave_completed` |
| Files | `snake_case.gd` / `snake_case.tscn` | `game_manager.gd` |

### Comments

```gdscript
## This is a docstring comment (double hash)
# ──────────────── Section separator ────────────────
# Inline explanation
```

### Type Hints

Always use explicit type annotations:

```gdscript
var health: float = 100.0
func take_damage(amount: float) -> void:
    health -= amount
```

### Resource Loading

Use `preload()` for static assets known at compile time; use `load()` only for dynamic/runtime paths:

```gdscript
const SCENE = preload("res://scenes/ui/game.tscn")
```

### EventBus Usage

```gdscript
# Emitting
EventBus.emit_signal("player_died", final_stats)

# Connecting (prefer lambdas for local handlers)
EventBus.connect("enemy_killed", _on_enemy_killed)
```

### Adding a New Ability

1. Create `scripts/abilities/my_ability.gd` extending `AbilityBase`
2. Override `_on_upgrade()` and `_process()` virtual methods
3. Register it in `upgrade_generator.gd` ability database with rarity and metadata
4. Follow the file naming pattern: `my_ability.gd` → class `class_name MyAbility`

### Adding a New Enemy

1. Create `scripts/enemies/enemy_mytype.gd` extending `EnemyBase`
2. Implement movement, attack, and death behaviors
3. Register the enemy type in `level_data.gd` for the appropriate level(s)
4. Add spawn weight to `wave_manager.gd`

---

## Building and Exporting

There is **no build script**. Export is done manually through the Godot editor:

1. Open project in Godot 4.2
2. **Project → Export → Android**
3. Requires Android SDK (Target SDK 34) and a keystore configured in the export preset
4. Output: APK for sideloading or Google Play

**No CI/CD pipeline exists.** All testing is manual in the Godot editor or on an Android device.

---

## Development Workflow

### Branch Strategy

- Default branch: `master`
- Feature branches follow the pattern: `claude/<description>-<id>`

### Typical Workflow

```bash
git checkout -b claude/my-feature-XxXxX
# make changes
git add scripts/systems/my_file.gd
git commit -m "feat: describe the change"
git push -u origin claude/my-feature-XxXxX
```

### Commit Message Convention

Prefix commits with a type:

| Prefix | When to use |
|--------|-------------|
| `feat:` | New feature or mechanic |
| `fix:` | Bug fix |
| `refactor:` | Code restructure without behavior change |
| `docs:` | Documentation only |
| `chore:` | Build config, tooling, assets |

---

## What to Avoid

- **Do not** add direct references between manager singletons. Use `EventBus`.
- **Do not** hardcode physics layer numbers — use the named layer constants.
- **Do not** place game systems as nodes in editor scenes; they are instantiated dynamically in `game_scene.gd`.
- **Do not** change the binary save format field order without writing a migration in `save_manager.gd`.
- **Do not** use `load()` where `preload()` works — it improves editor error catching.
- **Do not** add Android permissions to `export_presets.cfg` without a concrete requirement. Currently only `VIBRATE` is needed.
- **Do not** add a test framework, CI/CD pipeline, or package manager unless the project owner explicitly requests it — this is a deliberate manual workflow.

---

## File Count Summary

| Category | Count |
|----------|-------|
| GDScript files | 81 |
| Ability scripts | 39 |
| Enemy scripts | 12 (5 types + 7 bosses) |
| Map generators | 7 |
| UI scripts | 8 |
| Scene files (.tscn) | 8 |
| Sprite assets | 60+ |
| Total LOC (approx.) | 24,500 |
