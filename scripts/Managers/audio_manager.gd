extends Node2D

@onready var music_player = $MusicPlayer
@onready var sfx_pool = $SFXPool

# Add a variable to store the default volume so we know what to fade back up to
var default_music_volume_db: float = 0.0 
var current_track_name: String = "" # --- NEW: Remembers what is playing ---

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
	# --- NEW: Tell the player to run a function when the song ends ---
	music_player.finished.connect(_on_music_finished)
	AudioManager.play_next_track_with_fade("Sunrise", 0.5)

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
		
	current_track_name = track_name # --- NEW: Track the current song ---
	music_player.stream = stream
	music_player.play()

func play_next_track_with_fade(track_name: String, fade_duration: float = 2.0):
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var next_stream = music_tracks[track_name]
	
	if music_player.stream == next_stream and music_player.playing:
		return 
		
	current_track_name = track_name # --- NEW: Track the current song ---
		
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
		
		var fade_in_tween = create_tween()
		fade_in_tween.tween_property(music_player, "volume_db", default_music_volume_db, fade_duration)
	)

func stop_music():
	music_player.stop()

# ==========================================
# PLAYLIST SEQUENCING (Time-Based Looping)
# ==========================================
func _on_music_finished():
	# Safely find the TimeManager anywhere in the active scene tree
	var time_manager = get_tree().root.find_child("TimeManager", true, false)
	
	if not time_manager:
		music_player.play() # Failsafe loop if time manager is missing
		return
		
	# Check the clock and manually loop or transition tracks with a fast fade
	if time_manager.is_night:
		play_next_track_with_fade("NightTime", 0.1) 
	elif time_manager.current_time >= 6.0 and time_manager.current_time < 8.0:
		play_next_track_with_fade("Sunrise", 0.1)
	else:
		play_next_track_with_fade("Forest_Ambience", 0.1)

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
