# ==============================================================================
# Script: Managers/Level.gd
# Purpose: Core scene controller that governs procedural map generation, hotbar slot setup, UI popups, tile resource placement, projectile spawning, and save/load serialization for the entire level environment.
# Dependencies: Requires global Autoloads (InputManager, ResourceManager, SaveManager, EconomyManager), child layers/managers, and PackagedScene references for building blueprints.
# Signals: Emits and listens to signals for hotbar selection, resource destruction, and core placement.
# ==============================================================================
class_name Level
extends Node2D

# ENUMS & CONSTANTS
enum MapGenType { RIVER_DIVIDE, MAINLAND, LAKES }
enum MapBiome { FOREST, DESERT, ALPINE }

const ATLAS_COLUMNS := 3
const TILE_COUNT := 10
const MAP_WIDTH := 150
const MAP_HEIGHT := 150

# Terrain indices based on your library
const TERRAIN_DIRT := 0
const TERRAIN_WATER := 1
const TERRAIN_SAND := 2
const RES_TREE := 3
const RES_STONE := 4
const TERRAIN_GRASS := 5
const RES_IRON_ORE := 6

# EXPORTS & CONFIGURATION
@export_group("Map Settings")
@export var current_map_type: MapGenType = MapGenType.RIVER_DIVIDE
@export var current_biome: MapBiome = MapBiome.FOREST
@export var tile_size_px: Vector2 = Vector2(32, 32)
@export var tile_library: Array[TileDataResource] = []

@export_group("Building Scenes")

@export_subgroup("Logistics")
@export var conveyor_scene: PackedScene 
@export var router_scene: PackedScene 
@export var filter_scene: PackedScene
@export var bridge_scene: PackedScene
@export var launcher_scene: PackedScene
@export var receiver_scene: PackedScene

@export_group("Production")
@export var lumberjack_scene: PackedScene
@export var sawmill_scene: PackedScene
@export var mine_scene: PackedScene
@export var ore_drill_scene: PackedScene
@export var stonemason_scene: PackedScene
@export var fletcher_scene: PackedScene
@export var stone_crusher_scene: PackedScene

@export_subgroup("Defense")
@export var bow_tower_scene: PackedScene
@export var ballista_tower_scene: PackedScene
@export var scattershot_tower_scene: PackedScene
@export var sling_tower_scene: PackedScene
@export var wall_scene: PackedScene
@export var gate_scene: PackedScene
@export var ammo_distributor_scene: PackedScene

@export_subgroup("Infrastructure")
@export var stockpile_scene: PackedScene 
@export var firepit_scene: PackedScene
@export var quota_building: PackedScene

@export_subgroup("Helpers")
@export var item_scene: PackedScene 
@export var core_scene: PackedScene 
@export var projectile_scene: PackedScene

# RUNTIME STATE VARIABLES
var active_grid_objects := {}

# Tool Trackers
var last_hovered_upgrade_tile := Vector2i(-1, -1)
var is_terrain_remove_brush: bool = false
var last_terrain_tile := Vector2i(-1, -1)

# NODES & REFERENCES
@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer

@onready var hover_menu := $CanvasLayer/Popup_Layer/HoverMenu
@onready var hotbar = $CanvasLayer/Hud_Layer/HotBar_UI
@onready var detail_menu = $CanvasLayer/Popup_Layer/DetailMenu 
@onready var management_menu = $CanvasLayer/Popup_Layer/ManagementMenu
@onready var stat_menu = $CanvasLayer/Popup_Layer/StatisticsMenu

@onready var building_manager: BuildingManager = $BuildingManager
@onready var wave_manager: WaveManager = $WaveManager
@onready var corruption_manager: CorruptionManager = $CorruptionManager
@onready var quota_manager: QuotaManager = $QuotaManager
@onready var pathfinder = $Pathfinder



