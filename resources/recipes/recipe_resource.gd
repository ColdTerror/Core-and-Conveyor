# RecipeResource.gd
extends Resource
class_name RecipeResource

@export var recipe_name: String = "Processing"
@export var input_item: ItemResource    # What goes in (Log)
@export var input_count: int = 1        # How many?
@export var output_item: ItemResource   # What comes out (Plank)
@export var output_count: int = 2       # How many? (Bonus!)
@export var craft_time: float = 2.0     # How long it takes
