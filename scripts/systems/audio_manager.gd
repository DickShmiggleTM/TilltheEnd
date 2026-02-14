extends Node
## Manages all game audio. Uses procedurally generated sounds as placeholders.

var sfx_players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
const MAX_SFX_PLAYERS := 16

func _ready() -> void:
	for i in MAX_SFX_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		sfx_players.append(player)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	music_player.volume_db = -10.0
	add_child(music_player)

func play_sfx(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var player := _get_available_player()
	if player == null:
		return
	player.stream = _generate_sound(sound_name)
	player.volume_db = volume_db
	player.pitch_scale = pitch + randf_range(-0.05, 0.05)
	player.play()

func _get_available_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]

func _generate_sound(sound_name: String) -> AudioStream:
	# Generate placeholder procedural sounds
	# In production, replace with actual audio files
	return AudioStreamGenerator.new()

func play_music(_track_name: String) -> void:
	pass  # Placeholder for music system

func stop_music() -> void:
	if music_player:
		music_player.stop()
