extends SceneTree
## Проверка: все скрипты проекта компилируются.
func _initialize() -> void:
	var bad := 0
	for path in _scan("res://"):
		var s = load(path)
		if s == null or (s is GDScript and not s.can_instantiate() and not path.ends_with("check_scripts.gd")):
			print("FAIL ", path)
			bad += 1
	print("CHECK DONE, failed: ", bad)
	quit(1 if bad > 0 else 0)

func _scan(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with("."):
			continue
		out += _scan(dir.path_join(d))
	return out
