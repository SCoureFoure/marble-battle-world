extends Node2D

var state: BattleState
var sim: BattleSim
var renderer: BattleRenderer
var terrain: TerrainGrid
var terrain_layer: TerrainLayer
var label_pool: LabelPool
var hud: Label
var capture_path: String = ""
var capture_tick: int = 120
var ticks: int = 0
var sim_ms: float = 0.0
var _prev_owner: PackedInt32Array


func _ready() -> void:
	state = BattleState.new(1100, 1)
	state.spawn(350, 450, 0, 1, 1, true)
	state.spawn(1250, 450, 1, 1, 1, true)
	state.spawn_block(0, 500, Rect2(100, 100, 500, 700), -1)
	state.spawn_block(1, 500, Rect2(1000, 100, 500, 700), -1)

	terrain = TerrainGrid.new()
	terrain.setup(state.arena, Tuning.TERRAIN_CELL)
	TerrainGen.demo(terrain, state.rng)
	_prev_owner = terrain.owner.duplicate()

	sim = BattleSim.new(state)
	sim.set_terrain(terrain)

	terrain_layer = TerrainLayer.new()
	terrain_layer.name = "TerrainLayer"
	terrain_layer.grid = terrain
	add_child(terrain_layer)

	renderer = BattleRenderer.new()
	add_child(renderer)
	renderer.attach(state)

	label_pool = LabelPool.new()
	label_pool.name = "LabelPool"
	add_child(label_pool)

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
		elif arg.begins_with("--capture-tick="):
			capture_tick = int(arg.substr(15))


func _draw() -> void:
	draw_rect(state.arena, Color(0.93, 0.88, 0.75), true)
	draw_rect(state.arena, Color(0.25, 0.2, 0.15), false, 3.0)


func pos(i: int) -> Vector2:
	return Vector2(state.px[i], state.py[i])


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	sim.step(state, Tuning.DT)
	sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ticks += 1

	for event in state.events:
		var etype: int = event[0]
		var actor: int = event[1]
		var target: int = event[2]
		match etype:
			BattleState.Event.KILL:
				if actor >= 0:
					label_pool.popup("+1 kill", pos(actor), Color(0.1, 0.1, 0.1))
			BattleState.Event.LEVEL:
				label_pool.popup("LVL %d" % target, pos(actor), Color(0.6, 0.1, 0.6))
			BattleState.Event.CAPTAIN_DEAD:
				label_pool.popup("CAPTAIN DOWN", pos(target), Color(0.7, 0, 0))

	if terrain.owner != _prev_owner:
		terrain_layer.mark_dirty()
		_prev_owner = terrain.owner.duplicate()

	if capture_path != "" and ticks == capture_tick:
		_capture()


	hud.text = "fps %d  sim %.2f ms  alive %d  tick %d  f0 %d  f1 %d  winner %d" % [Engine.get_frames_per_second(), sim_ms, state.alive_count(), state.tick, state.faction_alive[0], state.faction_alive[1], sim.winner(state)]

	for f in range(state.faction_count):
		var captain: int = state.faction_captain[f]
		if captain >= 0:
			label_pool.set_captain(f, "Captain %d" % f, pos(captain))
		else:
			label_pool.hide_captain(f)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(capture_path)
	print("CAPTURE path=%s err=%d sim_ms=%.3f fps=%d alive=%d" % [capture_path, err, sim_ms, Engine.get_frames_per_second(), state.alive_count()])
	get_tree().quit()
