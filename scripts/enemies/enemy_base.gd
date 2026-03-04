class_name EnemyBase
extends CharacterBody3D
## Base class for all enemies. Handles health, movement toward player, death,
## EXP/pickup drops, knockback, damage flash, and stat scaling per wave.
##
## Visual system: uses a SpriteBillboard child for DOOM-style 2D sprites that
## rotate to show the correct directional frame based on camera angle.
## Subclasses configure the sprite via _get_sprite_texture() and related virtuals.

# ---------------------------------------------------------------------------
# Stats (override in subclasses)
# ---------------------------------------------------------------------------

@export var max_health: float = 30.0
@export var base_damage: float = 8.0
@export var speed: float = 4.5
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 0.8
@export var base_exp_drop: float = 10.0

# ---------------------------------------------------------------------------
# Wave scaling multipliers (set by wave_manager via initialize())
# ---------------------------------------------------------------------------

var wave_hp_mult: float = 1.0
var wave_dmg_mult: float = 1.0
var wave_speed_mult: float = 1.0

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var health: float = 30.0
var is_alive: bool = true
var slow_mult: float = 1.0       ## Reduced by frost aura (0.0 .. 1.0)
var damage_amp: float = 1.0      ## Increased by damage-amplification abilities

var _attack_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flash_timer: float = 0.0
var _player: Node3D = null

# ---------------------------------------------------------------------------
# Visual references
# ---------------------------------------------------------------------------

## Legacy reference kept for compatibility with subclasses that animate it.
## When using sprites this is null; subclasses should check before using.
var _mesh: Node3D = null

## The DOOM-style billboard sprite (always created in _ready).
var _sprite_billboard: SpriteBillboard = null

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const KNOCKBACK_FRICTION := 8.0
const FLASH_DURATION := 0.1
const GRAVITY := 9.8
const HEALTH_DROP_CHANCE := 0.08
const AMMO_DROP_CHANCE := 0.12
const BOMB_AMMO_DROP_CHANCE := 0.04
const BASE_GOLD_DROP_CHANCE := 0.15
const BASE_GOLD_AMOUNT := 5

# ---------------------------------------------------------------------------
# Virtual helpers – override in subclasses for sprite configuration
# ---------------------------------------------------------------------------

## Override to supply a Texture2D loaded from the enemy's sprite sheet.
## Return null to use the procedural colored-quad fallback.
func _get_sprite_texture() -> Texture2D:
	return null

## Override to set how many directional rows the sprite sheet has (4 or 8).
func _get_sprite_num_directions() -> int:
	return 8

## Override to set how many animation frames (columns) each direction row has.
func _get_sprite_frames_per_dir() -> int:
	return 1

## Override to set the sprite centre height above the enemy origin.
func _get_sprite_height() -> float:
	return 0.9

## Override to set the animation playback speed in frames per second.
func _get_sprite_fps() -> float:
	return 8.0

## Override to control whether left-side directions mirror right-side rows.
func _get_sprite_use_mirror() -> bool:
	return true

## Override to return the pixel_size passed to SpriteBillboard.
## Larger values = bigger sprite in world space.
func _get_sprite_pixel_size() -> float:
	return 0.005

## Override to return the tint/modulate color used as enemy color reference
## (also used for the procedural fallback quad).
func _get_enemy_color() -> Color:
	return Color(1.0, 0.3, 0.3)

# ---------------------------------------------------------------------------
# Legacy virtual helpers (kept so boss subclasses still compile)
# ---------------------------------------------------------------------------

## Legacy mesh creation — no longer used for regular enemies.
## Kept so boss subclasses that still build CSG geometry can override it.
func _create_mesh() -> Node3D:
	return null

func _create_collision_shape() -> Shape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.2, 0.8)
	return box

func _get_collision_offset() -> Vector3:
	return Vector3(0.0, 0.6, 0.0)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("enemies")
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# -- Collision layers/masks ------------------------------------------
	collision_layer = 4    # Layer 3 (bit 2 = value 4) — Enemies
	collision_mask = 1 | 2 | 8 | 32

	# -- Collision shape -------------------------------------------------
	var col_shape := CollisionShape3D.new()
	col_shape.shape = _create_collision_shape()
	col_shape.position = _get_collision_offset()
	add_child(col_shape)

	# -- Sprite billboard -----------------------------------------------
	_sprite_billboard = SpriteBillboard.new()
	_sprite_billboard.pixel_size = _get_sprite_pixel_size()

	var tex := _get_sprite_texture()
	if tex != null:
		_sprite_billboard.setup(
			self,
			tex,
			_get_sprite_num_directions(),
			_get_sprite_frames_per_dir(),
			_get_sprite_height(),
			_get_sprite_fps(),
			_get_sprite_use_mirror())
	else:
		_sprite_billboard.setup_colored(self, _get_enemy_color(), _get_sprite_height())

	add_child(_sprite_billboard)

	# -- Legacy mesh (subclasses that override _create_mesh still work) --
	_mesh = _create_mesh()
	if _mesh != null:
		add_child(_mesh)

	# -- Apply scaled stats ----------------------------------------------
	health = max_health * wave_hp_mult
	_attack_timer = 0.0

	# -- Find player reference -------------------------------------------
	_find_player()


