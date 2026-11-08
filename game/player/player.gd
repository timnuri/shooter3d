class_name Player
extends CharacterBody3D
## Игрок: движение (на основе Godot TPS Demo), здоровье, оружие, патроны.

signal health_changed(hp: float, max_hp: float)
signal died
signal weapon_changed(index: int)
signal ammo_changed(ammo: int, mag: int, reloading: bool)
signal hit_confirmed(killed: bool)
signal damaged(amount: float)

enum Animations {
	JUMP_UP,
	JUMP_DOWN,
	STRAFE,
	WALK,
}

const MOTION_INTERPOLATE_SPEED: float = 10.0
const ROTATION_INTERPOLATE_SPEED: float = 10.0
const MIN_AIRBORNE_TIME: float = 0.1
const JUMP_SPEED: float = 5.0

const MAX_HP: float = 100.0
const REGEN_DELAY: float = 6.0
const REGEN_PER_SEC: float = 5.0

const BulletScene: PackedScene = preload("res://player/bullet/bullet.tscn")

## Оружие. unlock_wave — с какой волны доступно.
const WEAPONS: Array[Dictionary] = [
	{
		name = "Автомат", cooldown = 0.13, damage = 1, pellets = 1, spread = 1.2,
		speed = 55.0, mag = 30, reload = 1.6, size = 0.7, shake = 0.12, pitch = 1.25, unlock_wave = 1,
	},
	{
		name = "Дробовик", cooldown = 0.85, damage = 1, pellets = 7, spread = 7.0,
		speed = 45.0, mag = 6, reload = 2.2, size = 0.6, shake = 0.5, pitch = 0.75, unlock_wave = 2,
	},
	{
		name = "Рельсотрон", cooldown = 1.1, damage = 10, pellets = 1, spread = 0.0,
		speed = 90.0, mag = 4, reload = 2.6, size = 1.6, shake = 0.7, pitch = 0.55, unlock_wave = 4,
	},
]

var airborne_time: float = 100.0
var orientation := Transform3D()
var root_motion := Transform3D()
var motion := Vector2()

var hp: float = MAX_HP
var dead: bool = false
var since_damage: float = 100.0
var weapon_index: int = 0
var unlocked: int = 1
var ammo: Array[int] = []
var reload_left: float = 0.0
var cooldown_left: float = 0.0

@onready var initial_position: Vector3 = transform.origin

@onready var player_input: PlayerInputSynchronizer = $InputSynchronizer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var player_model: Node3D = $PlayerModel
@onready var shoot_from: Marker3D = player_model.get_node(^"Robot_Skeleton/Skeleton3D/GunBone/ShootFrom")
@onready var crosshair: TextureRect = $Crosshair
@onready var fire_cooldown: Timer = $FireCooldown

@onready var sound_effects: Node = $SoundEffects
@onready var sound_effect_jump: AudioStreamPlayer = sound_effects.get_node(^"Jump")
@onready var sound_effect_land: AudioStreamPlayer = sound_effects.get_node(^"Land")
@onready var sound_effect_shoot: AudioStreamPlayer = sound_effects.get_node(^"Shoot")

@export var player_id: int = 1:
	set(value):
		player_id = value
		$InputSynchronizer.set_multiplayer_authority(value)

@export var current_animation := Animations.WALK


func _ready() -> void:
	orientation = player_model.global_transform
	orientation.origin = Vector3()
	add_to_group(&"player")
	for w in WEAPONS:
		ammo.append(w.mag)
	if not multiplayer.is_server():
		set_process(false)


func weapon() -> Dictionary:
	return WEAPONS[weapon_index]


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		apply_input(delta)
	else:
		animate(current_animation, delta)


