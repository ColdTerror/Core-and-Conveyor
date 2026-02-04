extends Node2D

@onready var level = get_parent() # Assuming Level is the parent

func _draw():
	# Call a public function in Level to handle the logic, 
	# but passing 'self' so we draw on THIS canvas item
	level.draw_drag_line(self)
