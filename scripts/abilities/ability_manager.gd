extends Node3D
class_name AbilityManager
## Manages all active abilities for the player.
## Abilities are passive/auto-activating and require NO player input.
## Attach as a child of the player node. Listens to EventBus for
## ability_acquired and ability_upgraded signals.

const MAX_ABILITIES := 6

# Map from ability_id -> scene script path
# Only passive/auto-activating abilities belong here.
# Skills (bomb, shadow_clone, meteor_strike) are managed by SkillManager.
const ABILITY_SCRIPTS: Dictionary = {
	"auto_turret":     "res://scripts/abilities/auto_turret.gd",
	"death_skulls":    "res://scripts/abilities/death_skulls.gd",
	"chain_lightning":  "res://scripts/abilities/chain_lightning.gd",
	"fire_nova":       "res://scripts/abilities/fire_nova.gd",
	"blood_scythe":    "res://scripts/abilities/blood_scythe.gd",
	"frost_aura":      "res://scripts/abilities/frost_aura.gd",
	"venom_trail":     "res://scripts/abilities/venom_trail.gd",
	"lifesteal_aura":  "res://scripts/abilities/lifesteal_aura.gd",
	"thorns_aura":     "res://scripts/abilities/thorns_aura.gd",
}

# Active ability nodes keyed by ability_id
var _active_abilities: Dictionary = {}

@onready var _player: Node3D = get_parent()


# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	EventBus.ability_acquired.connect(_on_ability_acquired)
	EventBus.ability_upgraded.connect(_on_ability_upgraded)


# ── Public API ────────────────────────────────────────────────────────

## Instantiate and activate a new ability from the given data dictionary.
## Returns true if the ability was added, false if at capacity or duplicate.
func add_ability(ability_data: Dictionary) -> bool:
	var ability_id: String = ability_data.get("id", "")
	if ability_id.is_empty():
		push_warning("AbilityManager: ability_data has no 'id' field.")
		return false
	if _active_abilities.has(ability_id):
		push_warning("AbilityManager: ability '%s' already active." % ability_id)
		return false
	if _active_abilities.size() >= MAX_ABILITIES:
		push_warning("AbilityManager: at max capacity (%d)." % MAX_ABILITIES)
		return false
	if not ABILITY_SCRIPTS.has(ability_id):
		push_warning("AbilityManager: no script registered for '%s'." % ability_id)
		return false

	# Load the script and create a node
	var script_path: String = ABILITY_SCRIPTS[ability_id]
	var script_res: GDScript = load(script_path) as GDScript
	if script_res == null:
		push_error("AbilityManager: failed to load script '%s'." % script_path)
		return false

	var ability_node := Node3D.new()
	ability_node.set_script(script_res)
	ability_node.name = ability_id
	add_child(ability_node)

	# Initialize through AbilityBase interface
	ability_node.initialize(ability_data, _player)
	_active_abilities[ability_id] = ability_node
	return true


## Upgrade an already-active ability to `new_level`.
func upgrade_ability(ability_id: String, new_level: int) -> void:
	if _active_abilities.has(ability_id):
		var node: Node3D = _active_abilities[ability_id]
		if node.has_method("upgrade"):
			node.upgrade(new_level)
	else:
		push_warning("AbilityManager: cannot upgrade '%s' -- not active." % ability_id)


## Return an array of all active ability nodes (AbilityBase instances).
func get_active_abilities() -> Array:
	return _active_abilities.values()


## Check whether a specific ability is currently active.
func has_ability(ability_id: String) -> bool:
	return _active_abilities.has(ability_id)


## Remove and clean up an ability by id.
func remove_ability(ability_id: String) -> void:
	if _active_abilities.has(ability_id):
		var node: Node3D = _active_abilities[ability_id]
		if node.has_method("deactivate"):
			node.deactivate()
		node.queue_free()
		_active_abilities.erase(ability_id)


# ── Signal callbacks ──────────────────────────────────────────────────

func _on_ability_acquired(ability_data: Dictionary) -> void:
	add_ability(ability_data)


func _on_ability_upgraded(ability_id: String, new_level: int) -> void:
	upgrade_ability(ability_id, new_level)