func _find_player() -> void:
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D
	else:
		var root := get_tree().current_scene
		if root:
			for child in root.get_children():
				if child is CharacterBody3D and child.collision_layer & 2:
					_player = child
					break

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func initialize(hp_mult: float, dmg_mult: float, spd_mult: float) -> void:
	wave_hp_mult = hp_mult
	wave_dmg_mult = dmg_mult
	wave_speed_mult = spd_mult
	health = max_health * wave_hp_mult


func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if not is_alive:
		return

	var final_amount := amount * damage_amp
	health -= final_amount

	# -- Knockback -------------------------------------------------------
	if knockback_dir != Vector3.ZERO:
		_knockback_velocity = knockback_dir.normalized() * clampf(final_amount * 0.5, 2.0, 15.0)

	# -- Damage flash ----------------------------------------------------
	_flash_timer = FLASH_DURATION
	if _sprite_billboard:
		_sprite_billboard.flash_white(FLASH_DURATION)
		_sprite_billboard.trigger_hurt()

	# -- Emit damage signal ----------------------------------------------
	EventBus.enemy_damaged.emit(self, final_amount)
	EventBus.damage_dealt.emit(final_amount, global_position + Vector3(0, 1.0, 0), false)

	# -- Death check -----------------------------------------------------
	if health <= 0.0:
		die()


func die() -> void:
	if not is_alive:
		return
	is_alive = false

	if _sprite_billboard:
		_sprite_billboard.trigger_death()

	# -- Drop EXP --------------------------------------------------------
	var exp_amount := base_exp_drop * wave_hp_mult
	_drop_exp(exp_amount)

	# -- Chance-based drops ----------------------------------------------
	if randf() < HEALTH_DROP_CHANCE:
		_drop_health()
	if randf() < AMMO_DROP_CHANCE:
		_drop_ammo()
	if randf() < BOMB_AMMO_DROP_CHANCE:
		_drop_bomb_ammo()
	_try_drop_gold()

	# -- Signals ---------------------------------------------------------
	EventBus.enemy_killed.emit(self, global_position)

	# -- Remove from scene -----------------------------------------------
	_on_death_effects()
	queue_free()

# ---------------------------------------------------------------------------
# Drops
# ---------------------------------------------------------------------------

func _drop_exp(amount: float) -> void:
	EventBus.exp_dropped.emit(global_position, amount)
	var parent := get_tree().current_scene
	if parent and parent.has_method("get_pickup_container"):
		parent = parent.get_pickup_container()
	elif parent == null:
		return
	Pickup.create_exp_drop(parent, global_position + Vector3(0, 0.5, 0), amount)


func _drop_health() -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	Pickup.create_health_drop(parent, global_position + Vector3(0, 0.5, 0), 15.0)


func _drop_ammo() -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	Pickup.create_ammo_drop(parent, global_position + Vector3(0, 0.5, 0))


func _drop_bomb_ammo() -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	Pickup.create_bomb_ammo_drop(parent, global_position + Vector3(0, 0.5, 0))


func _try_drop_gold() -> void:
	var luck: float = GameManager.get_trait("luck")
	var gold_chance := BASE_GOLD_DROP_CHANCE + luck * 0.05
	if randf() < gold_chance:
		var gold_amount := int(BASE_GOLD_AMOUNT * (1.0 + luck * 0.25))
		var parent := get_tree().current_scene
		if parent == null:
			return
		Pickup.create_gold_drop(parent, global_position + Vector3(0, 0.5, 0), gold_amount)

# ---------------------------------------------------------------------------
# Death FX (override for custom explosions etc.)
# ---------------------------------------------------------------------------

func _on_death_effects() -> void:
	pass

# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# -- Flash timer (legacy — billboard handles its own flash) ----------
	_flash_timer = maxf(_flash_timer - delta, 0.0)

	# -- Gravity ---------------------------------------------------------
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# -- Knockback decay -------------------------------------------------
	if _knockback_velocity.length() > 0.1:
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	# -- Movement toward player ------------------------------------------
	var move_dir := Vector3.ZERO
	if _player and is_instance_valid(_player):
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()

		if dist > attack_range * 0.8:
			move_dir = to_player.normalized()

		# -- Face the player ---------------------------------------------
		if to_player.length() > 0.1:
			var look_target := global_position + Vector3(to_player.x, 0, to_player.z)
			look_at(look_target, Vector3.UP)

		# -- Update sprite walk state ------------------------------------
		if _sprite_billboard:
			if dist > attack_range * 0.8:
				_sprite_billboard.set_walking()

	# Apply movement with slow_mult
	var effective_speed := speed * wave_speed_mult * slow_mult
	var horizontal := move_dir * effective_speed + Vector3(_knockback_velocity.x, 0, _knockback_velocity.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	# -- Attack logic ----------------------------------------------------
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_handle_attack(delta)

# ---------------------------------------------------------------------------
# Virtual attack handler – override in subclasses
# ---------------------------------------------------------------------------

func _handle_attack(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var dist := global_position.distance_to(_player.global_position)
	if dist <= attack_range:
		var effective_damage := base_damage * wave_dmg_mult
		if _player.has_method("take_damage"):
			_player.take_damage(effective_damage, self)
		_attack_timer = attack_cooldown
		if _sprite_billboard:
			_sprite_billboard.trigger_attack()

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func get_health_ratio() -> float:
	var mhp := max_health * wave_hp_mult
	return health / mhp if mhp > 0.0 else 0.0


func get_player() -> Node3D:
	return _player
