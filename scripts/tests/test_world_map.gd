extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# 1. Fresh map basics.
	var m := WorldMap.new(12, 8, 1)
	t.check(m.cols == 12, "cols")
	t.check(m.rows == 8, "rows")
	t.check(m.kind.size() == 96, "kind size")
	var all_plains := true
	for k in m.kind:
		if k != WorldMap.Kind.PLAINS:
			all_plains = false
			break
	t.check(all_plains, "all plains")
	var owner_ok := true
	for o in m.owner:
		if o != -1:
			owner_ok = false
			break
	t.check(owner_ok, "owner all -1")
	t.check(m.idx(11, 7) == 95, "idx(11,7) == 95")
	t.check(m.idx(12, 0) == -1, "idx(12,0) == -1")
	t.check(m.in_bounds(-1, 0) == false, "in_bounds(-1,0) == false")
	t.check(m.tile_of(40.0, 70.0) == Vector2i(1, 2), "tile_of(40,70)")
	t.check(m.tile_of(-5.0, 9999.0) == Vector2i(0, 7), "tile_of(-5,9999) clamped")
	t.check(m.center_of(1, 2) == Vector2(48, 80), "center_of(1,2)")

	# 2. cost_at / passable.
	m.kind[m.idx(2, 2)] = WorldMap.Kind.MOUNTAIN
	t.check(m.cost_at(2, 2) == 0.0, "cost_at mountain == 0")
	t.check(m.passable(2, 2) == false, "passable mountain == false")
	t.check(m.cost_at(0, 0) == 1.0, "cost_at plains == 1.0")
	t.check(m.cost_at(50, 50) == 0.0, "cost_at out of range == 0.0")

	# 3. reachable_count with one mountain.
	t.check(m.reachable_count(0, 0) == 95, "reachable_count one mountain == 95")

	# 4. reachable_count with a wall (fresh map).
	var w := WorldMap.new(12, 8, 1)
	for ty in range(8):
		w.kind[w.idx(5, ty)] = WorldMap.Kind.MOUNTAIN
	t.check(w.reachable_count(0, 0) == 40, "reachable_count behind wall == 40")

	# 5. Generation.
	var g := WorldMap.new(Tuning.WORLD_COLS, Tuning.WORLD_ROWS, 42)
	var towns := WorldGen.generate(g)
	var expected_town_count: int = Tuning.N_FACTIONS * Tuning.TOWNS_PER_FACTION + Tuning.NEUTRAL_TOWNS
	t.check(towns.size() == expected_town_count, "town count == %d" % expected_town_count)

	var all_town_kind := true
	for tw in towns:
		if g.kind[g.idx(tw.x, tw.y)] != WorldMap.Kind.TOWN:
			all_town_kind = false
	t.check(all_town_kind, "every town tile is TOWN")

	var spacing_ok := true
	for i in range(towns.size()):
		for j in range(i + 1, towns.size()):
			var a: Vector2i = towns[i]
			var b: Vector2i = towns[j]
			if maxi(absi(a.x - b.x), absi(a.y - b.y)) < Tuning.TOWN_MIN_SPACING:
				spacing_ok = false
	t.check(spacing_ok, "town spacing >= TOWN_MIN_SPACING")

	var rc0 := g.reachable_count(towns[0].x, towns[0].y)
	t.check(rc0 >= towns.size(), "reachable_count(town 0) >= town count")

	var all_passable := true
	var same_component := true
	for k in range(towns.size()):
		var tw: Vector2i = towns[k]
		if not g.passable(tw.x, tw.y):
			all_passable = false
		if g.reachable_count(tw.x, tw.y) != rc0:
			same_component = false
	t.check(all_passable, "every town is passable")
	t.check(same_component, "every town in the same component")

	var mountain_count := 0
	var hills_count := 0
	var forest_count := 0
	var river_count := 0
	var ruin_count := 0
	var graveyard_count := 0
	for k in g.kind:
		if k == WorldMap.Kind.MOUNTAIN:
			mountain_count += 1
		elif k == WorldMap.Kind.HILLS:
			hills_count += 1
		elif k == WorldMap.Kind.FOREST:
			forest_count += 1
		elif k == WorldMap.Kind.RIVER:
			river_count += 1
		elif k == WorldMap.Kind.RUIN:
			ruin_count += 1
		elif k == WorldMap.Kind.GRAVEYARD:
			graveyard_count += 1
	t.check(mountain_count >= 20, "mountain count >= 20")
	t.check(hills_count >= 60, "hills count >= 60")
	t.check(forest_count >= 100, "forest count >= 100")
	t.check(river_count >= 20, "river count >= 20")
	t.check(ruin_count == 6, "ruin count == 6")
	t.check(graveyard_count == 6, "graveyard count == 6")

	# 6. Determinism.
	var g2 := WorldMap.new(96, 54, 42)
	var towns2 := WorldGen.generate(g2)
	t.check(g.kind == g2.kind, "same seed -> identical kind array")
	t.check(towns == towns2, "same seed -> identical town list")

	var g3 := WorldMap.new(96, 54, 43)
	var towns3 := WorldGen.generate(g3)
	t.check(g.kind != g3.kind, "seed 43 -> different kind array")

	t.finish()
	quit()
