class_name TimelinePanel
extends CanvasLayer
## Top-left scrolling log of the last Tuning.TIMELINE_LINES lines of
## `world.events_log`, newest at the bottom. Source:
## docs/ARCHITECTURE.md §14.4, .warboss-horde/slices/m6-ui.md.

var world: World

var _label: Label
var _last_len: int = -1


func build(w: World) -> void:
	world = w

	_label = Label.new()
	_label.name = "TimelineLabel"
	# Below the HUD label, which sits at (8, 8).
	_label.position = Vector2(8, 28)
	add_child(_label)

	_last_len = -1
	_refresh()


func _process(_delta: float) -> void:
	if world == null:
		return
	if world.events_log.size() != _last_len:
		_refresh()


func _refresh() -> void:
	_last_len = world.events_log.size()
	var start := maxi(0, _last_len - Tuning.TIMELINE_LINES)
	var lines: Array = []
	for i in range(start, _last_len):
		lines.append(world.events_log[i])
	_label.text = "\n".join(lines)
