# ==============================================================================
# Script: UI/management_menu.gd
# Purpose: Orchestrates the fullscreen multi-tab Management Menu, which allows players to arrange group/building priority queues, view worker bot task status and leash camera followings, pin resource ledgers to the screen, control tracks on the Jukebox audio player, and verify quota target progress calendars.
# Dependencies: Requires BuildingManager (via export), and Autoloads GameState, AudioManager, EconomyManager. Child UI components for tabs, scroll boxes, list containers, and toggle switches.
# Signals: None.
# ==============================================================================
extends Control

@export var building_manager: BuildingManager

# --- UI REFERENCES ---
@onready var tab_container = $PanelContainer/TabContainer

# Priorities Tab
@onready var priority_list_container = $PanelContainer/TabContainer/Priorities/VBoxContainer/ScrollContainer/ListContainer

# Workers Tab
@onready var bot_list_container = $PanelContainer/TabContainer/Workers/VBoxContainer/ScrollContainer/ListContainer

# Resources Tab
@onready var resource_list_container = $PanelContainer/TabContainer/Resources/VBoxContainer/ScrollContainer/ListContainer

# --- Music Tab ---
@onready var music_now_playing_label = $PanelContainer/TabContainer/Jukebox/VBoxContainer/NowPlaying
@onready var music_jukebox_toggle = $PanelContainer/TabContainer/Jukebox/VBoxContainer/EnableJukebox
@onready var music_list_container = $PanelContainer/TabContainer/Jukebox/VBoxContainer/ScrollContainer/TrackListContainer

# --- Quota Tab ---
@onready var quota_info_label = $PanelContainer/TabContainer/Quota/VBoxContainer/InfoLabel
@onready var quota_list_container = $PanelContainer/TabContainer/Quota/VBoxContainer/ScrollContainer/ListContainer

# Floating Close Button
@onready var close_button = $PanelContainer/Close

# --- LIVE UPDATE TRACKING ---
var update_timer: float = 0.0
var update_interval: float = 0.5 
var bot_status_labels: Dictionary = {}

func _ready():
	# Listen to the global UI state machine
	GameState.menu_changed.connect(_on_global_menu_changed)
	
	# --- NEW: Listen to the global Audio Manager ---
	AudioManager.track_changed.connect(_on_audio_manager_track_changed)
	
	hide()
		
	if close_button:
		close_button.pressed.connect(close_menu)
		
	if tab_container:
		tab_container.focus_mode = Control.FOCUS_NONE
		
		var tab_bar = tab_container.get_tab_bar()
		tab_bar.focus_mode = Control.FOCUS_NONE
		tab_bar.tab_clicked.connect(_on_tab_clicked)
		
	# --- NEW: Wire up the Jukebox Toggle ---
	if music_jukebox_toggle:
		music_jukebox_toggle.toggled.connect(_on_jukebox_toggled)

func _process(delta):
	# Only refresh the live data if the menu is actually open
	if not visible:
		return
		
	update_timer -= delta
	
	if update_timer <= 0.0:
		update_timer = update_interval 
		
		# ONLY run the soft update if they are looking at the Workers tab!
		if tab_container and tab_container.current_tab == 1:
			_refresh_bot_tab(false) # Soft update = false
		elif tab_container and tab_container.current_tab == 4: 
			_refresh_quota_tab()

func _on_tab_clicked(tab_index):
	var target_tab = tab_index
	
	if target_tab == 0:
		_refresh_priority_tab()
	elif target_tab == 1:
		_refresh_bot_tab(true) # Force rebuild = true
	elif target_tab == 2:
		_refresh_resource_tab()
	elif target_tab == 3:
		_refresh_music_tab()
	elif target_tab == 4: 
		_refresh_quota_tab()
		
	# Force the tab to stay on the index the user clicked
	tab_container.call_deferred("set_current_tab", target_tab)

# UI STATE MACHINE ROUTING
func toggle_menu():
	if visible:
		close_menu()
	else:
		open_menu()

func open_menu():
	# Ask GameState for permission!
	if GameState.open_menu(GameState.MenuType.MANAGEMENT):
		_refresh_priority_tab()
		_refresh_bot_tab(true) # Force rebuild when opening
		_refresh_resource_tab()
		_refresh_music_tab() 
		_refresh_quota_tab()
		show()

func close_menu():
	# Tell GameState to clear out
	GameState.close_menu()

