extends Node2D
## Overworld scene root. Source: docs/ARCHITECTURE.md §11,
## .warboss-horde/slices/m3-world-scene.md.

const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15
const DRAG_THRESHOLD := 6.0
const TIME_CONTROLS_POS := Vector2(8, 28)

var world: World
var map_layer: MapLayer
var stack_layer: StackLayer
var label_pool: LabelPool
var map_labels: MapLabels
var battle_view: BattleView
var ledger_panel: LedgerPanel
var plinko_view: PlinkoView
var spectate_panel: SpectatePanel
var timeline_panel: TimelinePanel
var time_controls: HBoxContainer
var camera: Camera2D
var hud: Label
var follow_label: Label

var followed_unit: int = -1
var followed_stack: int = -1
var _follow_shown: int = -1
var _gen_unit: int = -1
var _followed_gen: int = 0

var steps_per_frame: int = 1
var paused: bool = false
var max_mode: bool = false
var world_ms: float = 0.0
var ticks: int = 0
var map_seed: int = -1

const SAVE_PATH := "user://save1.bin"
var _message: String = ""
var _message_timer: float = 0.0

var capture_path: String = ""
var capture_tick: int = 600
var capture_battle: bool = false

var _dragging: bool = false
var _drag_button: int = -1

var panels_visible: bool = true
var _left_down: bool = false
var _left_press: Vector2 = Vector2.ZERO
var _left_dragging: bool = false


static func is_drag(press: Vector2, now: Vector2) -> bool:
	return press.distance_to(now) > DRAG_THRESHOLD


static func clamp_to_map(p: Vector2, map_size: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.0, map_size.x), clampf(p.y, 0.0, map_size.y))


static func set_panels_visible(panels: Array, v: bool) -> void:
	for element in panels:
		if element == null:
			continue
		if element is CanvasLayer:
			element.visible = v


func _connect_spectate() -> void:
	spectate_panel.follow_requested.connect(_on_follow_requested)
	spectate_panel.center_requested.connect(_on_center_requested)


func _on_follow_requested(stack_id: int) -> void:
	if stack_id < 0 or stack_id >= world.stacks.n or world.stacks.alive[stack_id] == 0:
		return
	var cap: int = world.stacks.captain_unit[stack_id]
	if cap < 0:
		return
	followed_unit = cap
	followed_stack = stack_id
	_follow_shown = stack_id


func _on_center_requested(stack_id: int) -> void:
	if stack_id < 0 or stack_id >= world.stacks.n:
		return
	followed_unit = -1
	followed_stack = -1
	camera.position = clamp_to_map(Vector2(world.stacks.x[stack_id], world.stacks.y[stack_id]), _map_size())


func _ready() -> void:
	var seed_val: int = -1
	var follow_arg := false
	var zoom_arg: float = -1.0
	var panels_arg: int = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_val = int(arg.substr(7))
		elif arg.begins_with("--capture="):
			capture_path = arg.substr(10)
		elif arg.begins_with("--capture-tick="):
			capture_tick = int(arg.substr(15))
		elif arg.begins_with("--capture-battle="):
			capture_battle = int(arg.substr(17)) == 1
		elif arg.begins_with("--follow="):
			follow_arg = int(arg.substr(9)) == 1
		elif arg.begins_with("--zoom="):
			zoom_arg = float(arg.substr(7))
		elif arg.begins_with("--panels="):
			panels_arg = int(arg.substr(9))

	if seed_val < 0:
		# Fresh map on every plain run; drawn once here, outside the sim, so the run stays replayable with --seed=.
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.randomize()
		seed_val = seed_rng.randi_range(1, 2147483647)
	map_seed = seed_val
	print("WORLD seed=%d" % seed_val)

	world = World.create(seed_val)

	if follow_arg:
		_start_capture_follow()

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
	if zoom_arg > 0.0:
		camera.zoom = Vector2(zoom_arg, zoom_arg)
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

	map_labels = MapLabels.new()
	map_labels.name = "MapLabels"
	add_child(map_labels)
	map_labels.build(world, camera)

	battle_view = BattleView.new()
	battle_view.name = "BattleView"
	add_child(battle_view)
	battle_view.world = world

	ledger_panel = LedgerPanel.new()
	ledger_panel.name = "LedgerPanel"
	add_child(ledger_panel)
	ledger_panel.build(world)

	plinko_view = PlinkoView.new()
	plinko_view.name = "PlinkoView"
	add_child(plinko_view)
	plinko_view.build(world)

	spectate_panel = SpectatePanel.new()
	spectate_panel.name = "SpectatePanel"
	add_child(spectate_panel)
	spectate_panel.build(world)
	battle_view.spectate_panel = spectate_panel
	_connect_spectate()

	timeline_panel = TimelinePanel.new()
	timeline_panel.name = "TimelinePanel"
	add_child(timeline_panel)
	timeline_panel.build(world)

	hud = Label.new()
	hud.position = Vector2(8, 8)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(hud)

	follow_label = Label.new()
	follow_label.name = "FollowLabel"
	follow_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	follow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	follow_label.visible = followed_unit != -1
	layer.add_child(follow_label)

	_build_time_controls()

	if panels_arg == 0:
		panels_visible = false
	set_panels_visible(_panel_nodes(), panels_visible)


