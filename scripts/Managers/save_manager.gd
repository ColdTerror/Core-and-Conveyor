extends Node

const SAVE_PATH_TEMPLATE = "user://save_slot_%d.save"
var current_slot: int = 1 # Remembers the last slot used for "Quick Save"

# ==========================================
# SAVE LOGIC
# ==========================================
func save_game(slot: int = current_slot):
	current_slot = slot
	var save_data = {}
	
	# --- PHASE 1: Pack the Managers ---
	# We grab the global inventory dictionary and duplicate it so we don't accidentally link references
	save_data["economy"] = EconomyManager.global_inventory.duplicate(true)
	
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
	
	# --- PHASE 1: Rebuild the Managers ---
	if parsed_data.has("economy"):
		EconomyManager.global_inventory = parsed_data["economy"]
		EconomyManager.inventory_changed.emit() # Tell the UI to update!
		
	print("Game successfully loaded from Slot ", slot)
	print(parsed_data)
	return true
