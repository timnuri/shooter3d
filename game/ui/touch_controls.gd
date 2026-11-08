extends CanvasLayer
## Сенсорное управление.
## Левая часть экрана — плавающий джойстик (появляется там, где коснулся).
## Правая часть экрана — обзор пальцем. Кнопку «Огонь» тоже можно вести пальцем — камера поворачивается.
## Работает несколькими пальцами одновременно.

signal pause_pressed

const JOY_RADIUS: float = 120.0
const JOY_DEADZONE: float = 0.12

## Результаты для PlayerInput.
var move := Vector2.ZERO
var fire: bool = false
var aim_on: bool = false

var _look_accum := Vector2.ZERO
var _jump_flag: bool = false
var _reload_flag: bool = false
var _switch_flag: bool = false

## index пальца -> роль ("joy", "look", "fire", "aim", "jump", "reload", "weapon", "pause")
var _fingers: Dictionary = {}
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _pressed_time: Dictionary = {}

var weapon_name: String = ""
var ammo_text: String = ""
var reload_progress: float = 1.0

var _canvas: Control
var _font: Font


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_ui)
	add_child(_canvas)
	_font = ThemeDB.fallback_font
	visible = should_show()
	Settings.touch = self


func _exit_tree() -> void:
	if Settings.touch == self:
		Settings.touch = null


static func should_show() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return DisplayServer.is_touchscreen_available()


func reset() -> void:
	_fingers.clear()
	move = Vector2.ZERO
	fire = false
	_look_accum = Vector2.ZERO
	_canvas.queue_redraw()


func consume_look() -> Vector2:
	var v := _look_accum
	_look_accum = Vector2.ZERO
	return v


func take_jump() -> bool:
	var v := _jump_flag
	_jump_flag = false
	return v


func take_reload() -> bool:
	var v := _reload_flag
	_reload_flag = false
	return v


func take_switch() -> bool:
	var v := _switch_flag
	_switch_flag = false
	return v


# ---------------- Раскладка ----------------

func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


func _buttons() -> Dictionary:
	var s := _size()
	var w := s.x
	var h := s.y
	return {
		"fire": [Vector2(w - 250, h - 290), 115.0],
		"jump": [Vector2(w - 105, h - 150), 70.0],
		"aim": [Vector2(w - 455, h - 150), 70.0],
		"reload": [Vector2(w - 470, h - 390), 62.0],
		"weapon": [Vector2(w - 110, h - 450), 68.0],
		"pause": [Vector2(w - 70, 70), 45.0],
	}


func _hit_button(p: Vector2) -> String:
	var bs := _buttons()
	for key in bs:
		var c: Vector2 = bs[key][0]
		var r: float = bs[key][1]
		# Зона нажатия чуть больше нарисованной кнопки.
		if p.distance_to(c) <= r * 1.2:
			return key
	return ""


func _role_active(role: String) -> bool:
	for idx in _fingers:
		if _fingers[idx] == role:
			return true
	return false


# ---------------- Ввод ----------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_down(event.index, event.position)
		else:
			_on_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()


func _on_down(idx: int, p: Vector2) -> void:
	var btn := _hit_button(p)
	if btn != "":
		match btn:
			"jump":
				_jump_flag = true
			"reload":
				_reload_flag = true
			"weapon":
				_switch_flag = true
			"aim":
				aim_on = not aim_on
			"pause":
				pause_pressed.emit()
		_fingers[idx] = btn
	elif p.x < _size().x * 0.42 and not _role_active("joy"):
		_fingers[idx] = "joy"
		_joy_origin = p
		_joy_pos = p
		move = Vector2.ZERO
	else:
		_fingers[idx] = "look"
	_update_fire()
	_canvas.queue_redraw()


func _on_up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var role: String = _fingers[idx]
	_fingers.erase(idx)
	if role == "joy":
		move = Vector2.ZERO
	_update_fire()
	_canvas.queue_redraw()


