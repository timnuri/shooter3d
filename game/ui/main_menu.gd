extends Control
## Главное меню: Играть / Настройки / Авторы / Выход и экран загрузки уровня.

signal replace_main_scene(scene: PackedScene)

const LEVEL_PATH := "res://level/level.tscn"
const SettingsPanel = preload("res://ui/settings_panel.gd")

var _menu_box: Control
var _loading_box: Control
var _progress: ProgressBar
var _loading: bool = false
var _robot: Node3D


func _ready() -> void:
	theme = UIKit.make_theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	_build_background()
	_build_menu()


func _build_background() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	svc.add_child(sv)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.09, 0.1)
	env.fog_density = 0.03
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(-0.4, 2.0, 9.5)
	sv.add_child(cam)
	cam.look_at(Vector3(-1.2, 1.5, 0))

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.86, 0.7)
	key.shadow_enabled = true
	sv.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.5, 2.5, -2.5)
	rim.light_color = Color(0.5, 0.65, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 8.0
	sv.add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.12, 0.12)
	fm.roughness = 0.6
	fm.metallic = 0.4
	floor_mesh.material_override = fm
	sv.add_child(floor_mesh)

	var scene: PackedScene = load("res://enemies/red_robot/model/red_robot.glb")
	if scene:
		_robot = scene.instantiate()
		_robot.position = Vector3(-3.0, 0, 0)
		_robot.rotation_degrees = Vector3(0, 25, 0)
		sv.add_child(_robot)
		var ap := _robot.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for anim_name in ap.get_animation_list():
				if anim_name.to_lower().contains("idle"):
					ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
					ap.play(anim_name)
					break

	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.3, 0.5)
	gt.fill_to = Vector2(0.75, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)


func _process(delta: float) -> void:
	if _robot:
		_robot.rotate_y(delta * 0.15)
	if _loading:
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(LEVEL_PATH, progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_progress.value = float(progress[0]) * 100.0
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			_progress.value = 100.0
			replace_main_scene.emit(ResourceLoader.load_threaded_get(LEVEL_PATH))
		else:
			_loading = false
			push_error("Ошибка загрузки уровня: %d" % status)
			_loading_box.queue_free()
			_build_menu()


func _right_column() -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_left", 120)
	add_child(margin)
	var hb := HBoxContainer.new()
	margin.add_child(hb)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	hb.add_child(vb)
	_menu_box = margin
	return vb


func _build_menu() -> void:
	var vb := _right_column()
	var title := UIKit.label("ПОСЛЕДНИЙ\nРУБЕЖ", 92, UIKit.TEXT)
	vb.add_child(title)
	vb.add_child(UIKit.label("оборона от роботов", 30, UIKit.ACCENT))
	var best: int = Settings.get_v("game", "best_wave")
	if best > 0:
		vb.add_child(UIKit.label("Рекорд: волна %d" % best, 26, Color(1, 1, 1, 0.65)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	vb.add_child(gap)
	vb.add_child(UIKit.button("Играть", _start))
	vb.add_child(UIKit.button("Настройки", _open_settings))
	vb.add_child(UIKit.button("Авторы", _open_credits))
	if not Settings.is_web:
		vb.add_child(UIKit.button("Выход", func() -> void: get_tree().quit()))


func _start() -> void:
	if _loading:
		return
	_menu_box.queue_free()
	_loading_box = Control.new()
	_loading_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_box)
	var vb := UIKit.centered_panel(_loading_box, 0.4)
	vb.add_child(UIKit.label("Загрузка...", 44))
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(700, 36)
	_progress.show_percentage = false
	vb.add_child(_progress)
	vb.add_child(UIKit.label("Левая часть экрана — ходьба, правая — обзор.\nЗажмите «Огонь» и ведите пальцем, чтобы целиться.", 26, Color(1, 1, 1, 0.75)))
	ResourceLoader.load_threaded_request(LEVEL_PATH, "", true)
	_loading = true


func _open_settings() -> void:
	_menu_box.queue_free()
	var p := SettingsPanel.new()
	add_child(p)
	p.closed.connect(_build_menu)


func _open_credits() -> void:
	_menu_box.queue_free()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var vb := UIKit.centered_panel(c, 0.7)
	vb.add_child(UIKit.label("АВТОРЫ", 48, UIKit.ACCENT))
	var txt := "Уровень, модели, анимации, звуки и основа кода — Godot Third Person Shooter Demo.\n" + \
		"Графика и звуки: Juan Linietsky, Fernando Miguel Calabró (CC-BY 3.0).\n" + \
		"Музыка: Christian Fernando Perucchi (CC-BY 3.0).\n" + \
		"Код демо: Juan Linietsky и участники Godot Engine (MIT).\n" + \
		"Часть материалов предоставлена GameTextures.com.\n" + \
		"Движок: Godot Engine (godotengine.org)."
	var l := UIKit.label(txt, 26)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1100, 0)
	vb.add_child(l)
	_menu_box = c
	vb.add_child(UIKit.button("Назад", func() -> void:
		c.queue_free()
		_build_menu()))
