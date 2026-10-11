# ==============================================================================
# Script: Managers/settings_manager.gd
# Purpose: Global settings controller for display, video, and audio preferences.
#          Persists player preferences to user://settings.cfg and applies them at boot.
# Dependencies: Coordinates with AudioManager.
# ==============================================================================
extends Node

const SETTINGS_FILE = "user://settings.cfg"

# Window Mode enumeration
enum WindowMode {
	BORDERLESS_FULLSCREEN = 0,
	EXCLUSIVE_FULLSCREEN = 1,
	WINDOWED = 2
}

# Supported 16:9 Resolutions
const SUPPORTED_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(3840, 2160),
	Vector2i(2560, 1440),
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720)
]

const FPS_OPTIONS: Array[int] = [0, 60, 120, 144]

# Active configurations
var current_window_mode: WindowMode = WindowMode.BORDERLESS_FULLSCREEN
var current_resolution: Vector2i = Vector2i(1920, 1080)
var current_vsync: bool = true
var current_fps_limit: int = 0

signal display_settings_changed


func _ready() -> void:
	load_and_apply_settings()


## Loads user settings from configuration file or initializes default values.
func load_and_apply_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err == OK:
		# Read display settings
		var mode_val = config.get_value("display", "window_mode", WindowMode.BORDERLESS_FULLSCREEN)
		current_window_mode = mode_val as WindowMode
		
		var w = config.get_value("display", "resolution_width", 1920)
		var h = config.get_value("display", "resolution_height", 1080)
		current_resolution = Vector2i(w, h)
		
		# Safety check: clamp loaded resolution if monitor is smaller than saved config
		var screen = DisplayServer.window_get_current_screen()
		var screen_size = DisplayServer.screen_get_size(screen)
		if screen_size.x > 0 and screen_size.y > 0:
			if current_resolution.x > screen_size.x or current_resolution.y > screen_size.y:
				current_resolution = screen_size

		current_vsync = config.get_value("display", "vsync", true)
		current_fps_limit = config.get_value("display", "fps_limit", 0)
		
		# Read audio settings if present
		if config.has_section("audio"):
			var music_vol = config.get_value("audio", "music_volume", 1.0)
			var sfx_vol = config.get_value("audio", "sfx_volume", 1.0)
			var music_muted = config.get_value("audio", "music_muted", false)
			var sfx_muted = config.get_value("audio", "sfx_muted", false)
			
			if has_node("/root/AudioManager"):
				var audio = get_node("/root/AudioManager")
				audio.set_music_volume(music_vol)
				audio.set_sfx_volume(sfx_vol)
				audio.set_music_muted(music_muted)
				audio.set_sfx_muted(sfx_muted)
	else:
		# First launch defaults
		current_window_mode = WindowMode.BORDERLESS_FULLSCREEN
		current_resolution = Vector2i(1920, 1080)
		current_vsync = true
		current_fps_limit = 0
		save_settings()
	
	apply_display_settings(current_window_mode, current_resolution, current_vsync, current_fps_limit)


## Applies display changes immediately and updates config file.
func apply_display_settings(mode: WindowMode, res: Vector2i, vsync_enabled: bool, fps_limit: int = 0) -> void:
	current_window_mode = mode
	current_resolution = res
	current_vsync = vsync_enabled
	current_fps_limit = fps_limit

	# 1. Apply Window Mode & Window Sizing
	var root_window = get_tree().root if get_tree() else null
	var is_embedded = root_window.is_embedded() if root_window else false

	if is_embedded:
		# When running embedded inside the Godot editor, DisplayServer window operations are blocked.
		# Adjust the root Window node size directly to avoid engine warning prints.
		if mode == WindowMode.WINDOWED and root_window:
			root_window.size = res
	else:
		match mode:
			WindowMode.BORDERLESS_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			WindowMode.EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			WindowMode.WINDOWED:
				var screen = DisplayServer.window_get_current_screen()
				var usable = DisplayServer.screen_get_usable_rect(screen)
				var target_res = res
				
				# Clamping safety: never let windowed mode exceed the screen bounds
				if usable.size.x > 0 and usable.size.y > 0:
					target_res.x = mini(target_res.x, usable.size.x)
					target_res.y = mini(target_res.y, usable.size.y)

				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				DisplayServer.window_set_size(target_res)
				
				# Center window on current monitor's usable area
				if usable.size.x > 0 and usable.size.y > 0:
					var pos = usable.position + (usable.size - target_res) / 2
					pos.y = max(pos.y, usable.position.y)
					DisplayServer.window_set_position(pos)

	# 2. V-Sync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

	# 3. FPS Limit
	Engine.max_fps = fps_limit

	# 4. Save
	save_settings()
	display_settings_changed.emit()


## Saves current display preferences to settings.cfg.
func save_settings() -> void:
	var config = ConfigFile.new()
	# Load existing file first to preserve other sections (e.g., audio)
	config.load(SETTINGS_FILE)
	
	config.set_value("display", "window_mode", current_window_mode)
	config.set_value("display", "resolution_width", current_resolution.x)
	config.set_value("display", "resolution_height", current_resolution.y)
	config.set_value("display", "vsync", current_vsync)
	config.set_value("display", "fps_limit", current_fps_limit)
	config.save(SETTINGS_FILE)


## Saves audio preferences to settings.cfg.
func save_audio_settings(music_vol: float, sfx_vol: float, music_muted: bool, sfx_muted: bool) -> void:
	var config = ConfigFile.new()
	config.load(SETTINGS_FILE)
	
	config.set_value("audio", "music_volume", music_vol)
	config.set_value("audio", "sfx_volume", sfx_vol)
	config.set_value("audio", "music_muted", music_muted)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.save(SETTINGS_FILE)


## Returns a list of available resolutions that fit within the player's monitor.
func get_available_resolutions() -> Array[Vector2i]:
	var screen = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen)
	
	# Fallback if headless or undetected
	if screen_size.x <= 0 or screen_size.y <= 0:
		screen_size = Vector2i(1920, 1080)
	
	var list: Array[Vector2i] = []
	
	# If monitor native resolution is not in standard list, include it if it fits
	if not SUPPORTED_RESOLUTIONS.has(screen_size):
		list.append(screen_size)
	
	for res in SUPPORTED_RESOLUTIONS:
		# Only include resolutions that fit onto this monitor
		if res.x <= screen_size.x and res.y <= screen_size.y:
			if not list.has(res):
				list.append(res)
				
	# Always ensure at least 720p or smallest standard resolution is available as fallback
	if list.is_empty():
		list.append(Vector2i(1280, 720))
			
	return list
