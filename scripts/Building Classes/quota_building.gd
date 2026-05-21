
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

# --- UPGRADED: LIGHT UPDATE LOGIC ---
func _update_lights():
	if not _q_manager or not lights_parent: return
	
	# 1. GRACE PERIOD OVERRIDE: If no quota exists, turn all 7 lights ON!
	if _q_manager.daily_requirements.is_empty():
		for day_index in range(1, 8):
			var light_node = lights_parent.get_node_or_null("Light" + str(day_index))
			if light_node:
				light_node.visible = true
		return # Exit early, we don't need to check history

	# 2. NORMAL WEEK LOGIC
	var history: Array[bool] = []
	if "weekly_history" in _q_manager:
		history = _q_manager.weekly_history

	for day_index in range(1, 8):
		var light_node = lights_parent.get_node_or_null("Light" + str(day_index))
		if light_node:
			var array_index = day_index - 1
			
			if array_index < history.size():
				# PAST DAYS: Read the history array
				light_node.visible = history[array_index]
				
			elif array_index == history.size():
				# TODAY: Don't wait for midnight! Turn on instantly if the live quota is met.
				light_node.visible = _q_manager._is_daily_quota_met()
				
			else:
				# FUTURE DAYS: Always off until we reach them
				light_node.visible = false
# BELT FEEDING LOGIC

# 1. We NO LONGER use needs_materials(). Bots will ignore this building!

# 2. Tell the belts they can push items directly into our tiles
func accepts_item_at(_tile: Vector2i) -> bool:
	return true 

# 3. Check with the Global Manager if this item is currently needed
func can_accept_item(item: ItemResource) -> bool:
	if not _q_manager: return false
	return _q_manager.can_accept_item(item.display_name)

# 4. Eat the item off the belt and send it to the Global Manager
func add_item(item: ItemResource, amount: int) -> int:
	# Ask the manager: "I have X amount, how much of that do you actually need?"
	var amount_needed = _q_manager.get_needed_amount(item.display_name, amount)
	if amount_needed > 0:
		_q_manager.deliver_item(item.display_name, amount_needed)
		# We return amount_needed. 
		# If amount_needed < amount, the belt might still stall or 
		# you can logic it to 'crush' the extra, but usually, 
		# for automation, we return the full amount if we took any part of it
		# or exactly what was consumed. Let's return the amount consumed:
		return amount_needed
		
	return 0 # Quota for this item is already 100% full

# UI INFO FOR DETAIL MENU
func get_inventory_info() -> Dictionary:
	if not level_ref or not level_ref.has_node("QuotaManager"): 
		return {}
		
	var qm = level_ref.get_node("QuotaManager")
	var info = {}
	
	# --- NEW: GRACE PERIOD OVERRIDE ---
	if qm.daily_requirements.is_empty():
		info["Status"] = "GRACE PERIOD"
		info["Weekly Success"] = "7 / 7 Days"
		return info


	# (Keep your existing logic below this!)
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