## Binds level references to autoloads, initializes sub-managers, hooks up HUD signals,
## and triggers procedural map generation or unpacks saved slots on boot.
func _ready():
	# Push all the necessary references up to the Autoload!
	InputManager.level_ref = self
	InputManager.building_manager = building_manager
	InputManager.wave_manager = wave_manager
	InputManager.management_menu = management_menu
	InputManager.stat_menu = stat_menu
	InputManager.hover_popup = hover_menu
	
	hover_menu.hide()
	
	# Connect the resource signals
	ResourceManager.resource_state_changed.connect(_on_resource_state_changed)
	ResourceManager.resource_destroyed.connect(_on_resource_destroyed)
	
	# Setup pause menu signal
	var pause_menu = $CanvasLayer/PauseMenu 
	pause_menu.save_requested.connect(_on_pause_menu_save_requested)
	
	# Give the manager a reference to this Level node
	building_manager.initialize(self)
	quota_manager.initialize(self)

	# Connect Hotbar Signal
	if hotbar:
		hotbar.item_selected.connect(_on_hotbar_item_selected)
		_setup_hotbar_items()
		
	InputManager.object_selected.connect(detail_menu.open_menu)
	building_manager.core_placed_event.connect(_on_core_placed)
	
	building_manager.pathfinder = pathfinder
	
	if not SaveManager.pending_load_data.is_empty():
		SaveManager.unpack_save(self)
	else:
		generate_simple_map()

	var tm = get_tree().get_first_node_in_group("TimeManager")
	if tm:
		tm.season_changed.connect(update_seasonal_resource_sprites)

	update_seasonal_resource_sprites()



## Updates mouse location tracking, driving building upgrade visual preview overlays.
func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	var grid_pos = terrain_layer.local_to_map(mouse_pos)
	
	if InputManager.current_mode == InputManager.InteractionMode.UPGRADE:
		# Only update the UI if the mouse moved to a NEW tile
		if grid_pos != last_hovered_upgrade_tile:
			last_hovered_upgrade_tile = grid_pos
			building_manager.show_upgrade_preview(grid_pos)
	else:
		# If we cancel Upgrade Mode, hide the UI immediately
		if last_hovered_upgrade_tile != Vector2i(-1, -1):
			last_hovered_upgrade_tile = Vector2i(-1, -1)
			building_manager.placement_ended.emit() 



# HOTBAR & UI
var categorized_buildings := {}


## Constructs and populates the categorised structure databases and setups initial core slot.
func _setup_hotbar_items():
	categorized_buildings = {
		"Logistics": [
			{"name": "Belt", "scene": conveyor_scene},
			{"name": "Router", "scene": router_scene},
			{"name": "Filter", "scene": filter_scene},
			{"name": "Conveyer Bridge", "scene": bridge_scene},
			{"name": "Launcher", "scene": launcher_scene},
			{"name": "Receiver", "scene": receiver_scene}
		],
		"Production": [
			{"name": "Hut", "scene": lumberjack_scene},
			{"name": "Sawmill", "scene": sawmill_scene},
			{"name": "Stone Mine", "scene": mine_scene},
			{"name": "Ore Drill", "scene": ore_drill_scene},
			{"name": "Stonemason", "scene": stonemason_scene},
			{"name": "Fletcher", "scene": fletcher_scene},
			{"name": "Stone Crusher", "scene": stone_crusher_scene}
		],
		"Defense": [
			{"name": "Bow Tower", "scene": bow_tower_scene},
			{"name": "Ballista Tower", "scene": ballista_tower_scene},
			{"name": "Scattershot Tower", "scene": scattershot_tower_scene},
			{"name": "Sling Tower", "scene": sling_tower_scene},
			{"name": "Wall", "scene": wall_scene},
			{"name": "Gate", "scene": gate_scene},
			{"name": "Ammo Distributor", "scene": ammo_distributor_scene}
		],
		"Infrastructure": [
			{"name": "Stockpile", "scene": stockpile_scene},
			{"name": "Firepit", "scene": firepit_scene},
			{"name": "QuotaBuilding", "scene": quota_building}
		]
	}
	
	_add_building_to_bar("Core", core_scene)



