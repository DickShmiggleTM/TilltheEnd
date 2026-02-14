extends Node3D
## Floating damage number that appears in 3D world space.
## Floats upward and fades out over 0.8 seconds.
##
## Usage:
##   DamageNumber.create_damage_number(parent, position, amount, is_crit)
##   DamageNumber.create_heal_number(parent, position, amount)

class_name DamageNumber

# ── Configuration ────────────────────────────────────────────────────────────
const FLOAT_SPEED := 2.0
const FLOAT_DURATION := 0.8
const SPREAD_RANGE := 0.4  # Random horizontal spread

# ── State ────────────────────────────────────────────────────────────────────
var _label: Label3D
var _elapsed: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _initial_alpha: float = 1.0


func _ready() -> void:
	# Random horizontal offset for visual variety
	var offset := Vector3(
		randf_range(-SPREAD_RANGE, SPREAD_RANGE),
		0.0,
		randf_range(-SPREAD_RANGE, SPREAD_RANGE)
	)
	position += offset
	_velocity = Vector3(
		randf_range(-0.3, 0.3),
		FLOAT_SPEED,
		randf_range(-0.3, 0.3)
	)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= FLOAT_DURATION:
		queue_free()
		return

	# Float upward with deceleration
	position += _velocity * delta
	_velocity.y *= 0.97  # Gradual slowdown

	# Fade out
	var progress := _elapsed / FLOAT_DURATION
	if _label:
		var alpha := lerpf(_initial_alpha, 0.0, progress * progress)
		_label.modulate.a = alpha

		# Scale up slightly then back down
		var scale_factor := 1.0 + sin(progress * PI) * 0.3
		_label.pixel_size = _label.pixel_size  # Keep pixel_size, adjust font
		scale = Vector3.ONE * scale_factor


## Initialize this damage number with its visual properties.
func setup(amount: float, is_crit: bool, is_heal: bool = false) -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.01
	_label.render_priority = 100

	if is_heal:
		_label.text = "+%d" % ceili(amount)
		_label.modulate = Color(0.2, 1.0, 0.3, 1.0)
		_label.font_size = 48
		_label.outline_modulate = Color(0.0, 0.4, 0.1, 1.0)
	elif is_crit:
		_label.text = "%d!" % ceili(amount)
		_label.modulate = Color(1.0, 0.9, 0.1, 1.0)
		_label.font_size = 72
		_label.outline_modulate = Color(0.8, 0.4, 0.0, 1.0)
		# Crits float faster and last slightly longer
		_velocity.y *= 1.3
	else:
		_label.text = "%d" % ceili(amount)
		_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_label.font_size = 48
		_label.outline_modulate = Color(0.3, 0.0, 0.0, 1.0)

	_label.outline_size = 8
	_initial_alpha = _label.modulate.a
	add_child(_label)


# ── Static factory methods ───────────────────────────────────────────────────

## Create a floating damage number in the 3D world.
## parent: Node to add the damage number to (usually get_tree().current_scene)
## pos: World position where the number appears
## amount: Damage value to display
## is_crit: If true, shows larger yellow/gold text
static func create_damage_number(parent: Node, pos: Vector3, amount: float, is_crit: bool) -> DamageNumber:
	var instance := DamageNumber.new()
	instance.position = pos
	instance.setup(amount, is_crit, false)
	parent.add_child(instance)
	return instance


## Create a floating heal number in the 3D world.
## parent: Node to add the number to
## pos: World position where the number appears
## amount: Heal value to display
static func create_heal_number(parent: Node, pos: Vector3, amount: float) -> DamageNumber:
	var instance := DamageNumber.new()
	instance.position = pos
	instance.setup(amount, false, true)
	parent.add_child(instance)
	return instance
