extends Building
class_name CoreBuilding


# Visuals
var show_radii := false:
	set(value):
		show_radii = value
		queue_redraw()

func _ready():
	super()
	
	# Add to a group so enemies and managers can easily find it
	add_to_group("Core")
	#add_to_group("PriorityTarget")

# --- DRAWING THE RANGES (Debug / Placement) ---
func _draw():
	if not show_radii: return
	
	var tile_size = 32.0 # Assuming TILE_SIZE is 32
	var center_pos = Vector2.ZERO # Local center
	
	# Draw Build Radius (Green)
	draw_arc(center_pos, build_range * tile_size, 0, TAU, 64, Color(0.2, 1.0, 0.2, 0.5), 2.0)
	
	# Draw Safe Zone / Corruption Resistance (Blue)
	draw_arc(center_pos, corruption_range * tile_size, 0, TAU, 64, Color(0.2, 0.5, 1.0, 0.3), 2.0)

# --- VISIBILITY OVERRIDES ---
func set_ghost(enabled: bool):
	super.set_ghost(enabled)
	show_radii = enabled

func _on_mouse_entered():
	super._on_mouse_entered()
	show_radii = true

func _on_mouse_exited():
	super._on_mouse_exited()
	show_radii = false

# --- GAME OVER LOGIC ---
func take_damage(amount: int):
	# Override the base take_damage to add Game Over logic
	health -= amount
	
	# Optional: Flash red or play an alarm sound here!
	
	if health <= 0:
		_trigger_game_over()

func _trigger_game_over():
	print("CORE DESTROYED! GAME OVER!")
	
	# You can emit a global signal here, or call a GameManager.
	# For now, we will pause the tree to stop the action.
	get_tree().paused = true
	
	# TODO: Show Game Over UI Screen
