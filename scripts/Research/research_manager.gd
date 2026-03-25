extends Node

# ==========================================
# 1. THE GLOBAL MULTIPLIERS (Source of Truth)
# ==========================================
var bot_speed_mult: float = 1.0
var bot_carry_capacity: int = 1
var max_buildings_allowed: int = 15
var tower_damage_mult: float = 1.0

# Keep track of what we unlocked so the UI knows!
var unlocked_techs: Array[String] = []

# ==========================================
# 2. THE UNLOCK ROUTER
# ==========================================
func complete_research(tech_name: String):
	if tech_name in unlocked_techs: 
		return # Prevent double-unlocking
		
	unlocked_techs.append(tech_name)
	print("RESEARCH UNLOCKED: ", tech_name)
	
	# Route the upgrade to the correct variables based on the name from the GraphNode
	match tech_name:
		"Bot Speed 1":
			bot_speed_mult = 1.2 # +20% Speed
			_update_living_bots()
			
		"Bot Capacity 1":
			bot_carry_capacity = 2 # Carry 2 items!
			_update_living_bots()
			
		"Core Expansion 1":
			max_buildings_allowed = 30 # Instantly updates the cap
			
		"Tower Damage 1":
			tower_damage_mult = 1.15 # +15% Damage
			_update_living_towers()
			
		_:
			print("WARNING: Unknown tech unlocked -> ", tech_name)

# ==========================================
# 3. NOTIFY EXISTING UNITS
# ==========================================
# We use Godot's Group system to instantly shout at every bot currently on the map
func _update_living_bots():
	print("updating bots")
	get_tree().call_group("WorkerBots", "apply_research_buffs")

func _update_living_towers():
	pass
	#get_tree().call_group("Towers", "apply_research_buffs")
