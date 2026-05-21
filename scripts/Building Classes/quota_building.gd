# ==============================================================================
# Script: Building Classes/quota_building.gd
# Purpose: Defensive quota receiver building that accepts required items from conveyor networks to fund/satisfy daily quotas, updates weekly progress indicator lights (grace period support), and communicates progress back to the global QuotaManager.
# Dependencies: Inherits Building. Requires QuotaManager, global Autoload QuotaManager/EconomyManager, and child Light nodes.
# Signals: Inherits signals from Building (such as inventory_changed).
# ==============================================================================
class_name QuotaBuilding
extends Building

var level_ref: Node2D
var _q_manager: QuotaManager

@onready var lights_parent = $Lights


## Configures active level references, maps quota manager callbacks, and updates indicator lights.
func setup(level_instance: Node2D):
	level_ref = level_instance
	if level_ref.has_node("QuotaManager"):
		_q_manager = level_ref.get_node("QuotaManager")
		
		# Force our UI to refresh whenever ANY quota building eats an item!
		_q_manager.quota_progress_updated.connect(func(): 
			inventory_changed.emit()
			_update_lights()
		)
		
		_update_lights()



## Sets indicator lights based on past success history and today's completed quotas.
func _update_lights():
	if not _q_manager or not lights_parent: return
	
	# GRACE PERIOD OVERRIDE: If no active quota exists, light all 7 bulbs
	if _q_manager.daily_requirements.is_empty():
		for day_index in range(1, 8):
			var light_node = lights_parent.get_node_or_null("Light" + str(day_index))
			if light_node:
				light_node.visible = true
		return

	var history: Array[bool] = []
	if "weekly_history" in _q_manager:
		history = _q_manager.weekly_history

	for day_index in range(1, 8):
		var light_node = lights_parent.get_node_or_null("Light" + str(day_index))
		if light_node:
			var array_index = day_index - 1
			
			if array_index < history.size():
				# PAST DAYS: Read the history records
				light_node.visible = history[array_index]
				
			elif array_index == history.size():
				# TODAY: Light up instantly once live quota goals are met
				light_node.visible = _q_manager._is_daily_quota_met()
				
			else:
				# FUTURE DAYS: Kept off until reached
				light_node.visible = false



## Verifies if conveyor belt networks can feed items directly into the structure.
func accepts_item_at(_tile: Vector2i) -> bool:
	return true 



## Validates if the item type matches active daily quota requirements.
func can_accept_item(item: ItemResource) -> bool:
	if not _q_manager: return false
	return _q_manager.can_accept_item(item.display_name)



## Swallows the item from the belt and registers it against active daily quotas.
func add_item(item: ItemResource, amount: int) -> int:
	var amount_needed = _q_manager.get_needed_amount(item.display_name, amount)
	if amount_needed > 0:
		_q_manager.deliver_item(item.display_name, amount_needed)
		return amount_needed
		
	return 0



## Summarizes daily quota status, item delivery counts, and weekly progress metrics.
func get_inventory_info() -> Dictionary:
	if not level_ref or not level_ref.has_node("QuotaManager"): 
		return {}
		
	var qm = level_ref.get_node("QuotaManager")
	var info = {}
	
	if qm.daily_requirements.is_empty():
		info["Status"] = "GRACE PERIOD"
		info["Weekly Success"] = "7 / 7 Days"
		return info

	if qm._is_daily_quota_met():
		info["Status"] = "SAFE TODAY"
	else:
		info["Status"] = "PENDING"
		
	info["Weekly Success"] = "%d / 7 Days" % qm.successful_days
	
	for item in qm.daily_requirements.keys():
		var needed = qm.daily_requirements[item]
		var have = qm.daily_delivered.get(item, 0)
		info[item] = "%d / %d" % [have, needed]
		
	return info
