extends Node3D
## Hub World Scene — the persistent sanctuary between levels.
##
## Layout:
##   - Central circular plaza with 7 door alcoves arranged in a semicircle
##   - Each door corresponds to a level (1-7)
##   - Door 1 always unlocked; subsequent doors unlock after beating the previous level
##   - North side: relic shop with 3 purchasable relics displayed at a time
##   - Atmospheric lighting and decorative architecture
##
## Interaction:
##   - Player walks into a door's proximity area → prompt shown → E to enter
##   - Player walks into shop counter → relic purchase prompt shown
##   - On death: player returns here with all doors locked except 1

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const HUB_HUD_SCENE_PATH := "res://scenes/ui/hub_hud.tscn"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PLAZA_RADIUS: float = 24.0
const DOOR_ARC_RADIUS: float = 20.0
const DOOR_ARC_START: float = -PI * 0.7   ## Start angle for door arc
const DOOR_ARC_END: float = PI * 0.7      ## End angle for door arc
const FLOOR_SIZE: float = 80.0
const WALL_HEIGHT: float = 6.0
const CELL_SIZE: float = 4.0
const ENVIRONMENT_LAYER: int = 1
const TOTAL_LEVELS: int = 7

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var player: CharacterBody3D = null
var hud: Control = null
var _geometry_root: Node3D = null
var _lighting_root: Node3D = null
var _doors_root: Node3D = null

## Maps level_number → door StaticBody3D node
var _level_doors: Dictionary = {}
## Shop interactable node
var _shop_node: Node3D = null
## Currently highlighted interactable
var _current_target: Node3D = null

# Materials
var _mat_floor: StandardMaterial3D = null
var _mat_wall: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_pillar: StandardMaterial3D = null
var _mat_door_unlocked: StandardMaterial3D = null
var _mat_door_locked: StandardMaterial3D = null
var _mat_door_frame: StandardMaterial3D = null
var _mat_shop: StandardMaterial3D = null
var _mat_accent: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	get_tree().paused = false

	_create_materials()

	_geometry_root = Node3D.new()
	_geometry_root.name = "HubGeometry"
	add_child(_geometry_root)

	_lighting_root = Node3D.new()
	_lighting_root.name = "HubLighting"
	add_child(_lighting_root)

	_doors_root = Node3D.new()
	_doors_root.name = "HubDoors"
	add_child(_doors_root)

	_build_hub_environment()
	_build_plaza()
	_build_doors()
	_build_shop()
	_build_lighting()

	# Spawn player in center
	_setup_player()

	# Load HUD
	_setup_hud()

	# Apply any relics the player purchased (from previous hub visit)
	_apply_relic_effects()

	# Save progress when returning to hub after a level
	if GameManager.state == GameManager.GameState.LEVEL_COMPLETE:
		SaveManager.save_progress(SaveManager.create_save_from_state())

	GameManager.state = GameManager.GameState.HUB
	EventBus.hub_world_entered.emit()


func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	# Detect what the player is looking at (interactable scan via raycast)
	_update_interaction_target()

	# Handle interaction input
	if Input.is_action_just_pressed("ui_accept") or _is_interact_key_pressed():
		_try_interact()


func _exit_tree() -> void:
	pass

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerControllerScript)
	player.name = "Player"
	player.add_to_group("player")
	add_child(player)

	# Spawn at plaza center, facing the doors
	player.global_position = Vector3(0.0, 0.5, 4.0)
	player.rotation.y = PI  ## Face toward door arc (negative Z direction)

	# Disable weapon/ability systems in hub (no combat)
	# We accomplish this by not adding WeaponManager / AbilityManager


func _setup_hud() -> void:
	if ResourceLoader.exists(HUB_HUD_SCENE_PATH):
		var packed := load(HUB_HUD_SCENE_PATH) as PackedScene
		if packed:
			hud = packed.instantiate()
			add_child(hud)
	else:
		# Fallback: create minimal HUD in code
		_create_fallback_hud()


