extends SceneTree
## Tests for MapTileArt. See .warboss-horde/slices/map-tiles-art-test.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# Case 1: nine_slice
	t.check(MapTileArt.nine_slice(true, true, true, true) == Vector2i(1, 1), "nine_slice(T,T,T,T) == (1,1)")
	t.check(MapTileArt.nine_slice(false, true, false, true) == Vector2i(0, 0), "nine_slice(F,T,F,T) == (0,0)")
	t.check(MapTileArt.nine_slice(true, false, true, false) == Vector2i(2, 2), "nine_slice(T,F,T,F) == (2,2)")
	t.check(MapTileArt.nine_slice(false, false, false, false) == Vector2i(1, 1), "nine_slice(F,F,F,F) == (1,1)")
	t.check(MapTileArt.nine_slice(false, true, true, true) == Vector2i(1, 0), "nine_slice(F,T,T,T) == (1,0)")
	t.check(MapTileArt.nine_slice(true, true, true, false) == Vector2i(2, 1), "nine_slice(T,T,T,F) == (2,1)")

	# Case 2: hash
	t.check(MapTileArt.tile_hash(3, 4, 1) == MapTileArt.tile_hash(3, 4, 1), "tile_hash deterministic")
	t.check(MapTileArt.tile_hash(-5, 9, 2) >= 0, "tile_hash(-5,9,2) >= 0")
	var picks: Array[int] = []
	for tx in range(10):
		for ty in range(10):
			var p: int = MapTileArt.pick(tx, ty, 1, 4)
			if not picks.has(p):
				picks.append(p)
	t.check(picks.size() == 4, "pick(tx,ty,1,4) over 10x10 grid yields 4 distinct values")

	# Case 3: grass
	var grass_srcs: Array[Rect2i] = []
	var found_16_0: bool = false
	for tx in range(10):
		for ty in range(10):
			var grass_dict: Dictionary = MapTileArt.grass_op(tx, ty)
			var src: Rect2i = grass_dict["src"]
			var layer: int = grass_dict["layer"]
			t.check(src == Rect2i(16, 0, 16, 16) or src == Rect2i(0, 16, 16, 16) or src == Rect2i(16, 16, 16, 16) or src == Rect2i(0, 32, 16, 16), "grass_op src is one of 4 choices for (%d,%d)" % [tx, ty])
			t.check(layer == 0, "grass_op layer == 0 for (%d,%d)" % [tx, ty])
			if src == Rect2i(16, 0, 16, 16):
				found_16_0 = true
	t.check(found_16_0, "at least one grass_op uses Rect2i(16,0,16,16)")

	# Case 4: mountain singleton
	var m4: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m4.kind.size()):
		m4.kind[i] = WorldMap.Kind.PLAINS
	m4.kind[m4.idx(5, 4)] = WorldMap.Kind.MOUNTAIN
	var ops4: Array = MapTileArt.tile_ops(m4, 5, 4)
	var found_mountain_tex: bool = false
	for op_idx in range(ops4.size()):
		var op4: Dictionary = ops4[op_idx]
		if op4.has("tex"):
			if op4["tex"] == MapTileArt.TEX_C and op4["src"] == Rect2i(64, 16, 16, 16):
				found_mountain_tex = true
	t.check(found_mountain_tex, "mountain has tex==TEX_C and src==Rect2i(64,16,16,16)")
	var last_op4: Dictionary = ops4[ops4.size() - 1]
	t.check(last_op4["dst"] == Vector2i(0, -16), "mountain last op dst == (0,-16)")
	t.check(last_op4["src"] == Rect2i(0, 0, 16, 32), "mountain last op src == Rect2i(0,0,16,32)")
	t.check(last_op4["layer"] == 1, "mountain last op layer == 1")
	var found_bad_src: bool = false
	for op_idx in range(ops4.size()):
		var op4b: Dictionary = ops4[op_idx]
		if op4b.has("tex"):
			if op4b["tex"] == MapTileArt.TEX_C and op4b["src"] == Rect2i(0, 16, 16, 16):
				found_bad_src = true
	t.check(not found_bad_src, "mountain has no op with tex==TEX_C and src==Rect2i(0,16,16,16)")

	# Case 5: hills block
	var m5: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m5.kind.size()):
		m5.kind[i] = WorldMap.Kind.PLAINS
	for x in range(2, 5):
		for y in range(2, 5):
			m5.kind[m5.idx(x, y)] = WorldMap.Kind.HILLS
	var ops5_2_2: Array = MapTileArt.tile_ops(m5, 2, 2)
	var found_5_2_2: bool = false
	for op_idx in range(ops5_2_2.size()):
		var op5a: Dictionary = ops5_2_2[op_idx]
		if op5a.has("tex"):
			if op5a["tex"] == MapTileArt.TEX_W and op5a["src"] == Rect2i(64, 192, 16, 16):
				found_5_2_2 = true
	t.check(found_5_2_2, "hills at (2,2) has tex==TEX_W and src==Rect2i(64,192,16,16)")
	var ops5_3_3: Array = MapTileArt.tile_ops(m5, 3, 3)
	var found_5_3_3: bool = false
	for op_idx in range(ops5_3_3.size()):
		var op5b: Dictionary = ops5_3_3[op_idx]
		if op5b.has("tex"):
			if op5b["tex"] == MapTileArt.TEX_W and op5b["src"] == Rect2i(80, 208, 16, 16):
				found_5_3_3 = true
	t.check(found_5_3_3, "hills at (3,3) has tex==TEX_W and src==Rect2i(80,208,16,16)")
	var ops5_4_3: Array = MapTileArt.tile_ops(m5, 4, 3)
	var found_5_4_3: bool = false
	for op_idx in range(ops5_4_3.size()):
		var op5c: Dictionary = ops5_4_3[op_idx]
		if op5c.has("src"):
			if op5c["src"] == Rect2i(96, 208, 16, 16):
				found_5_4_3 = true
	t.check(found_5_4_3, "hills at (4,3) has src==Rect2i(96,208,16,16)")

	# Case 6: map border
	var m6: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m6.kind.size()):
		m6.kind[i] = WorldMap.Kind.PLAINS
	m6.kind[m6.idx(0, 0)] = WorldMap.Kind.HILLS
	var ops6: Array = MapTileArt.tile_ops(m6, 0, 0)
	var found_border: bool = false
	for op_idx in range(ops6.size()):
		var op6: Dictionary = ops6[op_idx]
		if op6.has("tex"):
			if op6["tex"] == MapTileArt.TEX_W and op6["src"] == Rect2i(96, 224, 16, 16):
				found_border = true
	t.check(found_border, "border hills at (0,0) has tex==TEX_W and src==Rect2i(96,224,16,16)")

	# Case 7: river shore
	var m7: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m7.kind.size()):
		m7.kind[i] = WorldMap.Kind.PLAINS
	m7.kind[m7.idx(6, 7)] = WorldMap.Kind.RIVER
	m7.kind[m7.idx(7, 7)] = WorldMap.Kind.RIVER
	var ops7: Array = MapTileArt.tile_ops(m7, 7, 7)
	var color_ops7: Array = _color_ops(ops7)
	t.check(color_ops7.size() == 2, "river shore has exactly 2 color ops")
	var color_op7_a: Dictionary = color_ops7[0]
	var color_op7_b: Dictionary = color_ops7[1]
	t.check(color_op7_a["rect"] == Rect2i(0, 0, 16, 1), "first color op rect == Rect2i(0,0,16,1)")
	t.check(color_op7_b["rect"] == Rect2i(15, 0, 1, 16), "second color op rect == Rect2i(15,0,1,16)")
	t.check(color_op7_a["color"] == MapTileArt.SHORE_COLOR, "first color op color == SHORE_COLOR")
	t.check(color_op7_b["color"] == MapTileArt.SHORE_COLOR, "second color op color == SHORE_COLOR")
	t.check(color_op7_a["layer"] == 1, "first color op layer == 1")
	t.check(color_op7_b["layer"] == 1, "second color op layer == 1")
	var first_op7: Dictionary = ops7[0]
	t.check(first_op7["tex"] == MapTileArt.TEX_C, "first op of river shore has tex == TEX_C")

	# Case 8: town
	var m8: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m8.kind.size()):
		m8.kind[i] = WorldMap.Kind.PLAINS
	m8.kind[m8.idx(3, 3)] = WorldMap.Kind.TOWN
	var ops8: Array = MapTileArt.tile_ops(m8, 3, 3)
	t.check(ops8.size() == 1, "town tile_ops has size 1")
	var op8: Dictionary = ops8[0]
	t.check(op8["layer"] == 0, "town op layer == 0")

	# Case 9: forest
	var m9: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m9.kind.size()):
		m9.kind[i] = WorldMap.Kind.PLAINS
	m9.kind[m9.idx(8, 2)] = WorldMap.Kind.FOREST
	var ops9: Array = MapTileArt.tile_ops(m9, 8, 2)
	t.check(ops9.size() == 1, "forest tile_ops has size 1")
	var op9: Dictionary = ops9[0]
	t.check(op9["tex"] == MapTileArt.TEX_W, "forest op tex == TEX_W")
	t.check(op9["src"] == Rect2i(64, 96, 16, 16), "forest op src == Rect2i(64,96,16,16)")

	# Case 10: ruin
	var m10: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m10.kind.size()):
		m10.kind[i] = WorldMap.Kind.PLAINS
	m10.kind[m10.idx(9, 5)] = WorldMap.Kind.RUIN
	var ops10: Array = MapTileArt.tile_ops(m10, 9, 5)
	var last_op10: Dictionary = ops10[ops10.size() - 1]
	t.check(last_op10["dst"] == Vector2i(0, -16), "ruin last op dst == (0,-16)")
	t.check(last_op10["layer"] == 1, "ruin last op layer == 1")
	var found_ruin: bool = false
	for op_idx in range(ops10.size()):
		var op10: Dictionary = ops10[op_idx]
		if op10.has("tex"):
			if op10["tex"] == MapTileArt.TEX_G and op10["src"] == Rect2i(16, 80, 16, 16):
				found_ruin = true
	t.check(found_ruin, "ruin has op with tex==TEX_G and src==Rect2i(16,80,16,16)")

	# Case 11: determinism
	var m11: WorldMap = WorldMap.new(12, 8, 1)
	for i in range(m11.kind.size()):
		m11.kind[i] = WorldMap.Kind.PLAINS
	for x in range(2, 5):
		for y in range(2, 5):
			m11.kind[m11.idx(x, y)] = WorldMap.Kind.HILLS
	var ops11_first: Array = MapTileArt.tile_ops(m11, 3, 3)
	var ops11_second: Array = MapTileArt.tile_ops(m11, 3, 3)
	t.check(str(ops11_first) == str(ops11_second), "tile_ops deterministic")
	var all_layers_valid: bool = true
	for tx_det in range(12):
		for ty_det in range(8):
			var ops_det: Array = MapTileArt.tile_ops(m11, tx_det, ty_det)
			for op_det_idx in range(ops_det.size()):
				var op_det: Dictionary = ops_det[op_det_idx]
				if op_det.has("layer"):
					var layer_val: int = op_det["layer"]
					if layer_val != 0 and layer_val != 1:
						all_layers_valid = false
	t.check(all_layers_valid, "all ops have layer 0 or 1")

	# Case 12: files
	var required_paths: PackedStringArray = MapTileArt.required_textures()
	t.check(required_paths.size() == 12, "required_textures().size() == 12")
	for path_idx in range(required_paths.size()):
		var path: String = required_paths[path_idx]
		t.check(ResourceLoader.exists(path), "ResourceLoader.exists('%s')" % path)
	t.check(MapTileArt.TEX_HOUSES.has(MapTileArt.house_texture(4, 6)), "house_texture(4,6) in TEX_HOUSES")
	t.check(MapTileArt.house_texture(4, 6) == MapTileArt.house_texture(4, 6), "house_texture(4,6) deterministic")

	t.finish()
	quit()


func _tex_ops(ops: Array) -> Array:
	var result: Array = []
	for i in range(ops.size()):
		var op: Dictionary = ops[i]
		if op.has("tex"):
			result.append(op)
	return result


func _color_ops(ops: Array) -> Array:
	var result: Array = []
	for i in range(ops.size()):
		var op: Dictionary = ops[i]
		if op.has("color"):
			result.append(op)
	return result
