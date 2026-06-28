# ==============================================================================
# Script: UI/split_flap_digit.gd
# Purpose: Simulates a mechanical split-flap digit with smooth 2D folding animations,
#          sequentially rolling through transitions, and customizable timing parameters.
# ==============================================================================
extends Control

@export_group("Animation Timing")
## Speed of a single flip fold/reveal
@export var flip_duration: float = 0.08 
## Delay between consecutive flips in a sequence
@export var character_advance_delay: float = 0.05 
@export var font_size: int = 48

@export_group("Standalone Testing")
@export var auto_count_up: bool = false
## Time between counter increments
@export var count_interval: float = 1.0 

# Node references
@onready var top_label: Label = $TopHalf/Label
@onready var bottom_label: Label = $BottomHalf/Label
@onready var flap: Control = $Flap
@onready var flap_label: Label = $Flap/Label
@onready var divider: ColorRect = $Divider

var current_char: String = "0"
var target_char: String = "0"
var is_flipping: bool = false
var queue: Array[String] = []

# For standalone testing
var test_timer: float = 0.0
var test_counter: int = 0

func _ready():
	# Apply font overrides
	for label in [top_label, bottom_label, flap_label]:
		label.add_theme_font_size_override("font_size", font_size)
	
	# Set initial state
	set_character_instantly(current_char)
	
	# Reset flap pivots and scale
	_reset_flap_state()
	

func set_size_custom(new_width: float, new_height: float, new_font_size: int):
	custom_minimum_size = Vector2(new_width, new_height)
	size = Vector2(new_width, new_height)
	font_size = new_font_size
	for label in [top_label, bottom_label, flap_label]:
		if label:
			label.add_theme_font_size_override("font_size", new_font_size)
	_reset_flap_state()
	

func _process(delta):
	if auto_count_up:
		test_timer += delta
		if test_timer >= count_interval:
			test_timer = 0.0
			test_counter = (test_counter + 1) % 10
			set_target_character(str(test_counter))

func set_character_instantly(c: String):
	current_char = c
	target_char = c
	top_label.text = c
	bottom_label.text = c
	flap_label.text = c
	queue.clear()
	is_flipping = false
	_reset_flap_state()

func set_target_character(c: String):
	if c == target_char:
		return
	target_char = c
	
	if current_char != target_char:
		queue.clear()
		var start = current_char.to_int() if current_char.is_valid_int() else 0
		var end = target_char.to_int() if target_char.is_valid_int() else 0
		
		# Calculate shortest path (forward vs backward)
		var dist_forward = (end - start + 10) % 10
		var dist_backward = (start - end + 10) % 10
		
		var step = 1 if dist_forward <= dist_backward else -1
		
		var current = start
		while current != end:
			current = (current + step + 10) % 10
			queue.append(str(current))
			
		_trigger_next_flip()

func _trigger_next_flip():
	if is_flipping or queue.is_empty():
		return
		
	var next_c = queue.pop_front()
	_animate_flip_to(next_c)

func _animate_flip_to(next_c: String):
	is_flipping = true
	
	# ----------------------------------------------------
	# PHASE 1: Fold Top Flap Down
	# ----------------------------------------------------
	# Static Top already displays the new character
	top_label.text = next_c
	
	# Moving Flap represents the old top half folding down
	flap.anchors_preset = PRESET_TOP_WIDE
	flap.anchor_bottom = 0.5
	flap.offset_bottom = 0
	flap_label.text = current_char
	# Offset label inside the top half so it aligns properly
	flap_label.anchors_preset = PRESET_FULL_RECT
	flap_label.anchor_bottom = 2.0
	
	# Pivot at bottom center of top half
	flap.pivot_offset = Vector2(size.x / 2.0, size.y / 4.0)
	flap.scale.y = 1.0
	
	var tween = create_tween().set_parallel(false)
	
	# Fold down
	tween.tween_property(flap, "scale:y", 0.0, flip_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# ----------------------------------------------------
	# PHASE 2: Transition Flap and Fold Reveal New Bottom
	# ----------------------------------------------------
	tween.tween_callback(func():
		# Flap now represents the new bottom half unfolding
		flap.anchors_preset = PRESET_BOTTOM_WIDE
		flap.anchor_top = 0.5
		flap.offset_top = 0
		flap_label.text = next_c
		# Offset label inside bottom half (needs to shift up by half height)
		flap_label.anchors_preset = PRESET_FULL_RECT
		flap_label.anchor_top = -1.0
		flap_label.anchor_bottom = 1.0
		
		# Pivot at top center of bottom half
		flap.pivot_offset = Vector2(size.x / 2.0, 0.0)
		flap.scale.y = 0.0
	)
	
	# Unfold down
	tween.tween_property(flap, "scale:y", 1.0, flip_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Complete and prepare next
	tween.tween_callback(func():
		# Static Bottom catches up
		bottom_label.text = next_c
		current_char = next_c
		is_flipping = false
		_reset_flap_state()
		
		# Wait slightly before triggering the next queued flip
		get_tree().create_timer(character_advance_delay).timeout.connect(_trigger_next_flip)
	)

func _reset_flap_state():
	flap.anchors_preset = PRESET_TOP_WIDE
	flap.anchor_bottom = 0.5
	flap.offset_bottom = 0
	flap.pivot_offset = Vector2(size.x / 2.0, size.y / 4.0)
	flap.scale.y = 1.0
	flap_label.text = current_char
	flap_label.anchors_preset = PRESET_FULL_RECT
	flap_label.anchor_bottom = 2.0
