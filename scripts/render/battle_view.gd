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

const SPECTATE_CLICK_PX := 12.0


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


func open(instance: BattleInstance) -> void:
	inst = instance
	terrain_layer.grid = inst.terrain
	_prev_owner = inst.terrain.owner.duplicate() if inst.terrain != null else PackedInt32Array()
	terrain_layer.mark_dirty()
	renderer.attach(inst.state)
	camera.position = inst.state.arena.get_center()
	camera.zoom = Vector2(1, 1)
	camera.make_current()
	visible = true
	if world != null:
		world.watched_battle = instance.id


func close() -> void:
	visible = false
	inst = null
	if world != null:
		world.watched_battle = -1


func pos(i: int) -> Vector2:
	return Vector2(inst.state.px[i], inst.state.py[i])


func _process(_dt: float) -> void:
	if not visible or inst == null:
		return

	# renderer.refresh() runs on its own via BattleRenderer._process (it is a
	# child of the SubViewport); calling it again here would rebuild all three
	# multimesh buffers twice per frame.

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
		if captain >= 0:
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
