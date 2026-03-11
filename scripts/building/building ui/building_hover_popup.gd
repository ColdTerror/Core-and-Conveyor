extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var inventory_box = $VBoxContainer/Inventory
@onready var work_bar = $VBoxContainer/WorkBar

var current_building: Building = null

func _ready():
	work_bar.visible = false
	hide() # Start hidden

func _process(_delta):
	# SAFETY CHECK: If building died, close popup immediately
	if visible and not is_instance_valid(current_building):
		hide_popup()
		return

	# PROGRESS BAR ANIMATION (Only runs if visible + is machine)
	if visible and current_building.has_method("get_progress_ratio"):
		work_bar.value = current_building.get_progress_ratio() * 100.0

func show_building_info(b: Building):
	# 1. Check if we are switching to a NEW building
	var is_new_target = (current_building != b)
	
	# 2. Clean up OLD connections
	_disconnect_signals()
	
	current_building = b
	
	# 3. Update Text & Connect Signals (Your existing logic)
	name_label.text = b.building_name 
	health_label.text = "%d / %d" % [b.health, b.max_health]
	_update_health_text(b.health, b.max_health)
	
	if not current_building.health_changed.is_connected(_on_health_changed):
		current_building.health_changed.connect(_on_health_changed)
		
	if not current_building.inventory_changed.is_connected(_on_inventory_changed):
		current_building.inventory_changed.connect(_on_inventory_changed)
	
	# Handle Inventory / Work Bar...
	work_bar.visible = (b is ProcessorBuilding)
	_refresh_inventory_ui()
	
	# --- 4. THE FLASH ANIMATION ---
	# Only play this if we switched targets or the popup was hidden
	if is_new_target or not visible:
		# Ensure we are visible first
		show()
		
		# Set Pivot to center so it scales from the middle
		pivot_offset = size / 2
		
		# Reset to "Small and Transparent"
		scale = Vector2(0.9, 0.9)
		modulate.a = 0.5 
		
		# Create a Tween to "Pop" it back to normal
		var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		# Animate Scale and Opacity back to 1.0 over 0.1 seconds (Very fast)
		tween.tween_property(self, "scale", Vector2.ONE, 0.1)
		tween.parallel().tween_property(self, "modulate:a", 1.0, 0.1)

func hide_popup():
	_disconnect_signals()
	current_building = null
	hide()

# --- HELPER: CLEAN DISCONNECT ---
func _disconnect_signals():
	if current_building and is_instance_valid(current_building):
		if current_building.health_changed.is_connected(_on_health_changed):
			current_building.health_changed.disconnect(_on_health_changed)
			
		if current_building.has_signal("inventory_changed"):
			if current_building.inventory_changed.is_connected(_on_inventory_changed):
				current_building.inventory_changed.disconnect(_on_inventory_changed)

# --- SIGNAL CALLBACKS ---

func _on_health_changed(current: int, max_hp: int):
	_update_health_text(current, max_hp)

func _update_health_text(current: int, max_hp: int):
	health_label.text = "HP: %d / %d" % [current, max_hp]

func _on_inventory_changed():
	_refresh_inventory_ui()

# --- INVENTORY LOGIC (Unchanged) ---

func _refresh_inventory_ui():
	if not current_building: return
	
	# Safety: Ensure building has this function before calling
	if not current_building.has_method("get_inventory_info"):
		hide_inventory()
		return

	var info = current_building.get_inventory_info()
	
	if not info.is_empty():
		show_inventory(info)
	else:
		hide_inventory()

func show_inventory(inventory: Dictionary):
	inventory_box.visible = true

	# Clear previous rows
	for child in inventory_box.get_children():
		child.queue_free()

	# --- 1. Determine Building Role (Buffer vs Storage) ---
	var is_buffer = false
	var max_cap = 0
	
	# Duck-typing: If the building has a 'buffer_capacity' variable, we assume 
	# it is a Harvester or Processor holding unsecured items.
	if "buffer_capacity" in current_building:
		is_buffer = true
		max_cap = current_building.buffer_capacity

	# --- 2. Populate rows ---
	for key in inventory.keys():
		var value = inventory[key] 
		var display_text = "Unknown"

		if key is Resource and "display_name" in key:
			display_text = key.display_name
		elif key is String:
			display_text = key
			
		var row := Label.new()
		
		# --- 3. Apply Terminology and Color Coding! ---
		if is_buffer and (value is int or value is float):
			if max_cap > 0 and value >= max_cap:
				# JAMMED WARNING (Red)
				row.text = "Buffer FULL [%s]: %d/%d" % [display_text, value, max_cap]
				row.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) 
			else:
				# UNSECURED BUFFER (Grey)
				var cap_str = str(max_cap) if max_cap > 0 else "?"
				row.text = "Output Buffer [%s]: %d/%s" % [display_text, value, cap_str]
				row.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7)) 
		else:
			# SECURED STORAGE (Green)
			if value is int or value is float:
				row.text = "Secured [%s]: %d" % [display_text, value]
			else:
				row.text = "Secured [%s]: %s" % [display_text, str(value)]
				
			row.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			
		inventory_box.add_child(row)

func hide_inventory():
	inventory_box.visible = false
