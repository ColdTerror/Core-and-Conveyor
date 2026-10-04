# ==============================================================================
# Script: research_manager.gd
# Purpose: Global Autoload managing player technology unlocks, multiplier levels, 
#          tier gates, and save/load state updates for player upgrades.
# Dependencies: Global groups ("Bots", "Towers", "Conveyors").
# Signals:
#   - research_unlocked: Emitted whenever a technology is successfully researched.
# ==============================================================================
extends Node

# GLOBAL MULTIPLIERS & LIMITS
var max_bots_allowed: int = 2     # Starts at 2, goes to 5
var bot_start_level: int = 1      # For future bots
var bot_max_level: int = 2        # Starts at 2, goes to 4

var belt_speed_mult: float = 1.0 
var max_buildings_allowed: int = 10
var tower_damage_mult: float = 1.0

signal research_unlocked

# TIER GATING
var tier_unlocked: int = 0  # 0 = nothing, 1 = tier 1 unlocked, 2 = tier 2, etc.

# Which tier does each tech belong to?
const TECH_TIERS: Dictionary = {
	"Core Expansion 1": 0,   # Tier 0 — always researchable, unlocks tier 1
	"Fleet Expansion":  1,  
	"Belt Speed 1":     1,   
	"Building Limit 1": 1,
	"Tower Damage 1":   1,
	"Wave Measurement": 1,
	"Core Expansion 2": 1,   # Requires tier 1, unlocks tier 2
	"Advanced Tooling": 2,   
	"Belt Speed 2":     2,   
	"Building Limit 2": 2,
	"Tower Damage 2":   2,
	"Moon Measurement 1": 2,
	"Core Expansion 3": 2,   # Requires tier 2, unlocks tier 3
	"Building Limit 3": 3,
	"Tower Damage 3":   3,
	"Moon Measurement 2": 3,
	"Thruster Upgrade": 3,
	"Pneumatic Logistics": 3,
	"Core Expansion 4": 3,   # Requires tier 3, unlocks tier 4
	"Battery Upgrade": 4,
}

# Master dictionary of technology research costs.
# Single source of truth for all research prices.
var research_costs: Dictionary = {
	# --- Tier 0 ---
	"Core Expansion 1": { "Wood": 25 },

	# --- Tier 1 ---
	"Wave Measurement": { "Wood": 25 },
	"Fleet Expansion":  { "Wood": 30, "Stone": 25 },
	"Belt Speed 1":     { "Wood": 25, "Stone": 25 },
	"Building Limit 1": { "Wood": 40, "Stone": 30 },
	"Tower Damage 1":   { "Wood": 35, "Stone": 35 },
	"Core Expansion 2": { "Wood": 50, "Stone": 50 },

	# --- Tier 2 ---
	"Moon Measurement 1": { "Planks": 20 },
	"Advanced Tooling":   { "Planks": 25, "Stone Bricks": 25 },
	"Belt Speed 2":       { "Planks": 30, "Stone Bricks": 20 },
	"Building Limit 2":   { "Planks": 35, "Stone Bricks": 35 },
	"Tower Damage 2":     { "Planks": 40, "Stone Bricks": 30 },
	"Core Expansion 3":   { "Planks": 50, "Stone Bricks": 50 },

	# --- Tier 3 ---
	"Moon Measurement 2":  { "Planks": 30, "Stone Bricks": 20 },
	"Pneumatic Logistics": { "Planks": 30, "Stone Bricks": 30, "Iron Ingot": 15 },
	"Thruster Upgrade":    { "Planks": 40, "Stone Bricks": 20, "Iron Ingot": 20 },
	"Building Limit 3":    { "Planks": 50, "Stone Bricks": 50, "Iron Ingot": 15 },
	"Tower Damage 3":      { "Planks": 50, "Stone Bricks": 40, "Iron Ingot": 25 },
	"Core Expansion 4":    { "Planks": 60, "Stone Bricks": 60, "Iron Ingot": 30 },

	# --- Tier 4 ---
	"Battery Upgrade": { "Planks": 50, "Stone Bricks": 40, "Iron Ingot": 35 }
}

var unlocked_techs: Array[String] = []

# Intel trackers
var wave_measure: bool = false
var moon_measure_level: int = 0


## Returns raw research cost dictionary (item names -> amounts) for a tech.
func get_research_cost(tech_name: String) -> Dictionary:
	if research_costs.has(tech_name):
		return research_costs[tech_name].duplicate()
	return {}


## Returns research cost dictionary resolved to ItemResource instances (ItemResource -> amount).
func get_research_cost_resources(tech_name: String) -> Dictionary:
	var raw_cost = get_research_cost(tech_name)
	var resolved_cost: Dictionary = {}
	for item_name in raw_cost:
		var item_res = ItemDatabase.get_item(item_name) if ItemDatabase else null
		if item_res:
			resolved_cost[item_res] = raw_cost[item_name]
		else:
			resolved_cost[item_name] = raw_cost[item_name]
	return resolved_cost


