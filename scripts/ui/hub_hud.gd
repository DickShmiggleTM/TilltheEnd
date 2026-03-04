extends CanvasLayer
## HUD overlay for the hub world.
## Displays gold, interaction prompts, door status, and a basic relic shop UI.

var _gold_label: Label = null
var _prompt_label: Label = null
var _message_label: Label = null
var _door_status_label: Label = null
var _message_timer: float = 0.0
var _shop_panel: Control = null
var _shop_open: bool = false


func _ready() -> void:
	_build_hud()
	_connect_signals()
	_update_gold(GameManager.player_gold)
	_update_door_status()


func _process(delta: float) -> void:
	# Auto-hide flash messages
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			if _message_label:
				_message_label.visible = false

	# ESC closes shop
	if _shop_open and Input.is_action_just_pressed("ui_cancel"):
		_close_shop()


# ---------------------------------------------------------------------------
# HUD construction
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	# Gold display (top-left)
	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.add_theme_font_size_override("font_size", 22)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_gold_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_gold_label.position = Vector2(20, 20)
	_gold_label.custom_minimum_size = Vector2(250, 40)
	add_child(_gold_label)

	# Interaction prompt (bottom center)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	_prompt_label.position = Vector2(-300, -90)
	_prompt_label.custom_minimum_size = Vector2(600, 50)
	_prompt_label.visible = false
	add_child(_prompt_label)

	# Flash message (center of screen)
	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.add_theme_font_size_override("font_size", 28)
	_message_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.position = Vector2(-300, -40)
	_message_label.custom_minimum_size = Vector2(600, 80)
	_message_label.visible = false
	add_child(_message_label)

	# Door status panel (top-right) — shows which levels are unlocked
	_door_status_label = Label.new()
	_door_status_label.name = "DoorStatusLabel"
	_door_status_label.add_theme_font_size_override("font_size", 14)
	_door_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_door_status_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_door_status_label.position = Vector2(-230, 20)
	_door_status_label.custom_minimum_size = Vector2(220, 180)
	add_child(_door_status_label)

	# Title reminder
	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "THE SANCTUARY"
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(0.5, 0.4, 0.7))
	title_label.set_anchors_preset(Control.PRESET_TOP_CENTER)
	title_label.position = Vector2(-100, 20)
	title_label.custom_minimum_size = Vector2(200, 30)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)


# ---------------------------------------------------------------------------
# Public interface (called by hub_scene.gd)
# ---------------------------------------------------------------------------

func update_gold(amount: int) -> void:
	_update_gold(amount)


func show_message(text: String, duration: float = 2.5) -> void:
	if _message_label:
		_message_label.text = text
		_message_label.visible = true
		_message_timer = duration


func show_shop() -> void:
	_open_shop()


# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.hub_interaction_changed.connect(_on_interaction_changed)
	EventBus.hub_door_unlocked.connect(_on_door_unlocked)
	EventBus.gold_collected.connect(_on_gold_changed)
	EventBus.relic_purchased.connect(_on_relic_purchased)


func _on_interaction_changed(target_label: String) -> void:
	if _prompt_label:
		if target_label.is_empty():
			_prompt_label.visible = false
		else:
			_prompt_label.text = "[ " + target_label + " ]"
			_prompt_label.visible = true


func _on_door_unlocked(level_number: int) -> void:
	_update_door_status()
	show_message("Level %d unlocked!" % level_number, 3.0)


func _on_gold_changed(_amount: int) -> void:
	_update_gold(GameManager.player_gold)


func _on_relic_purchased(_relic_id: String, _cost: int) -> void:
	_update_gold(GameManager.player_gold)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _update_gold(amount: int) -> void:
	if _gold_label:
		_gold_label.text = "GOLD: %d" % amount


func _update_door_status() -> void:
	if not _door_status_label:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("LEVELS:")
	for i in range(1, 8):
		var unlocked := GameManager.is_level_unlocked(i)
		var level_data := LevelData.get_level(i)
		var name_short: String = level_data.get("name", "Level %d" % i)
		if name_short.length() > 16:
			name_short = name_short.substr(0, 14) + ".."
		var marker := "✓" if unlocked else "✗"
		var color_tag := "[color=#22ff22]" if unlocked else "[color=#ff3322]"
		lines.append("  %s L%d: %s" % [marker, i, name_short])
	_door_status_label.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Shop panel (simple overlay)
# ---------------------------------------------------------------------------

func _open_shop() -> void:
	if _shop_open:
		return
	_shop_open = true

	_shop_panel = _build_shop_panel()
	add_child(_shop_panel)


func _close_shop() -> void:
	if not _shop_open:
		return
	_shop_open = false
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
		_shop_panel = null


func _build_shop_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ShopPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-320, -280)
	panel.custom_minimum_size = Vector2(640, 560)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "RELIC SHOP"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var gold_info := Label.new()
	gold_info.name = "ShopGoldLabel"
	gold_info.text = "Your Gold: %d" % GameManager.player_gold
	gold_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gold_info)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scroll container for relics
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 380)
	vbox.add_child(scroll)

	var relic_list := VBoxContainer.new()
	scroll.add_child(relic_list)

	for relic: Dictionary in RelicSystem.get_all_relics():
		relic_list.add_child(_build_relic_row(relic))

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close [ESC]"
	close_btn.pressed.connect(_close_shop)
	vbox.add_child(close_btn)

	return panel


func _build_relic_row(relic: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)

	var relic_id: String = relic.get("id", "")
	var cost: int = relic.get("cost", 0)
	var current_stack: int = GameManager.player_relics.get(relic_id, 0)
	var max_stack: int = relic.get("max_stack", 1)

	# Info label
	var info := Label.new()
	info.text = "[%s] %s — %dg (%d/%d)\n%s" % [
		RelicSystem.get_rarity(relic_id),
		relic.get("name", relic_id),
		cost,
		current_stack,
		max_stack,
		relic.get("description", "")
	]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 13)
	row.add_child(info)

	# Buy button
	var btn := Button.new()
	btn.text = "Buy\n%dg" % cost
	btn.custom_minimum_size = Vector2(70, 0)
	var can_buy := RelicSystem.can_purchase(relic_id)
	btn.disabled = not can_buy

	btn.pressed.connect(func() -> void:
		if GameManager.purchase_relic(relic_id, cost):
			show_message("Purchased: %s!" % relic.get("name", relic_id))
			# Rebuild shop panel to refresh state
			_close_shop()
			_open_shop()
	)

	row.add_child(btn)
	return row
