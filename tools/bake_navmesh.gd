extends SceneTree
## Запекает навигационную сетку уровня: godot --headless --path <проект> -s bake_navmesh.gd

func _initialize() -> void:
	var lvl: Node3D = load("res://level/level.tscn").instantiate()
	# Не запускаем скрипт уровня (волны и т.п.) — нужна только геометрия.
	lvl.set_script(null)
	root.add_child(lvl)
	await physics_frame
	await physics_frame
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.9
	nm.agent_height = 2.4
	nm.agent_max_climb = 0.45
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.region_min_size = 8.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, lvl)
	print("vertices in source: ", src.get_vertices().size())
	var t := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("baked in ", Time.get_ticks_msec() - t, " ms, polygons: ", nm.get_polygon_count(), " verts: ", nm.vertices.size())
	var err := ResourceSaver.save(nm, "res://level/navmesh.tres")
	print("save: ", err)
	quit()
