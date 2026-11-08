extends SceneTree
## Проверка меню и сенсорного управления без графики.

func _initialize() -> void:
	var main = load("res://main/main.tscn").instantiate()
	root.add_child(main)
	for i in 5: await process_frame
	var menu = main.get_child(0)
	print("menu: ", menu.name)
	menu._open_settings()
	for i in 3: await process_frame
	var sp = null
	for c in menu.get_children():
		if c.has_signal("closed"): sp = c
	print("settings panel: ", sp != null)
	sp._cycle_quality()
	sp._close()
	for i in 3: await process_frame
	menu._open_credits()
	for i in 3: await process_frame
	print("credits ok")
	menu._start()
	var t := 0
	while main.get_child(0) == menu and t < 3000:
		await process_frame
		t += 1
	var lvl = main.get_child(0)
	print("level: ", lvl.name, " after frames ", t)
	for i in 10: await physics_frame
	var touch = lvl.touch
	touch.visible = true
	var vs = root.get_visible_rect().size
	print("viewport visible size ", vs)
	# Палец 0 — джойстик слева, тянем вверх.
	_touch(0, Vector2(300, vs.y - 300), true)
	_drag(0, Vector2(300, vs.y - 420), Vector2(0, -120))
	# Палец 1 — обзор справа.
	_touch(1, Vector2(vs.x * 0.6, vs.y * 0.4), true)
	_drag(1, Vector2(vs.x * 0.6 + 50, vs.y * 0.4), Vector2(50, 0))
	await process_frame
	print("final xform ", root.get_final_transform())
	print("move=", touch.move, " look(after consume by player)=", touch._look_accum, " fingers=", touch._fingers)
	# Огонь
	var fire_pos: Vector2 = touch._buttons()["fire"][0]
	_touch(2, fire_pos, true)
	await process_frame
	print("fire=", touch.fire, " player shooting=", lvl.player.player_input.shooting)
	for i in 30: await physics_frame
	print("ammo after fire: ", lvl.player.ammo)
	_touch(2, fire_pos, false)
	_touch(0, Vector2(300, vs.y - 420), false)
	_touch(1, Vector2(vs.x * 0.6 + 50, vs.y * 0.4), false)
	await process_frame
	print("released: move=", touch.move, " fire=", touch.fire)
	# Пауза через кнопку
	var pause_pos: Vector2 = touch._buttons()["pause"][0]
	_touch(3, pause_pos, true)
	await process_frame
	print("paused=", paused, " menu open=", lvl.menus.is_open())
	lvl.menus._open_settings()
	await process_frame
	lvl.menus.resume_requested.emit()
	await process_frame
	print("resumed paused=", paused)
	lvl.player.take_damage(1000)
	for i in 200: await process_frame
	print("game over shown=", lvl.menus.is_open(), " paused=", paused)
	lvl.menus.restart_requested.emit()
	for i in 20: await process_frame
	print("restarted level: ", main.get_child(0).name, " wave=", main.get_child(0).wave)
	main.get_child(0).menus.menu_requested.emit()
	for i in 10: await process_frame
	print("back to menu: ", main.get_child(0).name)
	print("UI TEST DONE")
	quit()

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = pressed
	root.push_input(e)

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.relative = root.get_final_transform().basis_xform(rel)
	root.push_input(e)
