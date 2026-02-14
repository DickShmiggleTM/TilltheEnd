extends CanvasLayer
## Level-up reward selection screen.
## Pauses the game and presents 3 randomized upgrade choices.
## Works while paused (PROCESS_MODE_ALWAYS).

# ── Node references ──────────────────────────────────────────────────────────
var overlay: ColorRect
var title_label: Label
var choices_container: VBoxContainer
var choice_panels: Array[PanelContainer] = []

# ── State ────────────────────────────────────────────────────────────────────
var _choices: Array = []
var _upgrade_generator: Node

# ── Color coding by type ────────────────────────────────────────────────────
const TYPE_COLORS: Dictionary = {
	"weapon": Color(1.0, 0.4, 0.1),         # Red-orange
	"weapon_upgrade": Color(1.0, 0.5, 0.2),  # Orange
	"ability": Color(0.2, 0.7, 1.0),         # Blue-cyan
	"ability_upgrade": Color(0.3, 0.8, 1.0),  # Lighter cyan
	"trait": Color(0.4, 1.0, 0.3),           # Green
}

const TYPE_LABELS: Dictionary = {
	"weapon": "NEW WEAPON",
	"weapon_upgrade": "WEAPON UPGRADE",
	"ability": "NEW ABILITY",
	"ability_upgrade": "ABILITY UPGRADE",
	"trait": "TRAIT",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	overlay = %Overlay
	title_label = %TitleLabel
	choices_container = %ChoicesContainer

	# Start hidden
	visible = false

	# Find or create upgrade generator
	_upgrade_generator = Node.new()
	_upgrade_generator.set_script(load("res://scripts/systems/upgrade_generator.gd"))
	add_child(_upgrade_generator)

	# Connect to level up event
	EventBus.player_level_up.connect(_on_player_level_up)


func _on_player_level_up(new_level: int) -> void:
	_show_choices(new_level)


func _show_choices(player_level: int) -> void:
	# Generate 3 choices
	_choices = _upgrade_generator.generate_level_up_choices(player_level)

	# Pause the game
	get_tree().paused = true

	# Clear old choice panels
	for child in choices_container.get_children():
		child.queue_free()
	choice_panels.clear()

	# Build choice panels
	for i in _choices.size():
		var choice: Dictionary = _choices[i]
		var panel := _create_choice_panel(choice, i)
		choices_container.add_child(panel)
		choice_panels.append(panel)

	visible = true


func _create_choice_panel(choice: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 180)

	# Panel styling
	var style := StyleBoxFlat.new()
	var choice_type: String = choice.get("type", "trait")
	var type_color: Color = TYPE_COLORS.get(choice_type, Color(0.5, 0.5, 0.5))
	style.bg_color = Color(0.08, 0.05, 0.12, 0.92)
	style.border_color = type_color
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)

	# Content layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Type label (WEAPON / ABILITY / TRAIT / UPGRADE)
	var type_label := Label.new()
	type_label.text = TYPE_LABELS.get(choice_type, "UPGRADE")
	type_label.add_theme_font_size_override("font_size", 20)
	type_label.add_theme_color_override("font_color", type_color * 0.8)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(type_label)

	# Name label
	var name_label := Label.new()
	name_label.text = choice.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", type_color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = choice.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 24)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(desc_label)

	# Current level for upgrades
	var current_level: int = choice.get("current_level", 0)
	if current_level > 0:
		var lvl_label := Label.new()
		lvl_label.text = "Current Level: %d" % current_level
		lvl_label.add_theme_font_size_override("font_size", 20)
		lvl_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		vbox.add_child(lvl_label)

	# Make the whole panel clickable via a button overlay
	var button := Button.new()
	button.flat = true
	button.anchors_preset = 15  # Full rect
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_on_choice_selected.bind(index))
	# Hover effect
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1.0, 0.4, 0.1, 0.15)
	hover_style.corner_radius_top_left = 12
	hover_style.corner_radius_top_right = 12
	hover_style.corner_radius_bottom_left = 12
	hover_style.corner_radius_bottom_right = 12
	button.add_theme_stylebox_override("hover", hover_style)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	button.add_theme_stylebox_override("normal", normal_style)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(1.0, 0.4, 0.1, 0.3)
	pressed_style.corner_radius_top_left = 12
	pressed_style.corner_radius_top_right = 12
	pressed_style.corner_radius_bottom_left = 12
	pressed_style.corner_radius_bottom_right = 12
	button.add_theme_stylebox_override("pressed", pressed_style)
	panel.add_child(button)

	return panel


func _on_choice_selected(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return

	var choice: Dictionary = _choices[index]

	# Emit the upgrade selected signal -- GameManager handles the rest
	EventBus.upgrade_selected.emit(choice)

	# Hide and unpause (GameManager also unpauses, but be safe)
	visible = false
