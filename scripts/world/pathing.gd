class_name Pathing extends RefCounted
## AStarGrid2D wrapper over WorldMap. See docs/ARCHITECTURE.md §11.4.

var grid: AStarGrid2D


func _init(m: WorldMap) -> void:
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, m.cols, m.rows)
	grid.cell_size = Vector2(Tuning.TILE, Tuning.TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	_apply(m)


func refresh(m: WorldMap) -> void:
	_apply(m)


func _apply(m: WorldMap) -> void:
	for ty in m.rows:
		for tx in m.cols:
			var p := Vector2i(tx, ty)
			var ok := m.passable(tx, ty)
			grid.set_point_solid(p, not ok)
			if ok:
				grid.set_point_weight_scale(p, m.cost_at(tx, ty))


func find(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	if from == to:
		return PackedVector2Array()
	var raw := grid.get_point_path(from, to)
	if raw.is_empty():
		return PackedVector2Array()
	# get_point_position (used internally by get_point_path) returns
	# id * cell_size + offset — the cell's top-left corner, not its centre —
	# so shift by half a cell to land on tile centres (see fork note).
	var half := grid.cell_size / 2.0
	var out := PackedVector2Array()
	for i in range(1, raw.size()):
		out.append(raw[i] + half)
	return out
