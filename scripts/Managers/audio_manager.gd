# ==============================================================================
# Script: Managers/audio_manager.gd
# Purpose: Global audio controller that manages linear volume scales, channel mute states, dynamic time-based playlist changes, jukebox controls, and pitch-shifted polyphonic SFX pools.
# Dependencies: Requires child nodes MusicPlayer and SFXPool, and coordinates with TimeManager.
# Signals: Emits track_changed when a new music selection starts playing.
# ==============================================================================
extends Node2D

@onready var music_player = $MusicPlayer
@onready var sfx_pool = $SFXPool

# --- VOLUME & MUTE STATE ---
var default_music_volume_db: float = 0.0 
var default_sfx_volume_db: float = 0.0

var is_music_muted: bool = false
var is_sfx_muted: bool = false
var current_track_name: String = ""

# --- JUKEBOX STATE ---
var is_jukebox_enabled: bool = false 
signal track_changed(track_name: String)

# --- BUS INDICES ---
var music_bus_index: int
var sfx_bus_index: int

# AUDIO DICTIONARIES (Future-Proofed)
var music_tracks: Dictionary = {
	"Forest_Ambience": preload("res://audio/Music/Forest Ambience.wav"),
	"Sunrise": preload("res://audio/Music/Sunrise.wav"),
	"NightTime": preload("res://audio/Music/NightTime.wav")
}

# PLAYLISTS: Grouping the names of the tracks together
var playlists: Dictionary = {
	"Sunrise": ["Sunrise"],
	"Day": ["Forest_Ambience"],
	"Night_Normal": ["NightTime"],
	"Night_Full": ["NightTime"], # Placeholder until you add full moon tracks!
	"Night_Blood": ["NightTime"] # Placeholder until you add blood moon tracks!
}

var sfx_tracks: Dictionary = {
	"hammer": preload("res://audio/SFX/Bots/Kenny/impactPlank_medium_000.ogg"),
	"wood": preload("res://audio/SFX/Bots/Kenny/impactWood_medium_000.ogg"),
	"stone": preload("res://audio/SFX/Bots/Kenny/impactMining_000.ogg"),
	"pain": preload("res://audio/SFX/Bots/Kenny/impactPunch_heavy_001.ogg"),
	"walk_grass": preload("res://audio/SFX/Bots/Kenny/footstep_grass_004.ogg")
}

var sfx_playlists: Dictionary = {
	"walk_grass": [
		preload("res://audio/SFX/Bots/Kenny/footstep_grass_000.ogg"),
		preload("res://audio/SFX/Bots/Kenny/footstep_grass_001.ogg"),
		preload("res://audio/SFX/Bots/Kenny/footstep_grass_002.ogg"),
		preload("res://audio/SFX/Bots/Kenny/footstep_grass_003.ogg"),
		preload("res://audio/SFX/Bots/Kenny/footstep_grass_004.ogg")
	]
}



## Sets up default connections, grabs AudioServer bus indexes, and triggers initial music.
func _ready():
	music_player.finished.connect(_on_music_finished)
	
	music_bus_index = AudioServer.get_bus_index("Music")
	sfx_bus_index = AudioServer.get_bus_index("SFX")
	
	# We use play_next_track_with_fade so it broadcasts the track_changed signal right away!
	play_next_track_with_fade("Sunrise", 0.5)



## Loads and plays a specified music track instantly.
func play_music(track_name: String):
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var stream = music_tracks[track_name]
	
	if music_player.stream == stream and music_player.playing:
		return 
		
	current_track_name = track_name 
	track_changed.emit(current_track_name)
	
	music_player.stream = stream
	music_player.play()



## Transitions from the current track to a new track using crossfade tweens.
func play_next_track_with_fade(track_name: String, fade_duration: float = 2.0, is_jukebox_override: bool = false):
	# Block the TimeManager from interrupting the player's chosen song!
	if is_jukebox_enabled and not is_jukebox_override:
		return
		
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var next_stream = music_tracks[track_name]
	
	if music_player.stream == next_stream and music_player.playing:
		return 
		
	current_track_name = track_name 
	track_changed.emit(current_track_name)
		
	if not music_player.playing:
		music_player.stream = next_stream
		music_player.volume_db = default_music_volume_db
		music_player.play()
		return
		
	var fade_out_tween = create_tween()
	fade_out_tween.tween_property(music_player, "volume_db", -40.0, fade_duration) 
	
	fade_out_tween.tween_callback(func():
		music_player.stream = next_stream
		music_player.play()
		
		var target_vol = -80.0 if is_music_muted else default_music_volume_db
		
		var fade_in_tween = create_tween()
		fade_in_tween.tween_property(music_player, "volume_db", target_vol, fade_duration)
	)



## Selects a random track from the specified playlist and plays it with crossfade transitions.
func play_playlist_track(playlist_name: String, fade_duration: float = 2.0):
	if not playlists.has(playlist_name):
		push_warning("Playlist not found: " + playlist_name)
		return
		
	var tracks = playlists[playlist_name]
	if tracks.is_empty():
		return
		
	var random_track_name = tracks.pick_random()
	play_next_track_with_fade(random_track_name, fade_duration)