func _panel_nodes() -> Array:
	return [ledger_panel, spectate_panel, plinko_view, timeline_panel]


func _toggle_panels() -> void:
	panels_visible = not panels_visible
	set_panels_visible(_panel_nodes(), panels_visible)


func _map_size() -> Vector2:
	return Vector2(world.map.cols * Tuning.TILE, world.map.rows * Tuning.TILE)


func _build_time_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TimeControlsLayer"
	add_child(layer)

	time_controls = HBoxContainer.new()
	time_controls.name = "TimeControls"
	layer.add_child(time_controls)

	var btn_pause := Button.new()
	btn_pause.text = "⏸"
	btn_pause.pressed.connect(_toggle_pause)
	time_controls.add_child(btn_pause)

	var btn_1x := Button.new()
	btn_1x.text = "1x"
	btn_1x.pressed.connect(func(): _set_speed(1))
	time_controls.add_child(btn_1x)

	var btn_5x := Button.new()
	btn_5x.text = "5x"
	btn_5x.pressed.connect(func(): _set_speed(5))
	time_controls.add_child(btn_5x)

	var btn_50x := Button.new()
	btn_50x.text = "50x"
	btn_50x.pressed.connect(func(): _set_speed(50))
	time_controls.add_child(btn_50x)

	var btn_max := Button.new()
	btn_max.text = "MAX"
	btn_max.pressed.connect(_set_max)
	time_controls.add_child(btn_max)

	var btn_ui := Button.new()
	btn_ui.text = "UI"
	btn_ui.pressed.connect(_toggle_panels)
	time_controls.add_child(btn_ui)

	var btn_log := Button.new()
	btn_log.text = "Log"
	btn_log.pressed.connect(func(): timeline_panel.toggle_collapsed())
	time_controls.add_child(btn_log)

	var btn_factions := Button.new()
	btn_factions.text = "Factions"
	btn_factions.pressed.connect(func(): ledger_panel.toggle_collapsed())
	time_controls.add_child(btn_factions)

	time_controls.position = TIME_CONTROLS_POS


## `--follow=1`: follow the captain of the last stack (highest id) whose
## captain has `hero == 1` (a free company); none if no such stack.
func _start_capture_follow() -> void:
	var target_stack := -1
	var target_unit := -1
	for i in range(world.stacks.n):
		var cap: int = world.stacks.captain_unit[i]
		if cap >= 0 and world.units.hero[cap] == 1:
			target_stack = i
			target_unit = cap
	if target_stack != -1:
		followed_unit = target_unit
		followed_stack = target_stack


func _toggle_pause() -> void:
	paused = not paused


func _set_speed(v: int) -> void:
	steps_per_frame = v
	max_mode = false


func _set_max() -> void:
	max_mode = true


func _speed_label() -> String:
	if paused:
		return "PAUSED"
	if max_mode:
		return "MAX"
	return "x%d" % steps_per_frame


