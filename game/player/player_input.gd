class_name PlayerInputSynchronizer
extends MultiplayerSynchronizer
## Ввод игрока: клавиатура/мышь, геймпад и сенсорное управление.

const CAMERA_CONTROLLER_ROTATION_SPEED: float = 3.0
const CAMERA_MOUSE_ROTATION_SPEED: float = 0.0015
## Сколько радиан поворота даёт свайп на всю высоту экрана при чувствительности 1.0.
const TOUCH_LOOK_FACTOR: float = 3.0
const CAMERA_X_ROT_MIN: float = deg_to_rad(-89.9)
const CAMERA_X_ROT_MAX: float = deg_to_rad(70.0)
const AIM_HOLD_THRESHOLD: float = 0.4
## Сколько секунд после отпускания «Огня» камера остаётся в режиме прицела.
const AIM_AFTER_SHOT: float = 0.8

var toggled_aim: bool = false
var aiming_timer: float = 0.0
var shoot_linger: float = 0.0
var enabled: bool = true

@export var aiming: bool = false
@export var shoot_target := Vector3()
@export var motion := Vector2()
@export var shooting: bool = false
@export var jumping: bool = false

var reload_requested: bool = false
var switch_requested: int = 0 # 0 нет, 1 следующее, -1 предыдущее
var select_weapon: int = -1

@export var camera_animation: AnimationPlayer
@export var crosshair: TextureRect
@export var camera_base: Node3D
@export var camera_rot: Node3D
@export var camera_camera: Camera3D
@export var color_rect: ColorRect


func _ready() -> void:
	if get_multiplayer_authority() == multiplayer.get_unique_id():
		# Камера по умолчанию смотрит чуть вниз — поднимаем, чтобы прицел был на уровне горизонта.
		camera_rot.rotation.x = -0.3
		camera_camera.make_current()
		if not _touch_mode():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		set_process(false)
		set_process_input(false)
		color_rect.hide()


func _touch_mode() -> bool:
	return Settings.touch != null and Settings.touch.visible


func _process(delta: float) -> void:
	if not enabled:
		motion = Vector2()
		shooting = false
		return

	var touch: Node = Settings.touch
	motion = Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	if touch:
		motion += touch.move
	motion = motion.limit_length(1.0)

	var sens_x: float = Settings.get_v("controls", "sens_x")
	var sens_y: float = Settings.get_v("controls", "sens_y")
	var invert: float = -1.0 if Settings.get_v("controls", "invert_y") else 1.0

	var camera_move := Vector2(
			Input.get_action_strength(&"view_right") - Input.get_action_strength(&"view_left"),
			Input.get_action_strength(&"view_up") - Input.get_action_strength(&"view_down"))
	var camera_speed_this_frame: float = delta * CAMERA_CONTROLLER_ROTATION_SPEED
	if aiming:
		camera_speed_this_frame *= 0.5
	rotate_camera(Vector2(camera_move.x * sens_x, camera_move.y * sens_y * invert) * camera_speed_this_frame)

	if touch:
		var look: Vector2 = touch.consume_look()
		if look != Vector2.ZERO:
			var h: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
			var k: float = TOUCH_LOOK_FACTOR / h
			if aiming:
				k *= 0.6
			rotate_camera(Vector2(look.x * sens_x, look.y * sens_y * invert) * k)

	# --- Прицеливание ---
	var current_aim: bool = false
	if Input.is_action_just_released(&"aim") and aiming_timer <= AIM_HOLD_THRESHOLD:
		current_aim = true
		toggled_aim = true
	else:
		current_aim = toggled_aim or Input.is_action_pressed("aim")
		if Input.is_action_just_pressed("aim"):
			toggled_aim = false
	if touch and touch.aim_on:
		current_aim = true

	shooting = Input.is_action_pressed("shoot") or (touch != null and touch.fire)
	if shooting:
		shoot_linger = AIM_AFTER_SHOT
	else:
		shoot_linger = maxf(shoot_linger - delta, 0.0)
	if shoot_linger > 0.0:
		current_aim = true

	if current_aim:
		aiming_timer += delta
	else:
		aiming_timer = 0.0

	if aiming != current_aim:
		aiming = current_aim
		if aiming:
			camera_animation.play("shoot")
		else:
			camera_animation.play("far")

	if Input.is_action_just_pressed("jump") or (touch and touch.take_jump()):
		jump.rpc()
	if Input.is_action_just_pressed("reload") or (touch and touch.take_reload()):
		reload_requested = true
	if Input.is_action_just_pressed("next_weapon") or (touch and touch.take_switch()):
		switch_requested = 1
	if Input.is_action_just_pressed("prev_weapon"):
		switch_requested = -1
	for i in 3:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			select_weapon = i

	if shooting:
		update_shoot_target()

	var player_transform: Transform3D = get_parent().global_transform
	if player_transform.origin.y < -17.0:
		color_rect.modulate.a = minf((-17.0 - player_transform.origin.y) / 15.0, 1.0)
	else:
		color_rect.modulate.a *= 1.0 - delta * 4.0


