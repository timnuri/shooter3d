extends Node
## Настройки игры (графика, управление, звук, рекорды).
## Сохраняются в user://settings.ini.

enum GIType {
	SDFGI = 0,
	VOXEL_GI = 1,
	LIGHTMAP_GI = 2,
}

enum GIQuality {
	DISABLED = 0,
	LOW = 1,
	HIGH = 2,
}

enum Quality {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
}

const CONFIG_FILE_PATH = "user://settings.ini"

## Ссылка на сенсорное управление текущего уровня (или null).
var touch: Node = null

var is_mobile: bool = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
var is_web: bool = OS.has_feature("web")

var DEFAULTS := {
	video = {
		display_mode = Window.MODE_WINDOWED,
		vsync = DisplayServer.VSYNC_ENABLED,
		max_fps = 60,
		resolution_scale = 1.0,
		scale_filter = Viewport.SCALING_3D_MODE_BILINEAR,
		quality = Quality.MEDIUM,
		show_fps = true,
	},
	rendering = {
		taa = false,
		msaa = Viewport.MSAA_DISABLED,
		screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED,
		shadow_mapping = true,
		gi_type = GIType.LIGHTMAP_GI,
		gi_quality = GIQuality.LOW,
		ssao_quality = -1,
		ssil_quality = -1,
		bloom = true,
		volumetric_fog = false,
	},
	controls = {
		sens_x = 1.0,
		sens_y = 1.0,
		invert_y = false,
		aim_assist = true,
	},
	audio = {
		volume = 0.8,
	},
	game = {
		best_wave = 0,
		best_kills = 0,
	},
}

var config_file := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_audio()


func _input(input_event: InputEvent) -> void:
	if input_event.is_action_pressed(&"toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if (w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN) else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


func load_settings() -> void:
	config_file.load(CONFIG_FILE_PATH)
	var first_run := not config_file.has_section_key("video", "quality")
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not config_file.has_section_key(section, key):
				config_file.set_value(section, key, DEFAULTS[section][key])
	if first_run:
		# В браузере по умолчанию ставим низкое качество, в приложении — среднее.
		set_quality(Quality.LOW if is_web else Quality.MEDIUM)
	else:
		# Обновляем значения пресета (могли измениться в новой версии игры).
		set_quality(int(config_file.get_value("video", "quality")))


func save_settings() -> void:
	config_file.save(CONFIG_FILE_PATH)


func get_v(section: String, key: String) -> Variant:
	return config_file.get_value(section, key, DEFAULTS[section][key])


func set_v(section: String, key: String, value: Variant) -> void:
	config_file.set_value(section, key, value)


## Пресеты качества графики.
func set_quality(q: int) -> void:
	config_file.set_value("video", "quality", q)
	match q:
		Quality.LOW:
			config_file.set_value("video", "resolution_scale", 0.5)
			config_file.set_value("rendering", "shadow_mapping", false)
			config_file.set_value("rendering", "gi_quality", GIQuality.LOW)
			config_file.set_value("rendering", "bloom", false)
			config_file.set_value("rendering", "msaa", Viewport.MSAA_DISABLED)
		Quality.MEDIUM:
			config_file.set_value("video", "resolution_scale", 0.7)
			config_file.set_value("rendering", "shadow_mapping", true)
			config_file.set_value("rendering", "gi_quality", GIQuality.LOW)
			config_file.set_value("rendering", "bloom", true)
			config_file.set_value("rendering", "msaa", Viewport.MSAA_DISABLED)
		_:
			config_file.set_value("video", "resolution_scale", 1.0)
			config_file.set_value("rendering", "shadow_mapping", true)
			config_file.set_value("rendering", "gi_quality", GIQuality.LOW)
			config_file.set_value("rendering", "bloom", true)
			config_file.set_value("rendering", "msaa", Viewport.MSAA_2X)
	config_file.set_value("rendering", "gi_type", GIType.LIGHTMAP_GI)
	config_file.set_value("rendering", "ssao_quality", -1)
	config_file.set_value("rendering", "ssil_quality", -1)
	config_file.set_value("rendering", "volumetric_fog", false)


func apply_audio() -> void:
	var vol: float = get_v("audio", "volume")
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)


func apply_graphics_settings(window: Window, environment: Environment, scene_root: Node) -> void:
	if not is_mobile:
		window.mode = config_file.get_value("video", "display_mode")
	DisplayServer.window_set_vsync_mode(config_file.get_value("video", "vsync"))
	Engine.max_fps = config_file.get_value("video", "max_fps")
	var scale: float = config_file.get_value("video", "resolution_scale")
	window.scaling_3d_scale = scale
	window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if scale >= 0.99 or is_web else Viewport.SCALING_3D_MODE_FSR

	window.use_taa = false
	window.msaa_3d = config_file.get_value("rendering", "msaa")
	window.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

	if not config_file.get_value("rendering", "shadow_mapping"):
		scene_root.propagate_call("set", ["shadow_enabled", false])

	if environment:
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.sdfgi_enabled = false
		environment.glow_enabled = config_file.get_value("rendering", "bloom")
		environment.volumetric_fog_enabled = false
		environment.ssr_enabled = false
