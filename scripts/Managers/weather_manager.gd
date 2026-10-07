# ==============================================================================
# Script: Managers/weather_manager.gd
# Purpose: Dynamic biome-adaptive weather controller that governs weather cycles,
#          forecast generation, gameplay debuffs (bot speed, solar recharge,
#          tower range), non-lethal environmental building chipping ("small dings"),
#          and lightning storm timing.
# Dependencies: Coordinates with TimeManager, Level, BuildingManager, and AudioManager.
# Signals:
#   - weather_changed(new_weather, old_weather): Emitted on weather state transitions.
#   - weather_ding(building, damage): Emitted when storm/hail chips a structure.
#   - lightning_triggered(): Emitted when lightning strikes during thunderstorms.
# ==============================================================================
class_name WeatherManager
extends Node2D

enum WeatherType {
	CLEAR,
	RAIN,
	THUNDERSTORM,
	FOG,
	SNOW,
	BLIZZARD,
	HAIL,
	SANDSTORM
}

signal weather_changed(new_weather: WeatherType, old_weather: WeatherType)
signal weather_ding(building: Building, damage: int)
signal lightning_triggered

@export var level_ref: Level
@export var time_manager: TimeManager

# State
var current_weather: WeatherType = WeatherType.CLEAR
var next_weather: WeatherType = WeatherType.CLEAR
var weather_time_remaining: float = 3.0 # In-game hours remaining
var weather_total_duration: float = 3.0 # In-game hours duration

# Timers
var _ding_cooldown: float = 4.0
var _lightning_cooldown: float = 10.0


func _ready() -> void:
	add_to_group("WeatherManager")
	_ding_cooldown = randf_range(3.5, 6.0)
	_lightning_cooldown = randf_range(8.0, 16.0)
	
	if not time_manager:
		time_manager = get_tree().get_first_node_in_group("TimeManager") as TimeManager
		
	# Initialize initial next weather roll
	_roll_next_weather()


func _process(delta: float) -> void:
	if not time_manager or not time_manager.is_time_running:
		return

	# Calculate in-game hours passed this tick
	var hours_per_sec = 24.0 / (time_manager.real_minutes_per_day * 60.0)
	var delta_hours = hours_per_sec * delta
	weather_time_remaining -= delta_hours

	if weather_time_remaining <= 0.0:
		_transition_to_next_weather()

	# Process severe weather effects
	_process_severe_weather(delta)


## Transitions active weather to the pre-rolled forecast and schedules the subsequent event.
func _transition_to_next_weather() -> void:
	var old_weather = current_weather
	current_weather = next_weather
	
	# Weather lasts 2.0 to 4.0 in-game hours
	weather_total_duration = randf_range(2.0, 4.0)
	weather_time_remaining = weather_total_duration
	
	_roll_next_weather()
	
	weather_changed.emit(current_weather, old_weather)
	print("WeatherManager: Transitioned to %s. Next: %s in %.1f hrs" % [
		get_weather_name(current_weather),
		get_weather_name(next_weather),
		weather_total_duration
	])


## Rolls the next upcoming weather event based on the level's active biome.
func _roll_next_weather() -> void:
	var biome = Level.MapBiome.FOREST
	if level_ref:
		biome = level_ref.current_biome

	var pool: Array = []
	match biome:
		Level.MapBiome.DESERT:
			# Desert Pool: Clear (65%), Sandstorm (25%), Fog/Dust Haze (10%)
			pool = [
				{"type": WeatherType.CLEAR, "weight": 65},
				{"type": WeatherType.SANDSTORM, "weight": 25},
				{"type": WeatherType.FOG, "weight": 10}
			]
		Level.MapBiome.ALPINE:
			# Alpine Pool: Clear (55%), Snow (20%), Blizzard (15%), Hail (10%)
			pool = [
				{"type": WeatherType.CLEAR, "weight": 55},
				{"type": WeatherType.SNOW, "weight": 20},
				{"type": WeatherType.BLIZZARD, "weight": 15},
				{"type": WeatherType.HAIL, "weight": 10}
			]
		_:
			# Forest Pool: Clear (60%), Rain (20%), Thunderstorm (10%), Fog (10%)
			pool = [
				{"type": WeatherType.CLEAR, "weight": 60},
				{"type": WeatherType.RAIN, "weight": 20},
				{"type": WeatherType.THUNDERSTORM, "weight": 10},
				{"type": WeatherType.FOG, "weight": 10}
			]

	# Weighted random choice
	var total_weight = 0
	for item in pool:
		total_weight += item["weight"]

	var roll = randi_range(1, total_weight)
	var accum = 0
	for item in pool:
		accum += item["weight"]
		if roll <= accum:
			next_weather = item["type"]
			break


