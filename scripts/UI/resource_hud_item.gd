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
	unsecured_label.text = ""

func update_values(secured: int, in_transit: int):
	counter.set_value(secured)
	if in_transit > 0:
		unsecured_label.text = "(+%d)  " % in_transit
		unsecured_label.modulate = Color(0.2, 0.8, 0.2)
		unsecured_label.show()
	else:
		unsecured_label.text = "  "
		unsecured_label.hide()
