extends Node3D
## Manages equipped weapons, switching, firing, and first-person weapon display.
## Attached as a child of the player node. Supports up to 6 weapon slots.

# ── Constants ──────────────────────────────────────────────────────────────────
const MAX_WEAPONS := 6
const HITSCAN_RANGE := 100.0
const MUZZLE_FLASH_DURATION := 0.06
const WEAPON_BOB_SPEED := 12.0
const WEAPON_BOB_AMOUNT := 0.015
const SWIPE_THRESHOLD := 60.0  # Minimum pixels for a swipe to register

# Weapon sway constants
const WEAPON_SWAY_AMOUNT := 0.003
const WEAPON_SWAY_RETURN_SPEED := 6.0

# Recoil constant (tunable per weapon via weapon data override)
const RECOIL_AMOUNT := 0.02

# Hitscan weapon ids -- these use raycasts instead of projectiles
const HITSCAN_WEAPONS: Array[String] = ["railgun"]

# ── Exported ───────────────────────────────────────────────────────────────────
@export var projectile_scene_path: String = "res://scripts/weapons/projectile.gd"

# ── State ──────────────────────────────────────────────────────────────────────
var weapons: Array[Dictionary] = []
var current_weapon_index: int = 0
var fire_cooldown: float = 0.0
var bob_time: float = 0.0
var is_firing: bool = false  # For mobile auto-fire

# Minigun spin-up tracking
var spinup_factor: float = 0.0  # 0.0 = cold, 1.0 = fully spun-up
const SPINUP_RATE := 1.5  # Seconds to full spin-up
const SPINDOWN_RATE := 2.0  # Seconds to spin down

# Touch tracking for swipe detection
var _touch_start_pos: Vector2 = Vector2.ZERO
var _touch_start_time: float = 0.0
var _tracking_touch_index: int = -1

# Weapon sway state
var _sway_offset: Vector2 = Vector2.ZERO

# Recoil kick-back state
var _recoil_kick: float = 0.0

# ── Node references (created at runtime) ───────────────────────────────────────
var weapon_pivot: Node3D  # Holds the visual weapon mesh, positioned bottom-right
var weapon_mesh: Node3D  # The current weapon's CSG visual
var muzzle_point: Marker3D  # Where projectiles spawn / raycasts originate
var muzzle_flash_light: OmniLight3D
var raycast: RayCast3D

# Cached parent reference
var _player: CharacterBody3D


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_build_weapon_display()
	_build_raycast()

	# Connect to upgrade system events
	EventBus.weapon_acquired.connect(add_weapon)
	EventBus.weapon_upgraded.connect(_on_weapon_upgraded)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	# Weapon bob
	_update_weapon_bob(delta)

	# Weapon sway
	_update_weapon_sway(delta)

	# Recoil kick-back recovery
	_update_recoil_kick(delta)

	# Muzzle flash timer
	if muzzle_flash_light and muzzle_flash_light.visible:
		muzzle_flash_light.light_energy -= delta / MUZZLE_FLASH_DURATION * 2.0
		if muzzle_flash_light.light_energy <= 0.0:
			muzzle_flash_light.visible = false

	# Fire cooldown
	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# Minigun spin-up / spin-down
	_update_spinup(delta)

	# Mobile auto-fire: fires while the right side of the screen is held
	if is_firing and can_fire():
		fire()


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return

	# ── Desktop: mouse wheel weapon switch ──
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				switch_weapon(-1)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				switch_weapon(1)
				get_viewport().set_input_as_handled()

	# ── Accumulate look delta for weapon sway ──
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_sway_offset.x = clampf(_sway_offset.x - motion.relative.x * WEAPON_SWAY_AMOUNT, -0.05, 0.05)
		_sway_offset.y = clampf(_sway_offset.y - motion.relative.y * WEAPON_SWAY_AMOUNT, -0.05, 0.05)

	# ── Desktop: shoot action ──
	if event.is_action_pressed("shoot"):
		is_firing = true
	elif event.is_action_released("shoot"):
		is_firing = false

	# ── Mobile: touch handling ──
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var screen_size := get_viewport().get_visible_rect().size
		var is_right_side := touch.position.x > screen_size.x * 0.5

		if touch.pressed:
			if is_right_side:
				# Right side: start auto-fire and track for swipe
				is_firing = true
				_touch_start_pos = touch.position
				_touch_start_time = Time.get_ticks_msec() / 1000.0
				_tracking_touch_index = touch.index
			# Left side is handled by the player movement joystick
		else:
			if touch.index == _tracking_touch_index:
				is_firing = false
				# Check for vertical swipe to switch weapon
				var swipe_delta := touch.position - _touch_start_pos
				if absf(swipe_delta.y) > SWIPE_THRESHOLD and absf(swipe_delta.y) > absf(swipe_delta.x):
					if swipe_delta.y < 0:
						switch_weapon(-1)  # Swipe up = previous weapon
					else:
						switch_weapon(1)  # Swipe down = next weapon
				_tracking_touch_index = -1


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