func _process(delta: float) -> void:
	if dead:
		return
	since_damage += delta
	if since_damage > REGEN_DELAY and hp < MAX_HP:
		hp = minf(hp + REGEN_PER_SEC * delta, MAX_HP)
		health_changed.emit(hp, MAX_HP)

	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			reload_left = 0.0
			ammo[weapon_index] = weapon().mag
			_emit_ammo()

	if player_input.reload_requested:
		player_input.reload_requested = false
		start_reload()
	if player_input.switch_requested != 0:
		var dir := player_input.switch_requested
		player_input.switch_requested = 0
		set_weapon(wrapi(weapon_index + dir, 0, unlocked))
	if player_input.select_weapon >= 0:
		var idx := player_input.select_weapon
		player_input.select_weapon = -1
		if idx < unlocked:
			set_weapon(idx)


func _emit_ammo() -> void:
	ammo_changed.emit(ammo[weapon_index], weapon().mag, reload_left > 0.0)


func set_weapon(index: int) -> void:
	if index == weapon_index:
		return
	weapon_index = index
	reload_left = 0.0
	cooldown_left = 0.3
	weapon_changed.emit(weapon_index)
	_emit_ammo()
	if ammo[weapon_index] <= 0:
		start_reload()


func unlock_for_wave(wave: int) -> String:
	var new_name := ""
	for i in WEAPONS.size():
		if WEAPONS[i].unlock_wave <= wave and i >= unlocked:
			unlocked = i + 1
			new_name = WEAPONS[i].name
	return new_name


func start_reload() -> void:
	if reload_left > 0.0 or ammo[weapon_index] >= weapon().mag or dead:
		return
	reload_left = weapon().reload
	_emit_ammo()


func reload_progress() -> float:
	if reload_left <= 0.0:
		return 1.0
	return 1.0 - reload_left / weapon().reload


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	since_damage = 0.0
	add_camera_shake_trauma(0.9)
	damaged.emit(amount)
	health_changed.emit(maxf(hp, 0.0), MAX_HP)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		player_input.enabled = false
		died.emit()


func animate(anim: int, _delta: float) -> void:
	current_animation = anim as Animations

	if anim == Animations.JUMP_UP:
		animation_tree["parameters/state/transition_request"] = "jump_up"
	elif anim == Animations.JUMP_DOWN:
		animation_tree["parameters/state/transition_request"] = "jump_down"
	elif anim == Animations.STRAFE:
		animation_tree["parameters/state/transition_request"] = "strafe"
		animation_tree["parameters/aim/add_amount"] = player_input.get_aim_rotation()
		animation_tree["parameters/strafe/blend_position"] = Vector2(motion.x, -motion.y)
	elif anim == Animations.WALK:
		animation_tree["parameters/aim/add_amount"] = 0
		animation_tree["parameters/state/transition_request"] = "walk"
		animation_tree["parameters/walk/blend_position"] = Vector2(motion.length(), 0)


