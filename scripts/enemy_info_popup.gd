# EnemyInfoPopup.gd
extends PanelContainer

@onready var name_label = $VBoxContainer/NameLabel
@onready var hp_label = $VBoxContainer/HPLabel
@onready var hp_bar = $VBoxContainer/ProgressBar

var current_enemy: Enemy = null


func _ready():
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE # Important! Don't block clicks.

func _process(_delta):
	# FOLLOW LOGIC
	if visible and is_instance_valid(current_enemy):
		
		hp_label.text = "%d / %d" % [current_enemy.health, current_enemy.max_health] 
		hp_bar.value = current_enemy.health

	elif visible:
		# Enemy died while we were looking at it
		hide()

func show_info(enemy: Enemy):
	current_enemy = enemy
	name_label.text = "Enemy" # Or enemy.unit_name
	hp_bar.max_value = current_enemy.max_health # Or enemy.max_health
	show()

func hide_info():
	current_enemy = null
	hide()
