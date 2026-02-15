extends Node
## Manages save/load with roguelike permadeath.
## On player death, the save file is DELETED — restart from Level 1.
## On level completion, progress is saved so the player can resume.

const SAVE_PATH := "user://till_the_end_save.dat"

# Save data structure
var save_data: Dictionary = {}

func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)


## Save current run progress (called after beating a level's boss).
func save_progress(data: Dictionary) -> void:
	save_data = data.duplicate(true)
	save_data["timestamp"] = Time.get_unix_time_from_system()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()


## Load saved progress. Returns empty dict if no save exists.
func load_progress() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var data = file.get_var()
		file.close()
		if data is Dictionary:
			save_data = data
			return save_data

	return {}


## Delete save file — called on player death (permadeath).
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	save_data.clear()


## Check if a save file exists.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Create save data from current GameManager state.
func create_save_from_state() -> Dictionary:
	return {
		"current_level": GameManager.current_level,
		"player_level": GameManager.player_level,
		"player_exp": GameManager.player_exp,
		"player_exp_to_next": GameManager.player_exp_to_next,
		"player_weapons": GameManager.player_weapons.duplicate(true),
		"player_abilities": GameManager.player_abilities.duplicate(true),
		"player_traits": GameManager.player_traits.duplicate(true),
		"total_kills": GameManager.total_kills,
		"run_time": GameManager.run_time,
	}


## Restore GameManager state from save data.
func restore_state_from_save(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameManager.current_level = data.get("current_level", 1)
	GameManager.player_level = data.get("player_level", 1)
	GameManager.player_exp = data.get("player_exp", 0.0)
	GameManager.player_exp_to_next = data.get("player_exp_to_next", 100.0)
	GameManager.player_weapons = data.get("player_weapons", []).duplicate(true)
	GameManager.player_abilities = data.get("player_abilities", []).duplicate(true)
	if data.has("player_traits"):
		GameManager.player_traits = data.get("player_traits", {}).duplicate(true)
	GameManager.total_kills = data.get("total_kills", 0)
	GameManager.run_time = data.get("run_time", 0.0)


## Called when the player dies — permadeath erases progress.
func _on_player_died() -> void:
	delete_save()
