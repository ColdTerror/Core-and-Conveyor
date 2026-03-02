extends Building
class_name CoreBuilding

signal core_destroyed


func _ready():
	super()
	
	# Add to a group so enemies and managers can easily find it
	add_to_group("Core")
	add_to_group("PriorityTarget")
	
	# --- NEW: Connect myself to the Game Over Screen! ---
	var ui = get_tree().get_first_node_in_group("GameUI")
	if ui and ui.has_method("_on_core_destroyed"):
		core_destroyed.connect(ui._on_core_destroyed)
	
# --- GAME OVER LOGIC ---
func take_damage(amount: int):
	super(amount)
	
	# Optional: Flash red or play an alarm sound here!
	
	if health <= 0:
		_trigger_game_over()

func _trigger_game_over():
	print("CORE DESTROYED! GAME OVER!")
	core_destroyed.emit()
	
	# You can emit a global signal here, or call a GameManager.
	# For now, we will pause the tree to stop the action.
	get_tree().paused = true
	
	# TODO: Show Game Over UI Screen
