extends Node2D
class_name TimeManager

# ==========================================
# SIGNALS
# ==========================================
signal hour_passed(hour: int)
signal day_started(day_number: int)
signal night_started(day_number: int)

# ==========================================
# ENUMS & CONSTANTS
# ==========================================
enum MoonPhase { NORMAL, FULL, BLOOD }

# ==========================================
# EXPORTS & CONFIGURATION
# ==========================================
@export var lighting_modulate: CanvasModulate
@export var real_minutes_per_day: float = 2.0 

@export_group("Atmosphere")
@export var day_color := Color(1.0, 1.0, 1.0, 1)       # Bright and normal
@export var night_color := Color(0.5, 0.5, 0.8, 1)     # Dark, moody purple/blue
@export var blood_moon_color := Color(0.9, 0.2, 0.2, 1)# Terrifying Red!
@export var full_moon_color := Color(0.7, 0.8, 1.0, 1) # Bright, safe blue!
@export var sunrise_hour: int = 6
@export var sunset_hour: int = 18

# ==========================================
# RUNTIME STATE
# ==========================================
var is_time_running: bool = false
var current_day: int = 1
var current_time: float = 6.0 # Start at 6 AM
var current_hour: int = 6
var is_night: bool = false
var current_moon_phase: MoonPhase = MoonPhase.NORMAL

# ==========================================
# MAIN LOOP
# ==========================================
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
		
		# 1. CACHE THE OLD DAY
		var yesterday = current_day 
		
		# 2. FLIP THE CALENDAR FIRST
		current_day += 1
		print("--- DAY %d ---" % current_day)
		
		# 3. NOW TRIGGER THE UI REFRESH
		if EconomyManager.has_method("archive_daily_stats"):
			EconomyManager.archive_daily_stats(yesterday)
		
		
		
		
	# 3. Handle Hour Changes (For triggering waves!)
	var new_hour = int(floor(current_time))
	if new_hour != current_hour:
		current_hour = new_hour
		hour_passed.emit(current_hour)
		_check_day_night_triggers()

# ==========================================
# EVENT TRIGGERS (Dawn & Dusk)
# ==========================================
func _check_day_night_triggers():
	# --- SUNRISE ---
	if current_hour == sunrise_hour and is_night:
		is_night = false
		current_moon_phase = MoonPhase.NORMAL # Reset for the day
		day_started.emit(current_day)
		
	# --- SUNSET ---
	elif current_hour == sunset_hour and not is_night:
		is_night = true
		
		# Roll the Moon Phase
		var roll = randf()
		if roll < 0.15:
			current_moon_phase = MoonPhase.FULL
		elif roll > 0.85:
			current_moon_phase = MoonPhase.BLOOD
		else:
			current_moon_phase = MoonPhase.NORMAL
			
		night_started.emit(current_day)

# ==========================================
# VISUALS & LIGHTING
# ==========================================
func _update_lighting():
	if not lighting_modulate: return
	
	# Determine target night color based on phase
	var target_night_color = night_color
	if current_moon_phase == MoonPhase.BLOOD: target_night_color = blood_moon_color
	elif current_moon_phase == MoonPhase.FULL: target_night_color = full_moon_color
	
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
