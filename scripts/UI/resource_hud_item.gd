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

func setup(resource_name: String):
	name_label.text = "  %s: " % resource_name
	unsecured_label.text = "(+00) "
	unsecured_label.modulate = Color(0, 0, 0, 0)
	if counter and counter.has_method("set_size_custom"):
		counter.set_size_custom(32, 40, 32)

func update_values(secured: int, in_transit: int):
	counter.set_value(secured)
	unsecured_label.show()
	if in_transit > 0:
		unsecured_label.text = "(+%d) " % in_transit
		unsecured_label.modulate = Color(0.2, 0.8, 0.2, 1.0)
	else:
		unsecured_label.text = "(+00) "
		unsecured_label.modulate = Color(0, 0, 0, 0)