func add_weapon(weapon_data: Dictionary) -> void:
	if weapons.size() >= MAX_WEAPONS:
		return
	# Deep copy so we own the data
	var data := weapon_data.duplicate(true)
	weapons.append(data)
	# Auto-equip first weapon
	if weapons.size() == 1:
		current_weapon_index = 0
		_refresh_weapon_visual()


func fire() -> void:
	if weapons.is_empty():
		return
	if not can_fire():
		return

	var weapon := get_current_weapon()
	if weapon.is_empty():
		return

	# Ammo consumption: check if weapon uses an ammo type
	var ammo_type: String = weapon.get("ammo_type", "")
	if ammo_type != "":
		if not GameManager.consume_ammo(ammo_type, 1):
			return  # No ammo available -- don't fire

	# Calculate actual fire rate with trait modifier
	var base_fire_rate: float = weapon.get("fire_rate", 0.3)
	var fire_rate_mult: float = GameManager.player_traits.get("fire_rate_mult", 1.0)

	# Minigun spin-up: fire rate scales from 3x base down to base at full spin
	if weapon.get("spinup", false):
		var spinup_mult := lerpf(3.0, 1.0, spinup_factor)
		fire_cooldown = base_fire_rate * spinup_mult / fire_rate_mult
	else:
		fire_cooldown = base_fire_rate / fire_rate_mult

	# Determine pellet count (shotgun fires multiple)
	var pellet_count: int = weapon.get("pellets", 1)

	# Fire each pellet (ammo was already consumed once above for the whole trigger pull)
	for i in pellet_count:
		_fire_single_pellet(weapon)

	# Play muzzle flash
	_trigger_muzzle_flash(weapon.get("color", Color.WHITE))

	# Play sound effect
	AudioManager.play_sfx("shoot_" + weapon.get("id", "generic"), -5.0, 1.0)

	# Recoil / camera shake
	var recoil_amount: float = weapon.get("recoil_amount", RECOIL_AMOUNT)
	if _player and _player.has_method("apply_recoil"):
		_player.apply_recoil(recoil_amount)

	# Visual weapon kick-back
	_recoil_kick = recoil_amount * 5.0


func switch_weapon(direction: int) -> void:
	if weapons.size() <= 1:
		return
	# Reset spinup on switch
	spinup_factor = 0.0
	current_weapon_index = wrapi(current_weapon_index + direction, 0, weapons.size())
	_refresh_weapon_visual()


func get_current_weapon() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[current_weapon_index]


func can_fire() -> bool:
	if weapons.is_empty():
		return false
	if fire_cooldown > 0.0:
		return false
	return true


# ══════════════════════════════════════════════════════════════════════════════
# Firing logic
# ══════════════════════════════════════════════════════════════════════════════

func _fire_single_pellet(weapon: Dictionary) -> void:
	# Apply spread
	var spread_deg: float = weapon.get("spread", 0.0)
	var spread_rad := deg_to_rad(spread_deg)
	var spread_offset := Vector3(
		randf_range(-spread_rad, spread_rad),
		randf_range(-spread_rad, spread_rad),
		0.0
	)

	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return

	var fire_direction: Vector3 = -cam.global_basis.z
	fire_direction = fire_direction.rotated(cam.global_basis.x, spread_offset.y)
	fire_direction = fire_direction.rotated(cam.global_basis.y, spread_offset.x)
	fire_direction = fire_direction.normalized()

	var weapon_id: String = weapon.get("id", "")
	var is_hitscan := weapon_id in HITSCAN_WEAPONS

	if is_hitscan:
		_fire_hitscan(weapon, cam.global_position, fire_direction)
	else:
		_fire_projectile(weapon, fire_direction)


