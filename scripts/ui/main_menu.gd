extends Control
## Main menu for Till The End.
## Entry point scene. Presents title, subtitle, and options to start or quit.

var start_button: Button
var quit_button: Button
var title_label: Label
var subtitle_label: Label
var version_label: Label


func _ready() -> void:
	# Get references
	title_label = %TitleLabel
	subtitle_label = %SubtitleLabel
	start_button = %StartButton
	quit_button = %QuitButton
	version_label = %VersionLabel

	# Connect buttons
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Ensure not paused at menu
	get_tree().paused = false

	# Animate title pulse
	_start_title_pulse()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _start_title_pulse() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(title_label, "modulate:a", 0.7, 1.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(title_label, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
