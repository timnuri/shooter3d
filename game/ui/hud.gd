extends CanvasLayer
## Интерфейс во время игры: здоровье, волна, враги, очки, оружие, сообщения.

var _hp_fill: ColorRect
var _hp_back: ColorRect
var _hp_label: Label
var _wave_label: Label
var _enemies_label: Label
var _kills_label: Label
var _weapon_label: Label
var _banner: Label
var _banner_sub: Label
var _vignette: ColorRect
var _marker: Control
var _banner_tween: Tween

var _marker_t: float = 0.0
var _marker_kill: bool = false
var _hp_ratio: float = 1.0
var _hp_shown: float = 1.0
var touch_mode: bool = false


func _ready() -> void:
	layer = 4
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.8, 0.05, 0.02, 0.0)
	root.add_child(_vignette)

	# Здоровье — слева сверху.
	_hp_back = ColorRect.new()
	_hp_back.position = Vector2(40, 36)
	_hp_back.size = Vector2(380, 26)
	_hp_back.color = Color(0, 0, 0, 0.45)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_back)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(43, 39)
	_hp_fill.size = Vector2(374, 20)
	_hp_fill.color = Color(0.85, 0.9, 0.88)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_fill)
	_hp_label = _make_label(root, 26)
	_hp_label.position = Vector2(42, 64)
	_kills_label = _make_label(root, 26)
	_kills_label.position = Vector2(42, 100)

	# Волна — сверху по центру.
	_wave_label = _make_label(root, 38)
	_wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_wave_label, -300, 24, 600, 50)
	_enemies_label = _make_label(root, 26)
	_enemies_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_enemies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_enemies_label, -300, 72, 600, 40)

	# Оружие — справа снизу (для клавиатуры; на телефоне патроны над кнопкой «Огонь»).
	_weapon_label = _make_label(root, 32)
	_weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_weapon_label, -640, -110, 600, 80)

	# Большие сообщения по центру.
	_banner = _make_label(root, 64)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_banner, -700, -260, 1400, 90)
	_banner.modulate.a = 0.0
	_banner_sub = _make_label(root, 34)
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_banner_sub, -700, -175, 1400, 60)
	_banner_sub.modulate.a = 0.0

	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	root.add_child(_marker)


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _make_label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _process(delta: float) -> void:
	_hp_shown = lerpf(_hp_shown, _hp_ratio, minf(delta * 10.0, 1.0))
	_hp_fill.size.x = 374.0 * _hp_shown
	var low := _hp_ratio < 0.3
	_hp_fill.color = Color(0.95, 0.25, 0.2) if low else Color(0.85, 0.9, 0.88)
	_vignette.color.a = maxf(_vignette.color.a - delta * 0.9, 0.18 * (1.0 - _hp_ratio / 0.3) if low else 0.0)
	if _marker_t > 0.0:
		_marker_t -= delta
		_marker.queue_redraw()


func set_hp(hp: float, max_hp: float) -> void:
	_hp_ratio = clampf(hp / max_hp, 0.0, 1.0)
	_hp_label.text = "Здоровье %d" % roundi(hp)


func flash_damage() -> void:
	_vignette.color.a = minf(_vignette.color.a + 0.35, 0.55)


func set_wave(n: int) -> void:
	_wave_label.text = "Волна %d" % n


func set_enemies(n: int) -> void:
	_enemies_label.text = "Врагов осталось: %d" % n if n > 0 else ""


func set_kills(k: int) -> void:
	_kills_label.text = "Уничтожено: %d" % k


func set_weapon(weapon_name: String, ammo: int, mag: int, reloading: bool) -> void:
	if touch_mode:
		_weapon_label.text = ""
		return
	var a := "перезарядка..." if reloading else "%d / %d" % [ammo, mag]
	_weapon_label.text = "%s   %s" % [weapon_name, a]


func hit_marker(killed: bool) -> void:
	_marker_t = 0.25 if not killed else 0.45
	_marker_kill = killed
	_marker.queue_redraw()


func _draw_marker() -> void:
	if _marker_t <= 0.0:
		return
	var c := _marker.get_viewport_rect().size * 0.5
	var col := Color(1, 0.3, 0.2, minf(_marker_t * 4.0, 1.0)) if _marker_kill else Color(1, 1, 1, minf(_marker_t * 4.0, 1.0))
	var s := 22.0 if _marker_kill else 16.0
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_marker.draw_line(c + d * 8.0, c + d * s, col, 4.0, true)


func banner(text: String, sub: String = "", duration: float = 2.5) -> void:
	_banner.text = text
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.25)
	_banner_tween.chain().tween_interval(duration)
	_banner_tween.chain().set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 0.0, 0.5)
