extends Node

# ==========================================
# GLOBAL MULTIPLIERS
# ==========================================
var bot_speed_mult: float = 1.0
var belt_speed_mult: float = 1.0 
var max_buildings_allowed: int = 10
var tower_damage_mult: float = 1.0

signal research_unlocked

# ==========================================
# TIER GATING
# ==========================================
var tier_unlocked: int = 0  # 0 = nothing, 1 = tier 1 unlocked, 2 = tier 2, etc.

# Which tier does each tech belong to?
const TECH_TIERS: Dictionary = {
	"Core Expansion 1": 0,   # Tier 0 — always researchable, unlocks tier 1
	"Bot Speed 1":      1,
	"Belt Speed 1":     1,   
	"Building Limit 1": 1,
	"Tower Damage 1":   1,
	"Wave Measurement": 1,
	"Core Expansion 2": 1,   # Requires tier 1, unlocks tier 2
	"Bot Speed 2":      2,
	"Belt Speed 2":     2,   
	"Building Limit 2": 2,
	"Tower Damage 2":   2,
	"Moon Measurement": 2,
	"Core Expansion 3": 2,   # Requires tier 2, unlocks tier 3
}

var unlocked_techs: Array[String] = []

# --- INTEL TRACKERS ---
var wave_measure: bool = false
var moon_measure_level: int = 0

# ==========================================
# UNLOCK ROUTER
# ==========================================
func can_research(tech_name: String) -> bool:
	if tech_name in unlocked_techs: return false
	var required_tier = TECH_TIERS.get(tech_name, 999)
	return tier_unlocked >= required_tier

func complete_research(tech_name: String):
	if not can_research(tech_name):
		print("Cannot research: ", tech_name, " (tier ", TECH_TIERS.get(tech_name), " locked)")
		return

	unlocked_techs.append(tech_name)
	print("RESEARCH UNLOCKED: ", tech_name)
	
	# Apply the hard math
	_apply_tech(tech_name)
	
	# Only notify living units and UI when researching during active gameplay
	_update_living_bots()
	_update_living_towers()
	_update_living_belts() 
	research_unlocked.emit()

# --- Helper function to apply the stats silently ---
func _apply_tech(tech_name: String):
	match tech_name:
		"Core Expansion 1":
			tier_unlocked = 1
		"Core Expansion 2":
			tier_unlocked = 2
		"Core Expansion 3":
			tier_unlocked = 3
		"Bot Speed 1":
			bot_speed_mult = 1.25
		"Bot Speed 2":
			bot_speed_mult = 1.5
		"Belt Speed 1":          
			belt_speed_mult = 1.25
		"Belt Speed 2":          
			belt_speed_mult = 1.50
		"Building Limit 1":
			max_buildings_allowed = 20
		"Building Limit 2":
			max_buildings_allowed = 40
		"Tower Damage 1":
			tower_damage_mult = 1.10
		"Tower Damage 2":
			tower_damage_mult = 1.25
		"Wave Measurement":
			wave_measure = true
		"Moon Measurement", "Moon Measurement 1": 
			moon_measure_level = 1
		_:
			print("WARNING: Unknown tech -> ", tech_name)
	print(tech_name)

# ==========================================
# NOTIFY EXISTING UNITS
# ==========================================
func _update_living_bots():
	get_tree().call_group("WorkerBots", "_recalculate_stats")

func _update_living_towers():
	get_tree().call_group("Towers", "apply_research_buffs")

func _update_living_belts():
	get_tree().call_group("Conveyors", "apply_research_buffs")

# ==========================================
# SAVE / LOAD SYSTEM
# ==========================================
func get_save_data() -> Dictionary:
	return {
		"unlocked_techs": unlocked_techs
	}

func load_save_data(data: Dictionary):
	# 1. Reset all Autoload variables back to Day 1 defaults
	tier_unlocked = 0
	bot_speed_mult = 1.0
	belt_speed_mult = 1.0
	max_buildings_allowed = 10
	tower_damage_mult = 1.0
	wave_measure = false
	moon_measure_level = 0
	unlocked_techs.clear()
	
	# 2. Quietly "re-research" everything from the save file
	if data.has("unlocked_techs"):
		
		var saved_techs: Array[String] = []
		saved_techs.assign(data["unlocked_techs"])
		for tech in saved_techs:
			unlocked_techs.append(tech)
			_apply_tech(tech)
