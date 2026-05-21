# ==============================================================================
# Script: Managers/quota_manager.gd
# Purpose: Manages the progressive weekly quotas (infinite mathematically scaled algorithm), validates items fed from belts into the quota building, triggers daily score checks, and coordinates with wave/corruption managers on end-of-week failures.
# Dependencies: Global EconomyManager autoload, Level scene structures.
# Signals:
#   - quota_progress_updated: Emitted when quota progress or deliveries change.
# ==============================================================================
class_name QuotaManager
extends Node2D

signal quota_progress_updated

var current_week: int = 1
var daily_requirements: Dictionary = {}
var daily_delivered: Dictionary = {}

var successful_days: int = 0
var weekly_history: Array[bool] = []
var max_weekly_corruption: float = 100.0
var level_ref: Node2D

# --- NEW: Tracks if we already gave the player a point today! ---
var is_today_scored: bool = false 



## Binds this manager to the active level and resets daily delivery tracking.
func initialize(level_instance: Node2D):
	level_ref = level_instance
	
	if daily_requirements.is_empty():
		daily_requirements = get_quota_for_week(current_week)
		
	_reset_daily_deliveries()



## Computes resource quota requirements for the designated week using mathematical scaling.
func get_quota_for_week(week: int) -> Dictionary:
	if week <= 1:
		return {} 
		
	var offset_week = week - 2
	var cycle = offset_week / 5 
	var step = offset_week % 5 
	
	var base_refined_items = cycle * 100
	var step_ratio = float(step) / 4.0 
	var transitioning_refined = int(100.0 * step_ratio)
	var transitioning_raw = 100 - transitioning_refined
	
	var total_refined = base_refined_items + transitioning_refined
	var total_raw = transitioning_raw
	
	var quota = {}
	
	if total_raw > 0:
		quota["Wood"] = int(total_raw * 0.5)
		quota["Stone"] = int(total_raw * 0.5)
		
	if total_refined > 0:
		quota["Planks"] = int(total_refined * 0.4)
		quota["Stone Bricks"] = int(total_refined * 0.4)
		
		var arrows = total_refined - quota["Planks"] - quota["Stone Bricks"]
		if arrows > 0:
			quota["Stone Arrow"] = arrows
			
	return quota



## Checks whether the delivery of the specified resource is still required today.
func can_accept_item(item_name: String) -> bool:
	if not daily_requirements.has(item_name): 
		return false 
		
	var needed = daily_requirements[item_name]
	var have = daily_delivered.get(item_name, 0)
	
	return have < needed 



## Computes the exact amount needed to complete quota fulfillment for the resource.
func get_needed_amount(item_name: String, offered_amount: int) -> int:
	if not daily_requirements.has(item_name):
		return 0
		
	var total_required = daily_requirements[item_name]
	var currently_have = daily_delivered.get(item_name, 0)
	
	var space_left = total_required - currently_have
	
	if space_left <= 0:
		return 0
		
	return min(offered_amount, space_left)



## Receives a delivery of items towards meeting daily quota requirements.
func deliver_item(item_name: String, amount: int):
	if not daily_requirements.has(item_name):
		return

	if not daily_delivered.has(item_name):
		daily_delivered[item_name] = 0
		
	daily_delivered[item_name] += amount
	EconomyManager.log_item_consumed(item_name, amount)
	
	# Award the point instantly without waiting for midnight!
	if not is_today_scored and _is_daily_quota_met():
		is_today_scored = true
		successful_days += 1
		
		# Quota finish sound placeholder
		# if ClassDB.class_exists("AudioManager"):
		# 	AudioManager.play_sfx("quota_complete")
			
	quota_progress_updated.emit()



## Evaluates whether all daily requirements have been met.
func _is_daily_quota_met() -> bool:
	for item_name in daily_requirements:
		var needed = daily_requirements[item_name]
		var have = daily_delivered.get(item_name, 0)
		if have < needed:
			return false
	return true



## Processes midnight score checking and resets deliveries.
func process_end_of_day():
	# Grace periods (Week 1) don't receive items, so they never trigger the instant score.
	# We safely catch them here at midnight!
	if not is_today_scored and _is_daily_quota_met():
		is_today_scored = true
		successful_days += 1
		
	weekly_history.append(is_today_scored)
	is_today_scored = false
	
	_reset_daily_deliveries()
	quota_progress_updated.emit()



## Applies corruption penalties at the end of the week if quotas were failed.
func process_end_of_week():
	if current_week > 1:
		var failure_ratio: float = 1.0 - (float(successful_days) / 7.0)
		var penalty: int = int(max_weekly_corruption * failure_ratio)
		
		if penalty > 0:
			print("Week Failed! Applying penalty amount: ", penalty)
			# Play a global warning siren here
			
			if level_ref:
				level_ref.corruption_manager.apply_quota_penalty(penalty)
				
			if level_ref:
				level_ref.wave_manager.apply_quota_penalty(penalty)
			
	successful_days = 0
	weekly_history.clear()
	is_today_scored = false
	_reset_daily_deliveries()
	
	current_week += 1
	daily_requirements = get_quota_for_week(current_week)
	
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
		"daily_requirements": daily_requirements,
		"daily_delivered": daily_delivered,
		"is_today_scored": is_today_scored
	}


## Unpacks saved quota variables and updates UI state.
func load_save_data(data: Dictionary):
	successful_days = data.get("successful_days", 0)
	var saved_history = data.get("weekly_history", [])
	weekly_history.assign(saved_history)
	current_week = data.get("current_week", 1)
	is_today_scored = data.get("is_today_scored", false)
	
	if data.has("daily_requirements"):
		daily_requirements = data["daily_requirements"]
	else:
		daily_requirements = get_quota_for_week(current_week)
		
	if data.has("daily_delivered"):
		daily_delivered = data["daily_delivered"]
	else:
		_reset_daily_deliveries()
		
	quota_progress_updated.emit()