## Formats research cost into a readable string (e.g. "25 Wood, 25 Stone").
func get_cost_string(tech_name: String) -> String:
	var cost = get_research_cost(tech_name)
	if cost.is_empty():
		return "Free"
	var parts: Array[String] = []
	for item_name in cost:
		parts.append("%s: %d" % [item_name, cost[item_name]])
	return ", ".join(parts)


## Returns the starting level for newly constructed worker bots.
func get_bot_start_level() -> int:
	return bot_start_level


## Returns the maximum allowable level for worker bots.
func get_bot_max_level() -> int:
	return bot_max_level



## Checks if a technology is available to be researched based on unlocking criteria and tier gates.
func can_research(tech_name: String) -> bool:
	if tech_name in unlocked_techs: return false
	var required_tier = TECH_TIERS.get(tech_name, 999)
	return tier_unlocked >= required_tier



## Completes research on a specific technology, applying its effects, notifying active game systems, and emitting research_unlocked.
func complete_research(tech_name: String):
	if not can_research(tech_name):
		print("Cannot research: ", tech_name, " (tier ", TECH_TIERS.get(tech_name), " locked)")
		return

	if not tech_name in unlocked_techs:
		unlocked_techs.append(tech_name)
	print("RESEARCH UNLOCKED: ", tech_name)
	
	# Recalculate stats deterministically from all unlocked techs
	recalculate_all_stats()
	
	# Only notify living units and UI when researching during active gameplay
	_update_living_bots()
	_update_living_towers()
	_update_living_belts() 
	research_unlocked.emit()



## Recalculates all technology multipliers and thresholds deterministically from unlocked_techs.
func recalculate_all_stats():
	# Reset defaults
	tier_unlocked = 0
	max_bots_allowed = 2 
	bot_start_level = 1 
	bot_max_level = 2    
	belt_speed_mult = 1.0
	max_buildings_allowed = 10
	tower_damage_mult = 1.0
	wave_measure = false
	moon_measure_level = 0
	
	for tech in unlocked_techs:
		match tech:
			"Core Expansion 1":
				tier_unlocked = max(tier_unlocked, 1)
			"Core Expansion 2":
				tier_unlocked = max(tier_unlocked, 2)
			"Core Expansion 3":
				tier_unlocked = max(tier_unlocked, 3)
			"Fleet Expansion":      
				max_bots_allowed = max(max_bots_allowed, 5)
			"Advanced Tooling":      
				bot_max_level = max(bot_max_level, 4)
			"Belt Speed 1":          
				belt_speed_mult += 0.25
			"Belt Speed 2":          
				belt_speed_mult += 0.25
			"Building Limit 1":
				max_buildings_allowed += 25
			"Building Limit 2":
				max_buildings_allowed += 50
			"Building Limit 3":
				max_buildings_allowed += 75
			"Tower Damage 1":
				tower_damage_mult += 0.10
			"Tower Damage 2":
				tower_damage_mult += 0.25
			"Tower Damage 3":
				tower_damage_mult += 0.50
			"Wave Measurement":
				wave_measure = true
			"Moon Measurement 1": 
				moon_measure_level = max(moon_measure_level, 1)
			"Moon Measurement 2":
				moon_measure_level = max(moon_measure_level, 2)
			"Thruster Upgrade", "Battery Upgrade": #Bots check for these in unlocked tech in update bots
				pass
			"Pneumatic Logistics": #Level checks for this in unlocked tech when displaying buildings
				pass
			_:
				print("WARNING: Unknown tech -> ", tech)



## Forces existing worker bots to recalculate their stats after a research unlock.
func _update_living_bots():
	get_tree().call_group("Bots", "_recalculate_stats")


## Forces defensive towers to apply research buffs.
func _update_living_towers():
	get_tree().call_group("Towers", "apply_research_buffs")


## Forces conveyors to apply belt speed upgrades.
func _update_living_belts():
	get_tree().call_group("Conveyors", "apply_research_buffs")



## Packs the array of unlocked technology names into a dictionary for game saves.
func get_save_data() -> Dictionary:
	return {
		"unlocked_techs": unlocked_techs
	}



## Resets research stats to defaults and restores unlocked technologies from saved data.
func load_save_data(data: Dictionary):
	unlocked_techs.clear()
	
	if data.has("unlocked_techs"):
		var saved_techs: Array[String] = []
		saved_techs.assign(data["unlocked_techs"])
		for tech in saved_techs:
			unlocked_techs.append(tech)
			
	recalculate_all_stats()
