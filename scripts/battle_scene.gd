extends Node2D

var state: BattleState
var sim: BattleSim
var renderer: BattleRenderer
var hud: Label
var capture_path: String = ""
var ticks: int = 0
var sim_ms: float = 0.0


func _ready() -> void:
	state = BattleState.new(600, 1)
	state.spawn_block(0, 250, Rect2(100, 100, 500, 700), 1)
	state.spawn_block(1, 250, Rect2(1000, 100, 500, 700), 1)

	sim = BattleSim.new(state)

	renderer = BattleRenderer.new()
	add_child(renderer)
	renderer.attach(state)

	var cam := Camera2D.new()
	cam.position = state.arena.get_center()
	cam.zoom = Vector2(1, 1)
	add_child(cam)
	cam.make_current()

	hud = Label.new()
	hud.position = Vector2(8, 8)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.substr(10)


func _draw() -> void:
	draw_rect(state.arena, Color(0.93, 0.88, 0.75), true)
	draw_rect(state.arena, Color(0.25, 0.2, 0.15), false, 3.0)


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	sim.step(state, Tuning.DT)
	sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ticks += 1
	if capture_path != "" and ticks == 120:
		_capture()


func _process(_delta: float) -> void:
	hud.text = "fps %d  sim %.2f ms  alive %d  tick %d" % [Engine.get_frames_per_second(), sim_ms, state.alive_count(), state.tick]


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(capture_path)
	print("CAPTURE path=%s err=%d sim_ms=%.3f fps=%d alive=%d" % [capture_path, err, sim_ms, Engine.get_frames_per_second(), state.alive_count()])
	get_tree().quit()
