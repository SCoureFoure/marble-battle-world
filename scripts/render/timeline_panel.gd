class_name TimelinePanel
extends CanvasLayer
## Left-edge collapsible drawer showing the last Tuning.TIMELINE_LINES lines of
## `world.events_log`, newest at the bottom. Source:
## docs/ARCHITECTURE.md §14.4, .warboss-horde/slices/drawer-timeline.md.

const LOG_WIDTH := 340.0

var world: World

var collapsed: bool = false
var _drawer: HBoxContainer
var _tab: Button
var _panel: PanelContainer
var _label: Label
var _last_len: int = -1


func build(w: World) -> void:
	world = w

	_drawer = HBoxContainer.new()
	_drawer.name = "TimelineDrawer"
	add_child(_drawer)

	_panel = PanelContainer.new()
	_panel.name = "TimelinePanelContainer"
	_drawer.add_child(_panel)

	_label = Label.new()
	_label.name = "TimelineLabel"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(LOG_WIDTH, 0.0)
	_panel.add_child(_label)

	_tab = Button.new()
	_tab.name = "TimelineTab"
	_tab.text = "<"
	_tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tab.pressed.connect(toggle_collapsed)
	_drawer.add_child(_tab)

	_last_len = -1
	_refresh()


func set_collapsed(v: bool) -> void:
	collapsed = v
	_panel.visible = not v
	_tab.text = ">" if v else "<"


func toggle_collapsed() -> void:
	set_collapsed(not collapsed)


static func drawer_pos(view: Vector2, size: Vector2) -> Vector2:
	return Vector2(0.0, (view.y - size.y) * 0.5)


func _layout() -> void:
	if _drawer == null or not is_inside_tree():
		return
	_drawer.reset_size()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_drawer.position = drawer_pos(view, _drawer.size)


func _process(_delta: float) -> void:
	if world == null:
		return
	_layout()
	if world.events_log.size() != _last_len:
		_refresh()


func _refresh() -> void:
	_last_len = world.events_log.size()
	var start := maxi(0, _last_len - Tuning.TIMELINE_LINES)
	var lines: Array = []
	for i in range(start, _last_len):
		lines.append(world.events_log[i])
	_label.text = "\n".join(lines)
