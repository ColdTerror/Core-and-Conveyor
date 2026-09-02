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


## Returns all categorized Enemy entries.
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
			"description": "Standard corrupted miner resurrected by the dark fog. Moves directly toward defensive perimeters and attacking towers.",
			"stats": {
				"Max Health": "50",
				"Move Speed": "40 px/s",
				"Attack Type": "Melee (Bump)",
				"Attack Damage": "10",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Neutral (1.0x Piercing, 1.0x Crushing)",
			"combat_notes": "Reliable baseline target. Any tower and ammo combination is equally effective against them."
		},
		{
			"id": "fast_enemy",
			"name": "Spider",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(spider_tex, 4, 3, 0),
			"description": "A swift, scurrying arachnid designed to flank perimeter walls and harass busy worker bots with high sprint velocity.",
			"stats": {
				"Max Health": "25",
				"Move Speed": "75 px/s",
				"Attack Type": "Melee (Bump)",
				"Attack Damage": "5",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Piercing (+20% damage)",
			"combat_notes": "Vulnerable to sharp projectiles! Bow Towers with Wooden/Stone Arrows and Ballista Towers dispatch them quickly."
		},
		{
			"id": "flyer_drone",
			"name": "Flyer Drone",
			"category": "Enemies",
			"subcategory": "Air",
			"icon": get_atlas_texture(drone_tex, 3, 3, 0),
			"description": "An airborne drone that hovers over terrain obstacles, water bodies, and defensive walls to assault inner structures directly.",
			"stats": {
				"Max Health": "35",
				"Move Speed": "60 px/s",
				"Attack Type": "Melee (Dive)",
				"Attack Damage": "12",
				"Attack Speed": "1.0 /s",
				"Flying": "Yes (Ignores walls & water)"
			},
			"weaknesses": "Weak to Piercing (+20% damage)",
			"combat_notes": "Bypasses all wall chokepoints. Place Bow Towers and Ballistas inside your core base to intercept them."
		},
		{
			"id": "ranged_tank",
			"name": "Ranged Tank",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(tank_tex, 2, 3, 0),
			"description": "A heavy siege beast equipped with long-range bio-cannons that bombard defensive towers from beyond normal melee range.",
			"stats": {
				"Max Health": "40",
				"Move Speed": "40 px/s",
				"Attack Type": "Ranged Projectile",
				"Attack Range": "180 px",
				"Attack Damage": "8",
				"Attack Speed": "0.5 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20% damage)",
			"combat_notes": "Armored against arrows. Heavy crushing ammunition (Pebbles from Sling/Scattershot, or Boulders) deals +20% bonus damage."
		},
		{
			"id": "slime_large",
			"name": "Large Slime (Tier 3)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A massive, gelatinous blob with dense health. When defeated, it violently splits into two Medium Slimes.",
			"stats": {
				"Max Health": "120",
				"Move Speed": "30 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "15",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20% damage)",
			"combat_notes": "Extremely resistant to light arrows. Splitting nature makes Scattershot and Crushing weapons ideal counters."
		},
		{
			"id": "slime_medium",
			"name": "Medium Slime (Tier 2)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A fractured division of a Large Slime. Continues charging defensive structures and splits into two Small Slimes on death.",
			"stats": {
				"Max Health": "60",
				"Move Speed": "35 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "10",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20% damage)",
			"combat_notes": "Vulnerable to Crushing damage. Spawns two Small Slimes when destroyed."
		},
		{
			"id": "slime_small",
			"name": "Small Slime (Tier 1)",
			"category": "Enemies",
			"subcategory": "Ground",
			"icon": get_atlas_texture(slime_tex, 4, 2, 0),
			"description": "A fast, scurrying mini-slime that swarms defensive positions in groups after larger slimes are broken apart.",
			"stats": {
				"Max Health": "30",
				"Move Speed": "40 px/s",
				"Attack Type": "Melee (Squash)",
				"Attack Damage": "5",
				"Attack Speed": "1.0 /s",
				"Flying": "No"
			},
			"weaknesses": "Weak to Crushing (+20% damage)",
			"combat_notes": "Last stage of the slime life cycle. Does not split further upon death."
		}
	]


## Returns all categorized Building entries.
static func get_buildings() -> Array[Dictionary]:
	return [
		# --- DEFENSE ---
		{
			"id": "bow_tower",
			"name": "Bow Tower",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(288, 320, 64, 64)),
			"description": "Standard defensive turret that fires arrows at approaching enemies. Can be upgraded to Bow Tower Tier 2.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Attack Range": "8 Tiles",
				"Fire Rate": "1.0 /s",
				"Damage Mult": "1.0x",
				"Ammo Capacity": "20 Shots",
				"Preferred Ammo": "Arrow (Wooden / Stone)",
				"Build Cost": "25 Wood, 25 Stone"
			},
			"combat_notes": "Best deployed along entry paths to snipe fast and flying enemies with Piercing arrows."
		},
		{
			"id": "bow_tower_2",
			"name": "Bow Tower Tier 2",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(288, 320, 64, 64)),
			"description": "Upgraded archer tower with extended engagement range and reinforced firing velocity.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Attack Range": "10 Tiles",
				"Fire Rate": "1.2 /s",
				"Damage Mult": "1.5x",
				"Ammo Capacity": "25 Shots",
				"Preferred Ammo": "Arrow (Wooden / Stone)",
				"Upgrade Cost": "25 Wood, 25 Stone, 10 Planks, 10 Stone Bricks"
			},
			"combat_notes": "Outranges enemy ranged units and deals 50% more damage per arrow."
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
			"combat_notes": "Enormous range and devastating single-target punch. Highly effective against armored bosses and flyers."
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
			"combat_notes": "Rapid-fire Crushing damage tears through Ranged Tanks and Slimes quickly."
		},
		{
			"id": "ammo_distributor",
			"name": "Ammo Distributor",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(352, 448, 64, 64)),
			"description": "Automated supply cannon that launches ammunition packages directly into nearby towers within its 6-tile radius.",
			"stats": {
				"Footprint": "2x2 Tiles",
				"Supply Range": "6 Tiles",
				"Transfer Rate": "1.0s interval",
				"Batch Size": "Configurable (1 - 2+ ammo/pulse)",
				"Storage Capacity": "Up to 10 of each ammo type"
			},
			"combat_notes": "Eliminates the need for manual bot ammo deliveries to frontline towers."
		},
		{
			"id": "wall",
			"name": "Perimeter Wall",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(160, 160, 32, 32)),
			"description": "Sturdy stone barricade that blocks ground enemy movement and funnels horde units into defensive kill-zones.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Health": "150 HP",
				"Build Cost": "5 Stone"
			},
			"combat_notes": "Enemies will path around walls if open paths exist, or attack them if fully walled in."
		},
		{
			"id": "gate",
			"name": "Security Gate",
			"category": "Buildings",
			"subcategory": "Defense",
			"icon": get_building_atlas(Rect2(224, 192, 96, 32)),
			"description": "Automated portcullis that opens instantly for friendly worker bots while remaining barred against hostile night monsters.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Health": "150 HP"
			},
			"combat_notes": "Allows bots to venture outside perimeter walls to harvest resources during the daytime."
		},

		# --- LOGISTICS ---
		{
			"id": "conveyor_belt",
			"name": "Conveyor Belt",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 224, 32, 32)),
			"description": "Standard logistical belt lane that transports resources and finished ammunition between factories, stockpiles, and towers.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Speed": "Base (Upgradeable via Belt Speed Research)"
			},
			"combat_notes": "Does not count towards your building limit cap."
		},
		{
			"id": "router_building",
			"name": "Belt Router",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 192, 32, 32)),
			"description": "Splits incoming belt items evenly across up to 3 outgoing directions in round-robin sequence.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Outputs": "3 Directions"
			},
			"combat_notes": "Essential for distributing raw resources into multiple parallel crafters or ammo lines."
		},
		{
			"id": "filter_building",
			"name": "Belt Filter",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(64, 192, 32, 32)),
			"description": "Inspects passing items and diverts a specifically selected resource type to its filtered output, letting all other items pass straight.",
			"stats": {
				"Footprint": "1x1 Tile",
				"Configuration": "Selectable Item Filter"
			},
			"combat_notes": "Prevents mixed item jams on shared conveyor supply belts."
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
				"Capacity": "2 Isolated Lanes"
			},
			"combat_notes": "Solves complex factory layout spaghetti."
		},
		{
			"id": "stockpile",
			"name": "Stockpile",
			"category": "Buildings",
			"subcategory": "Logistics",
			"icon": get_building_atlas(Rect2(0, 0, 128, 128)),
			"description": "High-capacity bulk storage container. Holds up to 250 units of mixed or dedicated resources with belt input/output ports.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Capacity": "25/50 Items In Mixed/Dedicated",
				"Dedicated Mode": "Optional single-item lock that increases single item storage"
			},
			"combat_notes": "Buffers ammo and materials close to defenses so worker bots have short travel routes."
		},

		# --- PRODUCTION & INFRASTRUCTURE ---
		{
			"id": "core",
			"name": "Command Core",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(512, 192, 128, 128)),
			"description": "The heart of your colony. Contains primary research systems, base storag. If the core falls, the game is lost!",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Health": "100 HP",
				"Recharge Field": "Solar Powered"
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
				"Recipe": "Wood -> Planks"
			},
			"combat_notes": "Powers Bow Tower Tier 2 upgrades and Ballista Bolt crafting."
		},
		{
			"id": "stonemason",
			"name": "Stonemason",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(768, 0, 128, 128)),
			"description": "Masonry workshop that chips raw stone into polished Stone Bricks for fortified structures.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Recipe": "Stone -> Stone Bricks"
			},
			"combat_notes": "Required for Tier 2 buildings, reinforced walls, and advanced defense towers."
		},
		{
			"id": "fletcher",
			"name": "Fletcher",
			"category": "Buildings",
			"subcategory": "Production",
			"icon": get_building_atlas(Rect2(480, 0, 128, 128)),
			"description": "Dedicated ammunition workshop that crafts Wooden Arrows and Stone Arrows for bow towers.",
			"stats": {
				"Footprint": "4x4 Tiles",
				"Recipes": "Wooden Arrows, Stone Arrows"
			},
			"combat_notes": "Keep supplied with Wood and Stone to maintain steady ammo supply for night waves."
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
				"Recipes": "Stone -> Pebbles / Boulders"
			},
			"combat_notes": "Supplies Sling Towers and Scattershot Towers with Crushing ammo."
		}
	]