func _create_fallback_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HubHUD"
	add_child(canvas)

	var label := Label.new()
	label.name = "GoldLabel"
	label.text = "GOLD: %d" % GameManager.player_gold
	label.add_theme_font_size_override("font_size", 20)
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.position = Vector2(20, 20)
	canvas.add_child(label)

	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "[E] to interact"
	hint.add_theme_font_size_override("font_size", 18)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_CENTER)
	hint.position = Vector2(-100, -60)
	canvas.add_child(hint)

	hud = canvas

# ---------------------------------------------------------------------------
# Relic application
# ---------------------------------------------------------------------------

func _apply_relic_effects() -> void:
	RelicSystem.apply_relics()

# ---------------------------------------------------------------------------
# Interaction system
# ---------------------------------------------------------------------------

func _is_interact_key_pressed() -> bool:
	if Input.is_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_CTRL):
		# Use _physics_process-style edge detection via a simple flag
		if not _e_was_pressed:
			_e_was_pressed = true
			return true
	else:
		_e_was_pressed = false
	return false


var _e_was_pressed: bool = false


func _update_interaction_target() -> void:
	# Cast a short ray from the player camera to find interactable nodes
	var cam := player.get_node_or_null("Camera3D")
	if cam == null:
		# Try finding camera in children
		for child in player.get_children():
			if child is Camera3D:
				cam = child
				break
	if cam == null:
		return

	var space_state := get_world_3d().direct_space_state
	var ray_origin := cam.global_position
	var ray_dir := -cam.global_transform.basis.z
	var ray_end := ray_origin + ray_dir * 4.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [player.get_rid()]
	query.collision_mask = ENVIRONMENT_LAYER | 0xFFFFFFFF

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		if _current_target != null:
			_current_target = null
			EventBus.hub_interaction_changed.emit("")
		return

	var collider := result.get("collider")
	if collider == null:
		return

	# Check collider and its parent for interactable group
	var interactable: Node3D = null
	if collider.is_in_group("interactable"):
		interactable = collider
	elif collider.get_parent() and collider.get_parent().is_in_group("interactable"):
		interactable = collider.get_parent()

	if interactable != _current_target:
		_current_target = interactable
		var label: String = ""
		if interactable:
			label = interactable.get_meta("interact_label", "")
		EventBus.hub_interaction_changed.emit(label)


func _try_interact() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return

	if _current_target.is_in_group("hub_door"):
		var level_num: int = _current_target.get_meta("level_number", 0)
		if level_num > 0 and GameManager.is_level_unlocked(level_num):
			_enter_level(level_num)
		return

	if _current_target.is_in_group("hub_shop"):
		_open_shop()
		return

	if _current_target.is_in_group("hub_relic"):
		var relic_id: String = _current_target.get_meta("relic_id", "")
		_try_purchase_relic(relic_id)
		return


func _enter_level(level_num: int) -> void:
	GameManager.enter_level(level_num)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _open_shop() -> void:
	# Show shop screen — handled by HubHUD
	if hud and hud.has_method("show_shop"):
		hud.show_shop()


func _try_purchase_relic(relic_id: String) -> void:
	if not RelicSystem.can_purchase(relic_id):
		if hud and hud.has_method("show_message"):
			var relic := RelicSystem.get_relic(relic_id)
			var msg := "Not enough gold!" if GameManager.player_gold < relic.get("cost", 0) else "Already maxed!"
			hud.show_message(msg)
		return

	var relic := RelicSystem.get_relic(relic_id)
	var cost: int = relic.get("cost", 0)
	if GameManager.purchase_relic(relic_id, cost):
		_refresh_shop_display()
		if hud and hud.has_method("update_gold"):
			hud.update_gold(GameManager.player_gold)
		if hud and hud.has_method("show_message"):
			hud.show_message("Purchased: %s!" % relic.get("name", relic_id))

