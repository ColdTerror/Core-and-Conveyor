# ==============================================================================
# Script: Building Classes/firepit_building.gd
# Purpose: Extends Building with a dynamic warm PointLight2D that activates at
#          night and deactivates at dawn, creating an atmospheric firepit glow.
#          Light radius pulses gently to simulate a living flame. Hooks into the
#          TimeManager day_started/night_started signals for automatic toggling.
#          Also modulates by Blood Moon to produce a more intense, reddish glow.
# Dependencies: Inherits Building. Expects a TimeManager in the "TimeManager"
#               group. PointLight2D and its texture are created procedurally.
# ==============================================================================
extends Building
class_name FirepitBuilding


@export_group("Firepit Light")
@export var light_color: Color = Color(1.0, 0.55, 0.15, 1.0)        ## Warm orange flame
@export var blood_moon_light_color: Color = Color(1.0, 0.2, 0.05, 1.0) ## Intense red for Blood Moon
@export var light_energy_night: float = 0.9                           ## Brightness at night
@export var light_energy_day: float = 0.0                            ## Off during the day
@export var light_range: float = 160.0                               ## Radius in pixels
@export var pulse_speed: float = 1.8                                 ## How fast the flame flickers
@export var pulse_strength: float = 0.08                             ## How much the radius fluctuates


var _point_light: PointLight2D = null
var _time_manager: TimeManager = null
var _pulse_time: float = 0.0
var _is_lit: bool = false



## Sets up the firepit light and connects to TimeManager signals.
func _ready():
	super()
	_create_point_light()
	_connect_time_manager()



## Creates the PointLight2D procedurally and adds it as a child.
func _create_point_light():
	_point_light = PointLight2D.new()
	_point_light.name = "FireLight"
	_point_light.texture = _generate_gradient_texture()
	_point_light.color = light_color
	_point_light.energy = light_energy_day   # Start off (assume day)
	_point_light.texture_scale = light_range / 64.0
	_point_light.blend_mode = PointLight2D.BLEND_MODE_ADD
	_point_light.shadow_enabled = false       # No hard shadows — soft ambient glow only
	_point_light.z_index = 10
	add_child(_point_light)



## Generates a radial gradient texture for the light — bright centre, soft falloff.
func _generate_gradient_texture() -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.colors = [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
	gradient.offsets = [0.0, 1.0]

	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex



## Locates TimeManager from the group and connects day/night signals.
func _connect_time_manager():
	var managers = get_tree().get_nodes_in_group("TimeManager")
	if managers.is_empty():
		return

	_time_manager = managers[0] as TimeManager
	if not _time_manager:
		return

	_time_manager.day_started.connect(_on_day_started)
	_time_manager.night_started.connect(_on_night_started)

	# Immediately match whatever state the game is in (e.g. loaded mid-night)
	if _time_manager.is_night:
		_light_on(_time_manager.current_moon_phase)
	else:
		_light_off()



## Gently pulses the light radius and energy each frame to simulate a live flame.
func _process(delta: float):
	if _time_manager:
		if _time_manager.is_night != _is_lit:
			if _time_manager.is_night:
				_light_on(_time_manager.current_moon_phase)
			else:
				_light_off()

	if not _is_lit or not _point_light:
		return

	_pulse_time += delta * pulse_speed
	var flicker = sin(_pulse_time) * pulse_strength + cos(_pulse_time * 1.37) * (pulse_strength * 0.5)
	_point_light.texture_scale = (light_range / 64.0) * (1.0 + flicker)



## Turns the firepit glow on with the correct colour for the moon phase.
func _light_on(moon_phase: TimeManager.MoonPhase):
	if not _point_light:
		return

	_is_lit = true

	match moon_phase:
		TimeManager.MoonPhase.BLOOD:
			_point_light.color = blood_moon_light_color
			_point_light.energy = light_energy_night * 1.4  # More intense on Blood Moon
		TimeManager.MoonPhase.FULL:
			_point_light.color = light_color
			_point_light.energy = light_energy_night * 0.7  # Dimmer — moon provides extra light
		_:
			_point_light.color = light_color
			_point_light.energy = light_energy_night



## Turns the firepit glow off at daytime.
func _light_off():
	if not _point_light:
		return

	_is_lit = false
	_point_light.energy = light_energy_day



## Called at sunrise — extinguishes the light.
func _on_day_started(_day_num: int):
	_light_off()



## Called at sunset — ignites the light using the current moon phase.
func _on_night_started(_day_num: int):
	var moon_phase = TimeManager.MoonPhase.NORMAL
	if _time_manager:
		moon_phase = _time_manager.current_moon_phase
	_light_on(moon_phase)



## Disconnects signals cleanly when the building is removed from the scene tree.
func _exit_tree():
	if is_instance_valid(_time_manager):
		if _time_manager.day_started.is_connected(_on_day_started):
			_time_manager.day_started.disconnect(_on_day_started)
		if _time_manager.night_started.is_connected(_on_night_started):
			_time_manager.night_started.disconnect(_on_night_started)
