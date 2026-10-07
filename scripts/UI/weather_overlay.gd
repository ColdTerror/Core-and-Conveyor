# ==============================================================================
# Script: UI/weather_overlay.gd
# Purpose: Lightweight particle and atmosphere renderer displaying weather visuals
#          (rain, snow, hail, sandstorm, fog, and lightning flashes) across the viewport.
# Dependencies: Coordinates with WeatherManager.
# Signals: None.
# ==============================================================================
class_name WeatherOverlay
extends Control

var weather_manager: WeatherManager

# Particle nodes
var rain_particles: CPUParticles2D
var snow_particles: CPUParticles2D
var hail_particles: CPUParticles2D
var sand_particles: CPUParticles2D

# Atmosphere & Lightning
var atmosphere_tint: ColorRect
var lightning_flash: ColorRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_visuals()


func _ready() -> void:
	if not weather_manager:
		weather_manager = get_tree().get_first_node_in_group("WeatherManager") as WeatherManager
		
	if weather_manager:
		weather_manager.weather_changed.connect(_on_weather_changed)
		weather_manager.lightning_triggered.connect(_on_lightning_triggered)
		_apply_weather_visuals(weather_manager.current_weather, true)


## Builds lightweight CPUParticles2D emitters and full-screen ambient tint rectangles.
func _build_visuals() -> void:
	# 1. Full-screen atmosphere tint
	atmosphere_tint = ColorRect.new()
	atmosphere_tint.name = "AtmosphereTint"
	atmosphere_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere_tint.anchors_preset = Control.PRESET_FULL_RECT
	atmosphere_tint.anchor_right = 1.0
	atmosphere_tint.anchor_bottom = 1.0
	atmosphere_tint.color = Color(1.0, 1.0, 1.0, 0.0)
	add_child(atmosphere_tint)

	# 2. Rain Particles
	rain_particles = CPUParticles2D.new()
	rain_particles.name = "RainParticles"
	rain_particles.emitting = false
	rain_particles.amount = 120
	rain_particles.lifetime = 1.8
	rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain_particles.emission_rect_extents = Vector2(1000, 10)
	rain_particles.position = Vector2(960, -20)
	rain_particles.direction = Vector2(-0.25, 1.0)
	rain_particles.spread = 4.0
	rain_particles.initial_velocity_min = 650.0
	rain_particles.initial_velocity_max = 850.0
	rain_particles.color = Color(0.68, 0.82, 1.0, 0.65)
	rain_particles.scale_amount_min = 1.8
	rain_particles.scale_amount_max = 2.8
	add_child(rain_particles)

	# 3. Snow Particles
	snow_particles = CPUParticles2D.new()
	snow_particles.name = "SnowParticles"
	snow_particles.emitting = false
	snow_particles.amount = 85
	snow_particles.lifetime = 5.0
	snow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow_particles.emission_rect_extents = Vector2(1000, 10)
	snow_particles.position = Vector2(960, -20)
	snow_particles.direction = Vector2(-0.2, 1.0)
	snow_particles.spread = 18.0
	snow_particles.initial_velocity_min = 140.0
	snow_particles.initial_velocity_max = 240.0
	snow_particles.color = Color(0.95, 0.98, 1.0, 0.8)
	snow_particles.scale_amount_min = 2.0
	snow_particles.scale_amount_max = 3.5
	add_child(snow_particles)

	# 4. Hail Particles
	hail_particles = CPUParticles2D.new()
	hail_particles.name = "HailParticles"
	hail_particles.emitting = false
	hail_particles.amount = 55
	hail_particles.lifetime = 1.4
	hail_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	hail_particles.emission_rect_extents = Vector2(1000, 10)
	hail_particles.position = Vector2(960, -20)
	hail_particles.direction = Vector2(-0.1, 1.0)
	hail_particles.spread = 6.0
	hail_particles.initial_velocity_min = 750.0
	hail_particles.initial_velocity_max = 950.0
	hail_particles.color = Color(0.9, 0.95, 1.0, 0.85)
	hail_particles.scale_amount_min = 2.5
	hail_particles.scale_amount_max = 4.0
	add_child(hail_particles)

	# 5. Sandstorm Particles
	sand_particles = CPUParticles2D.new()
	sand_particles.name = "SandParticles"
	sand_particles.emitting = false
	sand_particles.amount = 110
	sand_particles.lifetime = 2.8
	sand_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sand_particles.emission_rect_extents = Vector2(10, 560)
	sand_particles.position = Vector2(-20, 540)
	sand_particles.direction = Vector2(1.0, 0.15)
	sand_particles.spread = 14.0
	sand_particles.initial_velocity_min = 450.0
	sand_particles.initial_velocity_max = 750.0
	sand_particles.color = Color(0.85, 0.65, 0.35, 0.5)
	sand_particles.scale_amount_min = 1.5
	sand_particles.scale_amount_max = 2.5
	add_child(sand_particles)

	# 6. Lightning Flash Rect
	lightning_flash = ColorRect.new()
	lightning_flash.name = "LightningFlash"
	lightning_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lightning_flash.anchors_preset = Control.PRESET_FULL_RECT
	lightning_flash.anchor_right = 1.0
	lightning_flash.anchor_bottom = 1.0
	lightning_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	add_child(lightning_flash)


## Hooked to weather transitions; updates active particle systems and tints.
func _on_weather_changed(new_weather: WeatherManager.WeatherType, _old_weather: WeatherManager.WeatherType) -> void:
	_apply_weather_visuals(new_weather, false)


## Applies particle emissions and fades atmospheric color rects.
func _apply_weather_visuals(weather: WeatherManager.WeatherType, instant: bool) -> void:
	# Disable all emitters initially
	rain_particles.emitting = false
	snow_particles.emitting = false
	hail_particles.emitting = false
	sand_particles.emitting = false

	var target_tint = Color(1.0, 1.0, 1.0, 0.0)

	match weather:
		WeatherManager.WeatherType.CLEAR:
			target_tint = Color(1.0, 1.0, 1.0, 0.0)
		WeatherManager.WeatherType.RAIN:
			rain_particles.emitting = true
			target_tint = Color(0.2, 0.3, 0.5, 0.08)
		WeatherManager.WeatherType.THUNDERSTORM:
			rain_particles.emitting = true
			target_tint = Color(0.12, 0.14, 0.28, 0.18)
		WeatherManager.WeatherType.FOG:
			target_tint = Color(0.78, 0.82, 0.88, 0.16)
		WeatherManager.WeatherType.SNOW:
			snow_particles.emitting = true
			target_tint = Color(0.65, 0.75, 0.9, 0.10)
		WeatherManager.WeatherType.BLIZZARD:
			snow_particles.emitting = true
			target_tint = Color(0.75, 0.85, 0.95, 0.22)
		WeatherManager.WeatherType.HAIL:
			hail_particles.emitting = true
			target_tint = Color(0.3, 0.4, 0.55, 0.12)
		WeatherManager.WeatherType.SANDSTORM:
			sand_particles.emitting = true
			target_tint = Color(0.75, 0.52, 0.22, 0.18)

	if instant:
		atmosphere_tint.color = target_tint
	else:
		var tween = create_tween()
		tween.tween_property(atmosphere_tint, "color", target_tint, 1.5)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)


## Fires a quick lightning flash across the screen during thunderstorms.
func _on_lightning_triggered() -> void:
	if not is_instance_valid(lightning_flash):
		return
	var tween = create_tween()
	tween.tween_property(lightning_flash, "color:a", 0.45, 0.04)
	tween.tween_property(lightning_flash, "color:a", 0.0, 0.22)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
