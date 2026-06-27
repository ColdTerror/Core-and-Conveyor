# ==============================================================================
# Script: UI/hot_bar_ui.gd
# Purpose: Controls the build/select hotbar, dynamic button creation, selection emission,
#          and core placement flashing animations.
# Dependencies: Exports for BuildingManager.
# Signals:
#   - item_selected(data_wrapper, is_building): Emitted when a hotbar button is pressed.
# ==============================================================================
extends Control

@onready var container = $PanelContainer/HBoxContainer

signal item_selected(data_wrapper, is_building)

@export var building_manager: BuildingManager

var core_button: Button
var flash_tween: Tween

var main_vbox: VBoxContainer
var info_panel: PanelContainer
var info_label: RichTextLabel

const BUILDING_DESCRIPTIONS: Dictionary = {
	"Core": "The heart of your base. If destroyed, the game is lost.",
	"Belt": "Transports items along a straight line in the direction placed.",
	"Router": "Distributes incoming items evenly to all open orthogonal output directions.",
	"Filter": "Directs a specified item type in one direction, and all other items in another.",
	"Conveyer Bridge": "Allows two crossing conveyor lines to pass items over each other without mixing.",
	"Launcher": "Launches items across open space or walls to a paired Receiver.",
	"Receiver": "Receives items launched by a paired Launcher and outputs them to conveyors.",
	"Hut": "Harvests wood from nearby trees automatically.",
	"Sawmill": "Processes raw Wood into Planks.",
	"Stone Mine": "Mines stone from nearby stone deposits automatically.",
	"Ore Drill": "Extracts iron and other ores from nearby bedrock deposits.",
	"Stonemason": "Refines raw Stone into Stone Bricks.",
	"Fletcher": "Crafts Wooden Arrows and Stone Arrows using Planks, Stone, and Iron.",
	"Stone Crusher": "Crushes Stone into Pebbles for Sling Towers.",
	"Bow Tower": "Basic defense tower that shoots arrows at nearby targets.",
	"Ballista Tower": "Heavy defense tower that fires slow but high-damage bolts.",
	"Scattershot Tower": "Fires a spread of multiple projectiles to deal area damage.",
	"Sling Tower": "Rapidly shoots pebbles at approaching enemies.",
	"Wall": "Defensive barrier that blocks enemy pathfinding and absorbs damage.",
	"Gate": "A barrier that blocks enemies but allows friendly worker bots to pass through.",
	"Ammo Distributor": "Distributes ammo from conveyors to adjacent defense towers.",
	"Stockpile": "A local warehouse that stores items and can output selected items onto belts.",
	"Firepit": "Illuminates the night, repels the corruption, and keeps nearby units safe.",
	"QuotaBuilding": "Tracks milestone delivery quotas for resource processing.",
	"Deconstruct": "Click and drag over structures to dismantle them.",
	"Upgrade": "Activate global upgrade brush mode. Click buildings to level them up.",
	"Terraform": "Click and drag over terrain tiles to assign terraforming construction sites."
}



## Initializes the hotbar panel and connects global placement event signals.
func _ready():
	# Clear placeholder buttons
	for child in container.get_children():
		child.queue_free()
		
	# Listen for Core placement
	if building_manager:
		building_manager.core_placed_event.connect(_on_core_placed)
		
	_setup_dynamic_info_bar()



## Dynamically creates and registers a square selection button with bound action data inside the hotbar.
func add_button(label_text: String, icon_texture: Texture2D, data, is_building: bool):
	var btn = Button.new()
	btn.text = label_text
	btn.icon = icon_texture
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.expand_icon = true
	btn.custom_minimum_size = Vector2(64, 64)
	
	# Connect click event binding data
	btn.pressed.connect(_on_button_pressed.bind(data, is_building))
	
	# Connect hover signals for the description bar
	btn.mouse_entered.connect(_on_button_hovered.bind(label_text, data, is_building))
	btn.mouse_exited.connect(_on_button_unhovered)
	
	container.add_child(btn)
	
	# Check for Core button to flash
	if label_text == "Core": 
		core_button = btn
		_start_core_flash()



## Purges all active selection buttons from the hotbar panel.
func clear_buttons():
	# Hide description if it's currently showing
	_on_button_unhovered()
	for child in container.get_children():
		child.queue_free()