## Hooked to building manager core placement, expanding HUD options upon completion.
func _on_core_placed():
	print_debug("from level on core placed")
	_show_main_categories()



## Renders primary building type folders in the hotbar HUD.
func _show_main_categories():
	if hotbar.has_method("clear_buttons"):
		hotbar.clear_buttons()
		
	_add_category_button("Logistics")
	_add_category_button("Production")
	_add_category_button("Defense")
	_add_category_button("Infrastructure")



## Opens a subfolder on the hotbar to display building blueprints.
func _show_category(category_name: String):
	if hotbar.has_method("clear_buttons"):
		hotbar.clear_buttons()
		
	hotbar.add_button("Back", null, "ACTION_BACK", false)
	
	var items = categorized_buildings[category_name]
	for item in items:
		if item["name"] in ["Launcher", "Receiver"] and not ("Pneumatic Logistics" in ResearchManager.unlocked_techs):
			continue
		_add_building_to_bar(item["name"], item["scene"])



## Formats category directory buttons on the hotbar.
func _add_category_button(category_name: String):
	hotbar.add_button(category_name, null, "CAT_" + category_name, false)



## Instantiates a temporary scene reference to fetch custom button textures, adding it to hotbar.
func _add_building_to_bar(name: String, packed_scene: PackedScene):
	if not packed_scene: return
	var temp = packed_scene.instantiate()
	var icon = temp.icon if "icon" in temp else null
	hotbar.add_button(name, icon, packed_scene, true)
	temp.queue_free()



## Responds to button select, activating building placements or routing folders.
func _on_hotbar_item_selected(data, is_building):
	building_manager.cancel_placement()
	
	if is_building:
		InputManager.current_mode = InputManager.InteractionMode.PLACE_BUILDING
		building_manager.start_placing(data)
	else:
		if typeof(data) == TYPE_STRING:
			if data.begins_with("CAT_"):
				var cat_name = data.replace("CAT_", "")
				_show_category(cat_name)
			elif data == "ACTION_BACK":
				_show_main_categories()



# RESOURCES & ENVIRONMENT


## Redraws individual resource sprites on the object layer when harvesting hits occur or regrowth finishes.
func _on_resource_state_changed(tile: Vector2i, state: int, data: TileDataResource):
	var season = TimeManager.Season.SPRING
	var tm = get_tree().get_first_node_in_group("TimeManager")
	if tm:
		season = tm.get_current_season()
		
	if current_biome == MapBiome.ALPINE:
		season = TimeManager.Season.WINTER

	match state:
		ResourceManager.ResourceState.FULL:
			var coords = data.get_seasonal_coords(season, ResourceManager.ResourceState.FULL)
			object_layer.set_cell(tile, 0, coords)
			if active_grid_objects.has(tile):
				active_grid_objects[tile]["health"] = active_grid_objects[tile].get("max_health", data.total_resources)
		ResourceManager.ResourceState.HARVESTING:
			var coords = data.get_seasonal_coords(season, ResourceManager.ResourceState.HARVESTING)
			if coords != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, coords)
		ResourceManager.ResourceState.DEPLETED:
			var coords = data.get_seasonal_coords(season, ResourceManager.ResourceState.DEPLETED)
			if coords != Vector2i(-1, -1):
				object_layer.set_cell(tile, 0, coords)
			else:
				object_layer.set_cell(tile, -1)



