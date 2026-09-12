class_name WorldMap
extends RefCounted
## Overworld tile grid. Source: docs/ARCHITECTURE.md §11.2.

enum Kind { PLAINS = 0, FOREST = 1, HILLS = 2, MOUNTAIN = 3, RIVER = 4, RUIN = 5, GRAVEYARD = 6, TOWN = 7 }

var cols: int
var rows: int
var kind: PackedByteArray           # cols*rows
var owner: PackedInt32Array         # faction id, -1 neutral; set from town ownership (M4 borders)
var rng: RandomNumberGenerator


func _init(cols_: int, rows_: int, seed: int) -> void:
	cols = cols_
	rows = rows_
	kind = PackedByteArray()
	kind.resize(cols * rows)
	owner = PackedInt32Array()
	owner.resize(cols * rows)
	owner.fill(-1)
	rng = RandomNumberGenerator.new()
	rng.seed = seed


func idx(tx: int, ty: int) -> int:
	if not in_bounds(tx, ty):
		return -1
	return ty * cols + tx


func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and tx < cols and ty >= 0 and ty < rows


func cost_at(tx: int, ty: int) -> float:
	var i := idx(tx, ty)
	if i < 0:
		return 0.0
	var k: int = kind[i]
	var c: float = Tuning.TILE_COST[k]
	return c


func passable(tx: int, ty: int) -> bool:
	return cost_at(tx, ty) > 0.0


func tile_of(x: float, y: float) -> Vector2i:
	var tx := int(floor(x / Tuning.TILE))
	var ty := int(floor(y / Tuning.TILE))
	tx = clampi(tx, 0, cols - 1)
	ty = clampi(ty, 0, rows - 1)
	return Vector2i(tx, ty)


func center_of(tx: int, ty: int) -> Vector2:
	return Vector2(tx + 0.5, ty + 0.5) * Tuning.TILE


func reachable_count(tx: int, ty: int) -> int:
	if not in_bounds(tx, ty):
		return 0
	var visited := {}
	var start_id := idx(tx, ty)
	visited[start_id] = true
	var queue: Array[Vector2i] = [Vector2i(tx, ty)]
	var count := 1
	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for d in neighbours:
			var nx := cur.x + d.x
			var ny := cur.y + d.y
			if not in_bounds(nx, ny):
				continue
			var nid := idx(nx, ny)
			if visited.has(nid):
				continue
			if not passable(nx, ny):
				continue
			visited[nid] = true
			count += 1
			queue.append(Vector2i(nx, ny))
	return count
