extends Node3D
class_name SkillManager
## Manages up to 3 active skills for the player.
## Skills are button-activated with cooldowns, unlike passive abilities.

const MAX_SKILLS := 3

const SKILL_SCRIPTS: Dictionary = {
	"bomb":           "res://scripts/abilities/bomb_ability.gd",
	"shadow_clone":   "res://scripts/abilities/shadow_clone.gd",
	"meteor_strike":  "res://scripts/abilities/meteor_strike.gd",
}

# Active skill nodes keyed by skill_id
var _active_skills: Dictionary = {}

# Ordered list of equipped skill IDs for slot indexing
var _skill_slots: Array[String] = []

@onready var _player: Node3D = get_parent()


func _ready() -> void:
	EventBus.skill_acquired.connect(_on_skill_acquired)
	EventBus.skill_upgraded.connect(_on_skill_upgraded)


## Instantiate and activate a new skill from the given data dictionary.
func add_skill(skill_data: Dictionary) -> bool:
	var skill_id: String = skill_data.get("id", "")
	if skill_id.is_empty():
		return false
	if _active_skills.has(skill_id):
		return false
	if _active_skills.size() >= MAX_SKILLS:
		return false
	if not SKILL_SCRIPTS.has(skill_id):
		return false

	var script_path: String = SKILL_SCRIPTS[skill_id]
	var script_res: GDScript = load(script_path) as GDScript
	if script_res == null:
		return false

	var skill_node := Node3D.new()
	skill_node.set_script(script_res)
	skill_node.name = skill_id
	add_child(skill_node)

	skill_node.initialize(skill_data, _player)
	_active_skills[skill_id] = skill_node
	_skill_slots.append(skill_id)
	return true


## Activate the skill in the given slot index (0-2).
func use_skill(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _skill_slots.size():
		return
	var skill_id := _skill_slots[slot_index]
	var node: Node3D = _active_skills.get(skill_id)
	if node and node.has_method("use_skill"):
		node.use_skill()


## Upgrade a skill by id.
func upgrade_skill(skill_id: String, new_level: int) -> void:
	if _active_skills.has(skill_id):
		var node: Node3D = _active_skills[skill_id]
		if node.has_method("upgrade"):
			node.upgrade(new_level)


## Get skill data for the given slot.
func get_skill_in_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _skill_slots.size():
		return {}
	var skill_id := _skill_slots[slot_index]
	var node: Node3D = _active_skills.get(skill_id)
	if node and "skill_data" in node:
		return node.skill_data
	return {}


## Get cooldown progress (0.0 = just started, 1.0 = ready) for a slot.
func get_cooldown_progress(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= _skill_slots.size():
		return 1.0
	var skill_id := _skill_slots[slot_index]
	var node: Node3D = _active_skills.get(skill_id)
	if node and node.has_method("get_cooldown_progress"):
		return node.get_cooldown_progress()
	return 1.0


## Check if a skill slot is ready to use.
func is_skill_ready(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _skill_slots.size():
		return false
	var skill_id := _skill_slots[slot_index]
	var node: Node3D = _active_skills.get(skill_id)
	if node and "is_ready" in node:
		return node.is_ready
	return false


func get_skill_count() -> int:
	return _skill_slots.size()


func has_skill(skill_id: String) -> bool:
	return _active_skills.has(skill_id)


func remove_skill(skill_id: String) -> void:
	if _active_skills.has(skill_id):
		var node: Node3D = _active_skills[skill_id]
		if node.has_method("deactivate"):
			node.deactivate()
		node.queue_free()
		_active_skills.erase(skill_id)
		_skill_slots.erase(skill_id)


func _on_skill_acquired(skill_data: Dictionary) -> void:
	add_skill(skill_data)


func _on_skill_upgraded(skill_id: String, new_level: int) -> void:
	upgrade_skill(skill_id, new_level)
