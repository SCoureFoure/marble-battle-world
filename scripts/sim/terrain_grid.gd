class_name TerrainGrid extends RefCounted
## Arena cell grid: friction / slope / obstacle sample. Source: docs/ARCHITECTURE.md §10.3.

enum Kind { PLAIN = 0, MUD = 1, COBBLE = 2, ICE = 3, WATER = 4, ROCK = 5, TREE = 6, TOWER = 7, FIRE = 8, SPIKE = 9, FLOWERS = 10 }

var cols: int
var rows: int
var cell: float
var origin: Vector2
var kind: PackedByteArray          # cols*rows, Kind
var slope_x: PackedFloat32Array
var slope_y: PackedFloat32Array
var owner: PackedInt32Array        # tower owner faction, -1 none
var friction: PackedFloat32Array   # per cell, = friction_of(kind[c])
var near_solid: PackedByteArray    # per cell, 1 if any cell in its 3x3 neighbourhood is solid
var dirty: bool = true


func setup(bounds: Rect2, cell_size: float) -> void:
	origin = bounds.position
	cell = cell_size
	cols = maxi(1, ceili(bounds.size.x / cell_size))
	rows = maxi(1, ceili(bounds.size.y / cell_size))
	var n := cols * rows
	kind.resize(n)
	kind.fill(0)
	slope_x.resize(n)
	slope_x.fill(0.0)
	slope_y.resize(n)
	slope_y.fill(0.0)
	owner.resize(n)
	owner.fill(-1)
	dirty = true


func finalize() -> void:
	var n := cols * rows
	friction.resize(n)
	near_solid.resize(n)
	for i in range(n):
		friction[i] = friction_of(kind[i])
	for cy in range(rows):
		for cx in range(cols):
			var c := cy * cols + cx
			var solid := false
			for gx in range(cx - 1, cx + 2):
				if gx < 0 or gx >= cols:
					continue
				for gy in range(cy - 1, cy + 2):
					if gy < 0 or gy >= rows:
						continue
					if is_solid(kind[gy * cols + gx]):
						solid = true
			near_solid[c] = 1 if solid else 0
	dirty = false


func cell_at(x: float, y: float) -> int:
	var cx := clampi(int((x - origin.x) / cell), 0, cols - 1)
	var cy := clampi(int((y - origin.y) / cell), 0, rows - 1)
	return cy * cols + cx


func kind_at(x: float, y: float) -> int:
	return kind[cell_at(x, y)]


func friction_of(k: int) -> float:
	var keep_frac: float = Tuning.DRAG_KEEP_PER_S[k]
	return pow(keep_frac, Tuning.DT)


static func is_solid(k: int) -> bool:
	return k == Kind.ROCK or k == Kind.TREE


func cell_center(c: int) -> Vector2:
	return origin + Vector2((c % cols) + 0.5, (c / cols) + 0.5) * cell


func set_cell(cx: int, cy: int, k: int) -> void:
	if cx < 0 or cx >= cols or cy < 0 or cy >= rows:
		return
	kind[cy * cols + cx] = k
	dirty = true


func fill_rect(cx0: int, cy0: int, cx1: int, cy1: int, k: int) -> void:
	var x0 := clampi(cx0, 0, cols - 1)
	var x1 := clampi(cx1, 0, cols - 1)
	var y0 := clampi(cy0, 0, rows - 1)
	var y1 := clampi(cy1, 0, rows - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			kind[cy * cols + cx] = k
	dirty = true


func set_slope(cx: int, cy: int, v: Vector2) -> void:
	if cx < 0 or cx >= cols or cy < 0 or cy >= rows:
		return
	var c := cy * cols + cx
	slope_x[c] = v.x
	slope_y[c] = v.y
