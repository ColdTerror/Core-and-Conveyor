# ==============================================================================
# Script: Managers/quota_manager.gd
# Purpose: Manages the Requisition Contract Board with 3 distinct Tiers (Raw, Refined,
#          Advanced), tier reputation progression, flexible level selection, a strict 100%
#          resource-saving cap, and midnight Research Points (RP) payouts.
# Dependencies: Global EconomyManager, ResearchManager autoloads, Level scene structures.
# Signals:
#   - quota_progress_updated: Emitted when deliveries, requirements, active contract, or day changes.
#   - daily_evaluation_completed(day: int, rp_earned: int, completion_ratio: float, rep_earned: int, leveled_up: bool, tier_unlocked: bool):
#       Emitted at midnight when daily evaluation finishes and rewards are granted.
# ==============================================================================
class_name QuotaManager
extends Node2D

signal quota_progress_updated
signal daily_evaluation_completed(day: int, rp_earned: int, completion_ratio: float, rep_earned: int, leveled_up: bool, tier_unlocked: bool, scheduled_contract_activated: String)

# MASTER REQUISITION CONTRACT CATALOG
const CONTRACT_CATALOG: Dictionary = {
	1: {
		"title": "Raw Requisition",
		"category": "Basic Materials",
		"desc": "Supply raw timber and stone to maintain foundation scaffolding.",
		"levels": {
			1: { "req": { "Wood": 20, "Stone": 20 }, "rp": 10, "rep_needed": 2 },
			2: { "req": { "Wood": 35, "Stone": 35 }, "rp": 18, "rep_needed": 3 },
			3: { "req": { "Wood": 50, "Stone": 50 }, "rp": 25, "rep_needed": 4 },
			4: { "req": { "Wood": 70, "Stone": 70 }, "rp": 30, "rep_needed": 0 },
		}
	},
	2: {
		"title": "Refined Requisition",
		"category": "Processed Goods",
		"desc": "Deliver sawed planks and masonry stone bricks for reinforced infrastructure.",
		"levels": {
			1: { "req": { "Planks": 15, "Stone Bricks": 15 }, "rp": 25, "rep_needed": 2 },
			2: { "req": { "Planks": 25, "Stone Bricks": 25 }, "rp": 35, "rep_needed": 3 },
			3: { "req": { "Planks": 40, "Stone Bricks": 40 }, "rp": 45, "rep_needed": 4 },
			4: { "req": { "Planks": 55, "Stone Bricks": 55 }, "rp": 50, "rep_needed": 0 },
		}
	},
	3: {
		"title": "Advanced Logistics",
		"category": "High-Tier Munitions",
		"desc": "Ship defensive arrows, smelted iron ingots, and precision materials off-world.",
		"levels": {
			1: { "req": { "Stone Arrow": 20, "Planks": 15, "Iron Ingot": 10 }, "rp": 50, "rep_needed": 3 },
			2: { "req": { "Stone Arrow": 30, "Planks": 25, "Iron Ingot": 15 }, "rp": 60, "rep_needed": 4 },
			3: { "req": { "Stone Arrow": 45, "Planks": 35, "Iron Ingot": 20 }, "rp": 70, "rep_needed": 5 },
			4: { "req": { "Stone Arrow": 60, "Planks": 50, "Iron Ingot": 30 }, "rp": 75, "rep_needed": 0 },
		}
	}
}

var current_day: int = 1
var current_week: int = 1

# Active Contract Selection
var active_tier: int = 1
var active_level: int = 1

# Scheduled Next-Day Contract (-1 if none, meaning auto-renew active contract)
var queued_tier: int = -1
var queued_level: int = -1

# Reputation and Progression State
var tier_reputation: Dictionary = { 1: 0, 2: 0, 3: 0 }
var tier_max_level: Dictionary = { 1: 1, 2: 1, 3: 1 }
var unlocked_tiers: Array = [1]

var daily_requirements: Dictionary = {}
var daily_delivered: Dictionary = {}

var successful_days: int = 0
var weekly_history: Array[bool] = []
var level_ref: Node2D

var is_today_scored: bool = false
var last_day_rp_earned: int = 0
var last_day_completion_ratio: float = 0.0



