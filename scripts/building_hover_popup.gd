extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var inventory_box = $VBoxContainer/Inventory


func show_building_info(b: Building):
	name_label.text = b.building_name
	health_label.text = "%d / %d" % [b.health, b.max_health]

	if b is StockpileBuilding:
		show_inventory(b.inventory)
	else:
		hide_inventory()

func show_inventory(inventory: Dictionary):
	inventory_box.visible = true

	# Clear previous rows
	for child in inventory_box.get_children():
		child.queue_free()

	# Empty inventory case
	if inventory.is_empty():
		var label := Label.new()
		label.text = "(Empty)"
		inventory_box.add_child(label)
		return

	# Populate rows
	for item in inventory.keys():
		var amount = inventory[item]

		var row := Label.new()
		row.text = "%s: %d" % [item.display_name, amount]
		inventory_box.add_child(row)

func hide_inventory():
	inventory_box.visible = false

func hide_popup():
	hide()
