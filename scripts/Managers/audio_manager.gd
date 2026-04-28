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

# ==========================================
# AUDIO DICTIONARIES (Future-Proofed)
# ==========================================
var music_tracks: Dictionary = {
	"Forest_Ambience": preload("res://audio/Music/Forest Ambience.wav"),
	"Sunrise": preload("res://audio/Music/Sunrise.wav"),
	"NightTime": preload("res://audio/Music/NightTime.wav")
}

var sfx_tracks: Dictionary = {
	# "hammer": preload("res://audio/hammer.wav"),
	# "bow_shoot": preload("res://audio/bow.wav")
}

func _ready():
	music_player.finished.connect(_on_music_finished)
	# We use play_next_track_with_fade so it broadcasts the track_changed signal right away!
	play_next_track_with_fade("Sunrise", 0.5)

# ==========================================
# MUSIC LOGIC
# ==========================================
func play_music(track_name: String):
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var stream = music_tracks[track_name]
	
	if music_player.stream == stream and music_player.playing:
		return 
		
	current_track_name = track_name 
	track_changed.emit(current_track_name) # Let the UI know!
	
	music_player.stream = stream
	music_player.play()

# Added 'is_jukebox_override' so the UI can force a track, but the TimeManager gets blocked!
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
	track_changed.emit(current_track_name) # Let the UI know!
		
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

func stop_music():
	music_player.stop()

# ==========================================
# PLAYLIST SEQUENCING (Time-Based Looping)
# ==========================================
func _on_music_finished():
	
	# --- If the Jukebox is on, loop the forced track forever! ---
	if is_jukebox_enabled:
		music_player.play()
		return
	
	var time_manager = get_tree().root.find_child("TimeManager", true, false)
	
	if not time_manager:
		music_player.play() 
		return
		
	if time_manager.is_night:
		play_next_track_with_fade("NightTime", 0.1) 
	elif time_manager.current_time >= 6.0 and time_manager.current_time < 8.0:
		play_next_track_with_fade("Sunrise", 0.1)
	else:
		play_next_track_with_fade("Forest_Ambience", 0.1)

# ==========================================
# JUKEBOX CONTROLS
# ==========================================
func get_track_list() -> Array:
	return music_tracks.keys()

func force_play_track(track_name: String):
	is_jukebox_enabled = true
	# We pass 'true' at the end to bypass the TimeManager block
	play_next_track_with_fade(track_name, 1.0, true)
	
func disable_jukebox():
	is_jukebox_enabled = false
	# Instantly manually trigger the music end function to resync with the clock
	_on_music_finished()

# ==========================================
# SFX LOGIC (Polyphonic)
# ==========================================
func play_sfx(sfx_name: String):
	if not sfx_tracks.has(sfx_name):
		push_warning("SFX not found: " + sfx_name)
		return
		
	var stream = sfx_tracks[sfx_name]
	for player in sfx_pool.get_children():
		if not player.playing:
			player.stream = stream
			player.play()
			return
			
	var fallback = sfx_pool.get_child(0)
	fallback.stream = stream
	fallback.play()
	
# ==========================================
# SETTINGS & OPTIONS MENU HOOKS
# ==========================================
func set_music_volume(linear_volume: float):
	default_music_volume_db = linear_to_db(max(linear_volume, 0.0001))
	if not is_music_muted:
		music_player.volume_db = default_music_volume_db

func set_sfx_volume(linear_volume: float):
	default_sfx_volume_db = linear_to_db(max(linear_volume, 0.0001))
	for player in sfx_pool.get_children():
		player.volume_db = default_sfx_volume_db

func set_music_muted(muted: bool):
	is_music_muted = muted
	if is_music_muted:
		music_player.volume_db = -80.0 
	else:
		music_player.volume_db = default_music_volume_db

func set_sfx_muted(muted: bool):
	is_sfx_muted = muted
	var target_vol = -80.0 if is_sfx_muted else default_sfx_volume_db
	for player in sfx_pool.get_children():
		player.volume_db = target_vol
