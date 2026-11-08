extends CanvasLayer
## Пауза и экран поражения.

signal resume_requested
signal restart_requested
signal menu_requested

const SettingsPanel = preload("res://ui/settings_panel.gd")

var _root: Control
var _current: Control = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


var _pause_shown: bool = false


func _input(event: InputEvent) -> void:
	if _pause_shown and is_open() and event.is_action_pressed(&"quit"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func is_open() -> bool:
	return _current != null and is_instance_valid(_current)


func close() -> void:
	_pause_shown = false
	if is_open():
		_current.queue_free()
	_current = null


func _new_screen() -> VBoxContainer:
	close()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	_current = c
	return UIKit.centered_panel(c)


func show_pause() -> void:
	var vb := _new_screen()
	_pause_shown = true
	vb.add_child(UIKit.label("ПАУЗА", 56, UIKit.ACCENT))
	vb.add_child(UIKit.button("Продолжить", func() -> void: resume_requested.emit()))
	vb.add_child(UIKit.button("Настройки", _open_settings))
	vb.add_child(UIKit.button("Начать заново", func() -> void: restart_requested.emit()))
	vb.add_child(UIKit.button("В главное меню", func() -> void: menu_requested.emit()))


func _open_settings() -> void:
	var p := SettingsPanel.new()
	_root.add_child(p)
	p.closed.connect(show_pause)
	close()
	_current = p


func show_game_over(wave: int, kills: int, best_wave: int, new_record: bool) -> void:
	var vb := _new_screen()
	vb.add_child(UIKit.label("ВЫ ПОГИБЛИ", 60, Color(1, 0.4, 0.3)))
	vb.add_child(UIKit.label("Волна: %d     Уничтожено роботов: %d" % [wave, kills], 32))
	if new_record:
		vb.add_child(UIKit.label("Новый рекорд!", 36, UIKit.ACCENT))
	else:
		vb.add_child(UIKit.label("Рекорд: волна %d" % best_wave, 28, Color(1, 1, 1, 0.7)))
	vb.add_child(UIKit.button("Ещё раз", func() -> void: restart_requested.emit()))
	vb.add_child(UIKit.button("В главное меню", func() -> void: menu_requested.emit()))
