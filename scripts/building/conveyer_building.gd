extends Building
class_name ConveyorBuilding

# ============================================================
# EXPORTS & VARIABLES
# ============================================================

@export var speed: float = 64.0  # Pixels per second the item travels

var direction: Vector2i = Vector2i.RIGHT  # Grid direction (UP, DOWN, LEFT, RIGHT)
var held_item: Node2D = null  # The item currently on this belt (null = empty)
var level_ref: Node2D  # Reference to the level/world node

# State tracking for two-phase movement system
var is_moving_to_edge: bool = false  # false = moving to center, true = moving to edge

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
	# Clean up orphaned items to prevent memory leaks
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
		var prev_direction = source_belt.direction
		# Check if directions are perpendicular (dot product = 0)
		# e.g., RIGHT (1,0) dot UP (0,1) = 0
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
	
	
	# Early exit: Nothing to move if belt is empty
	if held_item == null: 
		return
	
	# Safety check: Item might have been freed/deleted elsewhere
	if not is_instance_valid(held_item):
		held_item = null
		return
	
	var target_pos = Vector2.ZERO
	
	# ========================================
	# PHASE 1: Moving to Center
	# ========================================
	if not is_moving_to_edge:
		# Target is the belt's center point
		target_pos = global_position
		
		# Move item toward center
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		# Check if we've reached the center
		var distance_to_center = held_item.global_position.distance_to(target_pos)
		if distance_to_center < 1.0:
			# We're at center - settle here and wait
			held_item.global_position = target_pos  # Snap to exact center to stop micro-movements
			
			if  _can_push_to_neighbor():
				# Path is clear! Switch to Phase 2
				is_moving_to_edge = true
			# Otherwise: Stay at center, don't move
	
	# ========================================
	# PHASE 2: Moving to Edge (Handoff)
	# ========================================
	else:
		# Target is 16 pixels in front of center (the handoff point)
		target_pos = global_position + (Vector2(direction) * 16.0)
		
		# Move item toward edge
		var move_step = speed * delta
		held_item.global_position = held_item.global_position.move_toward(target_pos, move_step)
		
		# Have we reached the edge?
		if held_item.global_position.distance_to(target_pos) < 1.0:
			# Try to actually transfer the item
			if _push_to_neighbor():
				# Success! Item is gone, we're done
				pass
			else:
				# Failed! Neighbor filled up while we were moving
				# Go back to Phase 1 (wait at center) and start cooldown
				is_moving_to_edge = false
				
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
	if neighbor.has_method("can_accept_item") and "item_data" in held_item:
		# Ask the building if it can accept this specific item type
		return neighbor.can_accept_item(held_item.item_data)
	
	# Unknown neighbor type or missing methods
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
	elif neighbor.has_method("accept_item") and "item_data" in held_item:
		if neighbor.accept_item(held_item.item_data):
			# Building consumed the item (added to inventory)
			# We need to destroy the visual node
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
