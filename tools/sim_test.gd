extends SceneTree
## Автотест игрового процесса без графики: бот стреляет по ближайшему роботу.
## godot --headless --path <проект> -s sim_test.gd

var lvl: Node3D
var t := 0.0
var log_t := 0.0
var max_wave := 0
var PITCH_SIGN := 1.0

func _initialize() -> void:
	root.get_node("Settings").config_file.set_value("game", "best_wave", 0)
	lvl = load("res://level/level.tscn").instantiate()
	root.add_child(lvl)
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 60

func _process(delta: float) -> bool:
	t += delta
	log_t += delta
	var p = lvl.player
	if p and not p.dead:
		var best = null
		var bd := INF
		for e in get_nodes_in_group(&"enemies"):
			var d = e.global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = e
		var inp = p.player_input
		if int(t) % 25 == 0 and int(t) != int(t - delta):
			p.player_input.switch_requested = 1
		if best and bd < 40.0 and t < 160.0:
			var to: Vector3 = best.global_position - p.global_position
			var yaw := atan2(to.x, to.z)
			inp.camera_base.global_rotation.y = yaw
			var h := Vector2(to.x, to.z).length()
			inp.camera_rot.rotation.x = clampf(atan2((p.global_position.y + 1.6) - (best.global_position.y + 1.2), h), -1.2, 1.2) - 0.33
			Input.action_press("shoot")
		else:
			Input.action_release("shoot")
	if log_t > 5.0:
		log_t = 0.0
		var hp = p.hp if p else -1
		print("t=%.0f wave=%d alive=%d to_spawn=%d kills=%d hp=%.0f weapon=%d ammo=%s enemies=%d" % [t, lvl.wave, lvl.alive, lvl.to_spawn, lvl.kills, hp, p.weapon_index, str(p.ammo), get_nodes_in_group(&"enemies").size()])
		for e in get_nodes_in_group(&"enemies"):
			print("   robot pos=%s state=%d dist=%.1f sees=%s" % [str(e.global_position.snapped(Vector3.ONE*0.1)), e.state, e.global_position.distance_to(p.global_position), str(e.sees_player)])
	if lvl.game_over or t > 320.0:
		print("END t=%.0f wave=%d kills=%d game_over=%s" % [t, lvl.wave, lvl.kills, str(lvl.game_over)])
		return true
	return false
