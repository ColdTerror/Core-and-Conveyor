extends Building
class_name ConveyorBuilding

# ============================================================
# EXPORTS & VARIABLES
# ============================================================
@export var generic_item_scene: PackedScene # <--- NEW: Needed to respawn items on load!

@export var speed: float = 64.0  # Pixels per second the item travels

var direction: Vector2i = Vector2i.RIGHT  # Grid direction (UP, DOWN, LEFT, RIGHT)
var held_item: Node2D = null  # The item currently on this belt (null = empty)
var level_ref: Node2D  # Reference to the level/world node

# State tracking for two-phase movement system
var is_moving_to_edge: bool = false  # false = moving to center, true = moving to edge
var push_cooldown: float = 0.0
var is_delivering: bool = false

# ============================================================
# SETUP & CLEANUP
# ============================================================

# Called by BuildingManager when belt is placed
func setup(level_instance: Node2D, dir: Vector2i):
	level_ref = level_instance
	
	# Safety: Prevent zero direction which would break movement
	direction = dir if dir != Vector2i.ZERO else Vector2i.RIGHT
	
	# Rotate the belt sprite to match direction
	rotation = Vector2(direction).angle()

# Called when this node is removed from the scene tree
func _exit_tree():
	# Clean up held item
	if held_item and is_instance_valid(held_item):
		held_item.queue_free()
		held_item = null
	
# ============================================================
# ITEM ACCEPTANCE (INPUT)
# ============================================================

# Query function: Can this belt accept an item at the given tile?
# Used by harvesters and other belts before attempting transfer
func accepts_item_at(_tile: Vector2i) -> bool:
	return held_item == null  # Only accept if we're empty

# Actual transfer function: Take ownership of an item node
func accept_item_node(item_node: Node2D, source_belt: ConveyorBuilding = null) -> bool:
	# Reject if we already have an item or haven't been set up
	if held_item != null or not level_ref: 
		return false
	
	# Take ownership
	held_item = item_node
	is_moving_to_edge = false  # Start in "moving to center" phase
	
	# === PARENTING LOGIC ===
	# Ensure the item is a child of level_ref (not another belt or null)
	var old_parent = item_node.get_parent()
	
	# Check if the item is coming from another ConveyorBuilding via parameter
	var perpendicular_transfer = false
	
	if source_belt:
		if source_belt is RouterBuilding: 
			perpendicular_transfer = true 
		else:
			var prev_direction = source_belt.direction
			perpendicular_transfer = (Vector2(prev_direction).dot(Vector2(direction)) == 0)
	
	# If item has a parent AND it's not our level, remove it from old parent
	if old_parent and old_parent != level_ref:
		old_parent.remove_child(item_node)
	
	# If item has no parent now, add it to the level
	if not item_node.get_parent():
		level_ref.add_child(item_node)
	
	# === POSITION SNAPPING ===
	if perpendicular_transfer:
		# Item is turning a corner - DON'T snap position, let it move smoothly to center
		# The item will naturally continue from its current position toward our center
		pass
	else:
		# Item is continuing straight (or coming from non-belt) - snap to back edge
		var back_edge = global_position - (Vector2(direction) * 16.0)
		item_node.global_position = back_edge
		
	return true  # Success!


# ============================================================
# MOVEMENT LOOP (runs every frame)
# ============================================================

func _process(delta):
	if is_delivering: return
	
	# Early exit: Nothing to move if belt is empty
	if held_item == null: 
		return
	
	# Safety check: Item might have been freed/deleted elsewhere
	if not is_instance_valid(held_item):
		held_item = null
		return
		
	# --- HANDLE COOLDOWN ---
	if push_cooldown > 0:
		push_cooldown -= delta
		return # Stop calculating movement while we wait!

	var target_pos = Vector2.ZERO
	
	# ========================================
	# PHASE 1: Moving to Center
	# ========================================
	if not is_moving_to_edge:
		target_pos = global_position
		
		# Move item toward center
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		# Check if we've reached the center
		if held_item.global_position.distance_to(target_pos) < 1.0:
			held_item.global_position = target_pos # Snap to exact center
			
			var neighbor = _get_neighbor()
			
			# CASE A: Neighbor is a Belt. Do the normal 2-phase edge handoff.
			if neighbor and neighbor is ConveyorBuilding:
				if _can_push_to_neighbor():
					is_moving_to_edge = true 
					
			# CASE B: Neighbor is a Building. Push directly from the center!
			elif neighbor and neighbor.has_method("add_item") and "item_data" in held_item:
				if neighbor.add_item(held_item.item_data, 1) > 0:
					# Success! Lock the belt so the item behind it waits.
					is_delivering = true 
					
					var slide_target = global_position + (Vector2(direction) * 16.0)
					var tween = create_tween()
					tween.tween_property(held_item, "global_position", slide_target, 0.2)
					
					# --- NEW: Clean up ONLY when the animation finishes ---
					tween.tween_callback(func():
						if is_instance_valid(held_item):
							held_item.queue_free()
						held_item = null # Now the belt is actually empty!
						is_delivering = false # Unlock the belt!
					)
					# ------------------------------------------------------
				else:
					# The building is full! 
					push_cooldown = 0.5
	
	# ========================================
	# PHASE 2: Moving to Edge (Only used for Belt-to-Belt)
	# ========================================
	else:
		target_pos = global_position + (Vector2(direction) * 16.0)
		
		if not _can_push_to_neighbor():
			# Belt ahead filled up while we were moving. Sit at edge and wait.
			push_cooldown = 0.5 
			return
			
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		if held_item.global_position.distance_to(target_pos) < 1.0:
			if _push_to_neighbor():
				pass # Success! Item is gone.
			else:
				push_cooldown = 0.5

	
