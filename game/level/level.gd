extends Node3D
## Уровень: режим обороны от волн роботов.
## Основа — уровень из Godot TPS Demo.

signal quit
signal replace_main_scene(scene: PackedScene)

const RedRobot: PackedScene = preload("res://enemies/red_robot/red_robot.tscn")
const PlayerScene: PackedScene = preload("res://player/player.tscn")
const TouchControlsScript = preload("res://ui/touch_controls.gd")
const HudScript = preload("res://ui/hud.gd")
const GameMenusScript = preload("res://ui/game_menus.gd")
const NAVMESH_PATH := "res://level/navmesh.tres"

const MAX_ALIVE_MOBILE: int = 5
const MAX_ALIVE_DESKTOP: int = 7
const SPAWN_INTERVAL: float = 1.6
const INTERMISSION: float = 6.0
## Точка старта игрока — на большой площадке, куда могут дойти роботы.
const PLAYER_START := Vector3(55.0, -5.9, 65.0)

var lightmap_gi: LightmapGI = null
var player: Player = null
var touch: CanvasLayer = null
var hud: CanvasLayer = null
var menus: CanvasLayer = null
var nav_region: NavigationRegion3D = null

var wave: int = 0
var kills: int = 0
var to_spawn: int = 0
var alive: int = 0
var spawn_timer: float = 0.0
var intermission_left: float = 3.0
var wave_active: bool = false
var game_over: bool = false
var spawn_pool: Array[Vector3] = []
var nav_target_point := Vector3.ZERO

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var robot_spawn_points: Node3D = $RobotSpawnpoints
@onready var player_spawn_points: Node3D = $PlayerSpawnpoints
@onready var spawned_nodes: Node3D = $SpawnedNodes


func _ready() -> void:
	get_tree().paused = false
	Settings.apply_graphics_settings(get_window(), world_environment.environment, self)
	setup_lightmapgi()
	_setup_navigation()
	# Отладочная надпись (FPS и т.п.) из демо — скрыта, включается клавишей F3.
	if has_node("Debug"):
		$Debug.visible = false

	touch = TouchControlsScript.new()
	add_child(touch)
	touch.pause_pressed.connect(pause_game)
	hud = HudScript.new()
	hud.touch_mode = touch.visible
	add_child(hud)
	menus = GameMenusScript.new()
	add_child(menus)
	menus.resume_requested.connect(resume_game)
	menus.restart_requested.connect(_restart)
	menus.menu_requested.connect(_to_menu)

	var spawn_point: Marker3D = player_spawn_points.get_child(0)
	add_player(1, spawn_point)
	player.global_position = PLAYER_START
	player.initial_position = PLAYER_START

	hud.set_wave(1)
	hud.set_kills(0)
	hud.set_enemies(0)
	hud.set_hp(player.hp, Player.MAX_HP)
	_on_weapon_changed(0)
	hud.banner("ПОСЛЕДНИЙ РУБЕЖ", "Продержитесь как можно дольше", 2.5)


func _setup_navigation() -> void:
	if not ResourceLoader.exists(NAVMESH_PATH):
		push_warning("Нет навигационной сетки: роботы будут идти напрямую.")
		return
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = load(NAVMESH_PATH)
	add_child(nav_region)


func setup_lightmapgi() -> void:
	world_environment.environment.sdfgi_enabled = false
	$VoxelGI.hide()
	$ReflectionProbes.show()
	if lightmap_gi == null:
		var new_gi := LightmapGI.new()
		new_gi.light_data = load("res://level/level.lmbake")
		new_gi.name = "LightmapGI"
		lightmap_gi = new_gi
		add_child(new_gi)
	if Settings.config_file.get_value("rendering", "gi_quality") == Settings.GIQuality.DISABLED:
		lightmap_gi.hide()
		$ReflectionProbes.hide()
	if Settings.is_mobile or Settings.is_web:
		# Пробы отражений дорогие для телефона.
		$ReflectionProbes.hide()


