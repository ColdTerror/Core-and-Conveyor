extends Node2D
class_name TimeManager

# --- SIGNALS ---
signal hour_passed(hour: int)
signal day_started(day_number: int)
signal night_started(day_number: int)

# --- NEW: MOON PHASES ---
enum MoonPhase { NORMAL, FULL, BLOOD }
var current_moon_phase: MoonPhase = MoonPhase.NORMAL

# --- CONFIG ---
@export var lighting_modulate: CanvasModulate
@export var real_minutes_per_day: float = 2.0 

@export_group("Atmosphere")
@export var day_color := Color(1.0, 1.0, 1.0, 1)      # Bright and normal
@export var night_color := Color(0.5, 0.5, 0.8, 1)    # Dark, moody purple/blue
@export var blood_moon_color := Color(0.9, 0.2, 0.2, 1) # Terrifying Red!
@export var full_moon_color := Color(0.7, 0.8, 1.0, 1)  # Bright, safe blue!
@export var sunrise_hour: int = 6
@export var sunset_hour: int = 18

# --- STATE ---
var is_time_running: bool = false
var current_day: int = 1
var current_time: float = 6.0 # Start at 6 AM
var current_hour: int = 6
var is_night: bool = false

func _process(delta: float):
	_update_lighting()
	
	if not is_time_running:
		return
		
	# 1. Calculate how fast time should pass
	var game_hours_per_real_second = 24.0 / (real_minutes_per_day * 60.0)
	current_time += game_hours_per_real_second * delta
	
	# 2. Handle Day Rollover (Midnight)
	if current_time >= 24.0:
		current_time -= 24.0
		current_day += 1
		print("--- DAY %d ---" % current_day)
		
	# 3. Handle Hour Changes (For triggering waves!)
	var new_hour = int(floor(current_time))
	if new_hour != current_hour:
		current_hour = new_hour
		hour_passed.emit(current_hour)
		_check_day_night_triggers()

func _check_day_night_triggers():
	if current_hour == sunrise_hour and is_night:
		is_night = false
		current_moon_phase = MoonPhase.NORMAL # Reset for the day
		day_started.emit(current_day)
		
	elif current_hour == sunset_hour and not is_night:
		is_night = true
		
		# --- NEW: ROLL THE MOON PHASE ---
		var roll = randf()
		if roll < 0.15:
			current_moon_phase = MoonPhase.FULL
		elif roll > 0.85:
			current_moon_phase = MoonPhase.BLOOD
		else:
			current_moon_phase = MoonPhase.NORMAL
		# --------------------------------
			
		night_started.emit(current_day)

func _update_lighting():
	if not lighting_modulate: return
	
	# --- NEW: Determine target night color based on phase ---
	var target_night_color = night_color
	if current_moon_phase == MoonPhase.BLOOD: target_night_color = blood_moon_color
	elif current_moon_phase == MoonPhase.FULL: target_night_color = full_moon_color
	# --------------------------------------------------------
	
	var blend_factor = 0.0
	var transition_duration = 2.0 
	
	if current_time >= sunrise_hour and current_time <= sunrise_hour + transition_duration:
		# Morning fade in
		blend_factor = (current_time - sunrise_hour) / transition_duration
		lighting_modulate.color = target_night_color.lerp(day_color, blend_factor)
		
	elif current_time >= sunset_hour and current_time <= sunset_hour + transition_duration:
		# Evening fade out
		blend_factor = (current_time - sunset_hour) / transition_duration
		lighting_modulate.color = day_color.lerp(target_night_color, blend_factor)
		
	elif current_time > sunrise_hour + transition_duration and current_time < sunset_hour:
		# Middle of the day
		lighting_modulate.color = day_color
	else:
		# Dead of night
		lighting_modulate.color = target_night_color
