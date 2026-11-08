extends CharacterBody3D
## Красный робот (из Godot TPS Demo), доработан для режима обороны:
## ищет игрока по навигационной сетке, наносит урон лазером, сила растёт с волнами.

signal exploded()

enum State {
	IDLE = 0,
	APPROACH = 1,
	AIM = 2,
	SHOOTING = 3,
}

const PLAYER_AIM_TOLERANCE_DEGREES = deg_to_rad(15.0)
const AIM_TIME: float = 1.0
const AIM_PREPARE_TIME: float = 0.5
const BLEND_AIM_SPEED: float = 0.05
## Ближе этого расстояния робот перестаёт идти и просто стреляет.
const STOP_DISTANCE: float = 11.0
## Роботы в оригинале ходят медленно — немного ускоряем.
const MOVE_SPEED_MULT: float = 1.35
const REPATH_TIME: float = 0.4

@export var test_shoot: bool = false
@export var target_position := Vector3()
@export var health: int = 5
@export var state: State = State.IDLE
@export var dead: bool = false
@export var aim_preparing: float = AIM_PREPARE_TIME

## Параметры силы (задаются уровнем при появлении).
var max_health: int = 5
var laser_damage: float = 20.0
var shoot_wait: float = 5.0
var chase: bool = false
var accuracy: float = 0.75

var shoot_countdown: float = 5.0
var aim_countdown: float = AIM_TIME
var steer_target := Vector3()
var repath_left: float = 0.0
var sees_player: bool = false
var stuck_time: float = 0.0
var last_pos := Vector3()

var player: Node3D = null
var orientation := Transform3D()
var nav_agent: NavigationAgent3D = null

var blast_scene: PackedScene = preload("res://enemies/red_robot/laser/impact_effect/impact_effect.tscn")

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var shoot_animation: AnimationPlayer = $ShootAnimation

@onready var model: Node3D = $RedRobotModel
@onready var ray_from: BoneAttachment3D = model.get_node(^"Armature/Skeleton3D/RayFrom")
@onready var ray_mesh: MeshInstance3D = ray_from.get_node(^"RayMesh")
@onready var laser_raycast: RayCast3D = ray_from.get_node(^"RayCast")
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@onready var explosion_sound: AudioStreamPlayer3D = $SoundEffects/Explosion
@onready var hit_sound: AudioStreamPlayer3D = $SoundEffects/Hit

@onready var death: Node3D = $Death
@onready var death_shield1: RigidBody3D = death.get_node(^"PartShield1")
@onready var death_shield2: RigidBody3D = death.get_node(^"PartShield2")
@onready var death_head: RigidBody3D = death.get_node(^"PartHead")
@onready var death_detach_spark1: CPUParticles3D = death.get_node(^"DetachSpark1")
@onready var death_detach_spark2: CPUParticles3D = death.get_node(^"DetachSpark2")


func _ready() -> void:
	add_to_group(&"enemies")
	orientation = global_transform
	orientation.origin = Vector3()
	$AnimationTree.active = true
	shoot_countdown = shoot_wait * randf_range(0.4, 1.0)
	if test_shoot:
		shoot_countdown = 0.0

	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 1.5
	nav_agent.target_desired_distance = 2.0
	nav_agent.radius = 1.0
	nav_agent.height = 2.5
	nav_agent.avoidance_enabled = false
	add_child(nav_agent)

	if dead:
		model.visible = false
		collision_shape.disabled = true
		animation_tree.active = false

	last_pos = global_position
	animate(0.0)


## Настройка силы робота под номер волны.
func setup(wave: int) -> void:
	max_health = 8 + wave
	health = max_health
	laser_damage = minf(14.0 + wave * 2.0, 40.0)
	shoot_wait = maxf(5.0 - wave * 0.25, 2.5)
	accuracy = minf(0.7 + wave * 0.03, 0.9)


func set_target_player(p: Node3D) -> void:
	player = p
	chase = true
	state = State.APPROACH


func resume_approach() -> void:
	state = State.APPROACH
	aim_preparing = AIM_PREPARE_TIME
	shoot_countdown = shoot_wait


@rpc("call_local")
func hit() -> void:
	take_hit(1)


