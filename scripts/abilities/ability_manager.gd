extends Node3D
class_name AbilityManager
## Manages all active abilities for the player.
## Attach as a child of the player node. Listens to EventBus for
## ability_acquired, ability_upgraded, and bomb_ammo_collected signals.

var _max_abilities: int = 6

# Map from ability_id -> scene script path
const ABILITY_SCRIPTS: Dictionary = {
	# ── Original abilities ──────────────────────────────────────────────
	"auto_turret":         "res://scripts/abilities/auto_turret.gd",
	"death_skulls":        "res://scripts/abilities/death_skulls.gd",
	"bomb":                "res://scripts/abilities/bomb_ability.gd",
	"chain_lightning":     "res://scripts/abilities/chain_lightning.gd",
	"fire_nova":           "res://scripts/abilities/fire_nova.gd",
	"blood_scythe":        "res://scripts/abilities/blood_scythe.gd",
	"frost_aura":          "res://scripts/abilities/frost_aura.gd",
	"shadow_clone":        "res://scripts/abilities/shadow_clone.gd",
	"meteor_strike":       "res://scripts/abilities/meteor_strike.gd",
	# ── Clarified existing abilities ────────────────────────────────────
	"thornflesh":          "res://scripts/abilities/thornflesh.gd",
	"magnet_pull":         "res://scripts/abilities/magnet_pull_ability.gd",
	# ── New abilities ───────────────────────────────────────────────────
	"soul_shield":         "res://scripts/abilities/soul_shield.gd",
	"flaming_aura":        "res://scripts/abilities/flaming_aura.gd",
	"quick_learning":      "res://scripts/abilities/quick_learning.gd",
	"bounceback":          "res://scripts/abilities/bounceback.gd",
	"telekinesis":         "res://scripts/abilities/telekinesis_ability.gd",
	"big_boot":            "res://scripts/abilities/big_boot.gd",
	"rubber_rounds":       "res://scripts/abilities/rubber_rounds.gd",
	"spirit_shot":         "res://scripts/abilities/spirit_shot.gd",
	"gods_tear":           "res://scripts/abilities/gods_tear.gd",
	"quick_reflexes":      "res://scripts/abilities/quick_reflexes.gd",
	"lightweight":         "res://scripts/abilities/lightweight_ability.gd",
	"tough_skin":          "res://scripts/abilities/tough_skin.gd",
	"vengeful_rage":       "res://scripts/abilities/vengeful_rage.gd",
	"hyperfocus":          "res://scripts/abilities/hyperfocus.gd",
	"toxic_emission":      "res://scripts/abilities/toxic_emission.gd",
	"uplift":              "res://scripts/abilities/uplift_ability.gd",
	"sages_eye":           "res://scripts/abilities/sages_eye.gd",
	"versatility":         "res://scripts/abilities/versatility_ability.gd",
	"triggerhappy":        "res://scripts/abilities/triggerhappy.gd",
	"gifted":              "res://scripts/abilities/gifted_ability.gd",
	"spiritually_aligned": "res://scripts/abilities/spiritually_aligned.gd",
	"intimidating_gaze":   "res://scripts/abilities/intimidating_gaze.gd",
	"bullet_time":         "res://scripts/abilities/bullet_time_ability.gd",
	"voidwalker":          "res://scripts/abilities/voidwalker.gd",
	"clairvoyant":         "res://scripts/abilities/clairvoyant.gd",
	"acid_dipped":         "res://scripts/abilities/acid_dipped.gd",
}

# Active ability nodes keyed by ability_id
var _active_abilities: Dictionary = {}

@onready var _player: Node3D = get_parent()


# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	EventBus.ability_acquired.connect(_on_ability_acquired)
	EventBus.ability_upgraded.connect(_on_ability_upgraded)
	EventBus.bomb_ammo_collected.connect(_on_bomb_ammo_collected)


# ── Public API ────────────────────────────────────────────────────────

## Returns the current max abilities (can be increased by Versatility, Gifted, Voidwalker).
func get_max_abilities() -> int:
	return _max_abilities


## Add extra ability slots (called by slot-granting abilities).
func add_extra_slots(count: int) -> void:
	_max_abilities += count
	GameManager.MAX_ABILITIES = _max_abilities


## Remove extra ability slots (called on deactivation of slot-granting abilities).
func remove_extra_slots(count: int) -> void:
	_max_abilities = maxi(_max_abilities - count, 6)
	GameManager.MAX_ABILITIES = _max_abilities


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
	if _active_abilities.size() >= _max_abilities:
		push_warning("AbilityManager: at max capacity (%d)." % _max_abilities)
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


## Get data from an active ability (for weapon system to check passives).
func get_ability_data(ability_id: String) -> Dictionary:
	if _active_abilities.has(ability_id):
		var node: Node3D = _active_abilities[ability_id]
		if node.has_method("get_ability_info"):
			return node.get_ability_info()
	return {}


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


func _on_bomb_ammo_collected(amount: int) -> void:
	if _active_abilities.has("bomb"):
		var bomb_node: Node3D = _active_abilities["bomb"]
		if bomb_node.has_method("add_charges"):
			bomb_node.add_charges(amount)
