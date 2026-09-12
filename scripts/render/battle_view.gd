class_name BattleView
extends CanvasLayer
## Popup arena view for a live overworld BattleInstance: a SubViewport with
## its own Camera2D/TerrainLayer/BattleRenderer/LabelPool reading
## `inst.state` each frame. Mirrors scripts/battle_scene.gd's wiring for the
## same classes. Source: docs/ARCHITECTURE.md §11.5,
## .warboss-horde/slices/m3-world-scene.md.

var inst: BattleInstance
var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera2D
var background: BattleBackground
var terrain_layer: TerrainLayer
var renderer: BattleRenderer
var label_pool: LabelPool
var _prev_owner: PackedInt32Array


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


func close() -> void:
	visible = false
	inst = null


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