## Получить попадание. Возвращает true, если робот уничтожен.
func take_hit(amount: int = 1) -> bool:
	if dead:
		return false
	var param = "parameters/hit" + str(randi() % 3 + 1) + "/request"
	animation_tree[param] = 1
	hit_sound.play()
	health -= amount
	# Получив урон, робот разворачивается к игроку, даже если не видел его.
	if player == null:
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			set_target_player(players[0])
	if health <= 0:
		health = 0
		dead = true
		remove_from_group(&"enemies")
		animation_tree.active = false
		model.visible = false
		death.visible = true
		collision_shape.disabled = true

		death_detach_spark1.emitting = true
		death_detach_spark2.emitting = true

		death_shield1.explode()
		death_shield2.explode()
		death_head.explode()

		explosion_sound.play()
		exploded.emit()

		if multiplayer.is_server():
			get_tree().create_timer(6.0).timeout.connect(queue_free)
		return true
	return false


func shoot() -> void:
	if dead:
		return
	var gt: Transform3D = ray_from.global_transform
	var ray_origin: Vector3 = ray_from.global_transform.origin
	var ray_dir: Vector3 = gt.basis.y
	var max_dist: float = 1000.0

	var col: Dictionary = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * max_dist, 0xFFFFFFFF, [self]))
	if not col.is_empty():
		max_dist = ray_origin.distance_to(col.position)
	_clip_ray(max_dist)
	var mesh_offset: float = ray_mesh.position.z
	var laser_ember: CPUParticles3D = $RedRobotModel/Armature/Skeleton3D/RayFrom/LaserEmber
	laser_ember.position = Vector3(0.0, 0.0, -max_dist / 2.0 - mesh_offset)
	laser_ember.emission_box_extents.z = (max_dist - absf(mesh_offset)) / 2.0
	if not col.is_empty():
		var blast = blast_scene.instantiate()
		get_tree().get_root().add_child(blast)
		blast.global_transform.origin = col.position
	# Урон считаем по прямой видимости (лазер в анимации может немного «гулять»).
	if player is Player and _can_see_player() and randf() < accuracy:
		player.take_damage(laser_damage)


func animate(delta: float) -> void:
	if state == State.APPROACH:
		var goal: Vector3 = steer_target if steer_target != Vector3.ZERO else target_position
		var to_goal_local: Vector3 = goal * global_transform
		var angle_to_goal: float = atan2(to_goal_local.x, to_goal_local.z)
		var close: bool = sees_player and target_position != Vector3.ZERO and global_position.distance_to(target_position) < STOP_DISTANCE
		if angle_to_goal > PLAYER_AIM_TOLERANCE_DEGREES:
			animation_tree["parameters/state/transition_request"] = "turn_left"
		elif angle_to_goal < -PLAYER_AIM_TOLERANCE_DEGREES:
			animation_tree["parameters/state/transition_request"] = "turn_right"
		elif goal == Vector3.ZERO or close:
			animation_tree["parameters/state/transition_request"] = "idle"
		else:
			animation_tree["parameters/state/transition_request"] = "walk"
	else:
		animation_tree["parameters/state/transition_request"] = "idle"

	if target_position != Vector3.ZERO:
		animation_tree["parameters/aiming/blend_amount"] = clamp(aim_preparing / AIM_PREPARE_TIME, 0, 1)

		var to_cannon_local: Vector3 = (target_position + Vector3.UP) * ray_mesh.global_transform
		var h_angle: float = rad_to_deg(atan2(to_cannon_local.x, -to_cannon_local.z))
		var v_angle: float = rad_to_deg(atan2(to_cannon_local.y, -to_cannon_local.z))
		var blend_pos: Vector2 = animation_tree.get("parameters/aim/blend_position")
		blend_pos.x = clampf(blend_pos.x + BLEND_AIM_SPEED * delta * -h_angle, -1.0, 1.0)
		blend_pos.y = clampf(blend_pos.y + BLEND_AIM_SPEED * delta * v_angle, -1.0, 1.0)
		animation_tree["parameters/aim/blend_position"] = blend_pos


func _can_see_player() -> bool:
	var ray_origin: Vector3 = ray_from.global_transform.origin
	var ray_to: Vector3 = player.global_transform.origin + Vector3.UP
	# Другие роботы не закрывают обзор.
	var exclude: Array[RID] = []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		exclude.append(e.get_rid())
	exclude.append(get_rid())
	var col = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_origin, ray_to, 0xFFFFFFFF, exclude))
	return not col.is_empty() and col.collider == player


