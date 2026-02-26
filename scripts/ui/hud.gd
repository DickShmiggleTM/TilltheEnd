extends CanvasLayer
## In-game HUD for Till The End.
## Displays health, EXP, wave info, level info, weapon status, boss health,
## crosshair, kill counter, timer, and damage vignette. All elements use a dark
## semi-transparent theme with red/orange hellish colors.
## Wave display now shows "LEVEL X - WAVE Y/Z" format.

# ── Node references (assigned in _ready via find_child) ──────────────────────
var health_bar: ProgressBar
var health_label: Label
var exp_bar: ProgressBar
var level_label: Label
var wave_label: Label
var enemies_label: Label
var weapon_name_label: Label
var weapon_slots_container: HBoxContainer
var kill_label: Label
var timer_label: Label
var boss_health_bar: ProgressBar
var boss_name_label: Label
var boss_container: VBoxContainer
var crosshair: Control
var damage_vignette: ColorRect
var level_info_label: Label

# ── State ────────────────────────────────────────────────────────────────────
var _current_health: float = 100.0
var _max_health: float = 100.0
var _current_exp: float = 0.0
var _exp_to_next: float = 100.0
var _current_level: int = 1
var _current_wave: int = 0
var _enemies_remaining: int = 0
var _kill_count: int = 0
var _run_time: float = 0.0
var _vignette_alpha: float = 0.0
var _boss_active: bool = false
var _boss_health: float = 100.0
var _boss_max_health: float = 100.0
var _weapon_count: int = 0
var _active_weapon_index: int = 0
var _campaign_level: int = 1
var _campaign_level_name: String = ""