func _show_message(text: String, duration: float) -> void:
	_message = text
	_message_timer = duration


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if not paused:
		if max_mode:
			# MAX runs steps until Tuning.MAX_FRAME_MS elapsed in that frame
			# (at least one step, even if a single step already blows the
			# budget).
			while true:
				WorldSim.step(world, Tuning.DT)
				if (Time.get_ticks_usec() - t0) / 1000.0 >= Tuning.MAX_FRAME_MS:
					break
		else:
			for k in steps_per_frame:
				WorldSim.step(world, Tuning.DT)
	world_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ticks += 1
	battle_view.paused = paused

	if followed_unit != -1:
		if followed_unit != _gen_unit:
			_gen_unit = followed_unit
			_followed_gen = world.units.gen[followed_unit]
		elif world.units.gen[followed_unit] != _followed_gen:
			followed_unit = -1
			followed_stack = -1
			_gen_unit = -1
		if followed_unit != -1:
			var r := Follow.step(world, followed_unit, followed_stack)
			if r[2] != "":
				world.log_event(r[2])
			followed_unit = r[0]
			followed_stack = r[1]
			if followed_unit != -1 and followed_stack >= 0:
				camera.position = Vector2(world.stacks.x[followed_stack], world.stacks.y[followed_stack])
				if followed_stack != _follow_shown:
					spectate_panel.show_stack(followed_stack)
					_follow_shown = followed_stack
	if followed_unit == -1:
		_follow_shown = -1
	follow_label.visible = followed_unit != -1
	if followed_unit != -1:
		follow_label.text = "Following: %s — %s" % [
			world.units.names.get(followed_unit, "Unit %d" % followed_unit),
			world.stacks.label(followed_stack),
		]

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
		map_labels.refresh()
	map_labels.visible = not battle_view.visible

	var alive_stacks := 0
	var total_units := 0
	for i in range(world.stacks.n):
		if world.stacks.alive[i] == 1:
			alive_stacks += 1
			total_units += world.stacks.count[i]

	if _message_timer > 0.0:
		_message_timer -= delta
		hud.text = _message
	else:
		hud.text = "seed %s  t %.0fs  stacks %d  battles %d  units %d  fps %d  world %.1f ms  %s" % [
			str(map_seed) if map_seed >= 0 else "-",
			world.time, alive_stacks, world.battles.size(), total_units,
			Engine.get_frames_per_second(), world_ms, _speed_label(),
		]


func _unhandled_input(event: InputEvent) -> void:
	# Time controls and save/load are global: they work whether or not the
	# battle view is open.
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed:
			match kev.keycode:
				KEY_SPACE:
					_toggle_pause()
					return
				KEY_1:
					_set_speed(1)
					return
				KEY_2:
					_set_speed(5)
					return
				KEY_3:
					_set_speed(50)
					return
				KEY_4:
					_set_max()
					return
				KEY_F5:
					SaveGame.save(world, SAVE_PATH)
					return
				KEY_F9:
					_try_load()
					return
				KEY_F:
					_toggle_follow()
					return
				KEY_H:
					_toggle_panels()
					return
				KEY_L:
					timeline_panel.toggle_collapsed()
					return
				KEY_K:
					ledger_panel.toggle_collapsed()
					return

	if battle_view.visible:
		_left_down = false
		_left_dragging = false
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_down = true
				_left_press = mb.position
				_left_dragging = false
			else:
				if _left_down and not _left_dragging:
					if not _try_open_battle():
						_try_spectate_stack()
				_left_down = false
				_left_dragging = false
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
		var mm := event as InputEventMouseMotion
		if _left_down and not _left_dragging and is_drag(_left_press, mm.position):
			_left_dragging = true
			followed_unit = -1
			followed_stack = -1
		if _dragging or _left_dragging:
			camera.position = clamp_to_map(camera.position - mm.relative / camera.zoom.x, _map_size())