# ---------------------------------------------------------------------------
# Hub world geometry
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	# Dark stone sanctuary — ancient and atmospheric
	_mat_floor = _make_mat(Color(0.12, 0.10, 0.14), 0.90)
	_mat_wall = _make_mat(Color(0.10, 0.08, 0.12), 0.92)
	_mat_ceiling = _make_mat(Color(0.06, 0.04, 0.08), 0.98)
	_mat_pillar = _make_mat(Color(0.18, 0.14, 0.20), 0.75)
	_mat_door_frame = _make_mat(Color(0.22, 0.18, 0.26), 0.70)
	_mat_shop = _make_mat(Color(0.28, 0.20, 0.12), 0.65)
	_mat_accent = _make_mat(Color(0.55, 0.40, 0.10), 0.40)
	_mat_accent.metallic = 0.5

	_mat_door_unlocked = StandardMaterial3D.new()
	_mat_door_unlocked.albedo_color = Color(0.1, 0.6, 0.1)
	_mat_door_unlocked.roughness = 0.50
	_mat_door_unlocked.emission_enabled = true
	_mat_door_unlocked.emission = Color(0.05, 0.5, 0.05)
	_mat_door_unlocked.emission_energy_multiplier = 1.2

	_mat_door_locked = StandardMaterial3D.new()
	_mat_door_locked.albedo_color = Color(0.5, 0.05, 0.04)
	_mat_door_locked.roughness = 0.60
	_mat_door_locked.emission_enabled = true
	_mat_door_locked.emission = Color(0.4, 0.04, 0.03)
	_mat_door_locked.emission_energy_multiplier = 0.8


func _make_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _build_hub_environment() -> void:
	# Floor — large flat plane
	var floor_box := CSGBox3D.new()
	floor_box.name = "HubFloor"
	floor_box.size = Vector3(FLOOR_SIZE, 0.3, FLOOR_SIZE)
	floor_box.position = Vector3(0.0, -0.15, 0.0)
	floor_box.use_collision = true
	floor_box.collision_layer = ENVIRONMENT_LAYER
	floor_box.collision_mask = 0
	floor_box.material = _mat_floor
	_geometry_root.add_child(floor_box)

	# Ceiling
	var ceil_box := CSGBox3D.new()
	ceil_box.name = "HubCeiling"
	ceil_box.size = Vector3(FLOOR_SIZE, 0.3, FLOOR_SIZE)
	ceil_box.position = Vector3(0.0, WALL_HEIGHT + 0.15, 0.0)
	ceil_box.use_collision = false
	ceil_box.material = _mat_ceiling
	_geometry_root.add_child(ceil_box)

	# Four surrounding walls
	var wall_data: Array = [
		[Vector3(0.0, WALL_HEIGHT * 0.5, -FLOOR_SIZE * 0.5), Vector3(FLOOR_SIZE, WALL_HEIGHT, 0.4)],
		[Vector3(0.0, WALL_HEIGHT * 0.5, FLOOR_SIZE * 0.5), Vector3(FLOOR_SIZE, WALL_HEIGHT, 0.4)],
		[Vector3(-FLOOR_SIZE * 0.5, WALL_HEIGHT * 0.5, 0.0), Vector3(0.4, WALL_HEIGHT, FLOOR_SIZE)],
		[Vector3(FLOOR_SIZE * 0.5, WALL_HEIGHT * 0.5, 0.0), Vector3(0.4, WALL_HEIGHT, FLOOR_SIZE)],
	]
	for i in range(wall_data.size()):
		var wall := CSGBox3D.new()
		wall.name = "HubWall_%d" % i
		wall.position = wall_data[i][0]
		wall.size = wall_data[i][1]
		wall.use_collision = true
		wall.collision_layer = ENVIRONMENT_LAYER
		wall.collision_mask = 0
		wall.material = _mat_wall
		_geometry_root.add_child(wall)


