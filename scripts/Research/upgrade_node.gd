extends GraphNode

signal research_started

@export var research_name: String = "Bot Speed 1"
@export var desc: String = "Increase bot move speed"
@export var research_cost: Dictionary = {}

@onready var desc_label = $DescLabel
@onready var cost_label = $CostLabel
@onready var research_button = $Button

func _ready():
	title = research_name
	desc_label.text = desc
	cost_label.text = _format_costs(research_cost)
	research_button.pressed.connect(_on_research_pressed)
	
	# Refresh button state whenever research changes
	ResearchManager.research_unlocked.connect(_refresh_button)
	_refresh_button()

func _refresh_button():
	var already_done = research_name in ResearchManager.unlocked_techs
	var tier_met = ResearchManager.can_research(research_name)
	
	if already_done:
		research_button.text = "Researched"
		research_button.disabled = true
	elif not tier_met:
		research_button.text = "Locked"
		research_button.disabled = true
	else:
		research_button.text = "Research"
		research_button.disabled = false

func _on_research_pressed():
	if not ResearchManager.can_research(research_name):
		print("Tier not unlocked yet!")
		return
		
	var core = get_tree().get_first_node_in_group("Core")
	if core and core.has_method("start_research"):
		core.start_research(research_name, research_cost)
		research_started.emit()

func _format_costs(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in costs.keys():
		parts.append("%s: %s" % [resource.display_name, costs[resource]])
	return ", ".join(parts)
