
class_name QuotaBuilding
extends Building


var level_ref: Node2D
var _q_manager: QuotaManager

func setup(level_instance: Node2D):
	level_ref = level_instance
	if level_ref.has_node("QuotaManager"):
		_q_manager = level_ref.get_node("QuotaManager")
		
		# Force our UI to refresh whenever ANY quota building eats an item!
		_q_manager.quota_progress_updated.connect(func(): inventory_changed.emit())

# ==========================================
# BELT FEEDING LOGIC
# ==========================================

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

# ==========================================
# UI INFO FOR DETAIL MENU
# ==========================================
func get_inventory_info() -> Dictionary:
	var info = {}
	if not _q_manager: return info
	
	var is_fully_safe = true
	
	# Dynamically list every item required for the quota
	for item_name in _q_manager.daily_requirements:
		var needed = _q_manager.daily_requirements[item_name]
		var have = _q_manager.daily_delivered.get(item_name, 0)
		info[item_name] = "%d / %d" % [have, needed]
		if have < needed:
			is_fully_safe = false
			
	info["Weekly Success"] = "%d / 7 Days" % [_q_manager.successful_days]
	info["Status"] = "SAFE TODAY" if is_fully_safe else "AWAITING MATERIALS"
	
	return info