## Instantly stops all playing music tracks.
func stop_music():
	music_player.stop()



## Automatically sequences and chains tracks based on active moon phase or time of day.
func _on_music_finished():
	print("music finished signal")
	
	if is_jukebox_enabled:
		music_player.play()
		return
	
	var time_manager = get_tree().root.find_child("TimeManager", true, false)
	
	if not time_manager:
		music_player.play() 
		return
		
	if time_manager.is_night:
		match time_manager.current_moon_phase:
			TimeManager.MoonPhase.BLOOD:
				play_playlist_track("Night_Blood", 0.25)
			TimeManager.MoonPhase.FULL:
				play_playlist_track("Night_Full", 0.25)
			_:
				play_playlist_track("Night_Normal", 0.25)
				
	elif time_manager.current_time >= 6.0 and time_manager.current_time < 8.0:
		play_playlist_track("Sunrise", 0.25)
	else:
		play_playlist_track("Day", 0.25)



## Returns a list array containing all registered jukebox song identifiers.
func get_track_list() -> Array:
	return music_tracks.keys()


## Overrides clock events and forces a specific track to play in Jukebox mode.
func force_play_track(track_name: String):
	is_jukebox_enabled = true
	play_next_track_with_fade(track_name, 1.0, true)


## Deactivates jukebox mode and syncs active sound tracks back to TimeManager calendar phases.
func disable_jukebox():
	is_jukebox_enabled = false
	_on_music_finished()



## Plays non-positional UI sounds or positional 2D events with randomized pitch variations.
func play_sfx(sfx_name: String, pos: Vector2 = Vector2.INF, randomize_pitch: bool = true):
	if not sfx_tracks.has(sfx_name):
		push_warning("SFX not found: " + sfx_name)
		return
		
	var stream = sfx_tracks[sfx_name]
	var target_pos = pos
	
	if target_pos == Vector2.INF:
		var cam = get_viewport().get_camera_2d()
		if cam:
			target_pos = cam.global_position
		else:
			target_pos = Vector2.ZERO
	
	for player in sfx_pool.get_children():
		if not player.playing:
			player.stream = stream
			player.global_position = target_pos
			player.volume_db = default_sfx_volume_db
			
			if randomize_pitch:
				player.pitch_scale = randf_range(0.85, 1.15) 
			else:
				player.pitch_scale = 1.0
				
			player.play()
			return
			
	var fallback = sfx_pool.get_child(0)
	fallback.stream = stream
	fallback.global_position = target_pos
	fallback.volume_db = default_sfx_volume_db
	if randomize_pitch:
		fallback.pitch_scale = randf_range(0.85, 1.15)
	else:
		fallback.pitch_scale = 1.0
	fallback.play()



## Sets music volume based on a linear slider input.
func set_music_volume(linear_volume: float):
	if linear_volume <= 0.0:
		default_music_volume_db = -80.0
	else:
		default_music_volume_db = linear_to_db(linear_volume * linear_volume)
	if not is_music_muted:
		music_player.volume_db = default_music_volume_db



## Sets sound effects volume based on a linear slider input.
func set_sfx_volume(linear_volume: float):
	if linear_volume <= 0.0:
		default_sfx_volume_db = -80.0
	else:
		default_sfx_volume_db = linear_to_db(linear_volume * linear_volume)
	if not is_sfx_muted:
		AudioServer.set_bus_volume_db(sfx_bus_index, default_sfx_volume_db)



## Toggles music mute states without losing custom volume preferences.
func set_music_muted(muted: bool):
	is_music_muted = muted
	if is_music_muted:
		music_player.volume_db = -80.0 
	else:
		music_player.volume_db = default_music_volume_db



## Toggles sound effects bus mute states.
func set_sfx_muted(muted: bool):
	is_sfx_muted = muted
	AudioServer.set_bus_mute(sfx_bus_index, is_sfx_muted)



## Activates or disables low-pass filter effect enables.
func set_music_muffled(is_muffled: bool):
	AudioServer.set_bus_effect_enabled(music_bus_index, 0, is_muffled)



## Queries current music volume, returning linear percentages.
func get_music_volume_linear() -> float:
	if default_music_volume_db <= -80.0:
		return 0.0
	return sqrt(db_to_linear(default_music_volume_db))



## Queries current sound effects volume, returning linear percentages.
func get_sfx_volume_linear() -> float:
	if default_sfx_volume_db <= -80.0:
		return 0.0
	return sqrt(db_to_linear(default_sfx_volume_db))



## Packages music and sound volume and mute state values for saves.
func get_save_data() -> Dictionary:
	return {
		"music_vol": get_music_volume_linear(),
		"sfx_vol": get_sfx_volume_linear(),
		"music_muted": is_music_muted,
		"sfx_muted": is_sfx_muted
	}


## Unpacks saved music state, applying customized decibel balances and track loops.
func load_save_data(data: Dictionary):
	set_music_volume(data.get("music_vol", 0.5))
	set_sfx_volume(data.get("sfx_vol", 0.5))
	set_music_muted(data.get("music_muted", false))
	set_sfx_muted(data.get("sfx_muted", false))
