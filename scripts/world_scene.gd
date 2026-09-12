extends Node2D
## Overworld scene root. Source: docs/ARCHITECTURE.md §11,
## .warboss-horde/slices/m3-world-scene.md.

const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15

var world: World
var map_layer: MapLayer
var stack_layer: StackLayer
var label_pool: LabelPool
var battle_view: BattleView
var ledger_panel: LedgerPanel
var plinko_view: PlinkoView
var camera: Camera2D
var hud: Label

var steps_per_frame: int = 1
var world_ms: float = 0.0
var ticks: int = 0

var capture_path: String = ""
var capture_tick: int = 600
var capture_battle: bool = false

var _dragging: bool = false
var _drag_button: int = -1


func _ready() -> void:
	var seed_val := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_val = int(arg.substr(7))
		elif arg.begins_with("--capture="):
			capture_path = arg.substr(10)
		elif arg.begins_with("--capture-tick="):
			capture_tick = int(arg.substr(15))
		elif arg.begins_with("--capture-battle="):
			capture_battle = int(arg.substr(17)) == 1

	world = World.create(seed_val)

	map_layer = MapLayer.new()
	map_layer.name = "MapLayer"
	add_child(map_layer)
	map_layer.build(world)

	stack_layer = StackLayer.new()
	stack_layer.name = "StackLayer"
	add_child(stack_layer)
	stack_layer.world = world

	camera = Camera2D.new()
	var capital: Vector2 = world.towns[0]
	camera.position = world.map.center_of(int(capital.x), int(capital.y))
	camera.zoom = Vector2(0.6, 0.6)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.map.cols * Tuning.TILE)
	camera.limit_bottom = int(world.map.rows * Tuning.TILE)
	add_child(camera)
	camera.make_current()
	stack_layer.camera = camera

	label_pool = LabelPool.new()
	label_pool.name = "LabelPool"
	add_child(label_pool)
	stack_layer.label_pool = label_pool

	battle_view = BattleView.new()
	battle_view.name = "BattleView"
	add_child(battle_view)

	ledger_panel = LedgerPanel.new()
	ledger_panel.name = "LedgerPanel"
	add_child(ledger_panel)
	ledger_panel.build(world)

	plinko_view = PlinkoView.new()
	plinko_view.name = "PlinkoView"
	add_child(plinko_view)
	plinko_view.build(world)

	hud = Label.new()
	hud.position = Vector2(8, 8)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for k in steps_per_frame:
		WorldSim.step(world, Tuning.DT)
	world_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ticks += 1

	if capture_path != "" and ticks == capture_tick:
		if capture_battle and not battle_view.visible and world.battles.size() > 0:
			battle_view.open(world.battles[0])
		_capture()


	# The battle view fully covers the world view while open, so skip the
	# world's own redraw/label work then (map layer redraws on demand only,
	# never per frame at all; stack layer redraw + label sort/update are
	# heavy per-frame work not worth doing while hidden).
	if not battle_view.visible:
		map_layer.refresh_if_owner_changed()
		stack_layer.queue_redraw()
		stack_layer.update_labels()

	var alive_stacks := 0
	var total_units := 0
	for i in range(world.stacks.n):
		if world.stacks.alive[i] == 1:
			alive_stacks += 1
			total_units += world.stacks.count[i]

	hud.text = "t %.0fs  stacks %d  battles %d  units %d  fps %d  world %.1f ms  x%d" % [
		world.time, alive_stacks, world.battles.size(), total_units,
		Engine.get_frames_per_second(), world_ms, steps_per_frame,
	]


func _unhandled_input(event: InputEvent) -> void:
	if battle_view.visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_open_battle()
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging = true
				_drag_button = mb.button_index
			elif mb.button_index == _drag_button:
				_dragging = false
				_drag_button = -1
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion:
		if _dragging:
			var mm := event as InputEventMouseMotion
			camera.position -= mm.relative / camera.zoom.x
	elif event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed:
			match kev.keycode:
				KEY_1:
					steps_per_frame = 1
				KEY_2:
					steps_per_frame = 5
				KEY_3:
					steps_per_frame = 50


func _zoom(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


func _try_open_battle() -> void:
	var wp := get_global_mouse_position()

	var tile := world.map.tile_of(wp.x, wp.y)
	for b in world.battles:
		var inst: BattleInstance = b
		if inst.tile == tile:
			battle_view.open(inst)
			return

	var stacks := world.stacks
	for i in range(stacks.n):
		if stacks.alive[i] == 0 or stacks.state[i] != Stacks.State.BATTLE:
			continue
		var pos := Vector2(stacks.x[i], stacks.y[i])
		if pos.distance_to(wp) <= Tuning.STACK_RADIUS * 2.0:
			var bid := stacks.battle_id[i]
			for b2 in world.battles:
				var inst2: BattleInstance = b2
				if inst2.id == bid:
					battle_view.open(inst2)
					return


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(capture_path)
	print("CAPTURE path=%s err=%d world_ms=%.3f fps=%d stacks=%d battles=%d units=%d" % [
		capture_path, err, world_ms, Engine.get_frames_per_second(),
		world.stacks.n, world.battles.size(), world.units.n,
	])
	get_tree().quit()
