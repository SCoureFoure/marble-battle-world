class_name SpatialHash extends RefCounted

var cell_size: float
var origin: Vector2
var cols: int
var rows: int
var cell_start: PackedInt32Array   # size cols*rows + 1; cell c owns entries[cell_start[c] .. cell_start[c+1])
var entries: PackedInt32Array      # marble indices grouped by cell (counting sort)
var cell_of: PackedInt32Array      # size >= n; cell id per marble, -1 if excluded (DEAD)
var scratch: PackedInt32Array      # capacity Tuning.MAX_NEIGHBORS; filled by gather()

func setup(bounds: Rect2, cell: float) -> void:
	origin = bounds.position
	cell_size = cell
	cols = maxi(1, ceili(bounds.size.x / cell))
	rows = maxi(1, ceili(bounds.size.y / cell))
	cell_start.resize(cols * rows + 1)
	scratch.resize(Tuning.MAX_NEIGHBORS)

func cell_at(x: float, y: float) -> int:
	var cx := clampi(int((x - origin.x) / cell_size), 0, cols - 1)
	var cy := clampi(int((y - origin.y) / cell_size), 0, rows - 1)
	return cy * cols + cx

func build(px: PackedFloat32Array, py: PackedFloat32Array, state: PackedInt32Array, n: int) -> void:
	if cell_of.size() != n:
		cell_of.resize(n)
	if entries.size() != n:
		entries.resize(n)
	cell_start.fill(0)
	var cell_count := cols * rows
	for i in n:
		if state[i] == 2:
			cell_of[i] = -1
		else:
			var c := cell_at(px[i], py[i])
			cell_of[i] = c
			cell_start[c + 1] += 1
	for c in range(1, cell_count + 1):
		cell_start[c] += cell_start[c - 1]
	var fill := cell_start.duplicate()
	for i in n:
		var c := cell_of[i]
		if c >= 0:
			entries[fill[c]] = i
			fill[c] += 1

func gather(x: float, y: float) -> int:
	var cols_l := cols
	var rows_l := rows
	var cx := clampi(int((x - origin.x) / cell_size), 0, cols_l - 1)
	var cy := clampi(int((y - origin.y) / cell_size), 0, rows_l - 1)
	var gy0 := maxi(0, cy - 1)
	var gy1 := mini(rows_l - 1, cy + 1)
	var gx0 := maxi(0, cx - 1)
	var gx1 := mini(cols_l - 1, cx + 1)
	var k := 0
	var cap := scratch.size()
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			var c := gy * cols_l + gx
			var e0 := cell_start[c]
			var e1 := cell_start[c + 1]
			for e in range(e0, e1):
				if k == cap:
					return k
				scratch[k] = entries[e]
				k += 1
	return k
