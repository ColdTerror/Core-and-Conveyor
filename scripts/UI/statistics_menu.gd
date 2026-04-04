extends PanelContainer
#stat menu

@export var time_manager: TimeManager

@onready var title_label = $MainVBox/TitleLabel
@onready var btn_today = $MainVBox/TabRow/BtnToday
@onready var btn_yesterday = $MainVBox/TabRow/BtnYesterday
@onready var btn_week = $MainVBox/TabRow/BtnWeek
@onready var prod_list = $MainVBox/Columns/ProdColumn/ProdList
@onready var cons_list = $MainVBox/Columns/ConsColumn/ConsList
@onready var close_button = $MainVBox/CloseButton

enum ViewMode { TODAY, YESTERDAY, WEEK }
var current_mode: ViewMode = ViewMode.TODAY

func _ready():
	hide() 
	close_button.pressed.connect(toggle_menu)
	
	btn_today.pressed.connect(func(): _set_mode(ViewMode.TODAY))
	btn_yesterday.pressed.connect(func(): _set_mode(ViewMode.YESTERDAY))
	btn_week.pressed.connect(func(): _set_mode(ViewMode.WEEK))
	
	if EconomyManager.has_signal("stats_updated"):
		EconomyManager.stats_updated.connect(refresh_ui)

func toggle_menu():
	if visible: hide()
	else:
		refresh_ui()
		show()

func _set_mode(new_mode: ViewMode):
	current_mode = new_mode
	refresh_ui()

func refresh_ui():
	for child in prod_list.get_children(): child.queue_free()
	for child in cons_list.get_children(): child.queue_free()
		
	var display_day = 1
	if is_instance_valid(time_manager):
		display_day = time_manager.current_day

	btn_today.modulate = Color(0.4, 1.0, 0.4) if current_mode == ViewMode.TODAY else Color.WHITE
	btn_yesterday.modulate = Color(0.4, 1.0, 0.4) if current_mode == ViewMode.YESTERDAY else Color.WHITE
	btn_week.modulate = Color(0.4, 1.0, 0.4) if current_mode == ViewMode.WEEK else Color.WHITE

	# ==========================================
	# THE FIX: Calculate the mathematical range
	# ==========================================
	var start_day = 1
	var end_day = display_day

	match current_mode:
		ViewMode.TODAY:
			title_label.text = "=== Day %d Ledger ===" % display_day
			start_day = display_day
			end_day = display_day
		ViewMode.YESTERDAY:
			title_label.text = "=== Day %d Ledger ===" % (display_day - 1)
			start_day = display_day - 1
			end_day = display_day - 1
		ViewMode.WEEK:
			title_label.text = "=== Last 7 Days ==="
			start_day = display_day - 6
			end_day = display_day

	# Call our single, universal function!
	var combined = _get_stats_for_range(start_day, end_day)
	var prod_data = combined.prod
	var cons_data = combined.cons

	# Build Rows
	if prod_data.is_empty():
		_create_stat_row(prod_list, "Nothing produced.", "", Color(0.5, 0.5, 0.5))
	else:
		for item_name in prod_data:
			_create_stat_row(prod_list, item_name, "+%d" % prod_data[item_name], Color(0.4, 1.0, 0.4))
			
	if cons_data.is_empty():
		_create_stat_row(cons_list, "Nothing consumed.", "", Color(0.5, 0.5, 0.5))
	else:
		for item_name in cons_data:
			_create_stat_row(cons_list, item_name, "-%d" % cons_data[item_name], Color(1.0, 0.4, 0.4))

# ==========================================================
# THE UNIVERSAL AGGREGATOR
# ==========================================================
func _get_stats_for_range(start_day: int, end_day: int) -> Dictionary:
	var total_prod = {}
	var total_cons = {}
	
	# 1. Grab data from the active, unfinished day (if it falls in our range)
	var display_day = time_manager.current_day if is_instance_valid(time_manager) else 1
	if display_day >= start_day and display_day <= end_day:
		_add_to_dict(total_prod, EconomyManager.daily_production)
		_add_to_dict(total_cons, EconomyManager.daily_consumption)

	# 2. Grab data from the history archive
	for entry in EconomyManager.history_archive:
		if entry.day >= start_day and entry.day <= end_day:
			_add_to_dict(total_prod, entry.produced)
			_add_to_dict(total_cons, entry.consumed)
			
	return {"prod": total_prod, "cons": total_cons}

# Quick helper to merge dictionaries and add their numbers together
func _add_to_dict(target: Dictionary, source: Dictionary):
	for item in source:
		target[item] = target.get(item, 0) + source[item]

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

func _unhandled_input(event):
	# If the user presses Escape, AND this specific menu is currently open on screen...
	if event.is_action_pressed("ui_cancel") and visible:
		
		# 1. Close the menu! 
		# (Change 'hide()' to 'close_menu()' if your script has a custom cleanup function)
		hide() 
		
		# 2. Consume the input so it doesn't leak into the game world
		get_viewport().set_input_as_handled()
		