func _build_plaza() -> void:
	# Circular raised plaza platform in center
	var plaza := CSGCylinder3D.new()
	plaza.name = "Plaza"
	plaza.radius = PLAZA_RADIUS * 0.6
	plaza.height = 0.4
	plaza.sides = 24
	plaza.position = Vector3(0.0, 0.2, 0.0)
	plaza.use_collision = true
	plaza.collision_layer = ENVIRONMENT_LAYER
	plaza.collision_mask = 0
	plaza.material = _mat_pillar
	_geometry_root.add_child(plaza)

	# Decorative pillars arranged in a ring
	var pillar_count := 8
	for i in range(pillar_count):
		var angle := (TAU / pillar_count) * i
		var px := cos(angle) * (PLAZA_RADIUS * 0.55)
		var pz := sin(angle) * (PLAZA_RADIUS * 0.55)
		_build_pillar(Vector3(px, 0.0, pz), 0.5, WALL_HEIGHT * 1.1)

	# Central altar / spawn marker
	var altar := CSGCylinder3D.new()
	altar.name = "CenterAltar"
	altar.radius = 1.5
	altar.height = 0.8
	altar.sides = 12
	altar.position = Vector3(0.0, 0.4, 0.0)
	altar.use_collision = false
	altar.material = _mat_accent
	_geometry_root.add_child(altar)

	# Glowing accent ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.4, 0.3, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.2, 0.7)
	ring_mat.emission_energy_multiplier = 1.5
	ring_mat.roughness = 0.2

	var ring := CSGCylinder3D.new()
	ring.name = "AltarRing"
	ring.radius = 1.6
	ring.height = 0.05
	ring.sides = 24
	ring.position = Vector3(0.0, 0.82, 0.0)
	ring.use_collision = false
	ring.material = ring_mat
	_geometry_root.add_child(ring)


func _build_pillar(base_pos: Vector3, radius: float, height: float) -> void:
	var pillar := CSGCylinder3D.new()
	pillar.name = "Pillar"
	pillar.radius = radius
	pillar.height = height
	pillar.sides = 8
	pillar.position = base_pos + Vector3(0.0, height * 0.5, 0.0)
	pillar.use_collision = true
	pillar.collision_layer = ENVIRONMENT_LAYER
	pillar.collision_mask = 0
	pillar.material = _mat_pillar
	_geometry_root.add_child(pillar)

	# Capital (top ornament)
	var cap := CSGBox3D.new()
	cap.name = "PillarCap"
	cap.size = Vector3(radius * 2.8, 0.3, radius * 2.8)
	cap.position = base_pos + Vector3(0.0, height + 0.15, 0.0)
	cap.use_collision = false
	cap.material = _mat_accent
	_geometry_root.add_child(cap)

# ---------------------------------------------------------------------------
# Doors — 7 doors in a semicircular arc
# ---------------------------------------------------------------------------

func _build_doors() -> void:
	_level_doors.clear()

	var arc_span := DOOR_ARC_END - DOOR_ARC_START
	var step := arc_span / (TOTAL_LEVELS - 1)

	for i in range(TOTAL_LEVELS):
		var level_num := i + 1
		var angle := DOOR_ARC_START + step * i
		var px := cos(angle) * DOOR_ARC_RADIUS
		var pz := sin(angle) * DOOR_ARC_RADIUS
		var door_pos := Vector3(px, 0.0, pz)
		var door_rot_y := angle + PI  ## Face inward toward plaza center

		_build_single_door(level_num, door_pos, door_rot_y)


