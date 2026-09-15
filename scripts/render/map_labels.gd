class_name MapLabels
extends CanvasLayer
## Overworld army + town labels drawn in screen space: constant size at any zoom, outlined,
## overlapping labels hidden (armies first, each group nearest the view centre first).
## Source: .warboss-horde/slices/map-labels.md.

const LAYER := 1
const FONT_SIZE := 13
const OUTLINE_SIZE := 4
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.9)
const TOWN_MIN_ZOOM := 0.35
const MAX_LABELS := 80
const NEUTRAL_TOWN_COLOR := Color(0.92, 0.9, 0.82)
const RAZED_TOWN_COLOR := Color(0.6, 0.6, 0.6)

var world: World
var camera: Camera2D
var _canvas: _Canvas


static func army_text(name: String, count: int, retreating: bool) -> String:
	var text := "%s · %d" % [name, count]
	if retreating:
		text += " (retreat)"
	return text


static func text_color(c: Color) -> Color:
	return c.lerp(Color(1, 1, 1), 0.45)


static func label_rect(anchor: Vector2, width: float) -> Rect2:
	return Rect2(anchor.x - width * 0.5, anchor.y, width, FONT_SIZE + 4)


static func resolve_overlaps(rects: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(rects.size())
	out.fill(0)

	for i in range(rects.size()):
		var intersects_any := false
		for j in range(i):
			if out[j] == 1:
				if rects[i].intersects(rects[j]):
					intersects_any = true
					break
		if not intersects_any:
			out[i] = 1

	return out


func build(w: World, cam: Camera2D) -> void:
	world = w
	camera = cam
	layer = LAYER
	_canvas = _Canvas.new()
	_canvas.labels = self
	_canvas.name = "MapLabelsCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func refresh() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func collect(xform: Transform2D, view_size: Vector2, zoom: float) -> Array:
	if world == null:
		return []

	var font: Font = ThemeDB.fallback_font
	var view_rect := Rect2(Vector2.ZERO, view_size)
	var centre := view_size * 0.5

	var armies: Array = []
	var army_rects: Array = []

	# Armies: for each stack i with alive == 1
	for i in range(world.stacks.n):
		if world.stacks.alive[i] == 1:
			var r := Tuning.STACK_RADIUS * (0.7 + 0.2 * world.stacks.tier(i))
			var anchor := xform * Vector2(world.stacks.x[i], world.stacks.y[i] + r * 0.5 + 2.0)
			var text := army_text(String(world.stacks.names[i]), world.stacks.count[i], world.stacks.state[i] == Stacks.State.RETREATING)
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var rect := label_rect(anchor, width)

			if rect.intersects(view_rect):
				var col: Color = text_color(Tuning.FACTION_COLORS[world.stacks.faction[i] % Tuning.FACTION_COLORS.size()])
				armies.append({"text": text, "rect": rect, "color": col})
				army_rects.append(rect)

	# Sort armies by distance from view centre
	var army_indices: Array = []
	for idx in range(armies.size()):
		army_indices.append(idx)
	army_indices.sort_custom(func(a: int, b: int) -> bool:
		var rect_a: Rect2 = army_rects[a]
		var rect_b: Rect2 = army_rects[b]
		var dist_a: float = rect_a.get_center().distance_squared_to(centre)
		var dist_b: float = rect_b.get_center().distance_squared_to(centre)
		return dist_a < dist_b
	)

	var sorted_armies: Array = []
	var sorted_army_rects: Array = []
	for idx in army_indices:
		sorted_armies.append(armies[idx])
		sorted_army_rects.append(army_rects[idx])

	# Towns (only when zoom >= TOWN_MIN_ZOOM)
	var towns: Array = []
	var town_rects: Array = []

	if zoom >= TOWN_MIN_ZOOM:
		for k in range(world.towns.size()):
			var tv: Vector2 = world.towns[k]
			var tile := Vector2i(int(tv.x), int(tv.y))
			var anchor := xform * (world.map.center_of(tile.x, tile.y) + Vector2(0.0, Tuning.TILE * 0.5))
			var text := NameGen.town_name(tile)
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var rect := label_rect(anchor, width)

			if rect.intersects(view_rect):
				var col: Color
				if world.town_state[k] == 2:
					col = RAZED_TOWN_COLOR
				elif world.town_owner[k] >= 0:
					col = text_color(Tuning.FACTION_COLORS[world.town_owner[k] % Tuning.FACTION_COLORS.size()])
				else:
					col = NEUTRAL_TOWN_COLOR

				towns.append({"text": text, "rect": rect, "color": col})
				town_rects.append(rect)

	# Sort towns by distance from view centre
	var town_indices: Array = []
	for idx in range(towns.size()):
		town_indices.append(idx)
	town_indices.sort_custom(func(a: int, b: int) -> bool:
		var rect_a: Rect2 = town_rects[a]
		var rect_b: Rect2 = town_rects[b]
		var dist_a: float = rect_a.get_center().distance_squared_to(centre)
		var dist_b: float = rect_b.get_center().distance_squared_to(centre)
		return dist_a < dist_b
	)

	var sorted_towns: Array = []
	var sorted_town_rects: Array = []
	for idx in town_indices:
		sorted_towns.append(towns[idx])
		sorted_town_rects.append(town_rects[idx])

	# Combine armies + towns
	var ordered: Array = []
	var ordered_rects: Array = []
	for entry in sorted_armies:
		ordered.append(entry)
	for rect in sorted_army_rects:
		ordered_rects.append(rect)
	for entry in sorted_towns:
		ordered.append(entry)
	for rect in sorted_town_rects:
		ordered_rects.append(rect)

	# Resolve overlaps
	var vis := resolve_overlaps(ordered_rects)

	# Result: entries with vis[i] == 1, stopping at MAX_LABELS
	var result: Array = []
	for i in range(ordered.size()):
		if vis[i] == 1:
			result.append(ordered[i])
			if result.size() >= MAX_LABELS:
				break

	return result


## Plain Control so `_draw()` can be overridden (CanvasLayer has no drawing surface).
class _Canvas extends Control:
	var labels   # MapLabels; untyped to avoid a self-referential class_name lookup inside this nested class.

	func _draw() -> void:
		if labels == null or labels.world == null or labels.camera == null:
			return
		var font: Font = ThemeDB.fallback_font
		var xform: Transform2D = get_viewport().get_canvas_transform()
		var view: Vector2 = get_viewport().get_visible_rect().size
		for e in labels.collect(xform, view, labels.camera.zoom.x):
			var rect: Rect2 = e["rect"]
			var base := Vector2(rect.position.x, rect.position.y + MapLabels.FONT_SIZE)
			draw_string_outline(font, base, e["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, MapLabels.FONT_SIZE, MapLabels.OUTLINE_SIZE, MapLabels.OUTLINE_COLOR)
			draw_string(font, base, e["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, MapLabels.FONT_SIZE, e["color"])
