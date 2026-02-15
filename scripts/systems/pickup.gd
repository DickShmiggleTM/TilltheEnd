class_name Pickup
extends Area3D
## Collectible pickup for EXP orbs, health, ammo, and coins.
##
## EXP orbs are magnetically pulled toward the player when within the
## player's collect_range. All pickups bob up and down, have colored glow,
## and despawn after 30 seconds.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

const DESPAWN_TIME := 30.0
const BOB_SPEED := 3.0
const BOB_AMPLITUDE := 0.15
const MAGNETIC_ACCELERATION := 25.0
const MAX_ATTRACT_SPEED := 20.0
const COLLECT_DISTANCE := 0.6

# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------

var pickup_type: String = "exp"    ## "exp", "health", "ammo", "coin"
var value: float = 10.0
var attract_speed: float = 0.0

var _lifetime: float = DESPAWN_TIME
var _bob_time: float = 0.0
var _base_y: float = 0.0
var _mesh: Node3D = null
var _collected: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# -- Groups ----------------------------------------------------------
	if pickup_type == "exp":
		add_to_group("exp_pickups")
	add_to_group("pickups")

	# -- Collision -------------------------------------------------------
	collision_layer = 16   # Layer 5 (Pickups, bit 4 = value 16)
	collision_mask = 2     # Layer 2 (Player)

	# -- Collision shape -------------------------------------------------
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _get_collect_radius()
	col.shape = shape
	add_child(col)

	# -- Visual mesh -----------------------------------------------------
	_mesh = _create_visual()
	add_child(_mesh)

	# -- Store base height for bobbing -----------------------------------
	_base_y = position.y
	_bob_time = randf() * TAU  # Random phase so they don't bob in unison

	# -- Connect body entered signal -------------------------------------
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _collected:
		return

	# -- Despawn timer ---------------------------------------------------
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	# -- Bobbing ---------------------------------------------------------
	_bob_time += delta * BOB_SPEED
	if _mesh:
		_mesh.position.y = sin(_bob_time) * BOB_AMPLITUDE

	# -- Fade out near end of life (last 5 seconds) ----------------------
	if _lifetime < 5.0:
		var alpha := _lifetime / 5.0
		if _mesh is CSGPrimitive3D:
			var mat := (_mesh as CSGPrimitive3D).material as StandardMaterial3D
			if mat:
				mat.albedo_color.a = alpha

	# -- Magnetic attraction (EXP only, handled externally by player) ----
	# The player_controller._pull_nearby_exp() handles attraction.
	# This just provides the collect() method.

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func initialize(type: String, val: float, pos: Vector3) -> void:
	pickup_type = type
	value = val
	position = pos


func collect() -> void:
	if _collected:
		return
	_collected = true

	match pickup_type:
		"exp":
			EventBus.exp_collected.emit(value)
		"health":
			EventBus.health_collected.emit(value)
		"ammo":
			EventBus.ammo_collected.emit("bullet", int(value))
		"coin":
			EventBus.coin_collected.emit(int(value))

	queue_free()

# ---------------------------------------------------------------------------
# Static factory methods
# ---------------------------------------------------------------------------

static func create_exp_drop(parent: Node, position: Vector3, amount: float) -> void:
	# Split large EXP amounts into multiple smaller orbs
	var orb_count := 1
	var per_orb := amount
	if amount > 30.0:
		orb_count = mini(int(amount / 10.0), 5)
		per_orb = amount / float(orb_count)

	for i in orb_count:
		var pickup := Pickup.new()
		pickup.pickup_type = "exp"
		pickup.value = per_orb

		# Scatter slightly
		var offset := Vector3(
			randf_range(-0.5, 0.5),
			randf_range(0.0, 0.3),
			randf_range(-0.5, 0.5)
		)
		pickup.position = position + offset
		parent.call_deferred("add_child", pickup)


static func create_health_drop(parent: Node, position: Vector3, amount: float) -> void:
	var pickup := Pickup.new()
	pickup.pickup_type = "health"
	pickup.value = amount
	pickup.position = position
	parent.call_deferred("add_child", pickup)


static func create_ammo_drop(parent: Node, position: Vector3) -> void:
	var pickup := Pickup.new()
	pickup.pickup_type = "ammo"
	pickup.value = 10.0
	pickup.position = position
	parent.call_deferred("add_child", pickup)


static func create_coin_drop(parent: Node, position: Vector3, amount: int = 1) -> void:
	var pickup := Pickup.new()
	pickup.pickup_type = "coin"
	pickup.value = float(amount)
	pickup.position = position
	parent.call_deferred("add_child", pickup)

# ---------------------------------------------------------------------------
# Visual creation
# ---------------------------------------------------------------------------

func _create_visual() -> Node3D:
	var sphere := CSGSphere3D.new()
	var mat := StandardMaterial3D.new()

	match pickup_type:
		"exp":
			var size_factor := clampf(value / 20.0, 0.5, 1.5)
			sphere.radius = 0.15 * size_factor
			sphere.radial_segments = 8
			sphere.rings = 4
			mat.albedo_color = Color(0.3, 0.2, 0.9, 0.9)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.2, 1.0)
			mat.emission_energy_multiplier = 2.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		"health":
			sphere.radius = 0.2
			sphere.radial_segments = 8
			sphere.rings = 4
			mat.albedo_color = Color(0.1, 0.9, 0.2, 0.9)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 1.0, 0.3)
			mat.emission_energy_multiplier = 2.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		"ammo":
			sphere.radius = 0.18
			sphere.radial_segments = 8
			sphere.rings = 4
			mat.albedo_color = Color(1.0, 0.9, 0.1, 0.9)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.9, 0.2)
			mat.emission_energy_multiplier = 2.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

		"coin":
			sphere.radius = 0.16
			sphere.radial_segments = 8
			sphere.rings = 4
			mat.albedo_color = Color(1.0, 0.85, 0.0, 0.95)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.1)
			mat.emission_energy_multiplier = 3.0
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	sphere.material = mat
	return sphere


func _get_collect_radius() -> float:
	match pickup_type:
		"exp":
			return 0.5
		"health":
			return 0.7
		"ammo":
			return 0.7
		"coin":
			return 0.8
	return 0.5

# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	# Non-EXP pickups are collected on direct contact
	if pickup_type != "exp":
		if body.collision_layer & 2:  # Player layer
			collect()
