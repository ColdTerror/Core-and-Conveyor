extends Control
# game_ui.gd

@onready var container = $PanelContainer/HBoxContainer

# A dictionary to keep track of the labels we create
# Key: String (e.g. "Wood"), Value: Label Node
var resource_labels: Dictionary = {}

func _ready():
	update_labels()
	EconomyManager.resources_changed.connect(_on_resources_changed)

func _on_resources_changed():
	update_labels()

func update_labels():
	# Loop through every item currently known to the economy
	for resource_name in EconomyManager.global_inventory:
		var amount = EconomyManager.global_inventory[resource_name]
		
		# Optional: Skip drawing the label if we have 0 of that item
		# (Remove this if statement if you want it to show "Arrows: 0")
		#if amount <= 0 and not resource_labels.has(resource_name):
		#	continue 
		
		# If we don't have a label for this item yet, create one!
		if not resource_labels.has(resource_name):
			var new_label = Label.new()
			# You can add custom fonts/themes to new_label here if you want
			container.add_child(new_label)
			resource_labels[resource_name] = new_label
			
		# Update the text of the existing label
		resource_labels[resource_name].text = "  %s: %d  " % [resource_name, amount]