## Binds this manager to the active level and synchronizes day/contract state.
func initialize(level_instance: Node2D):
	level_ref = level_instance
	
	if level_ref and level_ref.has_node("TimeManager"):
		var tm = level_ref.get_node("TimeManager")
		current_day = tm.current_day
		current_week = int((current_day - 1) / 7) + 1
		
	if daily_requirements.is_empty():
		if current_day > 2:
			daily_requirements = get_contract_requirements(active_tier, active_level)
		else:
			daily_requirements = {}
			
	_reset_daily_deliveries()
	quota_progress_updated.emit()



## Checks whether a requisition tier is currently unlocked for selection.
func is_tier_unlocked(tier: int) -> bool:
	return tier in unlocked_tiers



## Returns the maximum unlocked level for a given tier.
func get_tier_max_level(tier: int) -> int:
	return tier_max_level.get(tier, 1)



## Returns the current reputation progress in a tier.
func get_tier_reputation(tier: int) -> int:
	return tier_reputation.get(tier, 0)



## Returns reputation points needed to advance to the next level in a tier (0 if at max level).
func get_reputation_needed_for_next_level(tier: int, current_lvl: int) -> int:
	var catalog = CONTRACT_CATALOG.get(tier, {})
	var levels = catalog.get("levels", {})
	if levels.has(current_lvl):
		return levels[current_lvl].get("rep_needed", 0)
	return 0



## Returns static information for a specific tier in the catalog.
func get_contract_definition(tier: int) -> Dictionary:
	return CONTRACT_CATALOG.get(tier, {})



## Returns level metadata (req, rp, rep_needed) for a specific tier and level.
func get_level_data(tier: int, level: int) -> Dictionary:
	var cat = CONTRACT_CATALOG.get(tier, {})
	var levels = cat.get("levels", {})
	return levels.get(level, {})



## Returns item requirements dictionary for a specific tier and level.
func get_contract_requirements(tier: int, level: int) -> Dictionary:
	var lvl_data = get_level_data(tier, level)
	if lvl_data.has("req"):
		return lvl_data["req"].duplicate()
	return {}



## Returns base Research Points reward for a specific tier and level.
func get_contract_rp(tier: int, level: int) -> int:
	var lvl_data = get_level_data(tier, level)
	return lvl_data.get("rp", 0)



## Returns the base RP payout for the currently active contract.
func get_active_contract_rp() -> int:
	return get_contract_rp(active_tier, active_level)



## Switches the active requisition contract immediately, updating today's requirements.
func select_contract(tier: int, level: int) -> bool:
	if not is_tier_unlocked(tier):
		return false
		
	var max_lvl = get_tier_max_level(tier)
	level = clamp(level, 1, max_lvl)
	
	active_tier = tier
	active_level = level
	queued_tier = -1
	queued_level = -1
	
	if current_day > 2:
		daily_requirements = get_contract_requirements(active_tier, active_level)
		_reset_daily_deliveries()
		is_today_scored = false
		
	quota_progress_updated.emit()
	return true



## Schedules a contract to activate cleanly at midnight with zero resource loss today.
func schedule_contract_for_tomorrow(tier: int, level: int) -> bool:
	if not is_tier_unlocked(tier):
		return false
		
	var max_lvl = get_tier_max_level(tier)
	level = clamp(level, 1, max_lvl)
	
	if tier == active_tier and level == active_level:
		cancel_scheduled_contract()
		return true
		
	queued_tier = tier
	queued_level = level
	quota_progress_updated.emit()
	return true



## Cancels any scheduled contract, reverting to auto-renewing today's contract tomorrow.
func cancel_scheduled_contract():
	queued_tier = -1
	queued_level = -1
	quota_progress_updated.emit()



## Checks whether an explicit contract change is scheduled for tomorrow.
func has_scheduled_contract() -> bool:
	return queued_tier != -1 and (queued_tier != active_tier or queued_level != active_level)



## Returns details of the contract scheduled for tomorrow, or empty dict if none.
func get_scheduled_contract_info() -> Dictionary:
	if not has_scheduled_contract():
		return {}
	var cat = get_contract_definition(queued_tier)
	return {
		"tier": queued_tier,
		"level": queued_level,
		"title": cat.get("title", "Contract"),
		"req": get_contract_requirements(queued_tier, queued_level),
		"rp": get_contract_rp(queued_tier, queued_level)
	}



