extends PanelContainer
#stat menu

# ==========================================================
# EXPORTS (Assign this in the Inspector!)
# ==========================================================
@export var time_manager: TimeManager

@onready var title_label = $MainVBox/TitleLabel
@onready var prod_list = $MainVBox/Columns/ProdColumn/ProdList
@onready var cons_list = $MainVBox/Columns/ConsColumn/ConsList
@onready var close_button = $MainVBox/CloseButton

func _ready():
	hide() # Start hidden
	
	close_button.pressed.connect(toggle_menu)
	
	# Listen to the Economy Manager's broadcasts!
	if EconomyManager.has_signal("stats_updated"):
		EconomyManager.stats_updated.connect(refresh_ui)

func toggle_menu():
	if visible:
		hide()
	else:
		refresh_ui()
		show()

func refresh_ui():
	# ==========================================================
	# THE FIX: Use the exported variable safely!
	# ==========================================================
	var display_day = 1
	if is_instance_valid(time_manager):
		display_day = time_manager.current_day
	else:
		print_debug("WARNING: TimeManager not assigned in StatisticsMenu Inspector!")
	
	# 1. Update the Title
	title_label.text = "=== Day %d Ledger ===" % display_day
	# ==========================================================
	
	# 2. Clear out the old dynamic rows
	for child in prod_list.get_children():
		child.queue_free()
	for child in cons_list.get_children():
		child.queue_free()
		
	# 3. Build Production Rows
	var prod_data = EconomyManager.daily_production
	if prod_data.is_empty():
		_create_stat_row(prod_list, "Nothing produced yet.", "", Color(0.5, 0.5, 0.5))
	else:
		for item_name in prod_data:
			var amount = prod_data[item_name]
			_create_stat_row(prod_list, item_name, "+%d" % amount, Color(0.4, 1.0, 0.4))
			
	# 4. Build Consumption Rows
	var cons_data = EconomyManager.daily_consumption
	if cons_data.is_empty():
		_create_stat_row(cons_list, "Nothing consumed yet.", "", Color(0.5, 0.5, 0.5))
	else:
		for item_name in cons_data:
			var amount = cons_data[item_name]
			_create_stat_row(cons_list, item_name, "-%d" % amount, Color(1.0, 0.4, 0.4))


func _create_stat_row(parent_container: Control, text_left: String, text_right: String, val_color: Color):
	var hbox = HBoxContainer.new()
	
	var name_label = Label.new()
	name_label.text = text_left
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
	
	var val_label = Label.new()
	val_label.text = text_right
	val_label.modulate = val_color
	
	hbox.add_child(name_label)
	hbox.add_child(val_label)
	
	parent_container.add_child(hbox)