func _on_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if not _fingers.has(idx):
		# Палец, начавший касание до появления управления.
		_on_down(idx, p)
		return
	var role: String = _fingers[idx]
	match role:
		"joy":
			_joy_pos = p
			var off := _joy_pos - _joy_origin
			# Если палец ушёл далеко — джойстик «едет» за пальцем.
			if off.length() > JOY_RADIUS * 1.6:
				_joy_origin = _joy_pos - off.normalized() * JOY_RADIUS * 1.6
				off = _joy_pos - _joy_origin
			var v := off / JOY_RADIUS
			if v.length() > 1.0:
				v = v.normalized()
			if v.length() < JOY_DEADZONE:
				v = Vector2.ZERO
			move = v
			_canvas.queue_redraw()
		"look", "fire":
			_look_accum += rel


func _update_fire() -> void:
	fire = _role_active("fire")


# ---------------- Отрисовка ----------------

func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _draw_button(c: Vector2, r: float, label: String, active: bool, fsize: int = 26, accent := Color(1, 1, 1)) -> void:
	var fill := Color(0, 0, 0, 0.28 if not active else 0.45)
	_canvas.draw_circle(c, r, fill)
	_canvas.draw_arc(c, r, 0, TAU, 64, Color(accent, 0.75 if active else 0.45), 3.0, true)
	if active:
		_canvas.draw_circle(c, r * 0.92, Color(accent, 0.12))
	var lines := label.split("\n")
	var total_h := lines.size() * fsize * 1.1
	for i in lines.size():
		var y := c.y - total_h * 0.5 + fsize * (i + 0.85) * 1.1
		_canvas.draw_string(_font, Vector2(c.x - r, y), lines[i], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fsize, Color(1, 1, 1, 0.9))


func _draw_ui() -> void:
	var bs := _buttons()
	var amber := Color(1.0, 0.72, 0.3)
	# Джойстик
	if _role_active("joy"):
		_canvas.draw_circle(_joy_origin, JOY_RADIUS, Color(0, 0, 0, 0.25))
		_canvas.draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.45), 3.0, true)
		var knob := _joy_origin + move * JOY_RADIUS
		_canvas.draw_circle(knob, 48, Color(1, 1, 1, 0.45))
	else:
		var s := _size()
		var hint := Vector2(230, s.y - 230)
		_canvas.draw_arc(hint, JOY_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.18), 2.0, true)
		_canvas.draw_circle(hint, 40, Color(1, 1, 1, 0.12))

	var fire_label := "ОГОНЬ"
	if reload_progress < 1.0:
		fire_label = "ПЕРЕ-\nЗАРЯДКА"
	_draw_button(bs.fire[0], bs.fire[1], fire_label, _role_active("fire"), 30, amber)
	if reload_progress < 1.0:
		_canvas.draw_arc(bs.fire[0], bs.fire[1] + 8, -PI / 2, -PI / 2 + TAU * reload_progress, 64, Color(amber, 0.9), 6.0, true)
	_draw_button(bs.jump[0], bs.jump[1], "ПРЫЖОК", _role_active("jump"), 20)
	_draw_button(bs.aim[0], bs.aim[1], "ПРИЦЕЛ", aim_on, 20, amber if aim_on else Color(1, 1, 1))
	_draw_button(bs.reload[0], bs.reload[1], "ПАТРОНЫ", _role_active("reload"), 18)
	_draw_button(bs.weapon[0], bs.weapon[1], weapon_name.replace(" ", "\n") if weapon_name != "" else "ОРУЖИЕ", _role_active("weapon"), 18)
	_draw_button(bs.pause[0], bs.pause[1], "II", _role_active("pause"), 28)
	if ammo_text != "":
		var c: Vector2 = bs.fire[0]
		var r: float = bs.fire[1]
		_canvas.draw_string(_font, Vector2(c.x - 150, c.y - r - 22), ammo_text, HORIZONTAL_ALIGNMENT_CENTER, 300, 34, Color(1, 1, 1, 0.95))