## `F`: following -> stop; else if the spectate panel shows a stack with a
## live captain -> start following that captain.
func _toggle_follow() -> void:
	if followed_unit != -1:
		followed_unit = -1
		followed_stack = -1
		return
	var s := spectate_panel.shown_stack
	if s >= 0 and world.stacks.captain_unit[s] >= 0:
		followed_unit = world.stacks.captain_unit[s]
		followed_stack = s
		_follow_shown = s


## Nearest alive stack to the click, within STACK_RADIUS * 2 / zoom world
## units (m6-ui.md §fiat spectate click hit test).
func _try_spectate_stack() -> void:
	var wp := get_global_mouse_position()
	var threshold: float = Tuning.STACK_RADIUS * 2.0 / camera.zoom.x
	var stacks := world.stacks
	var best := -1
	var best_dist := INF
	for i in range(stacks.n):
		if stacks.alive[i] == 0:
			continue
		var d := Vector2(stacks.x[i], stacks.y[i]).distance_to(wp)
		if d < best_dist:
			best_dist = d
			best = i
	if best != -1 and best_dist <= threshold:
		spectate_panel.show_stack(best)


func _try_load() -> void:
	var loaded: World = SaveGame.load(SAVE_PATH)
	if loaded == null:
		_show_message("load failed", 3.0)
		return
	_rebuild_layers(loaded)


## F9 success path: layers re-created from the new World, camera kept
## (m6-ui.md §fiat).
func _rebuild_layers(new_world: World) -> void:
	world = new_world
	map_seed = -1
	battle_view.close()
	_gen_unit = -1

	var ledger_was_collapsed: bool = ledger_panel.collapsed
	var timeline_was_collapsed: bool = timeline_panel.collapsed

	remove_child(map_layer)
	map_layer.queue_free()
	remove_child(stack_layer)
	stack_layer.queue_free()
	remove_child(ledger_panel)
	ledger_panel.queue_free()
	remove_child(plinko_view)
	plinko_view.queue_free()
	remove_child(spectate_panel)
	spectate_panel.queue_free()
	remove_child(timeline_panel)
	timeline_panel.queue_free()

	map_layer = MapLayer.new()
	map_layer.name = "MapLayer"
	add_child(map_layer)
	map_layer.build(world)

	stack_layer = StackLayer.new()
	stack_layer.name = "StackLayer"
	add_child(stack_layer)
	stack_layer.world = world
	stack_layer.camera = camera
	stack_layer.label_pool = label_pool
	map_labels.world = world

	ledger_panel = LedgerPanel.new()
	ledger_panel.name = "LedgerPanel"
	add_child(ledger_panel)
	ledger_panel.build(world)
	ledger_panel.set_collapsed(ledger_was_collapsed)

	plinko_view = PlinkoView.new()
	plinko_view.name = "PlinkoView"
	add_child(plinko_view)
	plinko_view.build(world)

	spectate_panel = SpectatePanel.new()
	spectate_panel.name = "SpectatePanel"
	add_child(spectate_panel)
	spectate_panel.build(world)
	battle_view.spectate_panel = spectate_panel
	_connect_spectate()

	timeline_panel = TimelinePanel.new()
	timeline_panel.name = "TimelinePanel"
	add_child(timeline_panel)
	timeline_panel.build(world)
	timeline_panel.set_collapsed(timeline_was_collapsed)

	battle_view.world = world

	set_panels_visible(_panel_nodes(), panels_visible)


func _zoom(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


## Returns true when the click opened a battle (so callers can fall back to
## spectate-stack hit testing otherwise).
func _try_open_battle() -> bool:
	var wp := get_global_mouse_position()

	var tile := world.map.tile_of(wp.x, wp.y)
	for b in world.battles:
		var inst: BattleInstance = b
		if inst.tile == tile:
			battle_view.open(inst)
			return true

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
					return true
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(capture_path)
	print("CAPTURE path=%s err=%d world_ms=%.3f fps=%d stacks=%d battles=%d units=%d" % [
		capture_path, err, world_ms, Engine.get_frames_per_second(),
		world.stacks.n, world.battles.size(), world.units.n,
	])
	get_tree().quit()