## Iterates over all active resources and updates their visual sprites to match the new season.
func update_seasonal_resource_sprites(new_season: int = -1):
	var season = new_season
	if season == -1:
		season = TimeManager.Season.SPRING
		var tm = get_tree().get_first_node_in_group("TimeManager")
		if tm:
			season = tm.get_current_season()
			
	if current_biome == MapBiome.ALPINE:
		season = TimeManager.Season.WINTER
			
	for tile in active_grid_objects:
		var obj = active_grid_objects[tile]
		var data = obj["data"] as TileDataResource
		
		# If it's a stump (depleted), it's tracked in ResourceManager regrowth tasks
		if ResourceManager.active_regrowth_tasks.has(tile):
			continue
			
		# If it's depleted, it's in the depleted state (unless it's already in regrowth tasks which is checked above)
		var state = ResourceManager.ResourceState.FULL
		if obj["health"] <= 0 and data.atlas_coords_depleted != Vector2i(-1, -1):
			state = ResourceManager.ResourceState.DEPLETED
		elif obj["health"] < obj.get("max_health", data.total_resources):
			state = ResourceManager.ResourceState.HARVESTING
			
		var coords = data.get_seasonal_coords(season, state)
		if coords != Vector2i(-1, -1):
			object_layer.set_cell(tile, 0, coords)



## Clears depleted tiles and tells pathfinders to recalculate walkable statuses.
func _on_resource_destroyed(tile: Vector2i):
	if active_grid_objects.has(tile):
		active_grid_objects.erase(tile)
	object_layer.erase_cell(tile) 
	
	if building_manager and building_manager.pathfinder:
		building_manager.pathfinder.set_obstacle(tile, false)
		building_manager.pathfinder.set_weighted_obstacle(tile, 1.0)



## Queries atlas coordinates to identify matching resource library indexes.
func get_object_tile_index(tile: Vector2i) -> int:
	var atlas := object_layer.get_cell_atlas_coords(tile)
	if atlas == Vector2i(-1, -1): return -1
	return atlas.y * ATLAS_COLUMNS + atlas.x



# COMBAT & PROJECTILES


## Spawns dynamic projectiles in active world space, passing scaling parameters.
func _on_tower_fired(source_tower, start_pos, target_node, item_data, final_damage, speed, angle_offset):
	if not projectile_scene:
		print("Error: Projectile Scene not assigned in Level Inspector")
		return
	
	var dir = Vector2.RIGHT 
	if is_instance_valid(target_node):
		dir = (target_node.global_position - start_pos).normalized()
	
	dir = dir.rotated(angle_offset)
	var proj = projectile_scene.instantiate()
	object_layer.add_child(proj)
	
	if proj.has_method("setup"):
		var p_lifetime = 10.0
		if "projectile_lifetime" in item_data:
			p_lifetime = item_data.projectile_lifetime
		var p_dmg_type = "None"
		if "damage_type" in item_data:
			p_dmg_type = item_data.damage_type
		proj.setup(start_pos, dir, speed, final_damage, item_data.texture, source_tower, p_lifetime, p_dmg_type)



# MAP GENERATION


