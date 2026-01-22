extends Node

enum ForestState {
	FULL,
	HARVESTING,
	DEPLETED
}

@export var forest_regrow_time := 5.0
@export var forest_mid_regrow_time := 2.0

# tile -> ForestState
var forest_states := {}

# tile -> time remaining
var regrowing_forests := {}

signal forest_state_changed(tile: Vector2i, state: int)

func harvest_forest(tile: Vector2i):
	if forest_states.get(tile, ForestState.FULL) != ForestState.FULL:
		return

	# Step 1: harvesting begins
	forest_states[tile] = ForestState.HARVESTING
	forest_state_changed.emit(tile, ForestState.HARVESTING)

	# Step 2: schedule depletion
	get_tree().create_timer(1.5).timeout.connect(func():
		forest_states[tile] = ForestState.DEPLETED
		forest_state_changed.emit(tile, ForestState.DEPLETED)

		# Step 3: start regrow timer
		regrowing_forests[tile] = forest_regrow_time
	)

func _process(delta):
	var finished := []

	for tile in regrowing_forests.keys():
		regrowing_forests[tile] -= delta

		# halfway point → leafless
		if regrowing_forests[tile] <= forest_mid_regrow_time \
		and forest_states[tile] == ForestState.DEPLETED:
			forest_states[tile] = ForestState.HARVESTING
			forest_state_changed.emit(tile, ForestState.HARVESTING)

		if regrowing_forests[tile] <= 0:
			finished.append(tile)

	for tile in finished:
		regrowing_forests.erase(tile)
		forest_states[tile] = ForestState.FULL
		forest_state_changed.emit(tile, ForestState.FULL)
