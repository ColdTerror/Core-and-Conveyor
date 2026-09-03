# ==============================================================================
# Script: Managers/codex_database.gd
# Purpose: Master registry and data provider for the in-game Codex / Wiki, supplying
#          structured stats, descriptions, categories, and icons for Items, Enemies,
#          and Buildings.
# Dependencies: ItemDatabase autoload. Assets in res://assets/.
# ==============================================================================
class_name CodexDatabase
extends RefCounted

## Helper to create an AtlasTexture sub-region from a spritesheet.
static func get_atlas_texture(tex: Texture2D, hframes: int = 1, vframes: int = 1, frame: int = 0) -> Texture2D:
	if not tex: return null
	if hframes <= 1 and vframes <= 1:
		return tex
	var fw = tex.get_width() / float(hframes)
	var fh = tex.get_height() / float(vframes)
	var col = frame % hframes
	var row = frame / hframes
	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(col * fw, row * fh, fw, fh)
	return atlas

## Helper to create an AtlasTexture from a Buildings.png rect.
static func get_building_atlas(rect: Rect2) -> Texture2D:
	var tex = load("res://assets/Buildings.png") as Texture2D
	if not tex: return null
	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = rect
	return atlas


## Returns all categorized Item entries.
static func get_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not ItemDatabase or not ItemDatabase.items:
		return list
		
	for key in ItemDatabase.items.keys():
		var res: ItemResource = ItemDatabase.items[key]
		if not res: continue
		
		var subcategory = "Materials"
		if res.is_ammo:
			subcategory = "Ammo"
		elif key in ["Wood", "Stone"]:
			subcategory = "Raw Resources"
		elif key in ["Plank", "Stone Brick"]:
			subcategory = "Refined"
			
		var stats: Dictionary = {}
		if res.is_ammo:
			stats["Damage"] = str(res.damage)
			stats["Damage Type"] = res.damage_type
			stats["Ammo Tag"] = res.ammo_type
			if res.projectile_speed > 0:
				stats["Speed"] = str(int(res.projectile_speed)) + " px/s"
			if res.projectile_lifetime > 0:
				stats["Lifetime"] = "%.1fs" % res.projectile_lifetime
				
			# Compatible towers note
			match res.ammo_type:
				"Arrow":
					stats["Compatible Towers"] = "Bow Tower (Preferred), Ballista Tower"
				"BallistaBolt":
					stats["Compatible Towers"] = "Ballista Tower (Preferred)"
				"Pebble":
					stats["Compatible Towers"] = "Sling Tower, Scattershot Tower"
				"Boulder":
					stats["Compatible Towers"] = "Catapult / Heavy Mortar"
		else:
			stats["Item Type"] = subcategory
			stats["Stack Size"] = str(res.stack_size if "stack_size" in res else 20)
			
		list.append({
			"id": key,
			"name": res.display_name,
			"category": "Items",
			"subcategory": subcategory,
			"icon": res.texture,
			"description": res.description if res.description != "" else ("A logistical resource used in construction and crafting."),
			"stats": stats,
			"combat_notes": ("Weakness bonus: Deals +20% damage against enemies vulnerable to " + res.damage_type) if res.is_ammo and res.damage_type != "None" else ""
		})
		
	return list