func _ready() -> void:
	layer = 10
	# Get node references
	health_bar = %HealthBar
	health_label = %HealthLabel
	exp_bar = %ExpBar
	level_label = %LevelLabel
	wave_label = %WaveLabel
	enemies_label = %EnemiesLabel
	weapon_name_label = %WeaponNameLabel
	weapon_slots_container = %WeaponSlots
	kill_label = %KillLabel
	timer_label = %TimerLabel
	boss_health_bar = %BossHealthBar
	boss_name_label = %BossNameLabel
	boss_container = %BossContainer
	crosshair = %Crosshair
	damage_vignette = %DamageVignette
	level_info_label = %LevelInfoLabel

	# Initial state
	boss_container.visible = false
	damage_vignette.modulate.a = 0.0

	# Set campaign level info from GameManager
	_campaign_level = GameManager.current_level
	_campaign_level_name = GameManager.current_level_data.get("name", "")

	_update_health_display()
	_update_exp_display()
	_update_wave_display()
	_update_kill_display()
	_update_timer_display()
	_update_level_info_display()

	# Connect EventBus signals
	EventBus.player_exp_gained.connect(_on_player_exp_gained)
	EventBus.player_level_up.connect(_on_player_level_up)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_healed.connect(_on_player_healed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.enemies_remaining_changed.connect(_on_enemies_remaining_changed)
	EventBus.weapon_acquired.connect(_on_weapon_acquired)
	EventBus.boss_wave_started.connect(_on_boss_wave_started)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.boss_killed.connect(_on_boss_killed)
	EventBus.level_started.connect(_on_level_started)


func _process(delta: float) -> void:
	if GameManager.state == GameManager.GameState.PLAYING:
		_run_time = GameManager.run_time
		_update_timer_display()

	# Fade vignette
	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(_vignette_alpha - delta * 2.5, 0.0)
		damage_vignette.modulate.a = _vignette_alpha


# ── Display update helpers ───────────────────────────────────────────────────

func _update_health_display() -> void:
	_max_health = GameManager.get_trait("max_health")
	health_bar.max_value = _max_health
	health_bar.value = _current_health
	health_label.text = "%d / %d" % [ceili(_current_health), ceili(_max_health)]


func _update_exp_display() -> void:
	exp_bar.max_value = _exp_to_next
	exp_bar.value = _current_exp
	level_label.text = "LVL %d" % _current_level


func _update_wave_display() -> void:
	wave_label.text = "LEVEL %d - WAVE %d/%d" % [_campaign_level, _current_wave, GameManager.total_waves]
	enemies_label.text = "%d REMAINING" % _enemies_remaining


func _update_kill_display() -> void:
	kill_label.text = "%d KILLS" % _kill_count


func _update_timer_display() -> void:
	var minutes := int(_run_time) / 60
	var seconds := int(_run_time) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


func _update_level_info_display() -> void:
	if level_info_label:
		level_info_label.text = "%s" % _campaign_level_name


func _update_weapon_slots() -> void:
	# Clear old slots
	for child in weapon_slots_container.get_children():
		child.queue_free()

	_weapon_count = GameManager.player_weapons.size()
	_active_weapon_index = 0  # Will be updated by weapon manager

	for i in _weapon_count:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size = Vector2(16, 16)
		if i == _active_weapon_index:
			dot.color = Color(1.0, 0.4, 0.1, 1.0)
		else:
			dot.color = Color(0.5, 0.5, 0.5, 0.6)
		weapon_slots_container.add_child(dot)


func _flash_vignette() -> void:
	_vignette_alpha = 0.6


func _update_boss_health(current: float, max_hp: float) -> void:
	boss_health_bar.max_value = max_hp
	boss_health_bar.value = current
	_boss_health = current
	_boss_max_health = max_hp


# ── Signal callbacks ─────────────────────────────────────────────────────────

func _on_player_exp_gained(amount: float, total: float, needed: float) -> void:
	_current_exp = total
	_exp_to_next = needed
	_update_exp_display()


func _on_player_level_up(new_level: int) -> void:
	_current_level = new_level
	_current_exp = GameManager.player_exp
	_exp_to_next = GameManager.player_exp_to_next
	_update_exp_display()


func _on_player_damaged(amount: float, _source: Node3D) -> void:
	# Update health from player
	var player_nodes := get_tree().get_nodes_in_group("player")
	if not player_nodes.is_empty() and player_nodes[0].has_method("get_health_ratio"):
		var player := player_nodes[0]
		_current_health = player.current_health
	else:
		_current_health = maxf(_current_health - amount, 0.0)
	_update_health_display()
	_flash_vignette()


func _on_player_healed(amount: float) -> void:
	_current_health = minf(_current_health + amount, _max_health)
	_update_health_display()


func _on_wave_started(wave_number: int) -> void:
	_current_wave = wave_number
	_update_wave_display()


func _on_wave_completed(_wave_number: int) -> void:
	_update_wave_display()


func _on_enemies_remaining_changed(count: int) -> void:
	_enemies_remaining = count
	_update_wave_display()


func _on_weapon_acquired(_weapon_data: Dictionary) -> void:
	var weapon: Dictionary = GameManager.player_weapons.back()
	if weapon:
		weapon_name_label.text = weapon.get("name", "Unknown")
	_update_weapon_slots()


func _on_boss_wave_started() -> void:
	_boss_active = true
	boss_container.visible = true
	# Show boss name from level data
	var boss_name: String = GameManager.current_level_data.get("boss_name", "BOSS")
	boss_name_label.text = boss_name
	_update_boss_health(100.0, 100.0)


func _on_boss_killed() -> void:
	_boss_active = false
	boss_container.visible = false


func _on_damage_dealt(amount: float, _position: Vector3, _is_crit: bool) -> void:
	# If boss is active, update boss health bar (approximate)
	if _boss_active:
		_boss_health = maxf(_boss_health - amount, 0.0)
		boss_health_bar.value = _boss_health


func _on_enemy_killed(_enemy: Node3D, _position: Vector3) -> void:
	_kill_count = GameManager.total_kills
	_update_kill_display()


func _on_level_started(level_number: int, level_data: Dictionary) -> void:
	_campaign_level = level_number
	_campaign_level_name = level_data.get("name", "")
	_update_wave_display()
	_update_level_info_display()


## Called by weapon manager or touch controls when weapon is switched
func set_active_weapon(index: int, weapon_data: Dictionary) -> void:
	_active_weapon_index = index
	weapon_name_label.text = weapon_data.get("name", "Unknown")
	_update_weapon_slots()
