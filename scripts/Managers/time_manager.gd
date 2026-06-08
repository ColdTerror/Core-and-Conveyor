# ==============================================================================
# Script: Managers/time_manager.gd
# Purpose: Dynamic day/night clock, calendar system, lighting modulate transitions, moon phase rolling (Normal, Full, Blood Moon), and debug skip controllers.
# Dependencies: Requires CanvasModulate node reference, global AudioManager, and coordinates with sub-managers.
# Signals:
#   - hour_passed: Emitted every in-game hour.
#   - day_started: Emitted at sunrise.
#   - night_started: Emitted at sunset.
# ==============================================================================
extends Node2D
class_name TimeManager

signal hour_passed(hour: int)
signal day_started(day_number: int)
signal night_started(day_number: int)

enum MoonPhase { NORMAL, FULL, BLOOD }

@export var lighting_modulate: CanvasModulate
@export var real_minutes_per_day: float = 2.0 

@export_group("Atmosphere")
@export var day_color := Color(1.0, 1.0, 1.0, 1)       # Bright and normal
@export var night_color := Color(0.5, 0.5, 0.8, 1)     # Dark, moody purple/blue
@export var blood_moon_color := Color(0.9, 0.65, 0.65, 1.0)# Terrifying Red!
@export var full_moon_color := Color(0.6, 0.7, 1.0, 1) # Bright, safe blue!
@export var sunrise_hour: int = 6
@export var sunset_hour: int = 18

@export_group("Debug & Testing")
@export var force_full_moon: bool = false
@export var force_blood_moon: bool = false

var is_time_running: bool = false
var current_day: int = 1
var current_time: float = 6.0 # Start at 6 AM
var current_hour: int = 6
var is_night: bool = false
var current_moon_phase: MoonPhase = MoonPhase.NORMAL



## Runs the real-time calendar clock, manages hourly signals, and transitions daytime color modulations.
func _process(delta: float):
	_update_lighting()
	
	if not is_time_running:
		return
		
	# Calculate how fast time should pass
	var game_hours_per_real_second = 24.0 / (real_minutes_per_day * 60.0)
	current_time += game_hours_per_real_second * delta
	
	# Handle Day Rollover (Midnight)
	if current_time >= 24.0:
		current_time -= 24.0
		_process_midnight()
		
	# Handle Hour Changes (For triggering waves!)
	var new_hour = int(floor(current_time))
	if new_hour != current_hour:
		current_hour = new_hour
		hour_passed.emit(current_hour)
		_check_day_night_triggers()



## Triggers daily score accounting, week ending checks, and archival metrics logs at midnight.
func _process_midnight():
	# CACHE THE OLD DAY
	var yesterday = current_day 
	
	var level_node = get_parent()
	if level_node and level_node.has_node("QuotaManager"):
		var quota_mgr = level_node.get_node("QuotaManager")
		quota_mgr.process_end_of_day()
		
		# If yesterday was day 7, 14, 21, etc., the week is over!
		if yesterday % 7 == 0:
			quota_mgr.process_end_of_week()
	
	# FLIP THE CALENDAR FIRST
	current_day += 1
	print("--- DAY %d ---" % current_day)
	
	# NOW TRIGGER THE UI REFRESH
	if EconomyManager.has_method("archive_daily_stats"):
		EconomyManager.archive_daily_stats(yesterday)



