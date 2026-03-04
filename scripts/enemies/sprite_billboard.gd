class_name SpriteBillboard
extends Node3D
## DOOM-style directional billboard sprite for enemies.
##
## Attaches to an enemy CharacterBody3D. The Sprite3D always faces the camera
## (billboard mode), while the displayed frame (row in the sprite sheet) is
## chosen based on the angle between the enemy's forward direction and the
## vector toward the camera. This gives 4- or 8-directional depth without
## true 3D geometry.
##
## Sprite sheet convention (rows × columns):
##   rows   = num_directions (or num_unique_rows for mirrored sheets)
##   cols   = frames_per_direction  (animation frames per direction)
##   row 0  = front  (camera directly ahead of enemy — enemy faces camera)
##   row 1  = front-right / right  (8-dir: front-right; 4-dir: right)
##   row 2  = right / back          (8-dir: right;        4-dir: back)
##   row 3  = back-right / left     (8-dir: back-right;   4-dir: left [OR mirror row 1])
##   row 4  = back                  (8-dir only)
##   rows 5-7 are mirrored from rows 3-1 — only needed if use_mirror=false
##
## With use_mirror=true (default), a 5-row sheet covers all 8 directions.
## With use_mirror=false, the sheet must have one row per direction.

signal direction_changed(new_direction: int)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

## Directional views in the sprite sheet: 4 or 8.
var num_directions: int = 8

## Animation frames per direction (columns in the sprite sheet).
var frames_per_direction: int = 1

## Playback speed in frames per second for looping animations.
var animation_fps: float = 8.0

## Height above the enemy origin where the sprite center is placed.
var height_offset: float = 0.9

## World units per pixel. Smaller = smaller sprite on screen.
var pixel_size: float = 0.005

## When true, left-side directions (dirs 5-7 for 8-dir, dir 3 for 4-dir)
## are rendered by mirroring the corresponding right-side row. This halves
## the number of rows required in the sprite sheet.
var use_mirror: bool = true

# ---------------------------------------------------------------------------
# Internal nodes
# ---------------------------------------------------------------------------

var _sprite: Sprite3D = null
var _camera: Camera3D = null

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var _enemy: Node3D = null
var _current_dir: int = 0        ## Direction index (0 = front)
var _anim_frame: int = 0         ## Current animation column
var _anim_timer: float = 0.0
var _is_flipped: bool = false    ## Whether the sprite is currently H-flipped

## True while a one-shot animation (attack / hurt / death) is playing.
var _state_locked: bool = false

enum AnimState { WALK, ATTACK, HURT, DEATH }
var _current_state: AnimState = AnimState.WALK

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Full setup: use an actual sprite-sheet texture.
## dirs        – 4 or 8 directional rows in the sheet.
## fpd         – animation frames per direction (columns).
## h_offset    – sprite centre height above enemy origin.
## fps         – animation playback speed.
## mirror      – mirror left-side frames from right-side rows.
func setup(
		enemy: Node3D,
		texture: Texture2D,
		dirs: int = 8,
		fpd: int = 1,
		h_offset: float = 0.9,
		fps: float = 8.0,
		mirror: bool = true) -> void:
	_enemy = enemy
	num_directions = dirs
	frames_per_direction = fpd
	height_offset = h_offset
	animation_fps = fps
	use_mirror = mirror

	var num_rows := _get_num_rows()

	_sprite = Sprite3D.new()
	_sprite.texture = texture
	_sprite.hframes = fpd
	_sprite.vframes = num_rows
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = pixel_size
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = true
	_sprite.double_sided = true
	add_child(_sprite)

	position = Vector3(0.0, height_offset, 0.0)


## Fallback setup: procedural colored quad for enemies without a sprite sheet.
## width / height control the quad's approximate world-space size.
func setup_colored(
		enemy: Node3D,
		color: Color,
		h_offset: float = 0.9) -> void:
	_enemy = enemy
	num_directions = 1
	frames_per_direction = 1
	use_mirror = false

	# Build a tiny gradient image to give some depth impression
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 32:
			var cx: float = abs(x - 16) / 16.0
			var cy: float = abs(y - 32) / 32.0
			var edge: float = maxf(cx * cx, cy * 0.5)
			var c: Color = color.darkened(edge * 0.55)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)

	_sprite = Sprite3D.new()
	_sprite.texture = tex
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = pixel_size
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = true
	_sprite.double_sided = true
	add_child(_sprite)

	position = Vector3(0.0, h_offset, 0.0)

# ---------------------------------------------------------------------------
# Animation state API
# ---------------------------------------------------------------------------

func set_state(state: AnimState, force: bool = false) -> void:
	if _state_locked and not force:
		return
	if _current_state == state:
		return
	_current_state = state
	_anim_frame = 0
	_anim_timer = 0.0
	_state_locked = state in [AnimState.ATTACK, AnimState.DEATH, AnimState.HURT]