## Returns all categorized Enemy entries with accurate physical multipliers.
static func get_enemies() -> Array[Dictionary]:
	var zombie_tex = load("res://assets/Enemies/Zombie_Enemy.png") as Texture2D
	var spider_tex = load("res://assets/Enemies/Spider_Enemy.png") as Texture2D
	var drone_tex = load("res://assets/Enemies/Drone_Enemy.png") as Texture2D
	var tank_tex = load("res://assets/Enemies/Tank_Enemy.png") as Texture2D
	var slime_tex = load("res://assets/Enemies/Slime_Enemy.png") as Texture2D

	return [
		{
			"id": "zombie_miner",
			"name": "Zombie Miner",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(zombie_tex, 8, 3, 0),
			"description": "Standard corrupted miner resurrected by the dark fog. Marches methodically toward defensive perimeter walls and attacking turrets.",
			"stats": {
				"Max Health": "50 HP",
				"Move Speed": "40 px/s",
				"Attack Type": "Melee (Bump)",
				"Attack Damage": "10",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Neutral (1.0x Piercing, 1.0x Crushing)",
			"combat_notes": "Balanced baseline horde monster. Any tower and ammo combination is equally effective."
		},
		{
			"id": "fast_enemy",
			"name": "Fast Enemy (Spider)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(spider_tex, 4, 3, 0),
			"description": "A swift, scurrying arachnid designed to flank perimeter defenses and ambush busy worker bots with high sprint velocity.",
			"stats": {
				"Max Health": "25 HP",
				"Move Speed": "75 px/s",
				"Attack Type": "Melee (Bump)",
				"Attack Damage": "5",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Piercing (+20% damage)",
			"combat_notes": "Vulnerable to Piercing projectiles! Bow Towers firing Wooden/Stone Arrows and Ballistas dispatch them rapidly."
		},
		{
			"id": "flyer_drone",
			"name": "Flyer Drone",
			"category": "Enemies",
			"subcategory": "Air",
			"icon": get_atlas_texture(drone_tex, 3, 3, 0),
			"description": "An airborne drone that glides effortlessly over terrain obstacles, lakes, and walls to assault internal factories directly.",
			"stats": {
				"Max Health": "35 HP",
				"Move Speed": "60 px/s",
				"Attack Type": "Melee (Dive)",
				"Attack Damage": "12",
				"Attack Speed": "1.0 /s",
				"Flying": "Yes (Ignores walls & water)"
			},
			"weaknesses": "Weak to Piercing (+20% damage)",
			"combat_notes": "Bypasses all perimeter wall mazes. Place Bow Towers and Ballistas inside your core base to intercept them."
		},
		{
			"id": "ranged_tank",
			"name": "Ranged Tank",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(tank_tex, 2, 3, 0),
			"description": "A heavily armored siege beast equipped with long-range bio-cannons that bombard defensive towers from safe standoff distance.",
			"stats": {
				"Max Health": "40 HP",
				"Move Speed": "40 px/s",
				"Attack Type": "Ranged Projectile",
				"Attack Range": "180 px",
				"Attack Damage": "8",
				"Attack Speed": "0.5 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20%) • Resists Piercing (-25%)",
			"combat_notes": "Thick armor deflects arrows (takes 0.75x Piercing damage). Heavy crushing ammunition (Pebbles from Sling/Scattershot, or Boulders) deals +20% bonus damage."
		},
		{
			"id": "slime_large",
			"name": "Large Slime (Tier 3)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A massive, gelatinous monster with dense health. When defeated, it violently fractures into two Medium Slimes.",
			"stats": {
				"Max Health": "120 HP",
				"Move Speed": "30 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "15",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20%) • Resists Piercing (-20%)",
			"combat_notes": "Dense gelatinous body absorbs light arrows (takes 0.8x Piercing damage). Crushing weapons like Scattershot Towers and Slings deal +20% bonus damage."
		},
		{
			"id": "slime_medium",
			"name": "Medium Slime (Tier 2)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A fractured division of a Large Slime. Charges defensive lines and splits into two Small Slimes upon destruction.",
			"stats": {
				"Max Health": "60 HP",
				"Move Speed": "35 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "10",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20%) • Resists Piercing (-10%)",
			"combat_notes": "Resistant to light arrow shots (takes 0.9x Piercing damage). Highly vulnerable to crushing kinetic pebbles."
		},
		{
			"id": "slime_small",
			"name": "Small Slime (Tier 1)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A fast, scurrying mini-slime that swarms defenses in clusters once parent slimes are destroyed. Does not split further.",
			"stats": {
				"Max Health": "30 HP",
				"Move Speed": "40 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "5",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20% damage)",
			"combat_notes": "Neutral to Piercing arrows (1.0x), but crushed quickly by Scattershot and Sling pebble fire (+20% damage)."
		}
	]


## Returns all categorized Building entries with verified footprints, icons, and structured upgrade tiers.
static func get_buildings() -> Array[Dictionary]:
	return [
		# ======================================================================
		# DEFENSE
		# ======================================================================
		{
			"id": "bow_tower",
			"name": "Bow Tower",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(288, 320, 64, 64)),
			"description": "Standard defensive turret that fires arrows at approaching enemies. Can be upgraded to Tier 2 for increased range, fire rate, and damage.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Attack Range": "8 Tiles",
				"Fire Rate": "1.0 /s",
				"Damage Mult": "1.0x",
				"Ammo Capacity": "20 Shots",
				"Preferred Ammo": "Arrow (Wooden / Stone)",
				"Build Cost": "25 Wood, 25 Stone"
			},
			"combat_notes": "Excellent perimeter defense. Fires Piercing arrows that deal +20% bonus damage against fast spiders and flying drones.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Standard defensive turret that fires arrows at approaching enemies.",
					"stats": {
						"Footprint": "2x2 Tiles",
						"Attack Range": "8 Tiles",
						"Fire Rate": "1.0 /s",
						"Damage Mult": "1.0x",
						"Ammo Capacity": "20 Shots",
						"Preferred Ammo": "Arrow (Wooden / Stone)",
						"Build Cost": "25 Wood, 25 Stone"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Upgraded archer tower with extended engagement range, reinforced firing velocity, and increased ammo capacity.",
					"stats": {
						"Footprint": "2x2 Tiles",
						"Attack Range": "10 Tiles",
						"Fire Rate": "2.0 /s",
						"Damage Mult": "1.5x",
						"Ammo Capacity": "25 Shots",
						"Preferred Ammo": "Arrow (Wooden / Stone)",
						"Upgrade Cost": "25 Wood, 25 Stone, 10 Planks, 10 Stone Bricks"
					}
				}
			]
		},
		{
			"id": "ballista_tower",
			"name": "Ballista Tower",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(192, 320, 96, 96)),
			"description": "Heavy long-range siege artillery that launches massive Ballista Bolts capable of impaling high-health monsters.",
			"stats": {
				"Footprint": "3x3 Tiles",
				"Attack Range": "14 Tiles",
				"Fire Rate": "0.3 /s",
				"Damage Mult": "3.0x",
				"Ammo Capacity": "20 Shots",
				"Preferred Ammo": "BallistaBolt (Piercing)",
				"Compatible Ammo": "BallistaBolt, Arrow (0.5x scale)",
				"Build Cost": "Planks, Stone Bricks"
			},
			"combat_notes": "Massive 14-tile reach and devastating 3.0x damage punch. Outranges all enemy siege artillery."
		},
		{
			"id": "scattershot_tower",
			"name": "Scattershot Tower",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(352, 320, 64, 64)),
			"description": "Multi-barrel shotgun turret that discharges 5 pebbles in a wide 20-degree cone for swarm suppression.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Attack Range": "5 Tiles",
				"Fire Rate": "0.5 /s",
				"Projectiles": "5 per shot (20° spread)",
				"Preferred Ammo": "Pebble (Crushing)",
				"Build Cost": "Planks, Stone"
			},
			"combat_notes": "Dominates close-quarters chokepoints against clustered ground swarms and splitting slimes."
		},
		{
			"id": "sling_tower",
			"name": "Sling Tower",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(416, 320, 64, 64)),
			"description": "Rapid-fire mechanical sling that pelts enemies continuously with crushing pebbles.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Attack Range": "7 Tiles",
				"Fire Rate": "3.0 /s (Rapid)",
				"Ammo Capacity": "50 Shots",
				"Preferred Ammo": "Pebble (Crushing)"
			},
			"combat_notes": "Rapid-fire Crushing damage tears through armored Ranged Tanks and Slimes quickly."
		},
		{
			"id": "ammo_distributor",
			"name": "Ammo Distributor",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(480, 320, 64, 64)),
			"description": "Automated supply cannon that launches ammunition packages directly into nearby towers within its radius.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Supply Range": "6 Tiles",
				"Transfer Interval": "1.0s",
				"Batch Size": "1 Ammo / pulse",
				"Storage Capacity": "Up to 10 of each ammo type",
				"Build Cost": "Planks, Stone Bricks"
			},
			"combat_notes": "Eliminates the need for manual bot ammo deliveries to frontline towers. Strictly delivers when target towers have room.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Automated supply cannon that launches ammunition packages directly into nearby towers within its radius.",
					"stats": {
						"Footprint": "2x2 Tiles",
						"Supply Range": "6 Tiles",
						"Transfer Interval": "1.0s",
						"Batch Size": "1 Ammo / pulse",
						"Storage Capacity": "Up to 10 of each ammo type",
						"Build Cost": "Planks, Stone Bricks"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Enhanced high-velocity supply distributor with wider delivery coverage and double the batch delivery payload.",
					"stats": {
						"Footprint": "2x2 Tiles",
						"Supply Range": "8 Tiles (+33%)",
						"Transfer Interval": "0.75s (Faster)",
						"Batch Size": "2 Ammo / pulse (Double)",
						"Turret Rotation": "20.0 rad/s (High Speed)",
						"Storage Capacity": "Up to 10 of each ammo type"
					}
				}
			]
		},
		{
			"id": "wall",
			"name": "Perimeter Wall",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(160, 160, 32, 32)),
			"description": "Sturdy defensive barricade that blocks ground enemy movement and funnels horde units into designated kill-zones.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Health": "100 HP",
				"Pathfinding Cost": "Scales dynamically with health",
				"Build Cost": "1 Wood / Stone"
			},
			"combat_notes": "Enemies will path around walls if open paths exist, or attack them if fully enclosed."
		},
		{
			"id": "gate",
			"name": "Security Gate",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(224, 224, 96, 32)),
			"description": "Reinforced 3-tile wide automated portcullis that opens instantly for friendly worker bots while barring enemies.",
			"stats": {
				"Footprint": "3x1 Tiles (Horizontal / Vertical)",
				"Health": "100 HP",
				"Orientation": "Auto-rotates horizontal/vertical"
			},
			"combat_notes": "Allows bots to venture outside perimeter walls to harvest resources during the day without leaving gaps for enemies."
		},

		# ======================================================================
		# LOGISTICS
		# ======================================================================
		{
			"id": "conveyor_belt",
			"name": "Conveyor Belt",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 224, 32, 32)),
			"description": "Logistical conveyor lane that transports resources and finished ammunition smoothly across your factory.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Speed": "Base (Upgradeable via Research)",
				"Build Cost": "1 Wood",
				"Building Limit": "Exempt (Does not consume building slots)"
			},
			"combat_notes": "Forms the logistical backbone of your factory and defense resupply lines."
		},
		{
			"id": "router_building",
			"name": "Belt Router",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 192, 32, 32)),
			"description": "Distributes incoming belt items evenly across up to 3 outgoing directions in round-robin sequence.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Outputs": "3 Directions",
				"Build Cost": "1 Wood, 1 Stone"
			},
			"combat_notes": "Essential for splitting raw resources into multiple parallel crafters or ammo production lines."
		},
		{
			"id": "filter_building",
			"name": "Belt Filter",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(64, 192, 32, 32)),
			"description": "Inspects passing items and diverts a specifically selected resource type to its filtered output, letting all others pass straight.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Configuration": "Selectable Item Filter",
				"Build Cost": "1 Wood, 1 Stone"
			},
			"combat_notes": "Prevents mixed-item jams on shared conveyor supply belts."
		},
		{
			"id": "conveyor_bridge",
			"name": "Conveyor Bridge",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(32, 192, 32, 32)),
			"description": "An elevated crossover bridge allowing two independent conveyor lines to intersect without mixing items.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Capacity": "2 Isolated Lanes (Horizontal & Vertical)"
			},
			"combat_notes": "Solves complex factory layout spaghetti."
		},
		{
			"id": "stockpile",
			"name": "Stockpile",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 0, 128, 128)),
			"description": "High-capacity bulk storage container with belt input/output ports. Can be locked to a single dedicated item.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Capacity (Mixed)": "50 Items",
				"Capacity (Dedicated)": "100 Items",
				"Build Cost": "25 Wood",
				"Dedicated Mode": "Optional single-item lock"
			},
			"combat_notes": "Buffers ammo and materials close to defenses so worker bots have short travel routes.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "High-capacity bulk storage container with belt input/output ports. Can be locked to a single dedicated item.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Capacity (Mixed)": "50 Items",
						"Capacity (Dedicated)": "100 Items",
						"Build Cost": "25 Wood",
						"Dedicated Mode": "Optional single-item lock"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Reinforced warehouse storage container with expanded internal volume.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Capacity (Mixed)": "75 Items (+50%)",
						"Capacity (Dedicated)": "200 Items (Double)",
						"Upgrade Cost": "50 Wood",
						"Dedicated Mode": "Optional single-item lock"
					}
				}
			]
		},
		{
			"id": "item_launcher",
			"name": "Item Launcher",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(544, 448, 128, 128)),
			"description": "High-velocity pneumatic launcher that shoots item payload canisters across long distances directly into an Item Receiver.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Health": "200 HP",
				"Delivery": "Pneumatic Air Capsule"
			},
			"combat_notes": "Connects distant mining outposts to your central base without needing miles of conveyor belts."
		},
		{
			"id": "item_receiver",
			"name": "Item Receiver",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(800, 448, 128, 128)),
			"description": "Pneumatic capture port that catches incoming item canisters from Item Launchers and unloads them onto belts.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Health": "200 HP",
				"Outputs": "Belt Unload Ports"
			},
			"combat_notes": "Place at your core factory to catch raw ores fired from remote extraction drill sites."
		},

		# ======================================================================
		# PRODUCTION & EXTRACTION
		# ======================================================================
		{
			"id": "core",
			"name": "Command Core",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(512, 192, 128, 128)),
			"description": "The heart of your colony. Contains primary research systems, base storage, and wireless bot charging emitters. If the core falls, the game is lost!",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Health": "1000 HP",
				"Recharge Field": "Solar Powered",
				"Base Storage": "Accepts all raw resources"
			},
			"combat_notes": "Protect at all costs! All enemy horde units prioritize breaching toward the Core."
		},
		{
			"id": "sawmill",
			"name": "Sawmill",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(256, 0, 128, 128)),
			"description": "Wood processing facility that cuts raw tree logs into refined Planks for construction and advanced ammo.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Recipe": "Wood -> Planks",
				"Cutting Speed": "1.0x (Standard)",
				"Build Cost": "50 Wood, 25 Stone"
			},
			"combat_notes": "Powers Bow Tower Tier 2 upgrades, Ballista Bolt crafting, and advanced structures.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Wood processing facility that cuts raw tree logs into refined Planks for construction and advanced ammo.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Recipe": "Wood -> Planks",
						"Cutting Speed": "1.0x (Standard)",
						"Build Cost": "50 Wood, 25 Stone"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Steam-powered sawmill with high-torque circular blades for accelerated plank production.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Recipe": "Wood -> Planks",
						"Cutting Speed": "Accelerated (High Speed)",
						"Upgrade Cost": "50 Wood, 50 Stone, 25 Planks"
					}
				}
			]
		},
		{
			"id": "stonemason",
			"name": "Stone Mason",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(768, 0, 192, 128)),
			"description": "Large masonry workshop that chips raw stone into polished Stone Bricks for fortified structures.",
			"stats": {
				"Footprint": "6x4 Tiles",
				"Recipe": "Stone -> Stone Bricks",
				"Chiseling Speed": "1.0x (Standard)",
				"Build Cost": "25 Wood, 50 Stone"
			},
			"combat_notes": "Required for Tier 2 buildings, reinforced walls, and advanced defense towers.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Large masonry workshop that chips raw stone into polished Stone Bricks for fortified structures.",
					"stats": {
						"Footprint": "6x4 Tiles",
						"Recipe": "Stone -> Stone Bricks",
						"Chiseling Speed": "1.0x (Standard)",
						"Build Cost": "25 Wood, 50 Stone"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Reinforced masonry foundry utilizing precision stonecutting blades.",
					"stats": {
						"Footprint": "6x4 Tiles",
						"Recipe": "Stone -> Stone Bricks",
						"Chiseling Speed": "Accelerated (High Speed)",
						"Upgrade Cost": "25 Wood, 50 Stone, 25 Stone Bricks"
					}
				}
			]
		},
		{
			"id": "fletcher",
			"name": "Fletcher",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(480, 0, 128, 128)),
			"description": "Dedicated ammunition workshop that crafts Wooden Arrows, Stone Arrows, and Ballista Bolts.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Recipes": "Wooden Arrows, Stone Arrows, Ballista Bolts",
				"Crafting Speed": "1.0x (Standard)",
				"Build Cost": "25 Wood, 25 Stone"
			},
			"combat_notes": "Keep supplied with Wood and Stone to maintain steady ammo production for night waves.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Dedicated ammunition workshop that crafts Wooden Arrows, Stone Arrows, and Ballista Bolts.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Recipes": "Wooden Arrows, Stone Arrows, Ballista Bolts",
						"Crafting Speed": "1.0x (Standard)",
						"Build Cost": "25 Wood, 25 Stone"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Automated bowyer and fletching lathe capable of assembling ammunition at rapid rates.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Recipes": "Wooden Arrows, Stone Arrows, Ballista Bolts",
						"Crafting Speed": "Accelerated (High Speed)",
						"Upgrade Cost": "50 Wood, 50 Stone, 25 Planks"
					}
				}
			]
		},
		{
			"id": "stone_crusher",
			"name": "Stone Crusher",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(992, 0, 128, 128)),
			"description": "Heavy industrial crusher that fractures large stones into sling Pebbles and artillery Boulders.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Recipes": "Stone -> Pebbles / Boulders",
				"Build Cost": "25 Wood, 15 Stone"
			},
			"combat_notes": "Supplies Sling Towers and Scattershot Towers with Crushing ammo."
		},
		{
			"id": "lumberjack",
			"name": "Lumberjack",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(128, 0, 128, 128)),
			"description": "Automated logging station that fells surrounding trees and outputs Wood logs continuously onto belts.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Harvest Target": "Forest Trees",
				"Work Interval": "2.0s per log",
				"Build Cost": "10 Wood"
			},
			"combat_notes": "Automates wood harvesting so worker bots can focus on construction and defense logistics.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Automated logging station that fells surrounding trees and outputs Wood logs continuously onto belts.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Harvest Target": "Forest Trees",
						"Work Interval": "2.0s per log",
						"Build Cost": "10 Wood"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Industrial timbering camp with high-power mechanical saws for rapid lumber harvesting.",
					"stats": {
						"Footprint": "4x4 Tiles",
						"Harvest Target": "Forest Trees",
						"Work Interval": "1.2s per log (Rapid)",
						"Upgrade Cost": "50 Wood"
					}
				}
			]
		},
		{
			"id": "stone_mine",
			"name": "Stone Mine",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(640, 0, 96, 96)),
			"description": "Automated quarry drill that extracts raw Stone from stone deposit tiles and outputs directly onto belts.",
			"stats": {
				"Footprint": "3x3 Tiles",
				"Harvest Target": "Stone Deposits",
				"Work Interval": "2.0s per stone",
				"Build Cost": "25 Wood"
			},
			"combat_notes": "Provides an infinite, automated flow of Stone for arrow crafting and fortification.",
			"tiers": [
				{
					"level_label": "Level 1 (Base)",
					"description": "Automated quarry drill that extracts raw Stone from stone deposit tiles and outputs directly onto belts.",
					"stats": {
						"Footprint": "3x3 Tiles",
						"Harvest Target": "Stone Deposits",
						"Work Interval": "2.0s per stone",
						"Build Cost": "25 Wood"
					}
				},
				{
					"level_label": "Level 2 (Upgraded)",
					"description": "Heavy pneumatic quarry extractor with deep-bore percussion drills.",
					"stats": {
						"Footprint": "3x3 Tiles",
						"Harvest Target": "Stone Deposits",
						"Work Interval": "1.2s per stone (Rapid)",
						"Upgrade Cost": "25 Wood, 50 Stone"
					}
				}
			]
		},
		{
			"id": "ore_drill",
			"name": "Ore Drill",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(896, 160, 96, 96)),
			"description": "Heavy rotary drill designed to bore deep into mineral veins to extract raw Iron Ore.",
			"stats": {
				"Footprint": "3x3 Tiles",
				"Harvest Target": "Iron Ore Veins",
				"Work Interval": "2.5s per ore",
				"Build Cost": "50 Wood, 25 Stone"
			},
			"combat_notes": "Key mid-to-late game building for extracting advanced metallurgy ores."
		},
		{
			"id": "bot_home",
			"name": "Bot Home",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(128, 544, 32, 32)),
			"description": "Dedicated docking post and high-efficiency charging stand for worker bots.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Charging": "Rapid Bot Recharging Stand",
				"Building Limit": "Exempt (Does not consume building slots)"
			},
			"combat_notes": "Place near distant mining or defense clusters so worker bots recharge locally without walking all the way back to the Core."
		}
	]