func _build_single_door(level_num: int, pos: Vector3, rot_y: float) -> void:
	var is_unlocked := GameManager.is_level_unlocked(level_num)
	var level_data := LevelData.get_level(level_num)
	var level_name: String = level_data.get("name", "Level %d" % level_num)

	# Door frame
	var frame_root := Node3D.new()
	frame_root.name = "DoorFrame_%d" % level_num
	frame_root.position = pos
	frame_root.rotation.y = rot_y
	_doors_root.add_child(frame_root)

	# Frame arch
	var arch := CSGBox3D.new()
	arch.name = "Arch"
	arch.size = Vector3(3.5, WALL_HEIGHT * 0.9, 0.5)
	arch.position = Vector3(0.0, WALL_HEIGHT * 0.45, 0.0)
	arch.use_collision = true
	arch.collision_layer = ENVIRONMENT_LAYER
	arch.collision_mask = 0
	arch.material = _mat_door_frame
	frame_root.add_child(arch)

	# Door panel (interactive)
	var body := StaticBody3D.new()
	body.name = "Door_%d" % level_num
	body.add_to_group("interactable")
	body.add_to_group("hub_door")
	body.set_meta("level_number", level_num)
	body.set_meta("is_unlocked", is_unlocked)

	var interact_label: String
	if is_unlocked:
		interact_label = "Enter: %s [E]" % level_name
	else:
		interact_label = "LOCKED — Beat Level %d first" % (level_num - 1)
	body.set_meta("interact_label", interact_label)

	# Door mesh
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(2.8, WALL_HEIGHT * 0.80, 0.15)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = _mat_door_unlocked if is_unlocked else _mat_door_locked
	mesh_inst.name = "DoorMesh"
	body.add_child(mesh_inst)

	# Collision
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8, WALL_HEIGHT * 0.80, 0.15)
	col.shape = shape
	body.add_child(col)

	# Proximity area for interaction highlight
	var area := Area3D.new()
	area.name = "DoorProximity"
	var area_col := CollisionShape3D.new()
	var area_shape := BoxShape3D.new()
	area_shape.size = Vector3(4.0, WALL_HEIGHT, 4.0)
	area_col.shape = area_shape
	area.add_child(area_col)
	area.collision_layer = 0
	area.collision_mask = 2  ## Player layer
	body.add_child(area)

	body.position = Vector3(0.0, WALL_HEIGHT * 0.40, 0.0)
	body.collision_layer = ENVIRONMENT_LAYER
	body.collision_mask = 0
	frame_root.add_child(body)

	# Level number label plaque
	var label_body := CSGBox3D.new()
	label_body.name = "LevelPlaque"
	label_body.size = Vector3(1.0, 0.5, 0.08)
	label_body.position = Vector3(0.0, WALL_HEIGHT * 0.10, 0.25)
	label_body.use_collision = false
	label_body.material = _mat_accent
	frame_root.add_child(label_body)

	# Light above each door
	var door_light := OmniLight3D.new()
	door_light.name = "DoorLight_%d" % level_num
	door_light.light_color = Color(0.1, 0.9, 0.1) if is_unlocked else Color(0.9, 0.1, 0.05)
	door_light.light_energy = 1.5
	door_light.omni_range = 6.0
	door_light.omni_attenuation = 2.0
	door_light.shadow_enabled = false
	door_light.position = pos + Vector3(0.0, WALL_HEIGHT * 0.9, 0.0)
	_lighting_root.add_child(door_light)

	_level_doors[level_num] = body

	# Connect hub_door_unlocked signal to refresh this door
	if not EventBus.hub_door_unlocked.is_connected(_on_door_unlocked):
		EventBus.hub_door_unlocked.connect(_on_door_unlocked)


func _on_door_unlocked(level_number: int) -> void:
	if not _level_doors.has(level_number):
		return
	var door_body: StaticBody3D = _level_doors[level_number]
	if not is_instance_valid(door_body):
		return

	door_body.set_meta("is_unlocked", true)
	var level_data := LevelData.get_level(level_number)
	var level_name: String = level_data.get("name", "Level %d" % level_number)
	door_body.set_meta("interact_label", "Enter: %s [E]" % level_name)

	# Update door mesh material
	var mesh_inst := door_body.get_node_or_null("DoorMesh")
	if mesh_inst:
		mesh_inst.material_override = _mat_door_unlocked

	# Flash the door light
	var parent := door_body.get_parent()
	if parent:
		var door_light := _lighting_root.get_node_or_null("DoorLight_%d" % level_number)
		if door_light:
			door_light.light_color = Color(0.1, 0.9, 0.1)

# ---------------------------------------------------------------------------
# Shop — north side of hub
# ---------------------------------------------------------------------------

