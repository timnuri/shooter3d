extends CharacterBody3D
## Снаряд игрока.

var speed: float = 20.0
var damage: int = 1
var shooter: Node = null
var light_on_hit: bool = true
var time_alive: float = 3.0
var hit: bool = false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var omni_light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	# Снаряды не сталкиваются друг с другом (важно для дробовика).
	collision_layer = 0
	collision_mask = 1
	if not multiplayer.is_server():
		set_physics_process(false)
		collision_shape.disabled = true
	if not light_on_hit:
		omni_light.visible = false


func _physics_process(delta: float) -> void:
	if hit:
		return
	time_alive -= delta
	if time_alive < 0.0:
		hit = true
		explode.rpc()
		return
	var displacement: Vector3 = -delta * speed * global_transform.basis.z.normalized()
	var col: KinematicCollision3D = move_and_collide(displacement)
	if col:
		var collider: Node3D = col.get_collider() as Node3D
		if collider and collider.has_method(&"take_hit"):
			var killed: bool = collider.take_hit(damage)
			if is_instance_valid(shooter) and shooter.has_method(&"on_bullet_hit"):
				shooter.on_bullet_hit(killed)
		collision_shape.disabled = true
		explode.rpc()
		hit = true


@rpc("call_local")
func explode() -> void:
	animation_player.play(&"explode")
	if light_on_hit and Settings.config_file.get_value("rendering", "shadow_mapping") and not Settings.is_mobile and not Settings.is_web:
		omni_light.shadow_enabled = true


func destroy() -> void:
	if not multiplayer.is_server():
		return
	queue_free()