func _fire_hitscan(weapon: Dictionary, origin: Vector3, direction: Vector3) -> void:
	# Railgun-style: pierces through multiple enemies
	var pierce_count: int = weapon.get("pierce", 1)
	var damage := _calculate_damage(weapon)

	# Use a physics query to find all bodies along the ray
	var space_state := get_world_3d().direct_space_state
	var end_pos := origin + direction * HITSCAN_RANGE
	var current_origin := origin
	var enemies_hit: int = 0
	var exclude: Array[RID] = []

	while enemies_hit < pierce_count:
		var query := PhysicsRayQueryParameters3D.create(current_origin, end_pos)
		# Mask: Enemies (layer 3) + Environment (layer 1)
		query.collision_mask = 0b000101  # Layers 1 and 3
		query.exclude = exclude

		var result := space_state.intersect_ray(query)
		if result.is_empty():
			break

		var hit_body: Node3D = result["collider"]
		var hit_pos: Vector3 = result["position"]
		exclude.append(result["rid"])

		if _is_enemy(hit_body):
			var is_crit := _roll_crit(weapon)
			var final_damage := damage
			if is_crit:
				var crit_mult: float = GameManager.player_traits.get("crit_damage", 1.5) + weapon.get("crit_bonus", 0.0)
				final_damage *= crit_mult

			_apply_damage_to_enemy(hit_body, final_damage, is_crit, hit_pos)
			_apply_armor_pierce(hit_body, weapon)
			enemies_hit += 1
			current_origin = hit_pos + direction * 0.1
		else:
			# Hit environment -- stop
			break

	# Draw the rail beam visual
	_draw_hitscan_trail(origin, current_origin if enemies_hit > 0 else end_pos, weapon.get("color", Color.MAGENTA))


func _fire_projectile(weapon: Dictionary, direction: Vector3) -> void:
	var muzzle_pos := muzzle_point.global_position if muzzle_point else global_position

	# Create projectile node at runtime (no .tscn required)
	var projectile := _create_projectile_node(weapon, direction, muzzle_pos)
	# Add to the scene tree at root level so it persists when player moves
	get_tree().current_scene.add_child(projectile)


func _create_projectile_node(weapon: Dictionary, direction: Vector3, spawn_pos: Vector3) -> Node3D:
	# Build projectile from the projectile script
	var projectile := Area3D.new()
	projectile.name = "Projectile"
	projectile.global_position = spawn_pos
	projectile.collision_layer = 32  # Layer 6: PlayerProjectiles
	projectile.collision_mask = 0b000101  # Layers 1 (Environment) + 3 (Enemies)

	# Attach the projectile script
	var script := load("res://scripts/weapons/projectile.gd") as GDScript
	if script:
		projectile.set_script(script)

	# Pass weapon data to the projectile after adding script
	projectile.set("direction", direction)
	projectile.set("speed", weapon.get("projectile_speed", 30.0))
	projectile.set("damage", _calculate_damage(weapon))
	projectile.set("weapon_data", weapon.duplicate(true))
	projectile.set("is_crit", _roll_crit(weapon))
	projectile.set("weapon_color", weapon.get("color", Color.WHITE))

	return projectile


# ══════════════════════════════════════════════════════════════════════════════
# Damage calculation
# ══════════════════════════════════════════════════════════════════════════════

func _calculate_damage(weapon: Dictionary) -> float:
	var base_damage: float = weapon.get("damage", 10.0)
	var level: int = weapon.get("level", 1)
	var level_mult: float = 1.0 + (level - 1) * 0.25
	var damage_mult: float = GameManager.player_traits.get("damage_mult", 1.0)
	return base_damage * level_mult * damage_mult


func _roll_crit(weapon: Dictionary) -> bool:
	var crit_chance: float = GameManager.player_traits.get("crit_chance", 0.05)
	return randf() < crit_chance


func _apply_damage_to_enemy(enemy: Node3D, damage: float, is_crit: bool, hit_pos: Vector3) -> void:
	# Call enemy's take_damage if it exists
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	# Emit combat events
	EventBus.enemy_damaged.emit(enemy, damage)
	EventBus.damage_dealt.emit(damage, hit_pos, is_crit)


