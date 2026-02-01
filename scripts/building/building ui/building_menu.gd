# BuildingMenu.gd
extends PanelContainer

@onready var title_label = $VBoxContainer/TitleLabel
@onready var recipe_label = $VBoxContainer/RecipeLabel
@onready var switch_button = $VBoxContainer/SwitchButton

var current_building: Building = null

func _ready():
	hide()
	# Connect buttons dynamically or via editor
	switch_button.pressed.connect(_on_switch_pressed)
	$VBoxContainer/CloseButton.pressed.connect(close_menu)

func open_menu(building: Building):
	current_building = building
	
	# 1. Update Title
	title_label.text = building.building_name
	
	# 2. Check if it handles Recipes
	if building is ProcessorBuilding:
		refresh_recipe_ui()
	else:
		# Hide recipe controls for generic buildings (Stockpiles, Huts)
		recipe_label.visible = false
		switch_button.visible = false
	
	show()
	# Optional: Pause game? get_tree().paused = true

func refresh_recipe_ui():
	var b = current_building as ProcessorBuilding
	
	if b.recipes.size() > 0:
		recipe_label.text = "Recipe: %s" % b.active_recipe.recipe_name
		recipe_label.visible = true
		
		# Only show Switch button if there are multiple options
		switch_button.visible = (b.recipes.size() > 1)
	else:
		recipe_label.text = "No Recipes Configured"
		switch_button.visible = false

func _on_switch_pressed():
	if current_building is ProcessorBuilding:
		# Call the cycle function we made earlier
		current_building.cycle_recipe()
		# Update the UI text immediately
		refresh_recipe_ui()

func close_menu():
	current_building = null
	hide()
