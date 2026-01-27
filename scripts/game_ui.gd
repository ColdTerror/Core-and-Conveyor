extends Control

@onready var wood_label = $PanelContainer/HBoxContainer/WoodLabel
@onready var stone_label = $PanelContainer/HBoxContainer/StoneLabel

func _ready():
	# 1. Update immediately to show starting resources
	update_labels()
	
	# 2. Connect to the global signal
	# whenever resources change, run our update function
	EconomyManager.resources_changed.connect(_on_resources_changed)

func _on_resources_changed():
	update_labels()

func update_labels():
	wood_label.text = " Wood: %d" % EconomyManager.wood
	stone_label.text = "Stone: %d " % EconomyManager.stone