func set_walking() -> void:
	set_state(AnimState.WALK)


func trigger_attack() -> void:
	set_state(AnimState.ATTACK)


func trigger_hurt() -> void:
	if _current_state != AnimState.DEATH:
		set_state(AnimState.HURT)


func trigger_death() -> void:
	set_state(AnimState.DEATH, true)


## Flash white briefly to indicate damage.
func flash_white(duration: float = 0.12) -> void:
	if _sprite == null:
		return
	var orig_mod: Color = _sprite.modulate
	_sprite.modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", orig_mod, duration)


## Tint the sprite with a color (e.g. red for berserker).
func set_tint(color: Color) -> void:
	if _sprite:
		_sprite.modulate = color


func reset_tint() -> void:
	if _sprite:
		_sprite.modulate = Color.WHITE

# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_ensure_camera()
	_update_direction()
	_update_animation(delta)
	_apply_frame()

# ---------------------------------------------------------------------------
# Direction calculation
# ---------------------------------------------------------------------------

func _ensure_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	var vp := get_viewport()
	if vp:
		_camera = vp.get_camera_3d()


func _update_direction() -> void:
	if num_directions <= 1 or _enemy == null or _camera == null:
		_current_dir = 0
		_is_flipped = false
		return

	# --- Vector from enemy to camera, projected onto XZ plane ---
	var to_cam: Vector3 = _camera.global_position - _enemy.global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	to_cam = to_cam.normalized()

	# --- Enemy's forward direction (where it is facing) in XZ plane ---
	var fwd: Vector3 = -_enemy.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	# --- Signed angle: 0° = camera in front, 90° = camera to enemy's right ---
	# cross_y is positive when to_cam is clockwise from fwd (camera to the right)
	var cross_y: float = fwd.cross(to_cam).y
	var dot_val: float = fwd.dot(to_cam)
	var angle_deg: float = rad_to_deg(atan2(cross_y, dot_val))
	angle_deg = fposmod(angle_deg, 360.0)  # Ensure 0..360

	# --- Map angle to direction index ---
	var sector: float = 360.0 / float(num_directions)
	var raw_dir: int = int((angle_deg + sector * 0.5) / sector) % num_directions

	if raw_dir != _current_dir or _is_flipped != _calc_flip(raw_dir):
		_current_dir = raw_dir
		_is_flipped = _calc_flip(raw_dir)
		direction_changed.emit(_current_dir)

	# Apply horizontal flip for left-side directions
	if _sprite:
		_sprite.flip_h = _is_flipped


func _calc_flip(dir: int) -> bool:
	if not use_mirror:
		return false
	if num_directions == 8:
		# Dirs 5, 6, 7 are mirrors of 3, 2, 1 respectively
		return dir in [5, 6, 7]
	elif num_directions == 4:
		# Dir 3 (left) is a mirror of dir 1 (right)
		return dir == 3
	return false


func _get_mirrored_row(dir: int) -> int:
	"""Convert a left-side direction index to its mirrored right-side row."""
	if num_directions == 8:
		match dir:
			5: return 3
			6: return 2
			7: return 1
	elif num_directions == 4:
		if dir == 3:
			return 1
	return dir


func _get_num_rows() -> int:
	"""Return how many rows are needed in the sprite sheet."""
	if not use_mirror:
		return num_directions
	# With mirroring, left dirs share rows with right dirs
	if num_directions == 8:
		return 5  # rows: front, front-right, right, back-right, back
	elif num_directions == 4:
		return 3  # rows: front, right, back
	return num_directions

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _update_animation(delta: float) -> void:
	if frames_per_direction <= 1:
		_anim_frame = 0
		return

	_anim_timer += delta
	if _anim_timer < 1.0 / animation_fps:
		return

	_anim_timer = 0.0
	_anim_frame += 1

	if _anim_frame >= frames_per_direction:
		match _current_state:
			AnimState.ATTACK, AnimState.HURT:
				# One-shot: return to walk
				_anim_frame = 0
				_state_locked = false
				_current_state = AnimState.WALK
			AnimState.DEATH:
				# Hold last frame
				_anim_frame = frames_per_direction - 1
				_state_locked = false
			_:
				# Loop walk
				_anim_frame = 0

# ---------------------------------------------------------------------------
# Frame application
# ---------------------------------------------------------------------------

func _apply_frame() -> void:
	if _sprite == null:
		return

	# Determine which sprite-sheet row to use
	var row: int
	if use_mirror and _is_flipped:
		row = _get_mirrored_row(_current_dir)
	else:
		row = _current_dir

	# Clamp row to valid range
	var max_row: int = _sprite.vframes - 1
	row = clampi(row, 0, max_row)

	# Frame index = row * frames_per_direction + animation_column
	_sprite.frame = row * frames_per_direction + _anim_frame
