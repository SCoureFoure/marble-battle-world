class_name MapTileArt
extends RefCounted
## Pure Kind -> pixel-art mapping for the baked overworld. See docs/systems/05-presentation-save.md.

const CELL := 16
const DIR := "res://assets/art/map/"
const TEX_W := DIR + "rpg_tileset_woodland_town.png"
const TEX_C := DIR + "rpg_tileset_cliffs_and_water.png"
const TEX_G := DIR + "rpg_tileset_graveyard.png"
const TEX_B := DIR + "rpg_tileset_beach_town.png"
const TEX_COLUMN := DIR + "column_ruined.png"
const TEX_PILLARS := [DIR + "rock_pillar_1.png", DIR + "rock_pillar_2.png", DIR + "rock_pillar_3.png"]
const TEX_HOUSES := [DIR + "house_woodland_1.png", DIR + "house_woodland_2.png", DIR + "house_woodland_6.png", DIR + "house_woodland_7.png"]
const SHORE_COLOR := Color(0.12, 0.25, 0.45, 1.0)


static func tile_hash(tx: int, ty: int, salt: int) -> int:
	var h: int = (tx * 73856093) ^ (ty * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF


static func pick(tx: int, ty: int, salt: int, n: int) -> int:
	return tile_hash(tx, ty, salt) % n


static func nine_slice(n_in: bool, s_in: bool, w_in: bool, e_in: bool) -> Vector2i:
	var col: int
	var row: int

	if w_in and e_in:
		col = 1
	elif not w_in and e_in:
		col = 0
	elif w_in and not e_in:
		col = 2
	else:
		col = 1

	if n_in and s_in:
		row = 1
	elif not n_in and s_in:
		row = 0
	elif n_in and not s_in:
		row = 2
	else:
		row = 1

	return Vector2i(col, row)


static func cell(tex: String, col: int, row: int, layer: int) -> Dictionary:
	return {"tex": tex, "src": Rect2i(col * CELL, row * CELL, CELL, CELL), "dst": Vector2i(0, 0), "layer": layer}


static func _in_set(m: WorldMap, tx: int, ty: int, kinds: Array) -> bool:
	if not m.in_bounds(tx, ty):
		return true
	var k: int = int(m.kind[m.idx(tx, ty)])
	return kinds.has(k)


static func _slice_for(m: WorldMap, tx: int, ty: int, kinds: Array) -> Vector2i:
	var n_in: bool = _in_set(m, tx, ty - 1, kinds)
	var s_in: bool = _in_set(m, tx, ty + 1, kinds)
	var w_in: bool = _in_set(m, tx - 1, ty, kinds)
	var e_in: bool = _in_set(m, tx + 1, ty, kinds)
	return nine_slice(n_in, s_in, w_in, e_in)


static func grass_op(tx: int, ty: int) -> Dictionary:
	var v: int = pick(tx, ty, 1, 10)
	if v <= 6:
		return cell(TEX_W, 1, 0, 0)
	elif v == 7:
		return cell(TEX_B, 0, 1, 0)
	elif v == 8:
		return cell(TEX_B, 1, 1, 0)
	else:
		return cell(TEX_B, 0, 2, 0)


static func house_texture(tx: int, ty: int) -> String:
	var p: String = TEX_HOUSES[pick(tx, ty, 8, 4)]
	return p


static func required_textures() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	result.append(TEX_W)
	result.append(TEX_C)
	result.append(TEX_G)
	result.append(TEX_B)
	result.append(TEX_COLUMN)
	result.append(TEX_PILLARS[0])
	result.append(TEX_PILLARS[1])
	result.append(TEX_PILLARS[2])
	result.append(TEX_HOUSES[0])
	result.append(TEX_HOUSES[1])
	result.append(TEX_HOUSES[2])
	result.append(TEX_HOUSES[3])
	return result


static func tile_ops(m: WorldMap, tx: int, ty: int) -> Array:
	var ops: Array = []
	var k: int = int(m.kind[m.idx(tx, ty)])

	if k == WorldMap.Kind.PLAINS:
		ops.append(grass_op(tx, ty))
		var p: int = pick(tx, ty, 2, 20)
		if p == 0:
			ops.append(cell(TEX_W, 0, 7, 1))
		elif p == 1:
			ops.append(cell(TEX_W, 1, 7, 1))
		elif p == 2:
			ops.append(cell(TEX_W, 12, 9, 1))

	elif k == WorldMap.Kind.FOREST:
		ops.append(cell(TEX_W, 4, 6, 0))

	elif k == WorldMap.Kind.HILLS:
		ops.append(grass_op(tx, ty))
		var s: Vector2i = _slice_for(m, tx, ty, [WorldMap.Kind.HILLS, WorldMap.Kind.MOUNTAIN])
		ops.append(cell(TEX_W, 4 + s.x, 12 + s.y, 0))
		var roll: int = pick(tx, ty, 3, 6)
		if roll == 0:
			ops.append(cell(TEX_W, 0, 1, 1))

	elif k == WorldMap.Kind.MOUNTAIN:
		ops.append(grass_op(tx, ty))
		var d: Vector2i = _slice_for(m, tx, ty, [WorldMap.Kind.HILLS, WorldMap.Kind.MOUNTAIN])
		ops.append(cell(TEX_W, 4 + d.x, 12 + d.y, 0))
		var r: Vector2i = _slice_for(m, tx, ty, [WorldMap.Kind.MOUNTAIN])
		if r == Vector2i(1, 1):
			ops.append(cell(TEX_C, 3 + posmod(tx, 2), 1 + posmod(ty, 2), 0))
		else:
			ops.append(cell(TEX_C, r.x, 1 + r.y, 0))

		var n_mountain: bool = m.in_bounds(tx, ty - 1) and int(m.kind[m.idx(tx, ty - 1)]) == WorldMap.Kind.MOUNTAIN
		var s_mountain: bool = m.in_bounds(tx, ty + 1) and int(m.kind[m.idx(tx, ty + 1)]) == WorldMap.Kind.MOUNTAIN
		var w_mountain: bool = m.in_bounds(tx - 1, ty) and int(m.kind[m.idx(tx - 1, ty)]) == WorldMap.Kind.MOUNTAIN
		var e_mountain: bool = m.in_bounds(tx + 1, ty) and int(m.kind[m.idx(tx + 1, ty)]) == WorldMap.Kind.MOUNTAIN

		if not n_mountain and not s_mountain and not w_mountain and not e_mountain:
			var pillar_tex: String = TEX_PILLARS[pick(tx, ty, 4, 3)]
			ops.append({"tex": pillar_tex, "src": Rect2i(0, 0, 16, 32), "dst": Vector2i(0, -16), "layer": 1})

	elif k == WorldMap.Kind.RIVER:
		var v: int = pick(tx, ty, 5, 4)
		if v == 0 or v == 1:
			ops.append(cell(TEX_C, 1, 0, 0))
		elif v == 2:
			ops.append(cell(TEX_C, 3, 0, 0))
		elif v == 3:
			ops.append(cell(TEX_C, 4, 0, 0))

		if m.in_bounds(tx, ty - 1) and int(m.kind[m.idx(tx, ty - 1)]) != WorldMap.Kind.RIVER:
			ops.append({"color": SHORE_COLOR, "rect": Rect2i(0, 0, 16, 1), "layer": 1})

		if m.in_bounds(tx, ty + 1) and int(m.kind[m.idx(tx, ty + 1)]) != WorldMap.Kind.RIVER:
			ops.append({"color": SHORE_COLOR, "rect": Rect2i(0, 15, 16, 1), "layer": 1})

		if m.in_bounds(tx - 1, ty) and int(m.kind[m.idx(tx - 1, ty)]) != WorldMap.Kind.RIVER:
			ops.append({"color": SHORE_COLOR, "rect": Rect2i(0, 0, 1, 16), "layer": 1})

		if m.in_bounds(tx + 1, ty) and int(m.kind[m.idx(tx + 1, ty)]) != WorldMap.Kind.RIVER:
			ops.append({"color": SHORE_COLOR, "rect": Rect2i(15, 0, 1, 16), "layer": 1})

	elif k == WorldMap.Kind.RUIN:
		ops.append(grass_op(tx, ty))
		ops.append(cell(TEX_G, 1, 5, 0))
		ops.append({"tex": TEX_COLUMN, "src": Rect2i(0, 0, 16, 32), "dst": Vector2i(0, -16), "layer": 1})

	elif k == WorldMap.Kind.GRAVEYARD:
		var ground: int = pick(tx, ty, 6, 2)
		if ground == 0:
			ops.append(cell(TEX_G, 3, 0, 0))
		else:
			ops.append(cell(TEX_G, 2, 1, 0))

		var deco: int = pick(tx, ty, 7, 3)
		if deco == 0:
			ops.append(cell(TEX_G, 12, 2, 1))
		elif deco == 1:
			ops.append(cell(TEX_G, 13, 2, 1))

	elif k == WorldMap.Kind.TOWN:
		ops.append(grass_op(tx, ty))

	else:
		ops.append(grass_op(tx, ty))

	return ops
