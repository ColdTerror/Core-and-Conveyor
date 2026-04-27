extends Node2D

@onready var music_player = $MusicPlayer
@onready var sfx_pool = $SFXPool

# Add a variable to store the default volume so we know what to fade back up to
var default_music_volume_db: float = 0.0 

# ==========================================
# AUDIO DICTIONARIES (Future-Proofed)
# ==========================================
# Right now we just have one track, but this structure makes it 
# incredibly easy to add "morning" or "night" arrays later!
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
	# Start our single track immediately
	play_music("Forest_Ambience")

# ==========================================
# MUSIC LOGIC
# ==========================================
func play_music(track_name: String):
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var stream = music_tracks[track_name]
	
	# Don't restart the song if it's already playing!
	if music_player.stream == stream and music_player.playing:
		return 
		
	music_player.stream = stream
	music_player.play()




func play_next_track_with_fade(track_name: String, fade_duration: float = 2.0):
	if not music_tracks.has(track_name):
		push_warning("Music track not found: " + track_name)
		return
		
	var next_stream = music_tracks[track_name]
	
	# Don't do anything if we are already playing this exact track
	if music_player.stream == next_stream and music_player.playing:
		return 
		
	# If no music is currently playing, just start the new one immediately
	if not music_player.playing:
		music_player.stream = next_stream
		music_player.volume_db = default_music_volume_db
		music_player.play()
		return
		
	# --- THE FADE LOGIC ---
	# 1. Create a tween to fade out the current song
	var fade_out_tween = create_tween()
	# Fading to -40 dB is functionally silent for most game audio
	fade_out_tween.tween_property(music_player, "volume_db", -40.0, fade_duration) 
	
	# 2. When the fade out finishes, swap the track and fade it back in!
	fade_out_tween.tween_callback(func():
		music_player.stream = next_stream
		music_player.play()
		
		var fade_in_tween = create_tween()
		fade_in_tween.tween_property(music_player, "volume_db", default_music_volume_db, fade_duration)
	)
func stop_music():
	music_player.stop()

# ==========================================
# SFX LOGIC (Polyphonic)
# ==========================================
func play_sfx(sfx_name: String):
	if not sfx_tracks.has(sfx_name):
		push_warning("SFX not found: " + sfx_name)
		return
		
	var stream = sfx_tracks[sfx_name]
	
	# Find an available player in the pool so sounds can overlap
	for player in sfx_pool.get_children():
		if not player.playing:
			player.stream = stream
			player.play()
			return
			
	# If 8 sounds are already playing at once, force the first one to overwrite
	# so we never drop a sound entirely.
	var fallback = sfx_pool.get_child(0)
	fallback.stream = stream
	fallback.play()