func add_player(id: int, spawn_point: Marker3D = null) -> void:
	if spawn_point == null:
		spawn_point = player_spawn_points.get_child(randi() % player_spawn_points.get_child_count())
	player = PlayerScene.instantiate()
	player.name = str(id)
	player.player_id = id
	player.transform = spawn_point.transform
	spawned_nodes.add_child(player)
	player.health_changed.connect(func(hp: float, mx: float) -> void: hud.set_hp(hp, mx))
	player.damaged.connect(func(_a: float) -> void: hud.flash_damage())
	player.weapon_changed.connect(_on_weapon_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hit_confirmed.connect(func(k: bool) -> void: hud.hit_marker(k))
	player.died.connect(_on_player_died)


func _on_weapon_changed(_i: int) -> void:
	var w := player.weapon()
	touch.weapon_name = w.name
	_on_ammo_changed(player.ammo[player.weapon_index], w.mag, player.reload_left > 0.0)


func _on_ammo_changed(ammo: int, mag: int, reloading: bool) -> void:
	touch.ammo_text = "" if reloading else "%d / %d" % [ammo, mag]
	hud.set_weapon(player.weapon().name, ammo, mag, reloading)


# ---------------- Волны ----------------

func _process(delta: float) -> void:
	if game_over or player == null:
		return
	touch.reload_progress = player.reload_progress()

	if spawn_pool.is_empty() and nav_region:
		_try_build_spawn_pool()

	if not wave_active:
		intermission_left -= delta
		if intermission_left <= 0.0:
			_start_wave()
		return

	if to_spawn > 0:
		spawn_timer -= delta
		var max_alive := MAX_ALIVE_MOBILE if (Settings.is_mobile or Settings.is_web) else MAX_ALIVE_DESKTOP
		if spawn_timer <= 0.0 and alive < max_alive:
			spawn_timer = SPAWN_INTERVAL
			if _spawn_robot():
				to_spawn -= 1
				_update_enemies()

	if to_spawn <= 0 and alive <= 0:
		_end_wave()


func _start_wave() -> void:
	wave += 1
	wave_active = true
	to_spawn = 2 + wave * 2
	spawn_timer = 0.5
	hud.set_wave(wave)
	_update_enemies()
	var new_weapon := player.unlock_for_wave(wave)
	if new_weapon != "":
		hud.banner("ВОЛНА %d" % wave, "Новое оружие: %s (кнопка «Оружие»)" % new_weapon, 2.8)
	else:
		hud.banner("ВОЛНА %d" % wave, "Роботов: %d" % to_spawn, 2.0)


func _end_wave() -> void:
	wave_active = false
	intermission_left = INTERMISSION
	player.hp = minf(player.hp + 35.0, Player.MAX_HP)
	player.health_changed.emit(player.hp, Player.MAX_HP)
	hud.banner("ВОЛНА %d ПРОЙДЕНА" % wave, "Следующая волна через несколько секунд", 3.0)


func _update_enemies() -> void:
	hud.set_enemies(to_spawn + alive)


## Собираем точки появления: только те, откуда есть путь до площадки игрока.
func _try_build_spawn_pool() -> void:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) < 2:
		return
	nav_target_point = NavigationServer3D.map_get_closest_point(map, PLAYER_START)
	var tries := 0
	while spawn_pool.size() < 60 and tries < 2500:
		tries += 1
		var r := NavigationServer3D.map_get_random_point(map, 1, true)
		if r.y > PLAYER_START.y + 4.0 or r.y < PLAYER_START.y - 4.0:
			continue
		if r.distance_to(nav_target_point) < 12.0:
			continue
		var path := NavigationServer3D.map_get_path(map, r, nav_target_point, true)
		if path.is_empty() or path[path.size() - 1].distance_to(nav_target_point) > 1.5:
			continue
		spawn_pool.append(r)
	for m in robot_spawn_points.get_children():
		var a := NavigationServer3D.map_get_closest_point(map, m.global_position)
		var path := NavigationServer3D.map_get_path(map, a, nav_target_point, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(nav_target_point) < 1.5:
			spawn_pool.append(a)
	print("Точек появления роботов: ", spawn_pool.size())


func _spawn_candidates() -> Array[Vector3]:
	if not spawn_pool.is_empty():
		return spawn_pool
	var pts: Array[Vector3] = []
	for m in robot_spawn_points.get_children():
		pts.append(m.global_position)
	return pts


func _spawn_robot() -> bool:
	var ppos := player.global_position
	var best := Vector3.ZERO
	var best_score := -INF
	var space := get_world_3d().direct_space_state
	for p in _spawn_candidates():
		var d := p.distance_to(ppos)
		if d < 14.0 or d > 48.0:
			continue
		# Лучше появляться там, где игрок не видит.
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, ppos + Vector3.UP * 1.5, 1)
		var hidden := not space.intersect_ray(q).is_empty()
		var score := randf() * 10.0 + (25.0 if hidden else 0.0) - absf(d - 24.0) * 0.4
		if score > best_score:
			best_score = score
			best = p
	if best_score == -INF:
		# Все точки слишком близко или далеко — берём ближайшую к 30 м.
		var bd := INF
		for p in _spawn_candidates():
			var dd := absf(p.distance_to(ppos) - 30.0)
			if p.distance_to(ppos) > 10.0 and dd < bd:
				bd = dd
				best = p
		if bd == INF:
			return false

	var robot: CharacterBody3D = RedRobot.instantiate()
	robot.setup(wave)
	var t := Transform3D(Basis(), best + Vector3.UP * 0.3)
	var to_player := ppos - best
	to_player.y = 0
	if to_player.length() > 0.1:
		# У робота перед — это +Z.
		t.basis = Basis.looking_at(-to_player.normalized(), Vector3.UP)
	robot.transform = t
	spawned_nodes.add_child(robot, true)
	robot.set_target_player(player)
	robot.exploded.connect(_on_robot_exploded.bind(robot))
	alive += 1
	return true


func _on_robot_exploded(robot: Node) -> void:
	alive = maxi(alive - 1, 0)
	if is_instance_valid(robot) and robot.health <= 0:
		kills += 1
		hud.set_kills(kills)
	_update_enemies()


# ---------------- Пауза / поражение ----------------

func pause_game() -> void:
	if game_over or get_tree().paused:
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	menus.show_pause()


func resume_game() -> void:
	menus.close()
	touch.reset()
	get_tree().paused = false
	if not touch.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_player_died() -> void:
	game_over = true
	var best: int = Settings.get_v("game", "best_wave")
	var record := wave > best
	if record:
		Settings.set_v("game", "best_wave", wave)
	if kills > int(Settings.get_v("game", "best_kills")):
		Settings.set_v("game", "best_kills", kills)
	Settings.save_settings()
	await get_tree().create_timer(1.8).timeout
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	menus.show_game_over(wave, kills, maxi(best, wave), record)


func _restart() -> void:
	get_tree().paused = false
	replace_main_scene.emit(load("res://level/level.tscn"))


func _to_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	quit.emit()


func _input(input_event: InputEvent) -> void:
	if input_event.is_action_pressed(&"quit"):
		pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_inside_tree() and not game_over:
			pause_game()
