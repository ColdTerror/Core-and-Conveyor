# ==============================================================================
# Script: projectile.gd
# Purpose: Drives target-seeking and linear physics behavior of arrows/projectiles
#          fired from defensive structures. Handles Line2D trails, ground impact
#          craters on miss, and target damage.
# Dependencies: Requires a Sprite2D child node. Connects to the Area2D body_entered signal.
# ==============================================================================
extends Area2D

var velocity: Vector2 = Vector2.ZERO
var damage: int = 0
var lifetime: float = 10.0
var damage_type: String = "None"
var source_tower: Node2D = null

# Range & Destination Tracking
var start_pos: Vector2 = Vector2.ZERO
var destination_pos: Vector2 = Vector2.ZERO
var max_travel_dist: float = 0.0
var dist_traveled: float = 0.0

# Trail
@onready var trail_line: Line2D = get_node_or_null("TrailLine")
var trail_points: Array[Vector2] = []
const MAX_TRAIL_POINTS: int = 10


## Sets up the projectile's initial position, velocity direction, speed, damage, texture, destination, and source tower.
func setup(pos: Vector2, dir: Vector2, speed: float, dmg: int, texture: Texture2D, source: Node2D = null, custom_lifetime: float = 10.0, dmg_type: String = "None", target_pos: Vector2 = Vector2.ZERO):
	global_position = pos
	start_pos = pos
	rotation = dir.angle() + deg_to_rad(45)
	velocity = dir * speed
	damage = dmg
	source_tower = source
	lifetime = custom_lifetime
	damage_type = dmg_type
	
	if target_pos != Vector2.ZERO:
		destination_pos = target_pos
		max_travel_dist = start_pos.distance_to(target_pos)
	else:
		# Fallback max distance based on speed and lifetime
		max_travel_dist = speed * min(custom_lifetime, 2.0)
		destination_pos = pos + dir * max_travel_dist
		
	if texture and has_node("Sprite2D"):
		$Sprite2D.texture = texture


func _physics_process(delta):
	var move_step = velocity * delta
	position += move_step
	dist_traveled += move_step.length()
	lifetime -= delta
	
	# Update Line2D Trail
	if trail_line:
		trail_points.push_front(global_position)
		if trail_points.size() > MAX_TRAIL_POINTS:
			trail_points.pop_back()
		trail_line.clear_points()
		for pt in trail_points:
			trail_line.add_point(pt)

	# Check if reached destination or lifetime expired
	if dist_traveled >= max_travel_dist or lifetime <= 0.0:
		_impact_ground()


## Spawns a ground impact crater / dust puff effect on miss and cleans up.
func _impact_ground():
	_spawn_crater_decal(global_position)
	_cleanup()


## Spawns a temporary visual dust puff / crater node that shrinks and fades out.
func _spawn_crater_decal(pos: Vector2):
	var crater = Node2D.new()
	crater.global_position = pos
	
	# Create dust puff sprite
	var sprite = Sprite2D.new()
	if has_node("Sprite2D") and $Sprite2D.texture:
		sprite.texture = $Sprite2D.texture
	sprite.modulate = Color(0.6, 0.5, 0.4, 0.6) # Dust brown / shadow
	sprite.scale = Vector2(0.5, 0.25)
	crater.add_child(sprite)
	
	if get_parent():
		get_parent().add_child(crater)
		
		var tween = crater.create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.4)
		tween.tween_property(sprite, "scale", Vector2(0.8, 0.4), 0.4)
		tween.chain().tween_callback(crater.queue_free)


func _cleanup():
	if trail_line:
		# Let trail line fade out cleanly
		trail_line.reparent(get_parent())
		var tween = trail_line.create_tween()
		tween.tween_property(trail_line, "modulate:a", 0.0, 0.2)
		tween.chain().tween_callback(trail_line.queue_free)
	queue_free()


## Detects collision with enemies, applies damage, and frees the projectile.
func _on_body_entered(body):
	if body.is_in_group("Enemies"):
		if body.has_method("take_damage"):
			var valid_source = source_tower if is_instance_valid(source_tower) else null
			body.take_damage(damage, valid_source, damage_type)
		_cleanup()
