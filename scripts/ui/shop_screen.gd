extends Control
## Shop screen for purchasing relics and redeeming vouchers.
## Accessible from the main menu before starting a run.
## Relics are permanent equippable perks (up to 5 slots).
## Vouchers are one-time-use cards (max 20).

signal shop_closed

# ── References (built at runtime) ──────────────────────────────────────────
var _overlay: ColorRect
var _title_label: Label
var _coin_label: Label
var _tabs_container: HBoxContainer
var _content_container: VBoxContainer
var _close_button: Button
var _relic_tab_button: Button
var _voucher_tab_button: Button
var _equipped_container: HBoxContainer
var _equipped_label: Label

var _current_tab: String = "relics"

const UpgradeGeneratorScript := preload("res://scripts/systems/upgrade_generator.gd")


func _ready() -> void:
	_build_ui()
	_refresh_display()


func _build_ui() -> void:
	# Full-screen overlay
	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.01, 0.05, 0.95)
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	add_child(_overlay)

	# Main vertical layout
	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_left = 40.0
	main_vbox.offset_right = -40.0
	main_vbox.offset_top = 60.0
	main_vbox.offset_bottom = -40.0
	main_vbox.add_theme_constant_override("separation", 16)
	add_child(main_vbox)

	# Title + coin row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 20)
	main_vbox.add_child(top_row)

	_title_label = Label.new()
	_title_label.text = "SHOP"
	_title_label.add_theme_font_size_override("font_size", 48)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_title_label)

	_coin_label = Label.new()
	_coin_label.add_theme_font_size_override("font_size", 36)
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	top_row.add_child(_coin_label)

	# Equipped relics display
	_equipped_label = Label.new()
	_equipped_label.text = "EQUIPPED RELICS:"
	_equipped_label.add_theme_font_size_override("font_size", 24)
	_equipped_label.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	main_vbox.add_child(_equipped_label)

	_equipped_container = HBoxContainer.new()
	_equipped_container.add_theme_constant_override("separation", 8)
	_equipped_container.custom_minimum_size = Vector2(0, 60)
	main_vbox.add_child(_equipped_container)

	# Tab buttons
	_tabs_container = HBoxContainer.new()
	_tabs_container.add_theme_constant_override("separation", 12)
	main_vbox.add_child(_tabs_container)

	_relic_tab_button = _create_tab_button("RELICS", "relics")
	_tabs_container.add_child(_relic_tab_button)

	_voucher_tab_button = _create_tab_button("VOUCHERS", "vouchers")
	_tabs_container.add_child(_voucher_tab_button)

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_theme_constant_override("separation", 12)
	scroll.add_child(_content_container)

	# Close button
	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.custom_minimum_size = Vector2(0, 64)
	_close_button.add_theme_font_size_override("font_size", 32)

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.3, 0.1, 0.1, 0.9)
	close_style.corner_radius_top_left = 8
	close_style.corner_radius_top_right = 8
	close_style.corner_radius_bottom_left = 8
	close_style.corner_radius_bottom_right = 8
	_close_button.add_theme_stylebox_override("normal", close_style)

	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.5, 0.15, 0.15, 0.9)
	close_hover.corner_radius_top_left = 8
	close_hover.corner_radius_top_right = 8
	close_hover.corner_radius_bottom_left = 8
	close_hover.corner_radius_bottom_right = 8
	_close_button.add_theme_stylebox_override("hover", close_hover)

	_close_button.pressed.connect(_on_close)
	main_vbox.add_child(_close_button)


func _create_tab_button(text: String, tab_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 48)
	btn.add_theme_font_size_override("font_size", 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.2, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.15, 0.3, 0.9)
	hover.corner_radius_top_left = 8
	hover.corner_radius_top_right = 8
	hover.corner_radius_bottom_left = 8
	hover.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("hover", hover)

	btn.pressed.connect(func() -> void:
		_current_tab = tab_id
		_refresh_display()
	)
	return btn


func _refresh_display() -> void:
	_coin_label.text = "COINS: %d" % GameManager.coins
	_refresh_equipped()

	# Clear content
	for child in _content_container.get_children():
		child.queue_free()

	match _current_tab:
		"relics":
			_build_relic_list()
		"vouchers":
			_build_voucher_list()