func update_shoot_target() -> void:
	var ch_pos = crosshair.position + crosshair.size * 0.5
	var ray_from = camera_camera.project_ray_origin(ch_pos)
	var ray_dir = camera_camera.project_ray_normal(ch_pos)
	var space: PhysicsDirectSpaceState3D = get_parent().get_world_3d().direct_space_state
	var exclude := Array([get_parent().get_rid()], TYPE_RID, "", null)
	var col = space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * 1000, 0xFFFFFFFF, exclude))
	if col.is_empty():
		shoot_target = ray_from + ray_dir * 1000.0
	else:
		shoot_target = col.position

	# Лёгкая помощь в прицеливании для сенсорного экрана:
	# если враг почти под прицелом — стреляем точно в него.
	if _touch_mode() and Settings.get_v("controls", "aim_assist"):
		var best: Node3D = null
		var best_angle: float = deg_to_rad(6.0)
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			if enemy.dead:
				continue
			var p: Vector3 = enemy.global_position + Vector3.UP * 1.2
			var to: Vector3 = p - ray_from
			var dist: float = to.length()
			if dist > 45.0 or dist < 0.5:
				continue
			var ang: float = ray_dir.angle_to(to / dist)
			if ang < best_angle:
				var vis = space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, p, 1, exclude))
				if vis.is_empty():
					best_angle = ang
					best = enemy
		if best:
			shoot_target = best.global_position + Vector3.UP * 1.2


func _input(input_event: InputEvent) -> void:
	if not enabled:
		return
	if input_event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens_x: float = Settings.get_v("controls", "sens_x")
		var sens_y: float = Settings.get_v("controls", "sens_y")
		var invert: float = -1.0 if Settings.get_v("controls", "invert_y") else 1.0
		var camera_speed_this_frame = CAMERA_MOUSE_ROTATION_SPEED
		if aiming:
			camera_speed_this_frame *= 0.75
		var rel: Vector2 = input_event.screen_relative
		rotate_camera(Vector2(rel.x * sens_x, rel.y * sens_y * invert) * camera_speed_this_frame)
	elif input_event is InputEventMouseButton and input_event.pressed and not _touch_mode():
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if input_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			switch_requested = -1
		elif input_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_requested = 1


func rotate_camera(move: Vector2) -> void:
	camera_base.rotate_y(-move.x)
	camera_base.orthonormalize()
	camera_rot.rotation.x = clampf(camera_rot.rotation.x + move.y, CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)


func get_aim_rotation() -> float:
	var camera_x_rot: float = clampf(camera_rot.rotation.x, CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)
	if camera_x_rot >= 0.0:
		return -camera_x_rot / CAMERA_X_ROT_MAX
	else:
		return camera_x_rot / CAMERA_X_ROT_MIN


func get_camera_base_quaternion() -> Quaternion:
	return camera_base.global_transform.basis.get_rotation_quaternion()


func get_camera_rotation_basis() -> Basis:
	return camera_rot.global_transform.basis


@rpc("call_local")
func jump() -> void:
	jumping = true