func apply_input(delta: float) -> void:
	motion = motion.lerp(player_input.motion, MOTION_INTERPOLATE_SPEED * delta)

	var camera_basis: Basis = player_input.get_camera_rotation_basis()
	var camera_z: Vector3 = camera_basis.z
	var camera_x: Vector3 = camera_basis.x
	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()

	airborne_time += delta
	if is_on_floor():
		if airborne_time > 0.5:
			land.rpc()
		airborne_time = 0

	var on_air: bool = airborne_time > MIN_AIRBORNE_TIME

	if not on_air and player_input.jumping and not dead:
		velocity.y = JUMP_SPEED
		on_air = true
		airborne_time = MIN_AIRBORNE_TIME
		jump.rpc()

	player_input.jumping = false

	if on_air:
		if velocity.y > 0:
			animate(Animations.JUMP_UP, delta)
		else:
			animate(Animations.JUMP_DOWN, delta)
		# В воздухе тоже можно стрелять.
		if player_input.aiming:
			var q_from_air: Quaternion = orientation.basis.get_rotation_quaternion()
			var q_to_air: Quaternion = player_input.get_camera_base_quaternion()
			orientation.basis = Basis(q_from_air.slerp(q_to_air, delta * ROTATION_INTERPOLATE_SPEED))
			try_shoot()
	elif player_input.aiming:
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = player_input.get_camera_base_quaternion()
		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
		animate(Animations.STRAFE, delta)
		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())
		try_shoot()
	else:
		var target: Vector3 = camera_x * motion.x + camera_z * motion.y
		if target.length() > 0.001:
			var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
			var q_to: Quaternion = Basis.looking_at(target).get_rotation_quaternion()
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
		animate(Animations.WALK, delta)
		root_motion = Transform3D(animation_tree.get_root_motion_rotation(), animation_tree.get_root_motion_position())

	if dead:
		root_motion = Transform3D()

	orientation *= root_motion

	var h_velocity: Vector3 = orientation.origin / delta
	if on_air:
		# В воздухе сохраняем горизонтальную скорость (root motion в прыжке нулевой).
		pass
	else:
		velocity.x = h_velocity.x
		velocity.z = h_velocity.z
	velocity += get_gravity() * delta
	set_velocity(velocity)
	set_up_direction(Vector3.UP)
	move_and_slide()

	orientation.origin = Vector3()
	orientation = orientation.orthonormalized()

	player_model.global_transform.basis = orientation.basis

	if transform.origin.y < -40.0:
		transform.origin = initial_position
		velocity = Vector3()


func try_shoot() -> void:
	if dead or not player_input.shooting:
		return
	if cooldown_left > 0.0 or reload_left > 0.0:
		return
	if ammo[weapon_index] <= 0:
		start_reload()
		return
	var w := weapon()
	cooldown_left = w.cooldown
	ammo[weapon_index] -= 1

	var shoot_origin: Vector3 = shoot_from.global_transform.origin
	var base_dir: Vector3 = (player_input.shoot_target - shoot_origin).normalized()
	for i in int(w.pellets):
		var dir := base_dir
		if w.spread > 0.0:
			var spread := deg_to_rad(w.spread)
			var side := base_dir.cross(Vector3.UP).normalized()
			if side.length() < 0.1:
				side = Vector3.RIGHT
			var up := side.cross(base_dir).normalized()
			dir = (base_dir + side * randf_range(-1, 1) * tan(spread) + up * randf_range(-1, 1) * tan(spread)).normalized()
		var bullet: CharacterBody3D = BulletScene.instantiate()
		bullet.speed = w.speed
		bullet.damage = w.damage
		bullet.shooter = self
		bullet.light_on_hit = (i == 0)
		get_parent().add_child(bullet, true)
		bullet.global_transform.origin = shoot_origin
		bullet.look_at(shoot_origin + dir)
		bullet.add_collision_exception_with(self)
	shoot.rpc()
	_emit_ammo()
	if ammo[weapon_index] <= 0:
		start_reload()


func on_bullet_hit(killed: bool) -> void:
	hit_confirmed.emit(killed)


@rpc("call_local")
func jump() -> void:
	animate(Animations.JUMP_UP, 0.0)
	sound_effect_jump.play()


@rpc("call_local")
func land() -> void:
	animate(Animations.JUMP_DOWN, 0.0)
	sound_effect_land.play()


@rpc("call_local")
func shoot() -> void:
	var shoot_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/ShootParticle
	shoot_particle.restart()
	shoot_particle.emitting = true
	var muzzle_particle = $PlayerModel/Robot_Skeleton/Skeleton3D/GunBone/ShootFrom/MuzzleFlash
	muzzle_particle.restart()
	muzzle_particle.emitting = true
	var w := weapon()
	sound_effect_shoot.pitch_scale = w.pitch * randf_range(0.95, 1.05)
	sound_effect_shoot.play()
	add_camera_shake_trauma(w.shake)


@rpc("call_local")
func hit() -> void:
	add_camera_shake_trauma(0.75)


@rpc("call_local")
func add_camera_shake_trauma(amount: float) -> void:
	player_input.camera_camera.add_trauma(amount)
