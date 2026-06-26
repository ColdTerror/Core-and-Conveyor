# ==============================================================================
# Script: UI/split_flap_counter.gd
# Purpose: Manages a 4-digit split-flap display layout, padding numbers with
#          leading zeros and routing character assignments to individual flaps.
# ==============================================================================
extends HBoxContainer
class_name SplitFlapCounter

@onready var digits = [
	$Digit1,
	$Digit2,
	$Digit3,
	$Digit4
]

func set_value(val: int):
	val = clamp(val, 0, 9999)
	var val_str = "%04d" % val
	for i in range(4):
		digits[i].set_target_character(val_str[i])