func _build_shop() -> void:
	# Shop alcove on the north wall
	var shop_x: float = 0.0
	var shop_z: float = -(FLOOR_SIZE * 0.35)

	# Shop counter
	var counter := CSGBox3D.new()
	counter.name = "ShopCounter"
	counter.size = Vector3(14.0, 1.2, 2.0)
	counter.position = Vector3(shop_x, 0.6, shop_z)
	counter.use_collision = true
	counter.collision_layer = ENVIRONMENT_LAYER
	counter.collision_mask = 0
	counter.material = _mat_shop
	_geometry_root.add_child(counter)

	# Shop backdrop wall panel
	var backdrop := CSGBox3D.new()
	backdrop.name = "ShopBackdrop"
	backdrop.size = Vector3(16.0, WALL_HEIGHT * 0.7, 0.3)
	backdrop.position = Vector3(shop_x, WALL_HEIGHT * 0.35, shop_z - 1.5)
	backdrop.use_collision = false
	backdrop.material = _mat_door_frame
	_geometry_root.add_child(backdrop)

	# "RELIC SHOP" sign above
	var sign := CSGBox3D.new()
	sign.name = "ShopSign"
	sign.size = Vector3(8.0, 1.0, 0.2)
	sign.position = Vector3(shop_x, WALL_HEIGHT * 0.72, shop_z - 1.2)
	sign.use_collision = false
	sign.material = _mat_accent
	_geometry_root.add_child(sign)

	# Shop interactive trigger
	var shop_body := StaticBody3D.new()
	shop_body.name = "ShopTrigger"
	shop_body.add_to_group("interactable")
	shop_body.add_to_group("hub_shop")
	shop_body.set_meta("interact_label", "Relic Shop [E]")
	shop_body.position = Vector3(shop_x, 0.6, shop_z)
	shop_body.collision_layer = ENVIRONMENT_LAYER
	shop_body.collision_mask = 0

	var shop_col := CollisionShape3D.new()
	var shop_shape := BoxShape3D.new()
	shop_shape.size = Vector3(14.0, 2.0, 4.0)
	shop_col.shape = shop_shape
	shop_body.add_child(shop_col)

	_geometry_root.add_child(shop_body)
	_shop_node = shop_body

	# Build relic display pedestals
	_build_relic_displays(shop_x, shop_z)

	# Shop lighting
	var shop_light := OmniLight3D.new()
	shop_light.name = "ShopLight"
	shop_light.light_color = Color(0.9, 0.75, 0.3)
	shop_light.light_energy = 2.0
	shop_light.omni_range = 12.0
	shop_light.omni_attenuation = 1.5
	shop_light.shadow_enabled = false
	shop_light.position = Vector3(shop_x, WALL_HEIGHT * 0.8, shop_z)
	_lighting_root.add_child(shop_light)


func _build_relic_displays(shop_x: float, shop_z: float) -> void:
	## Display 4 relics on pedestals above the counter
	var relics := RelicSystem.get_all_relics()
	var display_count := mini(4, relics.size())
	var spacing := 3.2
	var start_x := shop_x - (display_count - 1) * spacing * 0.5

	for i in range(display_count):
		var relic: Dictionary = relics[i]
		var dx := start_x + i * spacing
		var dz := shop_z - 0.4

		# Pedestal
		var ped := CSGCylinder3D.new()
		ped.name = "RelicPedestal_%d" % i
		ped.radius = 0.5
		ped.height = 1.3
		ped.sides = 8
		ped.position = Vector3(dx, 0.65, dz)
		ped.use_collision = false
		ped.material = _mat_pillar
		_geometry_root.add_child(ped)

		# Relic orb
		var relic_body := StaticBody3D.new()
		relic_body.name = "Relic_%s" % relic.get("id", "unknown")
		relic_body.add_to_group("interactable")
		relic_body.add_to_group("hub_relic")
		relic_body.set_meta("relic_id", relic.get("id", ""))
		var cost: int = relic.get("cost", 0)
		var relic_name: String = relic.get("name", "Relic")
		var desc: String = relic.get("description", "")
		var current_stack: int = GameManager.player_relics.get(relic.get("id", ""), 0)
		var max_stack: int = relic.get("max_stack", 1)
		var label: String = "%s — %dg [%d/%d]\n%s" % [relic_name, cost, current_stack, max_stack, desc]
		relic_body.set_meta("interact_label", label + " [E to buy]")
		relic_body.position = Vector3(dx, 1.65, dz)
		relic_body.collision_layer = ENVIRONMENT_LAYER
		relic_body.collision_mask = 0

		# Orb mesh
		var mesh_inst := MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.35
		sphere_mesh.height = 0.7
		mesh_inst.mesh = sphere_mesh

		# Color by rarity
		var rarity := RelicSystem.get_rarity(relic.get("id", ""))
		var orb_mat := StandardMaterial3D.new()
		match rarity:
			"MYTHIC":
				orb_mat.albedo_color = Color(0.8, 0.1, 0.8)
				orb_mat.emission = Color(0.6, 0.05, 0.6)
			"RARE":
				orb_mat.albedo_color = Color(0.1, 0.3, 0.9)
				orb_mat.emission = Color(0.05, 0.2, 0.7)
			_:
				orb_mat.albedo_color = Color(0.1, 0.7, 0.1)
				orb_mat.emission = Color(0.05, 0.5, 0.05)
		orb_mat.emission_enabled = true
		orb_mat.emission_energy_multiplier = 1.2
		orb_mat.roughness = 0.2
		orb_mat.metallic = 0.3
		mesh_inst.material_override = orb_mat
		relic_body.add_child(mesh_inst)

		# Collision
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.5
		col.shape = shape
		relic_body.add_child(col)

		_geometry_root.add_child(relic_body)

		# Floating bob
		var tween := create_tween().set_loops()
		tween.tween_property(relic_body, "position:y", 1.85, 1.2).set_trans(Tween.TRANS_SINE)
		tween.tween_property(relic_body, "position:y", 1.65, 1.2).set_trans(Tween.TRANS_SINE)