## Handles periodic building chipping ("small dings") and lightning flash timers.
func _process_severe_weather(delta: float) -> void:
	# 1. Non-lethal hail / thunder damage chipping
	if current_weather in [WeatherType.HAIL, WeatherType.THUNDERSTORM, WeatherType.BLIZZARD]:
		_ding_cooldown -= delta
		if _ding_cooldown <= 0.0:
			_ding_cooldown = randf_range(3.5, 6.0)
			_apply_weather_ding()

	# 2. Thunderstorm lightning flash strikes
	if current_weather == WeatherType.THUNDERSTORM:
		_lightning_cooldown -= delta
		if _lightning_cooldown <= 0.0:
			_lightning_cooldown = randf_range(7.0, 16.0)
			lightning_triggered.emit()


## Selects a random eligible building and inflicts a minor non-lethal ding (1–3 damage).
func _apply_weather_ding() -> void:
	if not level_ref or not level_ref.building_manager:
		return

	var bm = level_ref.building_manager
	var candidates: Array[Building] = []

	for b in bm.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		# Protect Core and Bot Homes from weather wear
		if b is CoreBuilding or b is BotHomeBuilding:
			continue
		# Non-lethal chipping: Must stay above 1 HP and above 10% maximum health
		if b.health > 1 and b.health > int(b.max_health * 0.10):
			candidates.append(b)

	if candidates.is_empty():
		return

	# Damage 1 or 2 random buildings
	var count = min(randi_range(1, 2), candidates.size())
	candidates.shuffle()

	for i in range(count):
		var target = candidates[i]
		var ding_amount = randi_range(1, 3)
		# Ensure we don't reduce below 1 HP
		var safe_amount = min(ding_amount, max(1, target.health - 1))
		if safe_amount > 0:
			target.take_damage(safe_amount)
			if AudioManager and AudioManager.has_method("play_sfx"):
				AudioManager.play_sfx("weather_ding", target.global_position)
			weather_ding.emit(target, safe_amount)


# --- GAMEPLAY MODIFIERS API ---

## Returns the active bot movement speed multiplier based on weather.
func get_bot_speed_multiplier() -> float:
	match current_weather:
		WeatherType.CLEAR:
			return 1.0
		WeatherType.RAIN:
			return 0.80 # -20%
		WeatherType.THUNDERSTORM:
			return 0.70 # -30%
		WeatherType.FOG:
			return 0.95 # -5%
		WeatherType.SNOW:
			return 0.75 # -25%
		WeatherType.BLIZZARD:
			return 0.65 # -35%
		WeatherType.HAIL:
			return 0.75 # -25%
		WeatherType.SANDSTORM:
			return 0.70 # -30%
	return 1.0


## Returns the solar recharge efficiency multiplier based on cloud cover / precipitation.
func get_solar_multiplier() -> float:
	match current_weather:
		WeatherType.CLEAR:
			return 1.0
		WeatherType.RAIN:
			return 0.50 # -50%
		WeatherType.THUNDERSTORM:
			return 0.25 # -75%
		WeatherType.FOG:
			return 0.70 # -30%
		WeatherType.SNOW:
			return 0.60 # -40%
		WeatherType.BLIZZARD:
			return 0.25 # -75%
		WeatherType.HAIL:
			return 0.40 # -60%
		WeatherType.SANDSTORM:
			return 0.35 # -65%
	return 1.0