## Checks whether the delivery of the specified resource is accepted today.
## Strictly enforces a 100% cap to preserve player resources.
func can_accept_item(item_name: String) -> bool:
	if not daily_requirements.has(item_name): 
		return false 
		
	var needed = daily_requirements[item_name]
	var have = daily_delivered.get(item_name, 0)
	
	return have < needed



## Computes amount accepted today for an item, stopping strictly at 100%.
func get_needed_amount(item_name: String, offered_amount: int) -> int:
	if not daily_requirements.has(item_name):
		return 0
		
	var total_required = daily_requirements[item_name]
	var currently_have = daily_delivered.get(item_name, 0)
	
	var space_left = total_required - currently_have
	if space_left <= 0:
		return 0
		
	return min(offered_amount, space_left)



## Receives a delivery of items towards daily quota requirements.
func deliver_item(item_name: String, amount: int):
	if not daily_requirements.has(item_name):
		return

	if not daily_delivered.has(item_name):
		daily_delivered[item_name] = 0
		
	daily_delivered[item_name] += amount
	EconomyManager.log_item_consumed(item_name, amount)
	
	if not is_today_scored and _is_daily_quota_met():
		is_today_scored = true
		successful_days += 1
			
	quota_progress_updated.emit()



## Calculates current overall daily completion ratio (clamped between 0.0 and 1.0).
func get_daily_completion_ratio() -> float:
	if daily_requirements.is_empty():
		return 1.0
		
	var total_req: int = 0
	var total_deliv: int = 0
	for item in daily_requirements:
		var req = daily_requirements[item]
		total_req += req
		var deliv = clamp(daily_delivered.get(item, 0), 0, req)
		total_deliv += deliv
		
	if total_req <= 0:
		return 1.0
	return clamp(float(total_deliv) / float(total_req), 0.0, 1.0)



## Calculates projected RP payout based on live deliveries.
func get_projected_rp_for_today() -> int:
	if daily_requirements.is_empty():
		return 0
		
	var base_rp = get_active_contract_rp()
	var ratio = get_daily_completion_ratio()
	
	if ratio >= 1.0:
		return base_rp
	else:
		return int(round(base_rp * (ratio * 0.5)))



## Evaluates whether the active contract is 100% fulfilled.
func _is_daily_quota_met() -> bool:
	if daily_requirements.is_empty():
		return true
	for item_name in daily_requirements:
		var needed = daily_requirements[item_name]
		var have = daily_delivered.get(item_name, 0)
		if have < needed:
			return false
	return true



## Processes midnight score checking, pays out RP, and advances Reputation / Levels.
func process_end_of_day(day_evaluated: int = -1):
	if day_evaluated != -1:
		current_day = day_evaluated
		
	var base_rp = get_active_contract_rp()
	var completion_ratio = get_daily_completion_ratio()
	var rp_earned: int = 0
	var rep_earned: int = 0
	var leveled_up: bool = false
	var new_tier_unlocked: bool = false
	
	if not daily_requirements.is_empty():
		if completion_ratio >= 1.0:
			rp_earned = base_rp
			rep_earned = 1
			tier_reputation[active_tier] = tier_reputation.get(active_tier, 0) + 1
			
			# Check if Reputation threshold is met to level up
			var cur_max_lvl = get_tier_max_level(active_tier)
			var rep_needed = get_reputation_needed_for_next_level(active_tier, cur_max_lvl)
			if rep_needed > 0 and tier_reputation[active_tier] >= rep_needed:
				tier_reputation[active_tier] -= rep_needed
				tier_max_level[active_tier] = cur_max_lvl + 1
				active_level = tier_max_level[active_tier]
				leveled_up = true
				
				# Check Tier Unlocks
				if active_tier == 1 and tier_max_level[1] >= 2 and not is_tier_unlocked(2):
					unlocked_tiers.append(2)
					new_tier_unlocked = true
				elif active_tier == 2 and tier_max_level[2] >= 2 and not is_tier_unlocked(3):
					unlocked_tiers.append(3)
					new_tier_unlocked = true
		else:
			# Partial delivery: halved penalty (e.g. 50% delivery = 25% RP payout)
			rp_earned = int(round(base_rp * (completion_ratio * 0.5)))
			
		if rp_earned > 0 and ResearchManager:
			ResearchManager.add_research_points(rp_earned)
			print("Contract Midnight Evaluation: Day %d completed at %.1f%%. Awarded %d RP!" % [current_day, completion_ratio * 100.0, rp_earned])
			
	var was_met = completion_ratio >= 1.0 or daily_requirements.is_empty()
	if not is_today_scored and was_met and not daily_requirements.is_empty():
		is_today_scored = true
		successful_days += 1
		
	weekly_history.append(was_met)
	last_day_rp_earned = rp_earned
	last_day_completion_ratio = completion_ratio
	is_today_scored = false
	
	var scheduled_activation_name: String = ""
	if has_scheduled_contract():
		var sched_cat = get_contract_definition(queued_tier)
		var sched_title = sched_cat.get("title", "Contract")
		scheduled_activation_name = "Tier %d (Level %d) - %s" % [queued_tier, queued_level, sched_title]
	
	daily_evaluation_completed.emit(current_day, rp_earned, completion_ratio, rep_earned, leveled_up, new_tier_unlocked, scheduled_activation_name)
	quota_progress_updated.emit()



