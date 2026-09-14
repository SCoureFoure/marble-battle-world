class_name BattleView
extends CanvasLayer
## Popup arena view for a live overworld BattleInstance: a SubViewport with
## its own Camera2D/TerrainLayer/BattleRenderer/LabelPool reading
## `inst.state` each frame. Mirrors scripts/battle_scene.gd's wiring for the
## same classes. Source: docs/ARCHITECTURE.md §11.5,
## .warboss-horde/slices/m3-world-scene.md.

var inst: BattleInstance
var world: World
var spectate_panel: SpectatePanel
var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera2D
var background: BattleBackground
var terrain_layer: TerrainLayer
var renderer: BattleRenderer
var label_pool: LabelPool
var _prev_owner: PackedInt32Array

# Post-battle aftermath (§18): set once the watched battle leaves world.battles.
var aftermath: BattleAftermath
var paused := false               # mirrored from world_scene each frame
var _aftermath_acc := 0.0
var _banner_t := 0.0
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label

const SPECTATE_CLICK_PX := 12.0
const AFTERMATH_MAX_STEPS := 4    # per frame; leftover time is dropped
const BANNER_FADE := 0.4


func _ready() -> void:
	visible = false

	container = SubViewportContainer.new()
	container.name = "Container"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(1600, 900)
	container.add_child(viewport)

	camera = Camera2D.new()
	viewport.add_child(camera)

	background = BattleBackground.new()
	background.name = "Background"
	viewport.add_child(background)

	terrain_layer = TerrainLayer.new()
	terrain_layer.name = "TerrainLayer"
	viewport.add_child(terrain_layer)

	renderer = BattleRenderer.new()
	viewport.add_child(renderer)

	label_pool = LabelPool.new()
	label_pool.name = "LabelPool"
	viewport.add_child(label_pool)

	banner = VBoxContainer.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 60.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	add_child(banner)
	banner_title = _banner_label(56, 10)
	banner_sub = _banner_label(22, 6)
	var hint := _banner_label(16, 4)
	hint.text = "Esc / right-click to close"
	hint.modulate = Color(1, 1, 1, 0.7)


func _banner_label(font_size: int, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	banner.add_child(l)
	return l


func open(instance: BattleInstance) -> void:
	_end_aftermath()
	inst = instance
	terrain_layer.grid = inst.terrain
	_prev_owner = inst.terrain.owner.duplicate() if inst.terrain != null else PackedInt32Array()
	terrain_layer.mark_dirty()
	renderer.attach(inst.state)
	_sync_palette()
	camera.position = inst.state.arena.get_center()
	camera.zoom = Vector2(1, 1)
	camera.make_current()
	visible = true
	if world != null:
		world.watched_battle = instance.id


func close() -> void:
	visible = false
	inst = null
	_end_aftermath()
	if world != null:
		world.watched_battle = -1


## The world has finished this battle (BattleBridge.finish removed it from
## world.battles), so its state is ours to animate: banner + BattleAftermath.
func _start_aftermath() -> void:
	var side: int = inst.sim.winner(inst.state)
	aftermath = BattleAftermath.new(inst.state, inst.sim, side)
	_aftermath_acc = 0.0
	var lines := BattleAftermath.banner_lines(inst, world, side)
	banner_title.text = lines[0]
	banner_sub.text = lines[1]
	var col := Color(0.92, 0.92, 0.92)
	if side >= 0:
		col = BattleRenderer.faction_color(side, renderer.palette)
	banner_title.add_theme_color_override("font_color", col)
	_banner_t = 0.0
	banner.modulate.a = 0.0
	banner.visible = true


func _end_aftermath() -> void:
	aftermath = null
	if banner != null:
		banner.visible = false


## Local battle faction -> the world faction's overworld colour, so a side
## is drawn in the same colour as its stacks and borders. Allies sharing a
## local index take the colour of the faction that opened that side. Rebuilt
## every frame because stacks can join mid-battle and take a new index.
static func build_palette(instance: BattleInstance, w: World) -> PackedInt32Array:
	var pal := PackedInt32Array()
	pal.resize(instance.faction_map.size())
	for lf in range(instance.faction_map.size()):
		var wf: int = instance.faction_map[lf]
		if wf < 0:
			pal[lf] = -1
		elif w != null and wf < w.faction_color.size():
			pal[lf] = w.faction_color[wf]
		else:
			pal[lf] = wf
	return pal


func _sync_palette() -> void:
	var pal := build_palette(inst, world)
	if pal == renderer.palette:
		return
	renderer.palette = pal
	terrain_layer.palette = pal
	terrain_layer.mark_dirty()


func pos(i: int) -> Vector2:
	return Vector2(inst.state.px[i], inst.state.py[i])


func _process(dt: float) -> void:
	if not visible or inst == null:
		return

	if aftermath == null and world != null and not world.battles.has(inst):
		_start_aftermath()
	if aftermath != null:
		# real frame time, not world speed: the aftermath looks the same at x1 and x50
		if not paused:
			_aftermath_acc += dt
			var steps := 0
			while _aftermath_acc >= Tuning.DT and steps < AFTERMATH_MAX_STEPS:
				aftermath.step(Tuning.DT)
				_aftermath_acc -= Tuning.DT
				steps += 1
			if steps == AFTERMATH_MAX_STEPS:
				_aftermath_acc = 0.0
		_banner_t += dt
		banner.modulate.a = clampf(_banner_t / BANNER_FADE, 0.0, 1.0)

	# renderer.refresh() runs on its own via BattleRenderer._process (it is a
	# child of the SubViewport); calling it again here would rebuild all three
	# multimesh buffers twice per frame.

	renderer.ingest(inst.state)
	_sync_palette()

	for event in inst.state.events:
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

	if inst.terrain != null and inst.terrain.owner != _prev_owner:
		terrain_layer.mark_dirty()
		_prev_owner = inst.terrain.owner.duplicate()

	for f in range(inst.state.faction_count):
		var captain: int = inst.state.faction_captain[f]
		if captain >= 0 and inst.state.state[captain] != BattleState.State.DEAD:
			label_pool.set_captain(f, "Captain %d" % f, pos(captain))
		else:
			label_pool.hide_captain(f)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and kev.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_spectate_marble(mb.position)


## m6-ui.md §fiat: nearest marble within 12 px of the SubViewport-space
## click. `mb.position` is in the container's local (window-scaled) space;
## the container stretches the fixed-size viewport to fill the screen, so it
## is rescaled to viewport pixels before comparing against marble positions
## projected through the viewport's own canvas_transform.
func _try_spectate_marble(container_click: Vector2) -> void:
	if spectate_panel == null or inst == null:
		return
	var container_size: Vector2 = container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return
	var vp_click: Vector2 = container_click * (Vector2(viewport.size) / container_size)

	var s := inst.state
	var best := -1
	var best_dist := INF
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var vp_pos: Vector2 = viewport.canvas_transform * Vector2(s.px[i], s.py[i])
		var d := vp_click.distance_to(vp_pos)
		if d < best_dist:
			best_dist = d
			best = i

	if best == -1 or best_dist > SPECTATE_CLICK_PX:
		return
	if best >= inst.unit_of.size():
		return
	spectate_panel.show_unit(world, inst.unit_of[best])
