# ==============================================================================
# Script: CostData.gd
# Purpose: Custom resource holding an item name and quantity mapping. Used for
#          general building cost and upgrade cost definitions.
# Dependencies: None.
# Signals: None.
# ==============================================================================
extends Resource
class_name CostData

# If you ever switch to ItemResources later, you just change this line!
@export var item_name: String = "Wood" 
@export var amount: int = 5
