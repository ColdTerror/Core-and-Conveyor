extends Building
class_name CoreBuilding




func _ready():
	super()
	
	# Add to a group so enemies and managers can easily find it
	add_to_group("Core")
	#add_to_group("PriorityTarget")






# --- GAME OVER LOGIC ---
func take_damage(amount: int):
	super(amount)
	
	# Optional: Flash red or play an alarm sound here!
	
	if health <= 0:
		_trigger_game_over()

func _trigger_game_over():
	print("CORE DESTROYED! GAME OVER!")
	
	# You can emit a global signal here, or call a GameManager.
	# For now, we will pause the tree to stop the action.
	get_tree().paused = true
	
	# TODO: Show Game Over UI Screen