## Emits selection data representing the pressed hotbar entry.
func _on_button_pressed(data, is_building):
	item_selected.emit(data, is_building)



## Triggers a looping pulse animation overlaying the core construction card until placed.
func _start_core_flash():
	if not core_button: return
	
	# Create a looping tween
	flash_tween = create_tween().set_loops()
	
	# Pulse to a highlighted yellow/green color
	var highlight_color = Color(0.5, 0.5, 0.0, 1.0)
	
	flash_tween.tween_property(core_button, "modulate", highlight_color, 0.6).set_trans(Tween.TRANS_SINE)
	flash_tween.tween_property(core_button, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)



## Halts core button flashing animations and restores standard button visuals when the core is constructed.
func _on_core_placed():
	# Halts animation and resets color when placed
	if flash_tween:
		flash_tween.kill()
		flash_tween = null
		
	if core_button:
		core_button.modulate = Color.WHITE



## Finds and deletes a hotbar action button by its matching label text.
func remove_button(button_name: String):
	# Loop through HBoxContainer buttons
	for child in container.get_children():
		if child is Button and child.text == button_name:
			child.queue_free()
			return


func _setup_dynamic_info_bar():
	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(400, 0)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style_box.set_corner_radius_all(8)
	style_box.content_margin_left = 12
	style_box.content_margin_right = 12
	style_box.content_margin_top = 8
	style_box.content_margin_bottom = 8
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = Color(0.3, 0.3, 0.35, 0.6)
	info_panel.add_theme_stylebox_override("panel", style_box)
	
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(376, 0)
	info_panel.add_child(info_label)
	
	add_child(info_panel)
	info_panel.hide()


func _on_button_hovered(label_text: String, data, is_building: bool):
	if not info_panel or not info_label: return
	
	var desc = ""
	var title = label_text
	var cost_text = ""
	
	if label_text == "Back":
		desc = "Return to the previous category menu."
	elif label_text in ["Logistics", "Production", "Defense", "Infrastructure",  "Tools"]:
		title = label_text
		if label_text == "Logistics":
			desc = "Conveyors, splitters, filters, and launchers to transport items around."
		elif label_text == "Production":
			desc = "Harvesters and processors to refine raw materials into products."
		elif label_text == "Defense":
			desc = "Towers, walls, and ammo distribution systems to defend the core."
		elif label_text == "Infrastructure":
			desc = "Storage stockpiles, lighting, and milestone goal objectives."
		elif label_text == "Tools":
			desc = "Dismantle, upgrade, and terraform tools to manage and reshape your factory."
	else:
		desc = BUILDING_DESCRIPTIONS.get(label_text, "A structure for your base.")
		
		# Get building cost
		if is_building and data is PackedScene:
			var temp = data.instantiate()
			if temp and temp.has_method("get_build_cost"):
				var cost_dict = temp.get_build_cost()
				if cost_dict.is_empty():
					cost_text = "Free to build!"
				else:
					var cost_parts = []
					for item_name in cost_dict:
						var amount = cost_dict[item_name]
						var have = EconomyManager.global_inventory.get(item_name, 0)
						var color_str = "#66ff66" if have >= amount else "#ff5555"
						cost_parts.append("[color=%s]%d %s[/color]" % [color_str, amount, item_name])
					cost_text = "Cost: " + ", ".join(cost_parts)
			if temp:
				temp.queue_free()
				
	var final_text = "[font_size=18][b]" + title + "[/b][/font_size]\n"
	if desc != "":
		final_text += desc + "\n"
	if cost_text != "":
		final_text += "[font_size=14]" + cost_text + "[/font_size]"
		
	info_label.text = final_text.strip_edges()
	info_panel.show()
	
	# Force size recalculation
	info_panel.reset_size()
	
	# Position the info bar directly above the original PanelContainer
	var hotbar_panel = get_node_or_null("PanelContainer")
	if hotbar_panel:
		# Centered horizontally with hotbar, and 10px above it
		info_panel.global_position.x = hotbar_panel.global_position.x + (hotbar_panel.size.x - info_panel.size.x) / 2
		info_panel.global_position.y = hotbar_panel.global_position.y - info_panel.size.y - 10


func _on_button_unhovered():
	if info_panel:
		info_panel.hide()
