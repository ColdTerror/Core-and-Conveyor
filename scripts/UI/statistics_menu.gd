# ==============================================================================
# Script: UI/statistics_menu.gd
# Purpose: Orchestrates the Statistics Ledger Menu overlay, presenting a production and consumption ledger for today, yesterday, or weekly stats, integrating live archival history from EconomyManager.
# Dependencies: Requires TimeManager (via export), and Autoloads GameState and EconomyManager. Child controls for lists, tabs, titles, and close buttons.
# Signals: None.
# ==============================================================================
extends Control

@export var time_manager: TimeManager

@onready var title_label = $PanelContainer/MainVBox/TitleLabel
@onready var btn_today = $PanelContainer/MainVBox/TabRow/BtnToday
@onready var btn_yesterday = $PanelContainer/MainVBox/TabRow/BtnYesterday
@onready var btn_week = $PanelContainer/MainVBox/TabRow/BtnWeek
@onready var prod_list = $PanelContainer/MainVBox/Columns/ProdColumn/ProdList
@onready var cons_list = $PanelContainer/MainVBox/Columns/ConsColumn/ConsList
@onready var close_button = $PanelContainer/MainVBox/CloseButton

enum ViewMode { TODAY, YESTERDAY, WEEK }
var current_mode: ViewMode = ViewMode.TODAY

func _ready():
	GameState.menu_changed.connect(_on_global_menu_changed)
	hide() 
	
	# --- UPDATE: Point to close_screen ---
	close_button.pressed.connect(close_screen)
	
	btn_today.pressed.connect(func(): _set_mode(ViewMode.TODAY))
	btn_yesterday.pressed.connect(func(): _set_mode(ViewMode.YESTERDAY))
	btn_week.pressed.connect(func(): _set_mode(ViewMode.WEEK))
	
	if EconomyManager.has_signal("stats_updated"):
		EconomyManager.stats_updated.connect(refresh_ui)

# UI STATE MACHINE ROUTING
func toggle_menu():
	if visible: 
		close_screen()
	else:
		open_screen()

func open_screen():
	# Ask GameState for permission. If it returns true, no other menus are blocking us!
	if GameState.open_menu(GameState.MenuType.STATS):
		refresh_ui()
		show()

func close_screen():
	# Tell GameState to clear out
	GameState.close_menu()

func _on_global_menu_changed(active_menu):
	# If the active menu is NO LONGER the Stats menu, hide ourselves!
	if active_menu != GameState.MenuType.STATS:
		hide()

# DATA & REFRESH LOGIC
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

	var combined = _get_stats_for_range(start_day, end_day)
	var prod_data = combined.prod
	var cons_data = combined.cons

	if prod_data.is_empty():
		_create_stat_row(prod_list, "Nothing produced.", "", Color(0.5, 0.5, 0.5))
	else:
		var prod_keys = prod_data.keys()
		prod_keys.sort_custom(func(a, b): return prod_data[a] > prod_data[b])
		for item_name in prod_keys:
			_create_stat_row(prod_list, item_name, "+%d" % prod_data[item_name], Color(0.4, 1.0, 0.4))
			
	if cons_data.is_empty():
		_create_stat_row(cons_list, "Nothing consumed.", "", Color(0.5, 0.5, 0.5))
	else:
		var cons_keys = cons_data.keys()
		cons_keys.sort_custom(func(a, b): return cons_data[a] > cons_data[b])
		for item_name in cons_keys:
			_create_stat_row(cons_list, item_name, "-%d" % cons_data[item_name], Color(1.0, 0.4, 0.4))

func _get_stats_for_range(start_day: int, end_day: int) -> Dictionary:
	var total_prod = {}
	var total_cons = {}
	
	var display_day = time_manager.current_day if is_instance_valid(time_manager) else 1
	if display_day >= start_day and display_day <= end_day:
		_add_to_dict(total_prod, EconomyManager.daily_production)
		_add_to_dict(total_cons, EconomyManager.daily_consumption)

	for entry in EconomyManager.history_archive:
		if entry.day >= start_day and entry.day <= end_day:
			_add_to_dict(total_prod, entry.produced)
			_add_to_dict(total_cons, entry.consumed)
			
	return {"prod": total_prod, "cons": total_cons}

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
