extends SceneTree
## Throwaway visual tool: captures a screenshot of four towns with different states.
## Run as: godot --path . --script res://tools/art/town_states_capture.gd -- --out=<absolute png>

var _frames: int = 0
var _built: bool = false
var out_path: String


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	for arg: String in args:
		if arg.begins_with("--out="):
			out_path = arg.substr(6)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if not _built:
		_built = true

		var w: World = World.create(1)
		var base: Vector2 = w.towns[0]

		for i: int in range(4):
			w.towns[i] = base + Vector2(3 * i, 0)

		w.town_owner[0] = 0
		w.town_owner[1] = 1
		w.town_owner[2] = 2
		w.town_owner[3] = -1

		w.town_state[0] = 0
		w.town_state[1] = 1
		w.town_state[2] = 2
		w.town_state[3] = 0

		if w.town_lord.size() > 0:
			w.town_lord[0] = -1
		if w.town_lord.size() > 1:
			w.town_lord[1] = -1
		if w.town_lord.size() > 2:
			w.town_lord[2] = -1
		if w.town_lord.size() > 3:
			w.town_lord[3] = -1

		var ml: MapLayer = MapLayer.new()
		root.add_child(ml)
		ml.build(w)

		var cam: Camera2D = Camera2D.new()
		cam.position = w.map.center_of(int(base.x) + 5, int(base.y))
		cam.zoom = Vector2(2.0, 2.0)
		root.add_child(cam)
		cam.make_current()

	_frames += 1

	if _frames == 10:
		var img: Image = root.get_texture().get_image()
		img.save_png(out_path)
		print("TOWNCAP ", out_path, " err=0")
		quit(0)
