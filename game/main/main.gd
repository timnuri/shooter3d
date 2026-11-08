extends Node


func _ready() -> void:
	multiplayer.server_relay = false
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = 60
	randomize()
	get_tree().quit_on_go_back = false
	go_to_main_menu()


func go_to_main_menu() -> void:
	var menu: PackedScene = ResourceLoader.load("res://ui/main_menu.tscn")
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	change_scene_to_packed(menu)


func replace_main_scene(resource: PackedScene) -> void:
	call_deferred("change_scene_to_packed", resource)


func change_scene_to_packed(resource: PackedScene) -> void:
	var node: Node = resource.instantiate()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(node)
	if node.has_signal(&"quit"):
		node.quit.connect(go_to_main_menu)
	if node.has_signal(&"replace_main_scene"):
		node.replace_main_scene.connect(replace_main_scene)
