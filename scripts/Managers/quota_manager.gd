# ==============================================================================
# Script: Managers/quota_manager.gd
# Purpose: Manages progressive daily quotas (starting Day 3), validates items fed from
#          belts into the quota building (up to 200% surplus cap), evaluates delivery ratios,
#          and credits Research Points (RP) at midnight based on performance.
# Dependencies: Global EconomyManager, ResearchManager autoloads, Level scene structures.
# Signals:
#   - quota_progress_updated: Emitted when deliveries, requirements, or days change.
#   - daily_evaluation_completed(day: int, rp_earned: int, completion_ratio: float):
#       Emitted at midnight when daily evaluation finishes and RP is credited.
# ==============================================================================
class_name QuotaManager
extends Node2D

signal quota_progress_updated
signal daily_evaluation_completed(day: int, rp_earned: int, completion_ratio: float)

@export var quota_growth_per_week: int = 50

var current_day: int = 1
var current_week: int = 1
var daily_requirements: Dictionary = {}
var daily_delivered: Dictionary = {}

var successful_days: int = 0
var weekly_history: Array[bool] = []
var max_weekly_corruption: float = 100.0
var level_ref: Node2D

var is_today_scored: bool = false 
var last_day_rp_earned: int = 0
var last_day_completion_ratio: float = 0.0



## Binds this manager to the active level and sets up day 1 / loaded state.
func initialize(level_instance: Node2D):
	level_ref = level_instance
	
	if level_ref and level_ref.has_node("TimeManager"):
		var tm = level_ref.get_node("TimeManager")
		current_day = tm.current_day
		current_week = int((current_day - 1) / 7) + 1
		
	if daily_requirements.is_empty():
		daily_requirements = get_quota_for_day(current_day)
		
	_reset_daily_deliveries()
	quota_progress_updated.emit()



## Computes resource quota requirements for a given day.
## Days 1-2: Grace Period (empty).
## Days 3-7: First Quota (raw Wood & Stone).
## Week 2+: Progressive expansion.
func get_quota_for_day(day: int) -> Dictionary:
	if day <= 2:
		return {} # Grace period for days 1 and 2
		
	var week = int((day - 1) / 7) + 1
	var quota: Dictionary = {}
	
	if week == 1:
		# Days 3-7: Starter delivery (50 raw items)
		quota["Wood"] = 25
		quota["Stone"] = 25
	elif week == 2:
		# Week 2 (Days 8-14): Expanded raw materials (80 items)
		var total_vol = 80
		quota["Wood"] = int(total_vol * 0.5)
		quota["Stone"] = total_vol - quota["Wood"]
	elif week == 3:
		# Week 3 (Days 15-21): Basic processing mix (120 items)
		var total_vol = 120
		quota["Wood"] = int(total_vol * 0.25)
		quota["Stone"] = int(total_vol * 0.25)
		quota["Planks"] = int(total_vol * 0.20)
		quota["Stone Bricks"] = int(total_vol * 0.20)
		quota["Stone Arrow"] = total_vol - quota["Wood"] - quota["Stone"] - quota["Planks"] - quota["Stone Bricks"]
	elif week == 4:
		# Week 4 (Days 22-28): Advanced processing (150 items)
		var total_vol = 150
		quota["Planks"] = int(total_vol * 0.40)
		quota["Stone Bricks"] = int(total_vol * 0.40)
		quota["Stone Arrow"] = total_vol - quota["Planks"] - quota["Stone Bricks"]
	else:
		# Year 2+ Infinite mathematically scaled composition
		var total_vol = 150 + (week - 4) * quota_growth_per_week
		quota["Wood"] = int(total_vol * 0.15)
		quota["Stone"] = int(total_vol * 0.15)
		quota["Planks"] = int(total_vol * 0.28)
		quota["Stone Bricks"] = int(total_vol * 0.28)
		quota["Stone Arrow"] = total_vol - quota["Wood"] - quota["Stone"] - quota["Planks"] - quota["Stone Bricks"]
		
	return quota



## Compatibility function returning base quota for the given week.
func get_quota_for_week(week: int) -> Dictionary:
	var representative_day = (week - 1) * 7 + (3 if week == 1 else 1)
	return get_quota_for_day(representative_day)



## Returns the base Research Points reward for completing 100% of the day's quota.
func get_base_rp_for_day(day: int) -> int:
	if day <= 2:
		return 0 # Grace period
	var week = int((day - 1) / 7) + 1
	if week == 1:
		return 50 # Day 3-7
	return 50 + (week - 1) * 20 # Week 2 = 70 RP, Week 3 = 90 RP, Week 4 = 110 RP



## Checks whether the delivery of the specified resource is accepted.
## Accepts up to 200% of the required daily amount (surplus cap).
func can_accept_item(item_name: String) -> bool:
	if not daily_requirements.has(item_name): 
		return false 
		
	var needed = daily_requirements[item_name]
	var max_allowed = needed * 2
	var have = daily_delivered.get(item_name, 0)
	
	return have < max_allowed



## Computes amount accepted today for an item, respecting the 200% surplus cap.
func get_needed_amount(item_name: String, offered_amount: int) -> int:
	if not daily_requirements.has(item_name):
		return 0
		
	var total_required = daily_requirements[item_name]
	var max_allowed = total_required * 2
	var currently_have = daily_delivered.get(item_name, 0)
	
	var space_left = max_allowed - currently_have
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
	
	# Mark scored for the day if 100% baseline is reached
	if not is_today_scored and _is_daily_quota_met():
		is_today_scored = true
		successful_days += 1
			
	quota_progress_updated.emit()



