extends Node2D

@onready var music_player = $MusicPlayer
@onready var sfx_pool = $SFXPool

# ==========================================
# AUDIO DICTIONARIES (Future-Proofed)
# ==========================================
# Right now we just have one track, but this structure makes it 
# incredibly easy to add "morning" or "night" arrays later!
var music_tracks: Dictionary = {
	"forest_ambience": preload("res://audio/Music/Forest Ambience.wav")
	# "morning_1": preload("res://audio/morning_vibes.wav"),
	# "night_1": preload("res://audio/moody_night.wav")
}

var sfx_tracks: Dictionary = {
	# "hammer": preload("res://audio/hammer.wav"),
	# "bow_shoot": preload("res://audio/bow.wav")
}

func _ready():
	# Start our single track immediately
	play_music("forest_ambience")

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