## Handles sunrise and sunset thresholds, rolling moon phases and updating audio playlists.
func _check_day_night_triggers():
	# --- SUNRISE ---
	if current_hour == sunrise_hour and is_night:
		is_night = false
		current_moon_phase = MoonPhase.NORMAL # Reset for the day
		day_started.emit(current_day)
		AudioManager.play_playlist_track("Sunrise", 3.0)
		
	# --- SUNSET ---
	elif current_hour == sunset_hour and not is_night:
		is_night = true
		
		# --- DEBUG OVERRIDES ---
		if force_full_moon:
			current_moon_phase = MoonPhase.FULL
		elif force_blood_moon:
			current_moon_phase = MoonPhase.BLOOD
		else:
			# Roll the Moon Phase normally
			var roll = randf()
			if roll < 0.15:
				current_moon_phase = MoonPhase.FULL
			elif roll > 0.85:
				current_moon_phase = MoonPhase.BLOOD
			else:
				current_moon_phase = MoonPhase.NORMAL
			
		night_started.emit(current_day)
		
		match current_moon_phase:
			MoonPhase.BLOOD:
				AudioManager.play_playlist_track("Night_Blood", 3.0)
			MoonPhase.FULL:
				AudioManager.play_playlist_track("Night_Full", 3.0)
			_:
				AudioManager.play_playlist_track("Night_Normal", 3.0)



## Modulates the global canvas color to blend between day and night phases smoothly.
func _update_lighting():
	if not lighting_modulate: return
	
	var target_night_color = night_color
	if current_moon_phase == MoonPhase.BLOOD: target_night_color = blood_moon_color
	elif current_moon_phase == MoonPhase.FULL: target_night_color = full_moon_color
	
	var blend_factor = 0.0
	var transition_duration = 2.0 
	
	if current_time >= sunrise_hour and current_time <= sunrise_hour + transition_duration:
		blend_factor = (current_time - sunrise_hour) / transition_duration
		lighting_modulate.color = target_night_color.lerp(day_color, blend_factor)
		
	elif current_time >= sunset_hour and current_time <= sunset_hour + transition_duration:
		blend_factor = (current_time - sunset_hour) / transition_duration
		lighting_modulate.color = day_color.lerp(target_night_color, blend_factor)
		
	elif current_time > sunrise_hour + transition_duration and current_time < sunset_hour:
		lighting_modulate.color = day_color
	else:
		lighting_modulate.color = target_night_color



## Packages calendar date variables and current time variables for saving.
func get_save_data() -> Dictionary:
	return {
		"is_time_running": is_time_running,
		"current_day": current_day,
		"current_time": current_time,
		"current_hour": current_hour,
		"is_night": is_night,
		"current_moon_phase": current_moon_phase
	}


## Unpacks saved time parameters and restores appropriate playlist tracks.
func load_save_data(data: Dictionary):
	is_time_running = data.get("is_time_running", false)
	current_day = data.get("current_day", 1)
	current_time = data.get("current_time", 6.0)
	current_hour = data.get("current_hour", 6)
	is_night = data.get("is_night", false)
	current_moon_phase = data.get("current_moon_phase", MoonPhase.NORMAL)
	
	_update_lighting()
	
	if is_night:
		match current_moon_phase:
			MoonPhase.BLOOD: AudioManager.play_playlist_track("Night_Blood", 0.5)
			MoonPhase.FULL: AudioManager.play_playlist_track("Night_Full", 0.5)
			_: AudioManager.play_playlist_track("Night_Normal", 0.5)
	elif current_time >= 6.0 and current_time < 8.0:
		AudioManager.play_playlist_track("Sunrise", 0.5)
	else:
		AudioManager.play_playlist_track("Day", 0.5)



## Forcefully jumps clock to sunset to trigger evening transitions on subsequent frame.
func debug_skip_to_night():
	if is_night: return
	
	# Set the clock to EXACTLY sunset
	current_time = float(sunset_hour)
	
	# Trick the brain into thinking it was just 5 PM. 
	# On the next frame, it will see the hour changed to 18 and trigger the sunset logic!
	current_hour = sunset_hour - 1
	is_night = false 


## Forcefully rolls calendar to midnight and transitions to the subsequent sunrise.
func debug_skip_to_next_morning():
	_process_midnight()
	
	# Set the clock to EXACTLY sunrise
	current_time = float(sunrise_hour)
	
	# Trick the brain into thinking it was just 5 AM.
	# On the next frame, it will see the hour changed to 6 and trigger the sunrise logic!
	current_hour = sunrise_hour - 1
	is_night = true