func _on_global_menu_changed(active_menu):
	# If the active menu is NO LONGER the Management menu, hide ourselves!
	if active_menu != GameState.MenuType.MANAGEMENT:
		hide()

# PRIORITIES TAB LOGIC

func _refresh_priority_tab():
	if not priority_list_container: return
	
	# Clean up old rows
	for child in priority_list_container.get_children():
		child.queue_free()
		
	if not building_manager: 
		print("PriorityMenu: Building Manager not assigned!")
		return
		
	# Grab the queue
	var queue = building_manager.master_priority_queue
	var max_rank = queue.size()
	
	# Build a row for every item
	for i in range(max_rank):
		var item = queue[i]
		var rank = i + 1
		_create_priority_row(item, rank, max_rank)

func _create_priority_row(item: Variant, rank: int, max_rank: int):
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# --- UP ARROW ---
	var up_btn = Button.new()
	up_btn.text = " ▲ "
	up_btn.disabled = (rank == 1)
	up_btn.pressed.connect(func():
		building_manager.move_priority_up(item)
		_refresh_priority_tab()
	)
	
	# --- DEDICATED RANK LABEL ---
	var rank_label = Label.new()
	rank_label.text = str(rank) + "."
	rank_label.custom_minimum_size = Vector2(30, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# --- NAME BUTTON ---
	var name_btn = Button.new()
	name_btn.custom_minimum_size = Vector2(200, 0)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_btn.flat = true 
	
	if typeof(item) == TYPE_STRING:
		name_btn.text = "[Group] %s" % item
		name_btn.modulate = Color(0.8, 0.8, 1.0) 
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		if is_instance_valid(item) and "building_name" in item:
			name_btn.text = item.building_name
			name_btn.pressed.connect(func():
				var cam = get_tree().get_first_node_in_group("Camera")
				if cam and cam.has_method("set_follow_target"):
					cam.set_follow_target(item)
			)
		else:
			name_btn.text = "[Invalid]"
			name_btn.disabled = true
			
	# --- DOWN ARROW ---
	var down_btn = Button.new()
	down_btn.text = " ▼ "
	down_btn.disabled = (rank == max_rank)
	down_btn.pressed.connect(func():
		building_manager.move_priority_down(item)
		_refresh_priority_tab()
	)
	
	# Assemble the row
	hbox.add_child(up_btn)
	hbox.add_child(rank_label)
	hbox.add_child(name_btn)  
	hbox.add_child(down_btn)
	
	priority_list_container.add_child(hbox)

# WORKERS TAB LOGIC

func _refresh_bot_tab(force_rebuild: bool = false):
	if not bot_list_container: return
	
	var bots = get_tree().get_nodes_in_group("Bots")
	
	# Hard Rebuild if forced (tab clicked/menu opened) OR if a bot was born/died
	if force_rebuild or bots.size() != bot_status_labels.size():
		_rebuild_bot_list(bots)
	else:
		# Soft Update! Change the text without deleting the buttons
		for bot in bots:
			if bot_status_labels.has(bot) and is_instance_valid(bot_status_labels[bot]):
				if bot.has_method("get_inventory_info"):
					var info = bot.get_inventory_info()
					var new_text = "Task: %s | Carrying: %s" % [info.get("Target", "Idle"), info.get("Carrying", "Nothing")]
					bot_status_labels[bot].text = new_text

func _rebuild_bot_list(bots: Array):
	# Clean up old UI rows and reset tracking
	bot_status_labels.clear()
	for child in bot_list_container.get_children():
		child.queue_free()
		
	if bots.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No active worker bots."
		bot_list_container.add_child(empty_label)
		return

	var bot_index = 1
	for bot in bots:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# --- NAME ---
		var name_label = Label.new()
		name_label.text = "Bot #" + str(bot_index)
		name_label.custom_minimum_size = Vector2(80, 0)
		
		# --- STATUS ---
		var status_label = Label.new()
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bot.has_method("get_inventory_info"):
			var info = bot.get_inventory_info()
			status_label.text = "Task: %s | Carrying: %s" % [info.get("Target", "Idle"), info.get("Carrying", "Nothing")]
		else:
			status_label.text = "Task: Unknown"
			
		# SAVE LABEL IN DICTIONARY
		bot_status_labels[bot] = status_label
		
		# --- FOLLOW BUTTON ---
		var follow_btn = Button.new()
		follow_btn.text = " Follow "
		follow_btn.modulate = Color(0.3, 0.8, 1.0) 
		
		follow_btn.pressed.connect(func():
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam and cam.has_method("set_follow_target"):
				cam.set_follow_target(bot)
			close_menu()
		)
		
		row.add_child(name_label)
		row.add_child(status_label)
		row.add_child(follow_btn)
		
		bot_list_container.add_child(row)
		bot_list_container.add_child(HSeparator.new())
		
		bot_index += 1

# RESOURCES TAB LOGIC

func _refresh_resource_tab():
	if not resource_list_container: return
	
	for child in resource_list_container.get_children():
		child.queue_free()
		
	var header = Label.new()
	header.text = "Top Bar Pinned Resources (Max 10)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(0.8, 0.8, 0.8)
	resource_list_container.add_child(header)
	resource_list_container.add_child(HSeparator.new())
	
	# Grab BOTH ledgers
	var secured_items = EconomyManager.global_inventory
	var unsecured_items = EconomyManager.get_unsecured_inventory()
	
	# Combine the keys so we don't miss items that are ONLY in transit
	var all_items_dict = {}
	for key in secured_items.keys(): all_items_dict[key] = true
	for key in unsecured_items.keys(): all_items_dict[key] = true
	
	var all_items = all_items_dict.keys()
	all_items.sort()
	
	if all_items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No resources discovered yet."
		resource_list_container.add_child(empty_label)
		return

	# Build a detailed row for every item
	for item_name in all_items:
		var available = secured_items.get(item_name, 0)
		var in_transit = unsecured_items.get(item_name, 0)
		var is_pinned = EconomyManager.pinned_resources.has(item_name)
		
		# Example: If you have a custom UI row generator, you can pass both numbers!
		# If you haven't updated _create_resource_row yet, you can format the string here:
		var display_text = "%d" % available
		if in_transit > 0:
			display_text += " (+%d In Transit)" % in_transit
			
		_create_resource_row(item_name, available, in_transit, is_pinned)

func _create_resource_row(item_name: String, available: int, in_transit: int, is_pinned: bool):
	var wrapper = VBoxContainer.new()
	var main_row = HBoxContainer.new()
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var pin_btn = Button.new()
	pin_btn.text = " [\u2605] " if is_pinned else " [  ] " 
	pin_btn.modulate = Color(1.0, 0.8, 0.2) if is_pinned else Color(0.5, 0.5, 0.5)
	pin_btn.pressed.connect(func(): _toggle_pin(item_name))
	
	var name_btn = Button.new()
	name_btn.text = item_name + " \u25BC"
	name_btn.custom_minimum_size = Vector2(150, 0)
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var amount_label = Label.new()
	amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Show "Available" and optionally "In Transit"
	var text = "Total: %d" % available
	if in_transit > 0:
		text += " (+%d)" % in_transit
	amount_label.text = text
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	main_row.add_child(pin_btn)
	main_row.add_child(name_btn)
	main_row.add_child(amount_label)
	
	var details_vbox = VBoxContainer.new()
	details_vbox.hide()
	
	name_btn.pressed.connect(func():
		_toggle_resource_details(item_name, details_vbox, name_btn)
	)
	
	wrapper.add_child(main_row)
	wrapper.add_child(details_vbox)
	
	resource_list_container.add_child(wrapper)
	resource_list_container.add_child(HSeparator.new())
	
func _toggle_resource_details(item_name: String, container: VBoxContainer, btn: Button):
	if container.visible:
		container.hide()
		btn.text = item_name + " \u25BC"
		return
		
	container.show()
	btn.text = item_name + " \u25B2"
	
	for child in container.get_children():
		child.queue_free()
	
	var found_any = false
	
	# Helper function to create the row
	var add_detail_row = func(b, amount, is_secured):
		var b_row = HBoxContainer.new()
		b_row.alignment = BoxContainer.ALIGNMENT_END
		
		# Indicate if it's secured/unsecured visually
		var status_icon = " \u2713 " if is_secured else " \u23F3 " 
		var b_label = Label.new()
		b_label.text = "    %s %s: %d" % [status_icon, b.building_name, amount]
		b_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b_label.modulate = Color(0.8, 0.8, 0.8) if is_secured else Color(0.6, 0.6, 0.6)
		
		var locate_btn = Button.new()
		locate_btn.text = " Locate "
		locate_btn.modulate = Color(0.3, 0.8, 1.0)
		locate_btn.pressed.connect(func():
			var cam = get_tree().get_first_node_in_group("Camera")
			if cam and cam.has_method("set_follow_target"):
				cam.set_follow_target(b)
			close_menu()
		)
		
		b_row.add_child(b_label)
		b_row.add_child(locate_btn)
		container.add_child(b_row)
	
	for b in building_manager.buildings:
		if not is_instance_valid(b) or b.is_queued_for_deletion(): continue
		
		# Determine if the building is a secured source (Stockpile/Core)
		var is_secured = EconomyManager.secured_sources.has(b)
		
		var b_amount = 0
		if b.has_method("get_economy_assets"):
			var assets = b.get_economy_assets()
			b_amount = assets.get(item_name, 0)
					
		if b_amount > 0:
			found_any = true
			add_detail_row.call(b, b_amount, is_secured)
			
	if not found_any:
		var empty = Label.new()
		empty.text = "    \u2514 Not currently stored anywhere."
		empty.modulate = Color(0.5, 0.5, 0.5)
		container.add_child(empty)
		
func _toggle_pin(item_name: String):
	if EconomyManager.pinned_resources.has(item_name):
		EconomyManager.pinned_resources.erase(item_name)
	else:
		if EconomyManager.pinned_resources.size() < 10:
			EconomyManager.pinned_resources.append(item_name)
		else:
			print("Pin limit reached! Unpin something else first.")
			return
			
	EconomyManager.inventory_changed.emit()
	_refresh_resource_tab()

# MUSIC TAB LOGIC 

func _refresh_music_tab():
	if not music_list_container: return

	# Setup the visual state of the Jukebox toggle
	if music_jukebox_toggle:
		music_jukebox_toggle.set_pressed_no_signal(AudioManager.is_jukebox_enabled)

	# Setup the Now Playing label
	_on_audio_manager_track_changed(AudioManager.current_track_name)

	# Clean up old buttons
	for child in music_list_container.get_children():
		child.queue_free()

	# Get the tracks and build the UI buttons
	var tracks = AudioManager.get_track_list()
	for track_name in tracks:
		var btn = Button.new()
		btn.text = track_name
		
		btn.pressed.connect(func():
			AudioManager.force_play_track(track_name)
			if music_jukebox_toggle:
				music_jukebox_toggle.set_pressed_no_signal(true) 
		)
		
		music_list_container.add_child(btn)

func _on_audio_manager_track_changed(new_track_name: String):
	if music_now_playing_label:
		music_now_playing_label.text = "Now Playing: " + new_track_name

func _on_jukebox_toggled(is_enabled: bool):
	if is_enabled:
		AudioManager.is_jukebox_enabled = true
	else:
		AudioManager.disable_jukebox()

# QUOTA TAB LOGIC 

func _refresh_quota_tab():
	if not quota_list_container or not building_manager or not building_manager.level_ref: 
		return
		
	var quota_mgr = building_manager.level_ref.get_node_or_null("QuotaManager")
	var time_mgr = building_manager.level_ref.get_node_or_null("TimeManager")
	
	if not quota_mgr or not time_mgr:
		print("Couldnt find quota or time manager")
		return

	# Update the Header Info & Weekly Totals
	var failure_ratio: float = 1.0 - (float(quota_mgr.successful_days) / 7.0)
	var current_penalty = quota_mgr.max_weekly_corruption * failure_ratio
	
	# --- FIXED: Handle empty Week 1 cleanly ---
	var weekly_req_text = ""
	if quota_mgr.daily_requirements.is_empty():
		weekly_req_text = "GRACE PERIOD - FREE BUILD"
		current_penalty = 0.0
	else:
		var items_added = 0
		for item in quota_mgr.daily_requirements:
			if items_added > 0: weekly_req_text += "   |   "
			var weekly_amount = quota_mgr.daily_requirements[item] * 7
			weekly_req_text += "%s: %d" % [item, weekly_amount]
			items_added += 1
	
	quota_info_label.text = "--- WEEK %d ---\n" % [int((time_mgr.current_day - 1) / 7) + 1]
	quota_info_label.text += "Weekly Factory Target: [ %s ]\n" % weekly_req_text
	quota_info_label.text += "Projected Corruption Penalty: +%d\n" % int(current_penalty)

	# Clean up old rows
	for child in quota_list_container.get_children():
		child.queue_free()

	# Calculate Calendar Math
	var current_day_index = (time_mgr.current_day - 1) % 7 
	var successes_assigned = 0

	# Build the 7-Day Calendar
	for day_i in range(7):
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# Day Label
		var day_label = Label.new()
		day_label.text = "Day " + str(day_i + 1)
		day_label.custom_minimum_size = Vector2(80, 0)
		row.add_child(day_label)
		
		if day_i < current_day_index:
			# --- UPGRADED: PAST DAYS (Using accurate history!) ---
			var status_lbl = Label.new()
			status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var passed_today = false
			
			# Check the exact history array!
			if quota_mgr.daily_requirements.is_empty():
				passed_today = true # Grace period is always a pass
			elif "weekly_history" in quota_mgr and day_i < quota_mgr.weekly_history.size():
				passed_today = quota_mgr.weekly_history[day_i]
				
			if passed_today:
				status_lbl.text = "QUOTA MET"
				status_lbl.modulate = Color(0.2, 1.0, 0.2) # Green
			else:
				status_lbl.text = "MISSED"
				status_lbl.modulate = Color(1.0, 0.2, 0.2) # Red
				
			row.add_child(status_lbl)
			
		elif day_i == current_day_index:
			# --- TODAY ---
			day_label.modulate = Color(1.0, 0.8, 0.2) 
			
			var today_vbox = VBoxContainer.new()
			today_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			# --- FIXED: Only draw the progress bar if there is a quota! ---
			if quota_mgr.daily_requirements.is_empty():
				var free_label = Label.new()
				free_label.text = "Free Build Time! Expand your factory."
				free_label.modulate = Color(0.4, 1.0, 0.4)
				today_vbox.add_child(free_label)
			else:
				# Calculate and build the Progress Bar
				var total_req = 0.0
				var total_have = 0.0
				for item in quota_mgr.daily_requirements:
					var needed = quota_mgr.daily_requirements[item]
					total_req += needed
					total_have += min(quota_mgr.daily_delivered.get(item, 0), needed)
					
				var progress_bar = ProgressBar.new()
				progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				progress_bar.custom_minimum_size = Vector2(0, 24)
				progress_bar.max_value = total_req
				progress_bar.value = total_have
				
				if total_have >= total_req:
					progress_bar.modulate = Color(0.2, 1.0, 0.2) 
					
				today_vbox.add_child(progress_bar)
				
				# Build the Material Breakdown Text
				var breakdown_hbox = HBoxContainer.new()
				breakdown_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
				
				var daily_items_added = 0
				for item in quota_mgr.daily_requirements:
					var needed = quota_mgr.daily_requirements[item]
					var have = quota_mgr.daily_delivered.get(item, 0)
					
					if daily_items_added > 0:
						var divider = Label.new()
						divider.text = "   |   "
						divider.modulate = Color(0.4, 0.4, 0.4)
						breakdown_hbox.add_child(divider)
					
					var item_label = Label.new()
					item_label.text = "%s: %d / %d" % [item, have, needed]
					
					if have >= needed:
						item_label.modulate = Color(0.2, 1.0, 0.2)
					else:
						item_label.modulate = Color(0.9, 0.9, 0.9)
						
					breakdown_hbox.add_child(item_label)
					daily_items_added += 1
					
				today_vbox.add_child(breakdown_hbox)
				
			row.add_child(today_vbox)
			
		else:
			# --- FUTURE DAYS ---
			var future_vbox = VBoxContainer.new()
			future_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var status_lbl = Label.new()
			status_lbl.text = "Pending..."
			status_lbl.modulate = Color(0.5, 0.5, 0.5) 
			future_vbox.add_child(status_lbl)
			
			var req_lbl = Label.new()
			# --- FIXED: Print safe text for empty quotas ---
			if quota_mgr.daily_requirements.is_empty():
				req_lbl.text = "Requires: Nothing!"
			else:
				var req_strings = []
				for item in quota_mgr.daily_requirements:
					req_strings.append("%s: %d" % [item, quota_mgr.daily_requirements[item]])
				req_lbl.text = "Requires: " + "  |  ".join(req_strings)
				
			req_lbl.modulate = Color(0.4, 0.4, 0.4)
			future_vbox.add_child(req_lbl)
			
			row.add_child(future_vbox)
			
		quota_list_container.add_child(row)
		quota_list_container.add_child(HSeparator.new())