func _refresh_equipped() -> void:
	for child in _equipped_container.get_children():
		child.queue_free()

	var max_slots := GameManager.get_max_relic_slots()
	_equipped_label.text = "EQUIPPED RELICS (%d/%d):" % [GameManager.equipped_relics.size(), max_slots]

	for i in max_slots:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(80, 50)

		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6

		if i < GameManager.equipped_relics.size():
			var relic: Dictionary = GameManager.equipped_relics[i]
			var relic_color: Color = relic.get("color", Color(0.5, 0.5, 0.5))
			style.bg_color = Color(relic_color.r * 0.3, relic_color.g * 0.3, relic_color.b * 0.3, 0.8)
			style.border_color = relic_color
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2

			var label := Label.new()
			label.text = relic.get("name", "?")[0]  # First character
			label.add_theme_font_size_override("font_size", 24)
			label.add_theme_color_override("font_color", relic_color)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slot.add_child(label)

			# Click to unequip
			var btn := Button.new()
			btn.flat = true
			btn.anchor_right = 1.0
			btn.anchor_bottom = 1.0
			btn.tooltip_text = "Unequip " + relic.get("name", "")
			btn.pressed.connect(func() -> void:
				GameManager.unequip_relic(i)
				SaveManager.save_meta()
				_refresh_display()
			)
			slot.add_child(btn)
		else:
			style.bg_color = Color(0.1, 0.08, 0.12, 0.5)
			style.border_color = Color(0.3, 0.3, 0.3, 0.3)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1

		slot.add_theme_stylebox_override("panel", style)
		_equipped_container.add_child(slot)


func _build_relic_list() -> void:
	var relic_db: Dictionary = UpgradeGeneratorScript.RELIC_DATABASE
	var owned_ids: Array[String] = []
	for r in GameManager.owned_relics:
		owned_ids.append(r.get("id", ""))

	for relic_id in relic_db:
		var relic: Dictionary = relic_db[relic_id]
		var is_owned := relic_id in owned_ids
		var is_equipped := false
		for eq in GameManager.equipped_relics:
			if eq.get("id", "") == relic_id:
				is_equipped = true
				break

		var panel := _create_shop_item_panel(relic, is_owned, is_equipped)
		_content_container.add_child(panel)


func _create_shop_item_panel(relic: Dictionary, is_owned: bool, is_equipped: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 120)

	var relic_color: Color = relic.get("color", Color(0.5, 0.5, 0.5))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.1, 0.9)
	style.border_color = relic_color * (1.0 if is_owned else 0.4)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	# Left: info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = relic.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", relic_color)
	info_vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = relic.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_label)

	# Right: action button
	var action_btn := Button.new()
	action_btn.custom_minimum_size = Vector2(160, 48)
	action_btn.add_theme_font_size_override("font_size", 22)

	if is_equipped:
		action_btn.text = "EQUIPPED"
		action_btn.disabled = true
	elif is_owned:
		action_btn.text = "EQUIP"
		action_btn.pressed.connect(func() -> void:
			GameManager.equip_relic(relic.duplicate(true))
			SaveManager.save_meta()
			_refresh_display()
		)
	else:
		var cost: int = relic.get("cost", 0)
		action_btn.text = "BUY (%d)" % cost
		if GameManager.coins < cost:
			action_btn.disabled = true
		action_btn.pressed.connect(func() -> void:
			if GameManager.buy_relic(relic.duplicate(true)):
				SaveManager.save_meta()
				_refresh_display()
		)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.1, 0.25, 0.8)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	action_btn.add_theme_stylebox_override("normal", btn_style)

	hbox.add_child(action_btn)

	return panel


func _build_voucher_list() -> void:
	if GameManager.vouchers.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No vouchers yet.\nEarn vouchers through special tasks and discovering secrets!"
		empty_label.add_theme_font_size_override("font_size", 24)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content_container.add_child(empty_label)
		return

	for i in GameManager.vouchers.size():
		var voucher: Dictionary = GameManager.vouchers[i]
		var panel := _create_voucher_panel(voucher, i)
		_content_container.add_child(panel)


func _create_voucher_panel(voucher: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 100)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.02, 0.9)
	style.border_color = Color(0.9, 0.7, 0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = voucher.get("name", "Voucher")
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	info_vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = voucher.get("description", "One-time use.")
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_label)

	var redeem_btn := Button.new()
	redeem_btn.text = "REDEEM"
	redeem_btn.custom_minimum_size = Vector2(140, 44)
	redeem_btn.add_theme_font_size_override("font_size", 22)
	redeem_btn.pressed.connect(func() -> void:
		GameManager.redeem_voucher(index)
		SaveManager.save_meta()
		_refresh_display()
	)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.15, 0.05, 0.8)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	redeem_btn.add_theme_stylebox_override("normal", btn_style)

	hbox.add_child(redeem_btn)

	return panel


func _on_close() -> void:
	shop_closed.emit()
