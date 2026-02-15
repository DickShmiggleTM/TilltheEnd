extends Control
## Main menu for Till The End.
## Entry point scene. Presents title, subtitle, and options to start, continue,
## shop (relics/vouchers), or quit. The CONTINUE button only appears if
## SaveManager.has_save() is true. Starting a new run when a save exists
## prompts for confirmation.

var start_button: Button
var continue_button: Button
var shop_button: Button
var quit_button: Button
var title_label: Label
var subtitle_label: Label
var version_label: Label
var confirm_dialog: ConfirmationDialog
var coin_label: Label

# Shop UI (created at runtime)
var _shop_screen: Control = null


func _ready() -> void:
	# Get references
	title_label = %TitleLabel
	subtitle_label = %SubtitleLabel
	start_button = %StartButton
	continue_button = %ContinueButton
	quit_button = %QuitButton
	version_label = %VersionLabel
	confirm_dialog = %ConfirmDialog

	# Shop button (may not exist in older .tscn)
	if has_node("%ShopButton"):
		shop_button = %ShopButton
	else:
		shop_button = find_child("ShopButton", true, false)

	# Coin label (may not exist in older .tscn)
	if has_node("%CoinLabel"):
		coin_label = %CoinLabel
	else:
		coin_label = find_child("CoinLabel", true, false)

	# Connect buttons
	start_button.pressed.connect(_on_start_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	confirm_dialog.confirmed.connect(_on_confirm_new_run)

	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)

	# Ensure not paused at menu
	get_tree().paused = false

	# Show/hide continue button based on save state
	_update_continue_visibility()
	_update_coin_display()

	# Animate title pulse
	_start_title_pulse()


func _update_continue_visibility() -> void:
	if SaveManager.has_save():
		continue_button.visible = true
	else:
		continue_button.visible = false


func _update_coin_display() -> void:
	if coin_label:
		coin_label.text = "COINS: %d" % GameManager.coins


func _on_start_pressed() -> void:
	if SaveManager.has_save():
		# Warn the player that starting a new run will erase progress
		confirm_dialog.dialog_text = "This will erase existing progress. Continue?"
		confirm_dialog.popup_centered()
	else:
		_start_new_run()


func _on_confirm_new_run() -> void:
	SaveManager.delete_save()
	_start_new_run()


func _start_new_run() -> void:
	GameManager.start_new_run()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_continue_pressed() -> void:
	var save_data := SaveManager.load_progress()
	if save_data.is_empty():
		# Save was corrupted or missing -- fall back to new run
		_start_new_run()
		return

	SaveManager.restore_state_from_save(save_data)
	var level: int = save_data.get("current_level", 1)
	GameManager.continue_run(level)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_shop_pressed() -> void:
	EventBus.shop_opened.emit()
	_show_shop()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _start_title_pulse() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(title_label, "modulate:a", 0.7, 1.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(title_label, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)


# ══════════════════════════════════════════════════════════════════════════
# Shop screen (created at runtime)
# ══════════════════════════════════════════════════════════════════════════

func _show_shop() -> void:
	if _shop_screen and is_instance_valid(_shop_screen):
		_shop_screen.visible = true
		return

	var shop_script_path := "res://scripts/ui/shop_screen.gd"
	if not ResourceLoader.exists(shop_script_path):
		push_warning("MainMenu: shop_screen.gd not found, cannot open shop.")
		return

	_shop_screen = Control.new()
	_shop_screen.set_script(load(shop_script_path))
	_shop_screen.name = "ShopScreen"
	add_child(_shop_screen)

	if _shop_screen.has_signal("shop_closed"):
		_shop_screen.shop_closed.connect(_on_shop_closed)


func _on_shop_closed() -> void:
	if _shop_screen:
		_shop_screen.visible = false
	_update_coin_display()
	EventBus.shop_closed.emit()
