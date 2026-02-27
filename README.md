# Godot Game Project

This is a Godot-based game project with a variety of assets, scenes, and scripts organized in a structured manner.

## Project Structure

```
├── GAME_REFERENCE.md          # Game reference documentation
├── export_presets.cfg         # Export configuration presets
├── icon.svg                  # Project icon
├── project.godot             # Main Godot project file
├── scenes/                   # Game scenes and visual assets
│   ├── *.tscn                # Scene files
│   ├── *.png                 # Image assets
│   ├── *.gif                 # Animated image assets
│   └── ui/                   # UI-related assets
└── scripts/                  # Game scripts organized by category
    ├── abilities/            # Ability-related scripts
    ├── enemies/              # Enemy-related scripts
    ├── map/                  # Map-related scripts
    ├── player/               # Player-related scripts
    ├── systems/              # System-related scripts
    ├── ui/                   # User interface scripts
    └── weapons/              # Weapon-related scripts
```

## Assets

The project includes a wide range of visual assets such as:
- Character sprites and animations
- Environmental objects (trees, decorations, etc.)
- UI elements
- Weapons and items
- Special effects

## Requirements

- Godot Engine (version compatible with the project.godot file)

## How to Run

1. Open the project in Godot Engine
2. Select the main scene (`scenes/game.tscn`) as the main scene in project settings
3. Run the project

## Export

Export presets are configured in `export_presets.cfg`. You can modify these presets in the Godot editor under Project -> Export.

## Development Notes

- The `GAME_REFERENCE.md` file likely contains important game design notes and references
- Scripts are well-organized by functionality for easier maintenance
- Assets are stored in the scenes folder along with scene files