func _apply_armor_pierce(enemy: Node3D, weapon: Dictionary) -> void:
	var armor_pierce: float = weapon.get("armor_pierce", 0.0)
	if armor_pierce > 0.0 and enemy.has_method("reduce_armor"):
		enemy.reduce_armor(armor_pierce)


func _is_enemy(node: Node3D) -> bool:
	# Check if the node is on the Enemies physics layer (layer 3)
	if node is PhysicsBody3D:
		return (node as PhysicsBody3D).collision_layer & 4 != 0  # Bit 2 = layer 3
	return node.is_in_group("enemies")


# ══════════════════════════════════════════════════════════════════════════════
# Spin-up (minigun)
# ══════════════════════════════════════════════════════════════════════════════

func _update_spinup(delta: float) -> void:
	var weapon := get_current_weapon()
	if weapon.is_empty():
		return
	if weapon.get("spinup", false):
		if is_firing:
			spinup_factor = minf(spinup_factor + delta / SPINUP_RATE, 1.0)
		else:
			spinup_factor = maxf(spinup_factor - delta / SPINDOWN_RATE, 0.0)
	else:
		spinup_factor = 0.0


# ══════════════════════════════════════════════════════════════════════════════
# Weapon sway
# ══════════════════════════════════════════════════════════════════════════════

func _update_weapon_sway(delta: float) -> void:
	if weapon_pivot == null:
		return

	# Smoothly return sway offset to zero when not looking
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, delta * WEAPON_SWAY_RETURN_SPEED)

	# Apply sway as rotation on the weapon pivot
	weapon_pivot.rotation.y = _sway_offset.x
	weapon_pivot.rotation.x = _sway_offset.y


# ══════════════════════════════════════════════════════════════════════════════
# Recoil kick-back visual
# ══════════════════════════════════════════════════════════════════════════════

func _update_recoil_kick(delta: float) -> void:
	if weapon_pivot == null:
		return

	# Smoothly recover kick-back to zero
	_recoil_kick = lerpf(_recoil_kick, 0.0, delta * 10.0)

	# Apply kick-back as a small upward + backward offset on weapon pivot position
	# Note: position.x and position.y base values are set by _update_weapon_bob;
	# we layer the kick on top additively here for the z-axis and y-axis.
	weapon_pivot.position.z = -0.45 + _recoil_kick
	weapon_pivot.position.y += _recoil_kick * 0.5


# ══════════════════════════════════════════════════════════════════════════════
# Visual construction (runtime -- no .tscn needed)
# ══════════════════════════════════════════════════════════════════════════════

func _build_weapon_display() -> void:
	# Weapon pivot: positioned at bottom-right of the first-person view
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	add_child(weapon_pivot)
	# Offset for a portrait-oriented FPS: bottom-right corner
	weapon_pivot.position = Vector3(0.25, -0.2, -0.45)

	# Muzzle point: front of the weapon barrel
	muzzle_point = Marker3D.new()
	muzzle_point.name = "MuzzlePoint"
	weapon_pivot.add_child(muzzle_point)
	muzzle_point.position = Vector3(0.0, 0.05, -0.3)

	# Muzzle flash light
	muzzle_flash_light = OmniLight3D.new()
	muzzle_flash_light.name = "MuzzleFlash"
	muzzle_point.add_child(muzzle_flash_light)
	muzzle_flash_light.light_energy = 0.0
	muzzle_flash_light.omni_range = 3.0
	muzzle_flash_light.visible = false

	# Default empty weapon mesh -- will be replaced by _refresh_weapon_visual
	weapon_mesh = null


func _build_raycast() -> void:
	raycast = RayCast3D.new()
	raycast.name = "WeaponRaycast"
	add_child(raycast)
	raycast.target_position = Vector3(0, 0, -HITSCAN_RANGE)
	raycast.collision_mask = 0b000101  # Layers 1 and 3
	raycast.enabled = false  # We use direct space state queries instead


