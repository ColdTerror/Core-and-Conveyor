extends Node2D
class_name TimeManager

# --- SIGNALS ---
signal hour_passed(hour: int)
signal day_started(day_number: int)
signal night_started(day_number: int)

# --- CONFIG ---
@export var lighting_modulate: CanvasModulate
@export var real_minutes_per_day: float = 2.0 

@export_group("Atmosphere")
@export var day_color := Color(1.0, 1.0, 1.0, 1)      # Bright and normal
@export var night_color := Color(0.5, 0.5, 0.8, 1) # Dark, moody purple/blue
@export var sunrise_hour: int = 6
@export var sunset_hour: int = 18

# --- STATE ---
var current_day: int = 1
var current_time: float = 6.0 # Start at 6 AM
var current_hour: int = 6
var is_night: bool = false

func _process(delta: float):
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

	# 4. Smoothly update the lighting every frame
	_update_lighting()

func _check_day_night_triggers():
	if current_hour == sunrise_hour and is_night:
		is_night = false
		day_started.emit(current_day)
		
	elif current_hour == sunset_hour and not is_night:
		is_night = true
		night_started.emit(current_day)

func _update_lighting():
	if not lighting_modulate: return
	
	# Create a smooth transition factor between 0.0 and 1.0
	var blend_factor = 0.0
	
	# Smoothly transition around sunrise and sunset (takes 2 in-game hours to fully transition)
	var transition_duration = 2.0 
	
	if current_time >= sunrise_hour and current_time <= sunrise_hour + transition_duration:
		# Morning fade in
		blend_factor = (current_time - sunrise_hour) / transition_duration
		lighting_modulate.color = night_color.lerp(day_color, blend_factor)
		
	elif current_time >= sunset_hour and current_time <= sunset_hour + transition_duration:
		# Evening fade out
		blend_factor = (current_time - sunset_hour) / transition_duration
		lighting_modulate.color = day_color.lerp(night_color, blend_factor)
		
	elif current_time > sunrise_hour + transition_duration and current_time < sunset_hour:
		# Middle of the day
		lighting_modulate.color = day_color
	else:
		# Dead of night
		lighting_modulate.color = night_color