# ============================================================
# NEIGHBOR INTERACTION
# ============================================================

# Query: Can we push to the next belt/building?
# This is called BEFORE we commit to moving the item to the edge
func _can_push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: 
		return false  # No neighbor = dead end
	
	# --- CASE 1: Neighbor is another Conveyor Belt ---
	if neighbor is ConveyorBuilding:
		# Accept if neighbor is empty OR its item is already leaving
		# This creates "pipelined" flow - we can start moving while
		# the neighbor's item is on its way out
		return neighbor.held_item == null or neighbor.is_moving_to_edge
	
	# --- CASE 2: Neighbor is a Building (Stockpile/Factory) ---
	if neighbor.has_method("add_item") and "item_data" in held_item:
		return true # Assume we can push. If it's full, the push will just fail later!
	
	return false

# Action: Actually transfer the item to the neighbor
# This is called when the item reaches the edge
func _push_to_neighbor() -> bool:
	var neighbor = _get_neighbor()
	if not neighbor: 
		return false
	
	# --- CASE 1: Push to another Conveyor Belt ---
	if neighbor is ConveyorBuilding:
		# Pass ourselves as the source so neighbor knows our direction
		if neighbor.accept_item_node(held_item, self):
			# Success! Neighbor took ownership
			held_item = null  # We no longer own it
			return true
	
	# --- CASE 2: Push to a Building (Stockpile/Factory) ---
	elif neighbor.has_method("add_item") and "item_data" in held_item:
		# Try to give it 1 item. If it returns > 0, it successfully took it!
		if neighbor.add_item(held_item.item_data, 1) > 0:
			# Building consumed the item, destroy the visual node on the belt
			held_item.queue_free()
			held_item = null
			return true
	
	# Transfer failed
	return false
# Helper: Get the building/belt in the direction we're facing
func _get_neighbor() -> Node:
	# Safety check
	if not level_ref: 
		return null
	
	# Convert our world position to grid coordinates
	var my_grid = level_ref.object_layer.local_to_map(global_position)
	
	# Calculate the grid position we're facing
	var neighbor_grid = my_grid + direction
	
	# Look up what's at that position in the BuildingManager
	var manager = level_ref.building_manager
	
	if manager.occupied_tiles.has(neighbor_grid):
		return manager.occupied_tiles[neighbor_grid]
	
	# Nothing there (empty space)
	return null

# ==========================================
# SAVE / LOAD SYSTEM (Conveyor)
# ==========================================
func get_save_data() -> Dictionary:
	# 1. Grab the base stats (health, building_name)
	var data = super.get_save_data()
	
	# 2. Save Conveyor properties
	data["direction"] = var_to_str(direction)
	data["is_moving_to_edge"] = is_moving_to_edge
	data["push_cooldown"] = push_cooldown
	data["is_delivering"] = is_delivering
	
	# 3. Save the physical item!
	if held_item and is_instance_valid(held_item) and "item_data" in held_item:
		data["held_item_name"] = held_item.item_data.display_name
		data["held_item_x"] = held_item.global_position.x
		data["held_item_y"] = held_item.global_position.y
		
	return data

func load_save_data(data: Dictionary):
	# 1. Restore the base stats
	super.load_save_data(data)
	
	# 2. Restore Conveyor properties
	if data.has("direction"):
		direction = str_to_var(data["direction"])
		rotation = Vector2(direction).angle() # Snap the sprite to the right rotation!
		
	is_moving_to_edge = data.get("is_moving_to_edge", false)
	push_cooldown = data.get("push_cooldown", 0.0)
	is_delivering = data.get("is_delivering", false)
	
	# 3. Respawn the physical item!
	if data.has("held_item_name"):
		if not generic_item_scene:
			print("ERROR: Conveyor cannot load item! Assign generic_item_scene in Inspector.")
			return
			
		var item_res = ItemDatabase.get_item(data["held_item_name"])
		if item_res:
			# Instantiate the node
			var new_item = generic_item_scene.instantiate()
			if new_item.has_method("setup"): new_item.setup(level_ref)
			if "item_data" in new_item: new_item.item_data = item_res
			
			# Teleport it to the exact pixel it was saved at
			new_item.global_position = Vector2(data["held_item_x"], data["held_item_y"])
			
			if new_item.has_method("_ready"): new_item._ready()
			
			# Add to world and take ownership
			level_ref.add_child(new_item)
			held_item = new_item