func _refresh_weapon_visual() -> void:
	# Remove old mesh
	if weapon_mesh and is_instance_valid(weapon_mesh):
		weapon_mesh.queue_free()
		weapon_mesh = null

	var weapon := get_current_weapon()
	if weapon.is_empty():
		return

	var weapon_id: String = weapon.get("id", "")
	var weapon_color: Color = weapon.get("color", Color.WHITE)

	# Build a simple CSG-based weapon model
	weapon_mesh = Node3D.new()
	weapon_mesh.name = "WeaponModel_" + weapon_id
	weapon_pivot.add_child(weapon_mesh)

	# Material with weapon color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = weapon_color
	mat.emission_enabled = true
	mat.emission = weapon_color * 0.3
	mat.emission_energy_multiplier = 0.5

	match weapon_id:
		"pistol":
			_build_pistol_mesh(weapon_mesh, mat)
		"shotgun":
			_build_shotgun_mesh(weapon_mesh, mat)
		"smg":
			_build_smg_mesh(weapon_mesh, mat)
		"rocket_launcher":
			_build_launcher_mesh(weapon_mesh, mat)
		"plasma_rifle":
			_build_rifle_mesh(weapon_mesh, mat)
		"railgun":
			_build_railgun_mesh(weapon_mesh, mat)
		"minigun":
			_build_minigun_mesh(weapon_mesh, mat)
		"flamethrower":
			_build_flamethrower_mesh(weapon_mesh, mat)
		"crossbow":
			_build_crossbow_mesh(weapon_mesh, mat)
		"acid_gun":
			_build_acid_gun_mesh(weapon_mesh, mat)
		_:
			_build_pistol_mesh(weapon_mesh, mat)


# ── Weapon mesh builders (simple CSG primitives) ──

func _build_pistol_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Barrel
	var barrel := CSGBox3D.new()
	barrel.size = Vector3(0.04, 0.04, 0.2)
	barrel.material = mat
	parent.add_child(barrel)
	# Grip
	var grip := CSGBox3D.new()
	grip.size = Vector3(0.035, 0.1, 0.04)
	grip.position = Vector3(0, -0.06, 0.07)
	grip.material = mat
	parent.add_child(grip)


func _build_shotgun_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Wide barrel
	var barrel := CSGBox3D.new()
	barrel.size = Vector3(0.06, 0.05, 0.35)
	barrel.material = mat
	parent.add_child(barrel)
	# Stock
	var stock := CSGBox3D.new()
	stock.size = Vector3(0.04, 0.06, 0.12)
	stock.position = Vector3(0, -0.02, 0.2)
	stock.material = mat
	parent.add_child(stock)


func _build_smg_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Compact barrel
	var barrel := CSGBox3D.new()
	barrel.size = Vector3(0.035, 0.04, 0.22)
	barrel.material = mat
	parent.add_child(barrel)
	# Magazine
	var mag := CSGBox3D.new()
	mag.size = Vector3(0.025, 0.08, 0.03)
	mag.position = Vector3(0, -0.055, 0.05)
	mag.material = mat
	parent.add_child(mag)


func _build_launcher_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Large cylindrical barrel
	var barrel := CSGCylinder3D.new()
	barrel.radius = 0.04
	barrel.height = 0.35
	barrel.rotation_degrees.x = 90.0
	barrel.material = mat
	parent.add_child(barrel)
	# Grip
	var grip := CSGBox3D.new()
	grip.size = Vector3(0.04, 0.12, 0.05)
	grip.position = Vector3(0, -0.08, 0.1)
	grip.material = mat
	parent.add_child(grip)


func _build_rifle_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Sleek barrel
	var barrel := CSGBox3D.new()
	barrel.size = Vector3(0.04, 0.045, 0.3)
	barrel.material = mat
	parent.add_child(barrel)
	# Scope bump
	var scope := CSGBox3D.new()
	scope.size = Vector3(0.02, 0.025, 0.06)
	scope.position = Vector3(0, 0.035, -0.05)
	scope.material = mat
	parent.add_child(scope)


func _build_railgun_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Long barrel with rails
	var barrel := CSGBox3D.new()
	barrel.size = Vector3(0.035, 0.035, 0.4)
	barrel.material = mat
	parent.add_child(barrel)
	# Top rail
	var rail_top := CSGBox3D.new()
	rail_top.size = Vector3(0.01, 0.015, 0.35)
	rail_top.position = Vector3(0, 0.025, -0.02)
	rail_top.material = mat
	parent.add_child(rail_top)
	# Bottom rail
	var rail_bot := CSGBox3D.new()
	rail_bot.size = Vector3(0.01, 0.015, 0.35)
	rail_bot.position = Vector3(0, -0.025, -0.02)
	rail_bot.material = mat
	parent.add_child(rail_bot)


