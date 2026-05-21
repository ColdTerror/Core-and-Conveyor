# ==============================================================================
# Script: Managers/save_manager.gd
# Purpose: Standard game state packaging and JSON-based file serialization system. Manages slot writing, directory creation, game reloading, and the sequential unpacking of state buffers across global autoloads and local node managers.
# Dependencies: Requires Global Autoloads (EconomyManager, AudioManager, ResearchManager) and Level scene sub-managers.
# Signals: None.
# ==============================================================================
extends Node

#Saves to C:\Users\tcmar\AppData\Roaming\Godot\app_userdata\Core and Conveyor
const SAVE_PATH_TEMPLATE = "user://save_slot_%d.save"
var current_slot: int = 1 # Remembers the last slot used for "Quick Save"


var pending_load_data: Dictionary = {}

func save_game(level_ref: Node2D, slot: int = current_slot):
	current_slot = slot
	var save_data = {}
	
	#Pack the Data
	save_data["economy_stats"] = EconomyManager.get_save_data()
	
	save_data["audio_manager"] = AudioManager.get_save_data()

	if is_instance_valid(level_ref) and level_ref.has_method("get_map_save_data"):
		save_data["map_data"] = level_ref.get_map_save_data()
		
	save_data["research_manager"] = ResearchManager.get_save_data()
	
	if level_ref.has_node("QuotaManager"):
		save_data["quota_manager"] = level_ref.get_node("QuotaManager").get_save_data()
		
	if is_instance_valid(level_ref) and level_ref.has_node("TimeManager"):
		save_data["time_manager"] = level_ref.get_node("TimeManager").get_save_data()
	
	if level_ref.has_node("CorruptionManager"):
			save_data["corruption_manager"] = level_ref.get_node("CorruptionManager").get_save_data()
	
	if level_ref.has_node("WaveManager"):
			save_data["wave_manager"] = level_ref.get_node("WaveManager").get_save_data()
	
	if level_ref.has_node("BuildingManager"):
		save_data["building_manager"] = level_ref.get_node("BuildingManager").get_save_data()
		
	# Convert our beautiful dictionary into a JSON text string
	var json_string = JSON.stringify(save_data)
	
	# Open the file on the player's hard drive and write the text
	var file_path = SAVE_PATH_TEMPLATE % slot
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file:
		file.store_string(json_string)
		file.close()
		print("Game successfully saved to Slot ", slot)
	else:
		print("ERROR: Could not save to ", file_path)

func load_game(slot: int):
	var file_path = SAVE_PATH_TEMPLATE % slot
	
	if not FileAccess.file_exists(file_path):
		print("No save file found in Slot ", slot)
		return false
		
	# Open the file and read the text
	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	# Convert the text back into a Godot Dictionary
	var parsed_data = JSON.parse_string(json_string)
	
	if typeof(parsed_data) != TYPE_DICTIONARY:
		print("ERROR: Save file is corrupted!")
		return false
		
	current_slot = slot
	
	pending_load_data = parsed_data
	get_tree().paused = false # Unpause in case they loaded from the pause menu!
	get_tree().reload_current_scene()
	
	
	print("Game successfully loaded from Slot ", slot)
	return true
	
	
func unpack_save(level_ref: Node2D):
	if pending_load_data.is_empty():
		return
		
	print("SaveManager: Unpacking data into the new world...")
	var data = pending_load_data
	

	#Unpack Data
	
	if data.has("audio_manager"):
		AudioManager.load_save_data(data["audio_manager"])
		
		
	if data.has("map_data") and level_ref.has_method("load_map_save_data"):
		level_ref.load_map_save_data(data["map_data"])
	
	if data.has("building_manager") and level_ref.has_node("BuildingManager"):
		var b_manager = level_ref.get_node("BuildingManager")
		
		# --- THE FIX: Force the manager to grab the level reference BEFORE loading! ---
		b_manager.initialize(level_ref) 
		
		b_manager.load_save_data(data["building_manager"])
		
	if data.has("research_manager"):
		ResearchManager.load_save_data(data["research_manager"])
		
	if data.has("quota_manager") and level_ref.has_node("QuotaManager"):
		level_ref.get_node("QuotaManager").load_save_data(data["quota_manager"])
		
	if data.has("corruption_manager") and level_ref.has_node("CorruptionManager"):
		level_ref.get_node("CorruptionManager").load_save_data(data["corruption_manager"])

	if data.has("economy_stats"):
		EconomyManager.load_save_data(data["economy_stats"])
		
	if data.has("time_manager") and level_ref.has_node("TimeManager"):
		level_ref.get_node("TimeManager").load_save_data(data["time_manager"])
	
	if data.has("wave_manager") and level_ref.has_node("WaveManager"):
		level_ref.get_node("WaveManager").load_save_data(data["wave_manager"])
			
	# Finally, do a roll call of the newly spawned physical buildings!
	EconomyManager.recalculate_global_inventory()
	
	# Empty the briefcase so it doesn't accidentally load again!
	pending_load_data.clear()
	print("SaveManager: Unpacking complete!")

func does_save_exist(slot: int) -> bool:
	var file_path = SAVE_PATH_TEMPLATE % slot
	return FileAccess.file_exists(file_path)

func delete_save(slot: int) -> bool:
	var file_path = SAVE_PATH_TEMPLATE % slot
	if FileAccess.file_exists(file_path):
		# Delete the file using DirAccess
		DirAccess.remove_absolute(file_path)
		print("Deleted save file in Slot ", slot)
		return true
	return false
