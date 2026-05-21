# ==============================================================================
# Script: upgrade_node.gd
# Purpose: Controls individual node cards inside the research GraphEdit tree, 
#          displaying description, cost formats, and processing unlock states.
# Dependencies: ResearchManager Autoload. Expects $DescLabel, $CostLabel, and $Button child nodes.
# Signals:
#   - research_started: Emitted when the user starts researching this specific node.
# ==============================================================================
@tool
extends GraphNode

signal research_started

# EXPORTS (With Editor Setters)
@export var research_name: String = "Bot Speed 1":
	set(value):
		research_name = value
		_refresh_editor_ui()

@export_multiline var desc: String = "Increase bot move speed":
	set(value):
		desc = value
		_refresh_editor_ui()

@export var research_cost: Dictionary = {}:
	set(value):
		research_cost = value
		_refresh_editor_ui()

# NODE REFERENCES
@onready var desc_label = $DescLabel
@onready var cost_label = $CostLabel
@onready var research_button = $Button

# INITIALIZATION
func _ready():
	# 1. Update the text immediately
	_refresh_editor_ui()
	
	# 2. EDITOR SAFETY CHECK: Stop here if we are inside the Godot Editor!
	if Engine.is_editor_hint():
		return
		
	# 3. GAME RUNTIME ONLY: Connect signals
	research_button.pressed.connect(_on_research_pressed)
	
	# Refresh button state whenever research changes
	ResearchManager.research_unlocked.connect(_refresh_button)
	_refresh_button()

# UI UPDATING
func _refresh_editor_ui():
	# CRITICAL: Prevent crashes if the setter fires before the node enters the scene tree
	if not is_node_ready():
		return
		
	title = research_name
	desc_label.text = desc
	cost_label.text = _format_costs(research_cost)

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

# ACTIONS
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
		# Safety check so the editor doesn't crash if an empty key is added
		if resource and "display_name" in resource:
			parts.append("%s: %s" % [resource.display_name, costs[resource]])
		elif resource is String:
			parts.append("%s: %s" % [resource, costs[resource]])
		else:
			parts.append("Unknown: %s" % costs[resource])
			
	return ", ".join(parts)
