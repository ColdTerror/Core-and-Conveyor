extends GraphNode

@export var research_name: String = "Bot Speed 1"
@export var desc: String = "Increase bot move speed"
# Example: {"Wood": 50, "Stone": 20}
@export var research_cost: Dictionary = {} 

@onready var desc_label = $DescLabel
@onready var cost_label = $CostLabel
@onready var research_button = $Button 

func _ready():
	# Set the GraphNode title
	title = research_name
	
	desc_label.text = desc
	# Build cost display text
	cost_label.text = _format_costs(research_cost)
	
	research_button.pressed.connect(_on_research_pressed)

func _format_costs(costs: Dictionary) -> String:
	var parts: Array[String] = []
	
	for resource in costs.keys():
		parts.append("%s: %s" % [resource.display_name, costs[resource]])
	
	return ", ".join(parts)

func _on_research_pressed():
	var core = get_tree().get_first_node_in_group("Core")
	if core and core.has_method("start_research"):
		core.start_research(research_name, research_cost)
		print("Sent bill to core for: ", research_name)
