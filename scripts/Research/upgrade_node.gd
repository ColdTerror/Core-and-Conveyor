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
		if research_cost == value:
			return
		research_cost = value
		_refresh_editor_ui()

@onready var desc_label = $DescLabel
@onready var cost_label = $CostLabel
@onready var research_button = $Button

var _is_syncing: bool = false


## Initializes the node, setting UI text and connecting runtime signals.
func _ready():
	_sync_costs_from_database()
	_refresh_editor_ui()
	
	# EDITOR SAFETY CHECK: Stop here if we are inside the Godot Editor!
	if Engine.is_editor_hint():
		return
		
	research_button.pressed.connect(_on_research_pressed)
	
	ResearchManager.research_unlocked.connect(_refresh_button)
	_refresh_button()


## Pulls centralized research costs from ResearchManager if available.
func _sync_costs_from_database():
	if _is_syncing:
		return
	if Engine.is_editor_hint():
		return
	_is_syncing = true
	if ResearchManager and ResearchManager.has_method("get_research_cost_resources"):
		var db_cost = ResearchManager.get_research_cost_resources(research_name)
		if not db_cost.is_empty():
			research_cost = db_cost
	_is_syncing = false


## Updates the title, description, and cost labels inside the editor and runtime UI.
func _refresh_editor_ui():
	# CRITICAL: Prevent crashes if the setter fires before the node enters the scene tree
	if not is_node_ready():
		return
		
	title = research_name
	if desc_label:
		desc_label.text = desc
	if cost_label:
		cost_label.text = _format_costs(research_cost)


## Syncs the research button text and state (Researched, Locked, or Research) with current status.
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



## Triggered on button press; initiates research if valid and emits the research_started signal.
func _on_research_pressed():
	if not ResearchManager.can_research(research_name):
		print("Tier not unlocked yet!")
		return
		
	_sync_costs_from_database()
	var core = get_tree().get_first_node_in_group("Core")
	if core and core.has_method("start_research"):
		core.start_research(research_name, research_cost)
		research_started.emit()



## Formats the research resource costs dictionary into a comma-separated display string.
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
