class_name QuotaManager
extends Node2D

signal quota_progress_updated

# ==========================================
# STATE VARIABLES
# ==========================================
var current_week: int = 1
var daily_requirements: Dictionary = {}
var daily_delivered: Dictionary = {}

var successful_days: int = 0
var max_weekly_corruption: float = 100.0
var level_ref: Node2D

# ==========================================
# SETUP
# ==========================================
func initialize(level_instance: Node2D):
	level_ref = level_instance
	
	# If daily_requirements is empty (like on a fresh game start), generate Week 1
	if daily_requirements.is_empty():
		daily_requirements = get_quota_for_week(current_week)
		
	_reset_daily_deliveries()

# ==========================================
# THE INFINITE QUOTA ALGORITHM
# ==========================================
func get_quota_for_week(week: int) -> Dictionary:
	if week <= 1:
		return {} # Week 1 is a free grace period to build basic infrastructure!
		
	# Offset the math so Week 2 acts as "Step 0"
	var offset_week = week - 2
	
	# Every 5 weeks is one full cycle (Week 2->6, Week 7->11, etc.)
	var cycle = offset_week / 5 
	var step = offset_week % 5  # Returns 0, 1, 2, 3, or 4
	
	# Base refined items carried over from previous completed cycles
	var base_refined_items = cycle * 100
	
	# The 100 items actively transitioning during THIS cycle
	var step_ratio = float(step) / 4.0 # 0.0 (Week 2), 0.25 (Week 3), 0.5 (Week 4), 0.75, 1.0 (Week 6)
	var transitioning_refined = int(100.0 * step_ratio)
	var transitioning_raw = 100 - transitioning_refined
	
	# Final totals for the week
	var total_refined = base_refined_items + transitioning_refined
	var total_raw = transitioning_raw
	
	var quota = {}
	
	# --- RAW ALLOCATION (50% Wood, 50% Stone) ---
	if total_raw > 0:
		quota["Wood"] = int(total_raw * 0.5)
		quota["Stone"] = int(total_raw * 0.5)
		
	# --- REFINED ALLOCATION (40% Planks, 40% Bricks, 20% Arrows) ---
	if total_refined > 0:
		quota["Planks"] = int(total_refined * 0.4)
		quota["Stone Bricks"] = int(total_refined * 0.4)
		
		# Do the math this way so we don't lose a single item to weird rounding!
		var arrows = total_refined - quota["Planks"] - quota["Stone Bricks"]
		if arrows > 0:
			quota["Stone Arrow"] = arrows
			
	return quota

# ==========================================
# BELT INTERACTION LOGIC
# ==========================================
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

func deliver_item(item_name: String, amount: int):
	# Only accept if it's something we actually need
	if not daily_requirements.has(item_name):
		return

	# Ensure the key exists in our tracker (safety fallback)
	if not daily_delivered.has(item_name):
		daily_delivered[item_name] = 0
		
	daily_delivered[item_name] += amount
	
	# Log it for the stats menu!
	EconomyManager.log_item_consumed(item_name, amount)
	quota_progress_updated.emit()
		
	# TODO: QUOTA FINISH SOUND
	# if _is_daily_quota_met():
	# 	if ClassDB.class_exists("AudioManager"):
	# 		AudioManager.play_sfx("quota_complete")

func _is_daily_quota_met() -> bool:
	for item_name in daily_requirements:
		var needed = daily_requirements[item_name]
		var have = daily_delivered.get(item_name, 0)
		if have < needed:
			return false
	return true

# ==========================================
# TIME & CORRUPTION LOGIC
# ==========================================
func process_end_of_day():
	# Because Week 1 has an empty dictionary {}, _is_daily_quota_met()
	# automatically returns true, giving the player 7 free success days!
	if _is_daily_quota_met():
		successful_days += 1
		
	_reset_daily_deliveries()
	quota_progress_updated.emit()

func process_end_of_week():
	# 1. Calculate the penalty for the week that just finished
	# (We only apply penalties if they failed a real quota > Week 1)
	if current_week > 1:
		var failure_ratio: float = 1.0 - (float(successful_days) / 7.0)
		var penalty: float = max_weekly_corruption * failure_ratio
		
		# Uncomment when you are ready to link the Corruption Manager!
		# if penalty > 0 and level_ref and level_ref.has_node("CorruptionManager"):
		# 	level_ref.get_node("CorruptionManager").add_corruption(penalty)
			
	# 2. Reset the success counter
	successful_days = 0
	_reset_daily_deliveries()
	
	# 3. Advance to the next week and grab the new algorithm quota!
	current_week += 1
	daily_requirements = get_quota_for_week(current_week)
	
	# 4. Update the UI
	quota_progress_updated.emit()

func _reset_daily_deliveries():
	daily_delivered.clear()
	
	# Initialize every requirement key with a value of 0
	for key in daily_requirements.keys():
		daily_delivered[key] = 0

# ==========================================
# SAVE / LOAD SYSTEM (Quota Manager)
# ==========================================
func get_save_data() -> Dictionary:
	return {
		"successful_days": successful_days,
		"current_week": current_week,
		"daily_requirements": daily_requirements,
		"daily_delivered": daily_delivered
	}

func load_save_data(data: Dictionary):
	successful_days = data.get("successful_days", 0)
	current_week = data.get("current_week", 1)
	
	# Restore the exact requirements in case they saved mid-week
	if data.has("daily_requirements"):
		daily_requirements = data["daily_requirements"]
	else:
		daily_requirements = get_quota_for_week(current_week)
		
	if data.has("daily_delivered"):
		daily_delivered = data["daily_delivered"]
	else:
		_reset_daily_deliveries()
		
	quota_progress_updated.emit()