## Calculates current overall daily completion ratio (1.0 = 100%, 2.0 = 200% cap).
func get_daily_completion_ratio() -> float:
	if daily_requirements.is_empty():
		return 1.0 # Grace period is counted as satisfied
		
	var total_req: int = 0
	var total_deliv: int = 0
	for item in daily_requirements:
		var req = daily_requirements[item]
		total_req += req
		var deliv = clamp(daily_delivered.get(item, 0), 0, req * 2)
		total_deliv += deliv
		
	if total_req <= 0:
		return 1.0
	return float(total_deliv) / float(total_req)



## Calculates projected RP payout based on live deliveries.
func get_projected_rp_for_today() -> int:
	if daily_requirements.is_empty():
		return 0
		
	var base_rp = get_base_rp_for_day(current_day)
	var ratio = get_daily_completion_ratio()
	
	if ratio < 1.0:
		# Under 100%: Halved return penalty (e.g. 80% delivery gives 40% RP)
		return int(round(base_rp * (ratio * 0.5)))
	else:
		# 100% to 200%: Base 100% RP + up to 25% surplus bonus
		var surplus_ratio = clamp(ratio - 1.0, 0.0, 1.0)
		return int(round(base_rp * (1.0 + 0.25 * surplus_ratio)))



## Evaluates whether the 100% baseline quota has been met today.
func _is_daily_quota_met() -> bool:
	if daily_requirements.is_empty():
		return true
	for item_name in daily_requirements:
		var needed = daily_requirements[item_name]
		var have = daily_delivered.get(item_name, 0)
		if have < needed:
			return false
	return true



## Evaluates whether all items have reached the 200% surplus cap.
func _is_daily_quota_maxed() -> bool:
	if daily_requirements.is_empty():
		return true
	for item_name in daily_requirements:
		var max_allowed = daily_requirements[item_name] * 2
		var have = daily_delivered.get(item_name, 0)
		if have < max_allowed:
			return false
	return true



## Processes midnight score checking and pays out Research Points.
func process_end_of_day(day_evaluated: int = -1):
	if day_evaluated != -1:
		current_day = day_evaluated
		
	var base_rp = get_base_rp_for_day(current_day)
	var completion_ratio = get_daily_completion_ratio()
	var rp_earned: int = 0
	
	if not daily_requirements.is_empty():
		if completion_ratio < 1.0:
			# Partial delivery: halved penalty (e.g. 80% completion = 40% RP payout)
			rp_earned = int(round(base_rp * (completion_ratio * 0.5)))
		else:
			# Baseline met + surplus up to 200% gives up to 125% RP (+25% bonus)
			var surplus_ratio = clamp(completion_ratio - 1.0, 0.0, 1.0)
			rp_earned = int(round(base_rp * (1.0 + 0.25 * surplus_ratio)))
			
		if rp_earned > 0 and ResearchManager:
			ResearchManager.add_research_points(rp_earned)
			print("Quota Midnight Evaluation: Day %d completed at %.1f%%. Awarded %d Research Points!" % [current_day, completion_ratio * 100.0, rp_earned])
			
	var was_met = completion_ratio >= 1.0 or daily_requirements.is_empty()
	if not is_today_scored and was_met and not daily_requirements.is_empty():
		is_today_scored = true
		successful_days += 1
		
	weekly_history.append(was_met)
	last_day_rp_earned = rp_earned
	last_day_completion_ratio = completion_ratio
	is_today_scored = false
	
	daily_evaluation_completed.emit(current_day, rp_earned, completion_ratio)
	quota_progress_updated.emit()



## Sets up the quota requirements for the new calendar day.
func start_next_day(new_day: int):
	current_day = new_day
	current_week = int((new_day - 1) / 7) + 1
	_reset_daily_deliveries()
	daily_requirements = get_quota_for_day(new_day)
	is_today_scored = false
	quota_progress_updated.emit()



## Cleans weekly tracking records at the end of each week.
## Note: Quota failure no longer penalizes waves or corruption!
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



## Packages current quota scoring history and variables for saving.
func get_save_data() -> Dictionary:
	return {
		"successful_days": successful_days,
		"weekly_history": weekly_history,
		"current_week": current_week,
		"current_day": current_day,
		"daily_requirements": daily_requirements,
		"daily_delivered": daily_delivered,
		"is_today_scored": is_today_scored,
		"last_day_rp_earned": last_day_rp_earned,
		"last_day_completion_ratio": last_day_completion_ratio
	}



## Unpacks saved quota variables and updates UI state.
func load_save_data(data: Dictionary):
	successful_days = data.get("successful_days", 0)
	var saved_history = data.get("weekly_history", [])
	weekly_history.assign(saved_history)
	current_week = data.get("current_week", 1)
	current_day = data.get("current_day", 1)
	is_today_scored = data.get("is_today_scored", false)
	last_day_rp_earned = data.get("last_day_rp_earned", 0)
	last_day_completion_ratio = data.get("last_day_completion_ratio", 0.0)
	
	if data.has("daily_requirements"):
		daily_requirements = data["daily_requirements"]
	else:
		daily_requirements = get_quota_for_day(current_day)
		
	if data.has("daily_delivered"):
		daily_delivered = data["daily_delivered"]
	else:
		_reset_daily_deliveries()
		
	quota_progress_updated.emit()