## Sets up the quota requirements for the new calendar day.
func start_next_day(new_day: int):
	current_day = new_day
	current_week = int((new_day - 1) / 7) + 1
	
	if has_scheduled_contract():
		active_tier = queued_tier
		active_level = queued_level
		queued_tier = -1
		queued_level = -1
		
	_reset_daily_deliveries()
	
	if new_day > 2:
		daily_requirements = get_contract_requirements(active_tier, active_level)
	else:
		daily_requirements = {}
		
	is_today_scored = false
	quota_progress_updated.emit()



## Cleans weekly tracking records at the end of each week.
func process_end_of_week():
	successful_days = 0
	weekly_history.clear()
	is_today_scored = false
	quota_progress_updated.emit()



## Empties daily delivery storage dict tracking resource counts.
func _reset_daily_deliveries():
	daily_delivered.clear()
	for key in daily_requirements.keys():
		daily_delivered[key] = 0



## Packages current contract requisition state, reputation, and scoring history for saving.
func get_save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"current_week": current_week,
		"active_tier": active_tier,
		"active_level": active_level,
		"queued_tier": queued_tier,
		"queued_level": queued_level,
		"tier_reputation": tier_reputation,
		"tier_max_level": tier_max_level,
		"unlocked_tiers": unlocked_tiers,
		"successful_days": successful_days,
		"weekly_history": weekly_history,
		"daily_requirements": daily_requirements,
		"daily_delivered": daily_delivered,
		"is_today_scored": is_today_scored,
		"last_day_rp_earned": last_day_rp_earned,
		"last_day_completion_ratio": last_day_completion_ratio
	}



## Unpacks saved requisition variables and restores state.
func load_save_data(data: Dictionary):
	current_day = data.get("current_day", 1)
	current_week = data.get("current_week", 1)
	active_tier = data.get("active_tier", 1)
	active_level = data.get("active_level", 1)
	queued_tier = data.get("queued_tier", -1)
	queued_level = data.get("queued_level", -1)
	
	if data.has("tier_reputation"):
		tier_reputation = data["tier_reputation"]
	else:
		tier_reputation = { 1: 0, 2: 0, 3: 0 }
		
	if data.has("tier_max_level"):
		tier_max_level = data["tier_max_level"]
	else:
		tier_max_level = { 1: 1, 2: 1, 3: 1 }
		
	if data.has("unlocked_tiers"):
		unlocked_tiers = data["unlocked_tiers"]
	else:
		unlocked_tiers = [1]
		
	successful_days = data.get("successful_days", 0)
	var saved_history = data.get("weekly_history", [])
	weekly_history.assign(saved_history)
	is_today_scored = data.get("is_today_scored", false)
	last_day_rp_earned = data.get("last_day_rp_earned", 0)
	last_day_completion_ratio = data.get("last_day_completion_ratio", 0.0)
	
	if data.has("daily_requirements"):
		daily_requirements = data["daily_requirements"]
	else:
		if current_day > 2:
			daily_requirements = get_contract_requirements(active_tier, active_level)
		else:
			daily_requirements = {}
			
	if data.has("daily_delivered"):
		daily_delivered = data["daily_delivered"]
	else:
		_reset_daily_deliveries()
		
	quota_progress_updated.emit()