func _build_minigun_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Cluster of barrels
	for i in 3:
		var barrel := CSGCylinder3D.new()
		barrel.radius = 0.015
		barrel.height = 0.3
		barrel.rotation_degrees.x = 90.0
		var angle := float(i) * TAU / 3.0
		barrel.position = Vector3(cos(angle) * 0.025, sin(angle) * 0.025, 0)
		barrel.material = mat
		parent.add_child(barrel)
	# Housing
	var housing := CSGCylinder3D.new()
	housing.radius = 0.04
	housing.height = 0.08
	housing.rotation_degrees.x = 90.0
	housing.position = Vector3(0, 0, 0.12)
	housing.material = mat
	parent.add_child(housing)


func _build_flamethrower_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Wide nozzle
	var nozzle := CSGCylinder3D.new()
	nozzle.radius = 0.035
	nozzle.height = 0.25
	nozzle.rotation_degrees.x = 90.0
	nozzle.material = mat
	parent.add_child(nozzle)
	# Tank
	var tank := CSGCylinder3D.new()
	tank.radius = 0.03
	tank.height = 0.1
	tank.position = Vector3(0, -0.05, 0.12)
	tank.material = mat
	parent.add_child(tank)


func _build_crossbow_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Rail
	var rail := CSGBox3D.new()
	rail.size = Vector3(0.025, 0.03, 0.3)
	rail.material = mat
	parent.add_child(rail)
	# Limbs
	var limb := CSGBox3D.new()
	limb.size = Vector3(0.18, 0.015, 0.015)
	limb.position = Vector3(0, 0, -0.12)
	limb.material = mat
	parent.add_child(limb)


func _build_acid_gun_mesh(parent: Node3D, mat: StandardMaterial3D) -> void:
	# Bulbous barrel
	var barrel := CSGCylinder3D.new()
	barrel.radius = 0.03
	barrel.height = 0.25
	barrel.rotation_degrees.x = 90.0
	barrel.material = mat
	parent.add_child(barrel)
	# Canister
	var canister := CSGCylinder3D.new()
	canister.radius = 0.035
	canister.height = 0.08
	canister.position = Vector3(0, -0.04, 0.08)
	canister.material = mat
	parent.add_child(canister)


# ══════════════════════════════════════════════════════════════════════════════
# Effects
# ══════════════════════════════════════════════════════════════════════════════

func _trigger_muzzle_flash(color: Color) -> void:
	if muzzle_flash_light == null:
		return
	muzzle_flash_light.light_color = color
	muzzle_flash_light.light_energy = 2.5
	muzzle_flash_light.visible = true


func _draw_hitscan_trail(from: Vector3, to: Vector3, color: Color) -> void:
	# Create a temporary beam visual using a stretched CSGBox3D
	var beam := CSGBox3D.new()
	var distance := from.distance_to(to)
	beam.size = Vector3(0.02, 0.02, distance)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = color
	beam_mat.emission_enabled = true
	beam_mat.emission = color
	beam_mat.emission_energy_multiplier = 3.0
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color.a = 0.8
	beam.material = beam_mat
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at_from_position(beam.global_position, to, Vector3.UP)

	# Fade out and remove
	var tween := get_tree().create_tween()
	tween.tween_property(beam_mat, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(beam.queue_free)


func _update_weapon_bob(delta: float) -> void:
	if weapon_pivot == null:
		return

	# Bob based on player velocity
	var speed := 0.0
	if _player and _player is CharacterBody3D:
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()

	if speed > 0.5:
		bob_time += delta * WEAPON_BOB_SPEED
	else:
		bob_time = lerpf(bob_time, 0.0, delta * 5.0)

	var bob_x := sin(bob_time) * WEAPON_BOB_AMOUNT * 0.5
	var bob_y := sin(bob_time * 2.0) * WEAPON_BOB_AMOUNT
	weapon_pivot.position.x = 0.25 + bob_x
	weapon_pivot.position.y = -0.2 + bob_y


# ══════════════════════════════════════════════════════════════════════════════
# Signal callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_weapon_upgraded(weapon_id: String, new_level: int) -> void:
	for i in weapons.size():
		if weapons[i].get("id", "") == weapon_id:
			weapons[i]["level"] = new_level
			break
	# Refresh visual in case the active weapon was upgraded
	_refresh_weapon_visual()
