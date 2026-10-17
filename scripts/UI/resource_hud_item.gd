# ==============================================================================
# Script: UI/resource_hud_item.gd
# Purpose: Manages a single resource display widget in the HUD, packing name labels,
#          secured split-flap digits, and unsecured static text indicators.
# ==============================================================================
extends HBoxContainer
class_name ResourceHUDItem

@onready var name_label = $NameLabel
@onready var counter = $SplitFlapCounter
@onready var unsecured_label = $UnsecuredLabel

const COLOR_UNSECURED_ACTIVE: Color = Color(0.2, 0.85, 0.2, 1.0)
const COLOR_UNSECURED_IDLE: Color = Color(0.65, 0.65, 0.65, 0.5)
const UNSECURED_MIN_WIDTH: float = 52.0

var current_resource_name: String = ""

func setup(p_resource_name: String) -> void:
	current_resource_name = p_resource_name
	name_label.text = "  %s: " % current_resource_name
	
	# Prevent inventory banner shrinking/jittering when uncounted items update
	unsecured_label.custom_minimum_size = Vector2(UNSECURED_MIN_WIDTH, 0)
	unsecured_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	unsecured_label.text = "(+0)"
	unsecured_label.modulate = COLOR_UNSECURED_IDLE
	
	if counter and counter.has_method("set_size_custom"):
		counter.set_size_custom(32, 40, 32)
	
	# Pass mouse filter so hovering any element triggers the tooltip
	mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	unsecured_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if counter:
		_configure_counter_mouse_filter(counter)
	
	_setup_tooltip()

func update_values(secured: int, in_transit: int) -> void:
	if counter:
		counter.set_value(secured)
	
	if not unsecured_label.visible:
		unsecured_label.show()

	if in_transit > 0:
		unsecured_label.text = "(+%d)" % in_transit
		unsecured_label.modulate = COLOR_UNSECURED_ACTIVE
	else:
		unsecured_label.text = "(+0)"
		unsecured_label.modulate = COLOR_UNSECURED_IDLE

func _setup_tooltip() -> void:
	var tip = "%s Inventory:\n• Main Number: Secured items stored in Core or Stockpiles (available to spend).\n• (+#): Unsecured items held in harvesting buildings, machines, or transit (not yet stored)." % current_resource_name
	tooltip_text = tip
	name_label.tooltip_text = tip
	unsecured_label.tooltip_text = tip
	if counter:
		counter.tooltip_text = tip
		if "digits" in counter:
			for d in counter.digits:
				if d:
					d.tooltip_text = tip

func _configure_counter_mouse_filter(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_configure_counter_mouse_filter(child)
