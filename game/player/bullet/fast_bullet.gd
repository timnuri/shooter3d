class_name FastBullet
extends Node3D
## Лёгкий снаряд для телефона: светящийся трассер + луч для попадания + искры.
## Заменяет тяжёлый снаряд из демо (там было 6 систем GPU-частиц на каждую пулю).

static var _tracer_mesh: Mesh
static var _tracer_mat: StandardMaterial3D
static var _spark_mesh: Mesh
static var _spark_mat: StandardMaterial3D

var speed: float = 60.0
var damage: int = 1
var shooter: Node = null
var dir := Vector3.FORWARD
var thickness: float = 1.0
var life: float = 2.0
var exclude: Array[RID] = []


static func _ensure_resources() -> void:
	if _tracer_mesh:
		return
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.8, 0.45)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(1.0, 0.6, 0.25)
	_tracer_mat.emission_energy_multiplier = 3.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 0.9
	cyl.radial_segments = 4
	cyl.rings = 1
	cyl.material = _tracer_mat
	_tracer_mesh = cyl

	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.75, 0.4)
	_spark_mat.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 0.12)
	box.material = _spark_mat
	_spark_mesh = box


func _ready() -> void:
	_ensure_resources()
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Цилиндр вдоль Y — поворачиваем вдоль направления полёта (-Z).
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.scale = Vector3(thickness, 1.0, thickness)
	add_child(mi)
	if dir.length() > 0.0:
		look_at(global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + dir * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var collider: Object = hit.collider
		if collider and collider.has_method(&"take_hit"):
			var killed: bool = collider.take_hit(damage)
			if is_instance_valid(shooter) and shooter.has_method(&"on_bullet_hit"):
				shooter.on_bullet_hit(killed)
			spawn_sparks(get_parent(), hit.position, hit.normal, Color(1.0, 0.55, 0.2), 14)
		else:
			spawn_sparks(get_parent(), hit.position, hit.normal, Color(1.0, 0.85, 0.6), 7)
		queue_free()
		return
	global_position = to
	life -= delta
	if life <= 0.0:
		queue_free()


static func spawn_sparks(parent: Node, pos: Vector3, normal: Vector3, color: Color, amount: int) -> void:
	_ensure_resources()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.mesh = _spark_mesh
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9.8, 0)
	p.particle_flag_align_y = false
	p.color = color
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos + normal * 0.05
	if normal.length() > 0.1:
		var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		p.look_at(pos + normal, up)
		# Частицы летят по +Z; look_at направляет -Z на нормаль — разворачиваем.
		p.rotate_object_local(Vector3.UP, PI)
	p.emitting = true
	p.get_tree().create_timer(0.7).timeout.connect(p.queue_free)
