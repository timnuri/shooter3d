extends Control
## Экран настроек: чувствительность, инверсия, помощь в прицеливании, графика, громкость.

signal closed

const QUALITY_NAMES := ["Низкая", "Средняя", "Высокая"]

var _quality_btn: Button
var _invert_btn: Button
var _assist_btn: Button
var _fps_btn: Button
var _value_labels: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	var vb := UIKit.centered_panel(self, 0.7)
	vb.add_child(UIKit.label("НАСТРОЙКИ", 52, UIKit.ACCENT))

	_add_slider(vb, "Чувствительность по горизонтали", "controls", "sens_x", 0.2, 3.0, 0.05)
	_add_slider(vb, "Чувствительность по вертикали", "controls", "sens_y", 0.2, 3.0, 0.05)
	_add_slider(vb, "Громкость", "audio", "volume", 0.0, 1.0, 0.05)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_invert_btn = UIKit.button("", _toggle_invert, 420, 84)
	row.add_child(_invert_btn)
	_assist_btn = UIKit.button("", _toggle_assist, 420, 84)
	row.add_child(_assist_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 18)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row2)
	_quality_btn = UIKit.button("", _cycle_quality, 520, 84)
	row2.add_child(_quality_btn)
	_fps_btn = UIKit.button("", _toggle_fps, 320, 84)
	row2.add_child(_fps_btn)
	var note := UIKit.label("Графика меняется при следующем запуске уровня", 22, Color(1, 1, 1, 0.55))
	vb.add_child(note)

	vb.add_child(UIKit.button("Готово", _close, 860, 96))
	_refresh()


func _add_slider(parent: VBoxContainer, title: String, section: String, key: String, mn: float, mx: float, step: float) -> void:
	var head := HBoxContainer.new()
	var l := UIKit.label(title, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var v := UIKit.label("", 28, UIKit.ACCENT)
	head.add_child(v)
	parent.add_child(head)
	_value_labels[section + "/" + key] = v

	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.custom_minimum_size = Vector2(860, 56)
	s.value = Settings.get_v(section, key)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(val: float) -> void:
		Settings.set_v(section, key, val)
		if section == "audio":
			Settings.apply_audio()
		_refresh())
	parent.add_child(s)


func _toggle_invert() -> void:
	Settings.set_v("controls", "invert_y", not Settings.get_v("controls", "invert_y"))
	_refresh()


func _toggle_assist() -> void:
	Settings.set_v("controls", "aim_assist", not Settings.get_v("controls", "aim_assist"))
	_refresh()


func _toggle_fps() -> void:
	Settings.set_v("video", "show_fps", not Settings.get_v("video", "show_fps"))
	_refresh()


func _cycle_quality() -> void:
	var q: int = (int(Settings.get_v("video", "quality")) + 1) % 3
	Settings.set_quality(q)
	_refresh()


func _refresh() -> void:
	for k in _value_labels:
		var parts: PackedStringArray = k.split("/")
		var val: float = Settings.get_v(parts[0], parts[1])
		_value_labels[k].text = ("%d%%" % roundi(val * 100)) if parts[0] == "audio" else ("%.2f" % val)
	_invert_btn.text = "Инверсия: " + ("вкл" if Settings.get_v("controls", "invert_y") else "выкл")
	_assist_btn.text = "Помощь в прицеле: " + ("вкл" if Settings.get_v("controls", "aim_assist") else "выкл")
	_quality_btn.text = "Графика: " + QUALITY_NAMES[int(Settings.get_v("video", "quality"))]
	_fps_btn.text = "Кадры/с: " + ("вкл" if Settings.get_v("video", "show_fps") else "выкл")


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()