## Returns the tile attack range penalty applied to defensive towers.
func get_tower_range_penalty() -> int:
	match current_weather:
		WeatherType.CLEAR:
			return 0
		WeatherType.RAIN:
			return 1
		WeatherType.THUNDERSTORM:
			return 2
		WeatherType.FOG:
			return 2
		WeatherType.SNOW:
			return 1
		WeatherType.BLIZZARD:
			return 2
		WeatherType.HAIL:
			return 1
		WeatherType.SANDSTORM:
			return 2
	return 0


# --- FORMATTING & STRINGS ---

## Returns the user-facing display name for a given weather type.
func get_weather_name(type: WeatherType) -> String:
	match type:
		WeatherType.CLEAR: return "Clear Skies"
		WeatherType.RAIN: return "Rain"
		WeatherType.THUNDERSTORM: return "Thunderstorm"
		WeatherType.FOG: return "Dense Fog"
		WeatherType.SNOW: return "Snowfall"
		WeatherType.BLIZZARD: return "Blizzard"
		WeatherType.HAIL: return "Hailstorm"
		WeatherType.SANDSTORM: return "Sandstorm"
	return "Clear"


## Returns the emoji / icon representing a given weather type.
func get_weather_icon(type: WeatherType) -> String:
	match type:
		WeatherType.CLEAR: return "☀️"
		WeatherType.RAIN: return "🌧️"
		WeatherType.THUNDERSTORM: return "⛈️"
		WeatherType.FOG: return "🌫️"
		WeatherType.SNOW: return "❄️"
		WeatherType.BLIZZARD: return "🌨️"
		WeatherType.HAIL: return "🧊"
		WeatherType.SANDSTORM: return "🌪️"
	return "☀️"


## Builds a descriptive tooltip string detailing active modifiers and upcoming forecast.
func get_weather_tooltip() -> String:
	var name_str = get_weather_name(current_weather)
	var icon_str = get_weather_icon(current_weather)
	var speed_pct = int(round((1.0 - get_bot_speed_multiplier()) * 100))
	var solar_pct = int(round((1.0 - get_solar_multiplier()) * 100))
	var range_pen = get_tower_range_penalty()
	
	var lines = []
	lines.append("%s %s" % [icon_str, name_str])
	
	if speed_pct > 0:
		lines.append("• Bot Move Speed: -%d%%" % speed_pct)
	else:
		lines.append("• Bot Move Speed: Normal")
		
	if solar_pct > 0:
		lines.append("• Solar Charging: -%d%%" % solar_pct)
	else:
		lines.append("• Solar Charging: 100%")
		
	if range_pen > 0:
		lines.append("• Tower Attack Range: -%d tiles" % range_pen)
	else:
		lines.append("• Tower Range: Optimal")

	if current_weather in [WeatherType.HAIL, WeatherType.THUNDERSTORM, WeatherType.BLIZZARD]:
		lines.append("• Weather Wear: Minor chipping on outer buildings")

	lines.append(" ")
	var next_name = get_weather_name(next_weather)
	var next_icon = get_weather_icon(next_weather)
	lines.append("Forecast: %s %s in ~%.1f hrs" % [next_icon, next_name, max(0.1, weather_time_remaining)])

	return "\n".join(lines)


## Reconfigures weather cycle for a newly selected biome.
func reset_for_biome() -> void:
	current_weather = WeatherType.CLEAR
	weather_total_duration = randf_range(2.0, 4.0)
	weather_time_remaining = weather_total_duration
	_roll_next_weather()
	weather_changed.emit(current_weather, current_weather)


# --- SAVE & LOAD ---

## Packs weather state for serialization.
func get_save_data() -> Dictionary:
	return {
		"current_weather": current_weather,
		"next_weather": next_weather,
		"weather_time_remaining": weather_time_remaining,
		"weather_total_duration": weather_total_duration
	}


## Restores weather state from save data.
func load_save_data(data: Dictionary) -> void:
	current_weather = data.get("current_weather", WeatherType.CLEAR)
	next_weather = data.get("next_weather", WeatherType.CLEAR)
	weather_time_remaining = data.get("weather_time_remaining", 3.0)
	weather_total_duration = data.get("weather_total_duration", 3.0)
	weather_changed.emit(current_weather, current_weather)
