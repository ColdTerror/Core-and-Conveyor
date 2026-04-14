extends Node

#Saves to C:\Users\tcmar\AppData\Roaming\Godot\app_userdata\Core and Conveyor
const SAVE_PATH_TEMPLATE = "user://save_slot_%d.save"
var current_slot: int = 1 # Remembers the last slot used for "Quick Save"


var pending_load_data: Dictionary = {}

# ==========================================
# SAVE LOGIC
# ==========================================
func save_game(level_ref: Node2D, slot: int = current_slot):
	current_slot = slot
	var save_data = {}
	
	#Pack the Data
	save_data["economy_stats"] = EconomyManager.get_save_data()

	if is_instance_valid(level_ref) and level_ref.has_method("get_map_save_data"):
		save_data["map_data"] = level_ref.get_map_save_data()
		
	save_data["research_manager"] = ResearchManager.get_save_data()
	
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

# ==========================================
# LOAD LOGIC
# ==========================================
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
	
	
# ==========================================
# UNPACKING SEQUENCE (Called by the new scene)
# ==========================================
func unpack_save(level_ref: Node2D):
	if pending_load_data.is_empty():
		return
		
	print("SaveManager: Unpacking data into the new world...")
	var data = pending_load_data
	

	#Unpack Data
	if data.has("map_data") and level_ref.has_method("load_map_save_data"):
		level_ref.load_map_save_data(data["map_data"])
	
	if data.has("research_manager"):
		ResearchManager.load_save_data(data["research_manager"])
	

	if data.has("economy_stats"):
		EconomyManager.load_save_data(data["economy_stats"])
		

	
	# Finally, do a roll call of the newly spawned physical buildings!
	EconomyManager.recalculate_global_inventory()
	
	# Empty the briefcase so it doesn't accidentally load again!
	pending_load_data.clear()
	print("SaveManager: Unpacking complete!")