func _update_path(delta: float) -> void:
	repath_left -= delta
	if repath_left <= 0.0:
		repath_left = REPATH_TIME
		sees_player = _can_see_player()
		nav_agent.target_position = target_position
		# Защита от застревания: если почти не двигаемся во время ходьбы — идём по сетке.
		var walking: bool = state == State.APPROACH and animation_tree["parameters/state/current_state"] == "walk"
		if walking and global_position.distance_to(last_pos) < 0.15:
			stuck_time += REPATH_TIME
		elif global_position.distance_to(last_pos) > 0.5:
			stuck_time = maxf(stuck_time - REPATH_TIME, 0.0)
		last_pos = global_position
	if sees_player and stuck_time < 1.5:
		steer_target = target_position
	elif nav_agent.is_navigation_finished():
		steer_target = target_position
	else:
		steer_target = nav_agent.get_next_path_position()
	steer_target.y = global_position.y


func _physics_process(delta: float) -> void:
	if dead:
		return

	if not multiplayer.is_server():
		animate(delta)
		return

	if test_shoot:
		shoot()
		test_shoot = false

	if not is_instance_valid(player) or (player is Player and player.dead):
		target_position = Vector3()
		steer_target = Vector3()
		state = State.IDLE
		animate(delta)
		velocity = Vector3(0, velocity.y, 0) + get_gravity() * delta
		move_and_slide()
		return

	target_position = player.global_transform.origin
	_update_path(delta)

	if state == State.APPROACH:
		if aim_preparing > 0:
			aim_preparing = maxf(aim_preparing - delta, 0.0)

		var to_player_local: Vector3 = target_position * global_transform
		var angle_to_player: float = atan2(to_player_local.x, to_player_local.z)
		if sees_player and angle_to_player > -PLAYER_AIM_TOLERANCE_DEGREES and angle_to_player < PLAYER_AIM_TOLERANCE_DEGREES:
			shoot_countdown -= delta
			if shoot_countdown < 0.0:
				if _can_see_player():
					state = State.AIM
					aim_countdown = AIM_TIME
					aim_preparing = 0.0
				else:
					shoot_countdown = shoot_wait

	elif state == State.AIM or state == State.SHOOTING:
		var max_dist: float = 1000.0
		if laser_raycast.is_colliding():
			max_dist = (ray_from.global_transform.origin - laser_raycast.get_collision_point()).length()
		_clip_ray(max_dist)
		if aim_preparing < AIM_PREPARE_TIME:
			aim_preparing = minf(aim_preparing + delta, AIM_PREPARE_TIME)

		aim_countdown -= delta
		if aim_countdown < 0.0 and state == State.AIM:
			if _can_see_player():
				state = State.SHOOTING
				shoot_countdown = shoot_wait
				play_shoot.rpc()
			else:
				resume_approach()

	animate(delta)
	orientation *= Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())

	var h_velocity: Vector3 = orientation.origin / delta * MOVE_SPEED_MULT
	velocity.x = h_velocity.x
	velocity.z = h_velocity.z
	velocity += get_gravity() * delta
	set_velocity(velocity)
	set_up_direction(Vector3.UP)
	move_and_slide()

	orientation.origin = Vector3()
	orientation = orientation.orthonormalized()

	global_transform.basis = orientation.basis

	if global_position.y < -40.0:
		# Упал за карту — убираем без награды.
		dead = true
		remove_from_group(&"enemies")
		exploded.emit()
		queue_free()


@rpc("call_local")
func play_shoot() -> void:
	shoot_animation.play(&"shoot")


func shoot_check() -> void:
	test_shoot = true


func _clip_ray(length: float) -> void:
	var mesh_offset: float = ray_mesh.position.z
	if not OS.has_feature("dedicated_server"):
		ray_mesh.get_surface_override_material(0).set_shader_parameter("clip", length + mesh_offset)


func _on_area_body_entered(body: Node3D) -> void:
	if body is Player or body.name == "Target":
		player = body
		state = State.APPROACH


func _on_area_body_exited(body: Node3D) -> void:
	if chase:
		return
	if body is Player:
		player = null
		state = State.IDLE
