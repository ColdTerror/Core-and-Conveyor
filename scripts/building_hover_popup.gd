extends PanelContainer

@onready var name_label = $VBoxContainer/Name
@onready var health_label = $VBoxContainer/Health
@onready var inventory_box = $VBoxContainer/Inventory

func show_building(building: StockpileBuilding):
	name_label.text = building.building_name
	health_label.text = "Health: %d / %d" % [building.health, building.max_health]

	# Clear old inventory
	for child in inventory_box.get_children():
		child.queue_free()

	for item in building.inventory.keys():
		var amount = building.inventory[item]
		var label := Label.new()
		label.text = "%s: %d" % [item.display_name, amount]
		inventory_box.add_child(label)

	show()

func hide_popup():
	hide()