func _refresh_shop_display() -> void:
	# Remove and rebuild relic display pedestals
	for child in _geometry_root.get_children():
		if child.name.begins_with("RelicPedestal_") or child.name.begins_with("Relic_"):
			child.queue_free()
	await get_tree().process_frame
	var shop_x: float = 0.0
	var shop_z: float = -(FLOOR_SIZE * 0.35)
	_build_relic_displays(shop_x, shop_z)

# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------

func _build_lighting() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.01, 0.04)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.10, 0.25)
	env.ambient_light_energy = 0.40

	env.tonemap_mode = Environment.TONE_MAP_FILMIC
	env.tonemap_exposure = 1.0

	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.04, 0.10)
	env.fog_density = 0.005
	env.fog_light_energy = 0.4

	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	world_env.environment = env
	_lighting_root.add_child(world_env)

	# Central ambient light
	var central_light := OmniLight3D.new()
	central_light.name = "CentralLight"
	central_light.light_color = Color(0.5, 0.4, 0.8)
	central_light.light_energy = 1.5
	central_light.omni_range = 30.0
	central_light.omni_attenuation = 1.2
	central_light.shadow_enabled = false
	central_light.position = Vector3(0.0, WALL_HEIGHT * 0.7, 0.0)
	_lighting_root.add_child(central_light)

	# Dim directional fill light
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "FillLight"
	dir_light.light_color = Color(0.3, 0.25, 0.4)
	dir_light.light_energy = 0.2
	dir_light.shadow_enabled = false
	dir_light.rotation_degrees = Vector3(-45, 0, 0)
	_lighting_root.add_child(dir_light)

	# Corner torches
	var torch_positions := [
		Vector3(FLOOR_SIZE * 0.35, WALL_HEIGHT * 0.5, FLOOR_SIZE * 0.35),
		Vector3(-FLOOR_SIZE * 0.35, WALL_HEIGHT * 0.5, FLOOR_SIZE * 0.35),
		Vector3(FLOOR_SIZE * 0.35, WALL_HEIGHT * 0.5, -FLOOR_SIZE * 0.35),
		Vector3(-FLOOR_SIZE * 0.35, WALL_HEIGHT * 0.5, -FLOOR_SIZE * 0.35),
	]
	for i in range(torch_positions.size()):
		var torch_light := OmniLight3D.new()
		torch_light.name = "TorchLight_%d" % i
		torch_light.light_color = Color(0.9, 0.5, 0.1)
		torch_light.light_energy = 1.2
		torch_light.omni_range = 16.0
		torch_light.omni_attenuation = 2.0
		torch_light.shadow_enabled = false
		torch_light.position = torch_positions[i]
		_lighting_root.add_child(torch_light)
