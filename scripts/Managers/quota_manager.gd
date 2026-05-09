class_name QuotaManager
extends Node2D


signal quota_progress_updated

# The global goal for the entire base
var daily_requirements: Dictionary = {"Wood": 100, "Stone": 100}
var daily_delivered: Dictionary = {}

var successful_days: int = 0
var max_weekly_corruption: float = 100.0
var level_ref: Node2D

func initialize(level_instance: Node2D):
	level_ref = level_instance
	_reset_daily_deliveries()

# --- BELT INTERACTION LOGIC ---
func can_accept_item(item_name: String) -> bool:
	if not daily_requirements.has(item_name): 
		return false # We don't want this item!
		
	var needed = daily_requirements[item_name]
	var have = daily_delivered.get(item_name, 0)
	
	return have < needed # True if we still need more today!

# New helper to see how much of a stack we can actually take
func get_needed_amount(item_name: String, offered_amount: int) -> int:
	if not daily_requirements.has(item_name):
		return 0
		
	var total_required = daily_requirements[item_name]
	var currently_have = daily_delivered.get(item_name, 0)
	
	var space_left = total_required - currently_have
	
	if space_left <= 0:
		return 0
		
	# Take either the whole stack or just enough to fill the requirement
	return min(offered_amount, space_left)

# Keep your deliver_item function simple
func deliver_item(item_name: String, amount: int):
	# Only accept if it's something we actually need
	if not daily_requirements.has(item_name):
		return

	# Ensure the key exists in our tracker (safety fallback)
	if not daily_delivered.has(item_name):
		daily_delivered[item_name] = 0
		
	daily_delivered[item_name] += amount
	EconomyManager.log_item_consumed(item_name, amount)
	quota_progress_updated.emit()
		
	#TODO
	#QUOTA FINISH SOUND
	#if _is_daily_quota_met():
	#	if ClassDB.class_exists("AudioManager"):
	#			AudioManager.play_sfx("quota_complete")
			
			

func _is_daily_quota_met() -> bool:
	for item_name in daily_requirements:
		var needed = daily_requirements[item_name]
		var have = daily_delivered.get(item_name, 0)
		if have < needed:
			return false
	return true

# --- TIME & CORRUPTION LOGIC ---
func process_end_of_day():
	if _is_daily_quota_met():
		successful_days += 1
		
	_reset_daily_deliveries()
	quota_progress_updated.emit()

func process_end_of_week():
	# 7/7 days = 0 penalty. 0/7 days = 100% penalty.
	var failure_ratio: float = 1.0 - (float(successful_days) / 7.0)
	var penalty: float = max_weekly_corruption * failure_ratio
	
	print("Failed")
	print(penalty)
	#if penalty > 0 and level_ref and level_ref.has_node("CorruptionManager"):
	#	level_ref.get_node("CorruptionManager").add_corruption(penalty)
		
	successful_days = 0
	_reset_daily_deliveries()
	quota_progress_updated.emit()

func _reset_daily_deliveries():
	# Clear the old data
	daily_delivered.clear()
	
	# Initialize every requirement key with a value of 0
	for key in daily_requirements.keys():
		daily_delivered[key] = 0
