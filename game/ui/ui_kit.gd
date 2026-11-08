class_name UIKit
extends RefCounted
## Общий стиль интерфейса: крупные кнопки под палец, тёмные панели, янтарный акцент.

const ACCENT := Color(1.0, 0.72, 0.3)
const TEXT := Color(0.95, 0.95, 0.92)
const PANEL := Color(0.05, 0.06, 0.07, 0.86)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 34

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.14, 0.92)
	normal.border_color = Color(1, 1, 1, 0.18)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = ACCENT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.35)
	pressed.border_color = ACCENT
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color(ACCENT, 0.6)

	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_color", "Label", TEXT)

	# Ползунки
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 8
	fill.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _circle_texture(44, Color(1, 1, 1))
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(44, ACCENT))

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(14)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(2)
	panel.content_margin_left = 40
	panel.content_margin_right = 40
	panel.content_margin_top = 30
	panel.content_margin_bottom = 30
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


static func _circle_texture(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 34, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, cb: Callable, min_w: float = 520.0, min_h: float = 96.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## Затемнённый фон на весь экран + панель по центру с колонкой.
static func centered_panel(parent: Control, dim: float = 0.55) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var pc := PanelContainer.new()
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	return vb
