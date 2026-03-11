extends Resource
class_name RecipeResource

@export var recipe_name: String = "New Recipe"
@export var craft_time: float = 2.0

# NEW: A Dictionary where the Key is the ItemResource, and the Value is the integer amount needed.
@export var inputs: Dictionary = {} 

@export var output_item: ItemResource
@export var output_count: int = 1