## Drives procedural map generation utilizing layered simplex noises and falloff gradients.
func generate_simple_map():
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()
	
	var left_points = []
	var right_points = []
	var top_points = []
	var bottom_points = []
	for i in range(5):
		left_points.append(1.0 if randf() < 0.5 else 0.0)
		right_points.append(1.0 if randf() < 0.5 else 0.0)
		top_points.append(1.0 if randf() < 0.5 else 0.0)
		bottom_points.append(1.0 if randf() < 0.5 else 0.0)
	
	print("Generating map. Edge Control Points - Left: ", left_points, ", Right: ", right_points, ", Top: ", top_points, ", Bottom: ", bottom_points)
	
	var land_noise = FastNoiseLite.new()
	land_noise.seed = randi()
	land_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	land_noise.frequency = 0.035 
	
	var forest_noise = FastNoiseLite.new()
	forest_noise.seed = randi()
	forest_noise.frequency = 0.025 
	
	var stone_noise = FastNoiseLite.new()
	stone_noise.seed = randi() + 1 
	stone_noise.frequency = 0.025 
	
	var biome_noise = FastNoiseLite.new()
	biome_noise.seed = randi() + 2
	biome_noise.frequency = 0.015 
	
	var river_noise = FastNoiseLite.new()
	river_noise.seed = randi() + 3
	river_noise.frequency = 0.006 
	
	var iron_noise = FastNoiseLite.new()
	iron_noise.seed = randi() + 4
	iron_noise.frequency = 0.03 
	
	var water_level = 0.16
	var sand_level = 0.20
	
	match current_map_type:
		MapGenType.LAKES:
			land_noise.frequency = 0.010
			water_level = 0.38
			sand_level = 0.40
		MapGenType.MAINLAND:
			pass 
		MapGenType.RIVER_DIVIDE:
			pass 
			
	var terrain_map := {}
	var margin := 0.22

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var grid_pos = Vector2i(x, y)
			
			var falloff := 1.0
			
			# Smooth Left Edge
			var ty_l = float(y) / MAP_HEIGHT
			var scaled_ty_l = ty_l * 4.0
			var idx_y_l = clamp(int(scaled_ty_l), 0, 3)
			var frac_y_l = scaled_ty_l - idx_y_l
			var smooth_y_l = frac_y_l * frac_y_l * (3.0 - 2.0 * frac_y_l)
			var val_left = lerp(float(left_points[idx_y_l]), float(left_points[idx_y_l+1]), smooth_y_l)
			if val_left > 0.0:
				var dist_left = float(x) / MAP_WIDTH
				var edge_clamp = clamp(dist_left / margin, 0.0, 1.0)
				falloff *= lerp(1.0, edge_clamp, val_left)

			# Smooth Right Edge
			var ty_r = float(y) / MAP_HEIGHT
			var scaled_ty_r = ty_r * 4.0
			var idx_y_r = clamp(int(scaled_ty_r), 0, 3)
			var frac_y_r = scaled_ty_r - idx_y_r
			var smooth_y_r = frac_y_r * frac_y_r * (3.0 - 2.0 * frac_y_r)
			var val_right = lerp(float(right_points[idx_y_r]), float(right_points[idx_y_r+1]), smooth_y_r)
			if val_right > 0.0:
				var dist_right = float(MAP_WIDTH - 1 - x) / MAP_WIDTH
				var edge_clamp = clamp(dist_right / margin, 0.0, 1.0)
				falloff *= lerp(1.0, edge_clamp, val_right)

			# Smooth Top Edge
			var tx_t = float(x) / MAP_WIDTH
			var scaled_tx_t = tx_t * 4.0
			var idx_x_t = clamp(int(scaled_tx_t), 0, 3)
			var frac_x_t = scaled_tx_t - idx_x_t
			var smooth_x_t = frac_x_t * frac_x_t * (3.0 - 2.0 * frac_x_t)
			var val_top = lerp(float(top_points[idx_x_t]), float(top_points[idx_x_t+1]), smooth_x_t)
			if val_top > 0.0:
				var dist_top = float(y) / MAP_HEIGHT
				var edge_clamp = clamp(dist_top / margin, 0.0, 1.0)
				falloff *= lerp(1.0, edge_clamp, val_top)

			# Smooth Bottom Edge
			var tx_b = float(x) / MAP_WIDTH
			var scaled_tx_b = tx_b * 4.0
			var idx_x_b = clamp(int(scaled_tx_b), 0, 3)
			var frac_x_b = scaled_tx_b - idx_x_b
			var smooth_x_b = frac_x_b * frac_x_b * (3.0 - 2.0 * frac_x_b)
			var val_bottom = lerp(float(bottom_points[idx_x_b]), float(bottom_points[idx_x_b+1]), smooth_x_b)
			if val_bottom > 0.0:
				var dist_bottom = float(MAP_HEIGHT - 1 - y) / MAP_HEIGHT
				var edge_clamp = clamp(dist_bottom / margin, 0.0, 1.0)
				falloff *= lerp(1.0, edge_clamp, val_bottom)
			
			var noise_val = (land_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var elevation = noise_val * falloff

			var type = TERRAIN_WATER
			if elevation < water_level: type = TERRAIN_WATER
			elif elevation < sand_level: type = TERRAIN_SAND
			else: type = TERRAIN_DIRT
				
			if type == TERRAIN_DIRT:
				var biome_val = biome_noise.get_noise_2d(x, y)
				if biome_val < -0.10:
					type = TERRAIN_GRASS
				
			if current_map_type == MapGenType.RIVER_DIVIDE:
				if type == TERRAIN_DIRT or type == TERRAIN_GRASS or type == TERRAIN_SAND:
					var r_val = abs(river_noise.get_noise_2d(x, y))
					if r_val < 0.05: type = TERRAIN_WATER
					elif r_val < 0.06: type = TERRAIN_SAND
			
			terrain_map[grid_pos] = type

	for pos in terrain_map:
		var type = terrain_map[pos]
		if type >= 0 and type < tile_library.size():
			var data = tile_library[type]
			var default_coords = Vector2i(type % ATLAS_COLUMNS, type / ATLAS_COLUMNS)
			var final_coords = data.atlas_coords_full if data.atlas_coords_full != Vector2i(-1, -1) else default_coords
			
			# Biome-specific Palette Swaps
			if current_biome == MapBiome.DESERT:
				# Swap Grass (5) and Dirt (0) to Sand (2, 0)
				if type == TERRAIN_GRASS or type == TERRAIN_DIRT:
					final_coords = Vector2i(2, 0)
			elif current_biome == MapBiome.ALPINE:
				# Swap Grass (5) to Dirt (0, 0) for a cold rocky look
				if type == TERRAIN_GRASS:
					final_coords = Vector2i(0, 0)
					
			terrain_layer.set_cell(pos, 0, final_coords)

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			
			if terrain_map[pos] == TERRAIN_GRASS:
				var f_val = forest_noise.get_noise_2d(x, y)
				var min_threshold = 0.15
				var spawn_mult = 1.0
				
				if current_biome == MapBiome.DESERT:
					min_threshold = 0.40 # Very few tree spots
					spawn_mult = 0.20 # 80% fewer trees
				elif current_biome == MapBiome.ALPINE:
					min_threshold = 0.25 # Less wood
					spawn_mult = 0.50 # 50% fewer trees
					
				if f_val > min_threshold:
					var spawn_chance = 0.85
					if f_val > 0.4:
						spawn_chance = 0.95
					elif f_val < 0.25:
						spawn_chance = 0.50
						
					if randf() < (spawn_chance * spawn_mult):
						var normalized_f = (f_val + 1.0) / 2.0
						place_resource_at(pos, RES_TREE, normalized_f)
						
			elif terrain_map[pos] == TERRAIN_DIRT:
				var s_val = stone_noise.get_noise_2d(x, y)
				var min_threshold = 0.15
				var spawn_mult = 1.0
				
				if current_biome == MapBiome.DESERT:
					min_threshold = 0.08 # More stone mountains
					spawn_mult = 1.2
				elif current_biome == MapBiome.ALPINE:
					min_threshold = 0.08 # More stone mountains
					spawn_mult = 1.2
					
				if s_val > min_threshold:
					var spawn_chance = 1.0
					if s_val < 0.22:
						spawn_chance = 0.80
						
					if randf() < (spawn_chance * spawn_mult):
						var normalized_s = (s_val + 1.0) / 2.0
						place_resource_at(pos, RES_STONE, normalized_s)
						_spawn_iron_ore_vein_near(pos, iron_noise, terrain_map)
					
	var map_rect = Rect2i(0, 0, MAP_HEIGHT, MAP_WIDTH)
	pathfinder.setup(terrain_layer, object_layer, map_rect)
	print("Map generated: ", MapGenType.keys()[current_map_type])



## Draws a resource node at the designated coordinate, tracking health buffers.
func place_resource_at(grid_pos: Vector2i, resource_index: int, noise_val: float = -1.0):
	if resource_index >= tile_library.size(): return
	var data = tile_library[resource_index]
	object_layer.set_cell(grid_pos, 0, data.atlas_coords_full)
	
	if resource_index == RES_TREE:
		var grass_index = TERRAIN_GRASS
		if grass_index < tile_library.size():
			var grass_data = tile_library[grass_index]
			var default_coords = Vector2i(grass_index % ATLAS_COLUMNS, grass_index / ATLAS_COLUMNS)
			var final_coords = grass_data.atlas_coords_full if grass_data.atlas_coords_full != Vector2i(-1, -1) else default_coords
			terrain_layer.set_cell(grid_pos, 0, final_coords)
	
	var initial_health = data.total_resources
	if noise_val >= 0.0:
		if resource_index == RES_TREE:
			# noise_val (d_val) is in [0.60, 1.0]
			var t = clamp((noise_val - 0.60) / 0.40, 0.0, 1.0)
			initial_health = lerp(float(data.total_resources), float(data.total_resources * 2), t)
		elif resource_index == RES_STONE:
			# noise_val (s_val) is in [0.55, 1.0]
			var t = clamp((noise_val - 0.55) / 0.45, 0.0, 1.0)
			initial_health = lerp(float(data.total_resources), float(data.total_resources * 2), t)
			
	active_grid_objects[grid_pos] = {
		"health": int(initial_health),
		"max_health": int(initial_health),
		"data": data
	}



## Spawns iron ore resource outcrops procedurally near a stone outcrop if the terrain is land.
func _spawn_iron_ore_vein_near(stone_pos: Vector2i, iron_noise: FastNoiseLite, terrain_map: Dictionary) -> void:
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var dist = abs(dx) + abs(dy)
			if dist == 0: continue
			
			var check_pos = stone_pos + Vector2i(dx, dy)
			if check_pos.x < 0 or check_pos.x >= MAP_WIDTH or check_pos.y < 0 or check_pos.y >= MAP_HEIGHT:
				continue
				
			var current_terrain = terrain_map.get(check_pos, -1)
			if current_terrain == TERRAIN_DIRT or current_terrain == TERRAIN_GRASS:
				var iron_val = (iron_noise.get_noise_2d(check_pos.x, check_pos.y) + 1.0) / 2.0
				if iron_val > 0.65:
					place_resource_at(check_pos, RES_IRON_ORE, -1)



## Places an individual tile into active maps.
func place_tile(grid_pos: Vector2i, data: TileDataResource):
	var correct_index = tile_library.find(data)
	if correct_index == -1: return
	
	var atlas_coords = Vector2i(correct_index % ATLAS_COLUMNS, correct_index / ATLAS_COLUMNS)
	if not data.is_object:
		var final_coords = data.atlas_coords_full if data.atlas_coords_full != Vector2i(-1, -1) else atlas_coords
		terrain_layer.set_cell(grid_pos, 0, final_coords)
	else:
		if can_place_object(grid_pos):
			var final_coords = data.atlas_coords_full if data.atlas_coords_full != Vector2i(-1, -1) else atlas_coords
			object_layer.set_cell(grid_pos, 0, final_coords)
			active_grid_objects[grid_pos] = {
				"health": data.total_resources,
				"max_health": data.total_resources,
				"data": data
			}



## Verifies whether the coordinate target is empty and walkable terrain.
func can_place_object(grid_pos: Vector2i) -> bool:
	var terrain_atlas = terrain_layer.get_cell_atlas_coords(grid_pos)
	if terrain_atlas == Vector2i(-1, -1): return false 
	
	var terrain_index = terrain_atlas.y * ATLAS_COLUMNS + terrain_atlas.x
	if terrain_index == TERRAIN_WATER: return false
	if object_layer.get_cell_source_id(grid_pos) != -1: return false
	if building_manager.occupied_tiles.has(grid_pos): return false

	return true



# MAP SAVE / LOAD


## Connects pause menus to save serializers.
func _on_pause_menu_save_requested(slot: int):
	SaveManager.save_game(self, slot)
	


## Packs level environment floor layouts, resources, camera vectors, and bots for saving.
func get_map_save_data() -> Dictionary:
	var terrain_data = {}
	for pos in terrain_layer.get_used_cells():
		var atlas = terrain_layer.get_cell_atlas_coords(pos)
		terrain_data[var_to_str(pos)] = var_to_str(atlas)

	var object_data = {}
	for pos in active_grid_objects:
		var obj = active_grid_objects[pos]
		var correct_index = tile_library.find(obj["data"])
		object_data[var_to_str(pos)] = {
			"health": obj["health"],
			"max_health": obj.get("max_health", obj["health"]),
			"lib_index": correct_index
		}

	var saved_bots = []
	for bot in get_tree().get_nodes_in_group("Bots"):
		saved_bots.append(bot.get_save_data())
		
	var current_camera = get_viewport().get_camera_2d()
		
	return {
		"map_type": current_map_type,
		"biome": current_biome,
		"terrain": terrain_data,
		"objects": object_data,
		"worker_bots": saved_bots,
		"camera_x": current_camera.global_position.x,
		"camera_y": current_camera.global_position.y,
		"camera_zoom_x": current_camera.zoom.x,
		"camera_zoom_y": current_camera.zoom.y
	}


## Rebuilds the level environment floor map, objects, spawned bots, and camera placements from saves.
func load_map_save_data(data: Dictionary):
	terrain_layer.clear()
	object_layer.clear()
	active_grid_objects.clear()

	current_map_type = data.get("map_type", 0)
	current_biome = data.get("biome", 0)

	var terrain_data = data.get("terrain", {})
	for pos_str in terrain_data:
		var pos = str_to_var(pos_str)
		var atlas = str_to_var(terrain_data[pos_str])
		terrain_layer.set_cell(pos, 0, atlas)

	var object_data = data.get("objects", {})
	for pos_str in object_data:
		var pos = str_to_var(pos_str)
		var obj_info = object_data[pos_str]
		var lib_idx = obj_info["lib_index"]

		if lib_idx >= 0 and lib_idx < tile_library.size():
			var tile_data = tile_library[lib_idx]
			
			var final_coords = tile_data.atlas_coords_full
			var max_hp = obj_info.get("max_health", tile_data.total_resources)
			if obj_info["health"] <= 0 and tile_data.atlas_coords_depleted != Vector2i(-1, -1):
				final_coords = tile_data.atlas_coords_depleted
			elif obj_info["health"] < max_hp and tile_data.atlas_coords_harvesting != Vector2i(-1, -1):
				final_coords = tile_data.atlas_coords_harvesting
				
			object_layer.set_cell(pos, 0, final_coords)
			active_grid_objects[pos] = {
				"health": obj_info["health"],
				"max_health": max_hp,
				"data": tile_data
			}
			
	var map_rect = Rect2i(0, 0, MAP_HEIGHT, MAP_WIDTH)
	pathfinder.setup(terrain_layer, object_layer, map_rect)
	
	if data.has("worker_bots"):
		var bot_scene = load("res://scenes/Workers/WorkerBot.tscn")
		
		for b_data in data["worker_bots"]:
			var new_bot = bot_scene.instantiate()
			object_layer.add_child(new_bot)
			
			new_bot.setup(self)
			new_bot.load_save_data(b_data)
			
			new_bot.hovered.connect(InputManager._on_object_hovered)
			new_bot.unhovered.connect(InputManager._on_object_unhovered)
	
	var current_camera = get_viewport().get_camera_2d()
	if current_camera:
		if data.has("camera_x") and data.has("camera_y"):
			current_camera.global_position = Vector2(data["camera_x"], data["camera_y"])
			
		if data.has("camera_zoom_x") and data.has("camera_zoom_y"):
			current_camera.zoom = Vector2(data["camera_zoom_x"], data["camera_zoom_y"])
	print("Map loaded successfully!")
