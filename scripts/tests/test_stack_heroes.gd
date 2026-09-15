extends SceneTree
## Overworld hero markers on StackLayer: sprite rect, walk cycle, flag stack,
## hero texture cache. Source: .warboss-horde/slices/stack-heroes.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _v_approx(t: TestKit, a: Vector2, b: Vector2) -> bool:
	return t.approx(a.x, b.x, 1e-3) and t.approx(a.y, b.y, 1e-3)


func _init() -> void:
	var t := TestKit.new()

	# 1. hero_rect tier 0 / tier 3
	var r0 := StackLayer.hero_rect(Vector2(100, 100), 0)
	t.check(t.approx(r0.position.x, 89.92, 1e-3) and t.approx(r0.position.y, 84.04, 1e-3)
		and t.approx(r0.size.x, 20.16, 1e-3) and t.approx(r0.size.y, 20.16, 1e-3), "1: hero_rect tier 0")
	var r3 := StackLayer.hero_rect(Vector2(0, 0), 3)
	# r = 12 * 1.3 = 15.6, side = 37.44
	t.check(t.approx(r3.position.x, -18.72, 1e-3) and t.approx(r3.position.y, 7.8 - 37.44, 1e-3)
		and t.approx(r3.size.x, 37.44, 1e-3), "1b: hero_rect tier 3")

	# 2. step_walk
	var w1 := StackLayer.step_walk(Vector2(0, 0), 2, 0.5)
	t.check(w1[0] == 2 and t.approx(w1[1], 0.5) and w1[2] == 1, "2a: idle keeps facing, frame 1")
	var w2 := StackLayer.step_walk(Vector2(0.04, 0.0), 3, 7.0)
	t.check(w2[0] == 3 and t.approx(w2[1], 7.0) and w2[2] == 1, "2b: below 0.05 is idle")
	var w3 := StackLayer.step_walk(Vector2(-5, 1), 0, 0.0)
	t.check(w3[0] == 1 and t.approx(w3[1], sqrt(26.0) * 0.08) and w3[2] == 0, "2c: left, anim advances")
	var w4 := StackLayer.step_walk(Vector2(10, 0), 0, 1.5)
	t.check(w4[0] == 2 and t.approx(w4[1], 2.3) and w4[2] == 2, "2d: right, frame 2")
	var w5 := StackLayer.step_walk(Vector2(0, 25), 1, 1.5)
	t.check(w5[0] == 0 and t.approx(w5[1], 3.5) and w5[2] == 1, "2e: down (toward camera)")
	var w6 := StackLayer.step_walk(Vector2(3, -10), 0, 0.0)
	t.check(w6[0] == 3, "2f: up is away (3)")
	var w7 := StackLayer.step_walk(Vector2(4, -4), 0, 0.0)
	t.check(w7[0] == 2, "2g: tie |dx|==|dy| is horizontal")

	# 3. pole + flag geometry
	var rect := Rect2(0, 0, 20, 20)
	var pole := StackLayer.pole_segment(rect)
	t.check(pole.size() == 2 and _v_approx(t, pole[0], Vector2(18, 16)) and _v_approx(t, pole[1], Vector2(18, -9)), "3a: pole_segment")
	var f0 := StackLayer.flag_points(rect, 0)
	t.check(f0.size() == 3 and _v_approx(t, f0[0], Vector2(18, -9)) and _v_approx(t, f0[1], Vector2(30, -6.6))
		and _v_approx(t, f0[2], Vector2(18, -4.2)), "3b: primary flag")
	var f2 := StackLayer.flag_points(rect, 2)
	t.check(f2.size() == 3 and _v_approx(t, f2[0], Vector2(18, 1.8)) and _v_approx(t, f2[1], Vector2(26.4, 4.2))
		and _v_approx(t, f2[2], Vector2(18, 6.6)), "3c: ally flag (smaller, lower)")

	# 4. flag_factions
	var w := World.create(1)
	w.faction_count = maxi(w.faction_count, 6)
	for g in range(6):
		w.faction_alive[g] = 1
	w.relations.fill(0.0)
	t.check(StackLayer.flag_factions(w, 0) == PackedInt32Array([0]), "4a: no allies -> own only")
	w.add_relation(0, 3, 1.0)
	w.add_relation(0, 1, 1.0)
	w.add_relation(0, 2, 0.4)
	t.check(StackLayer.flag_factions(w, 0) == PackedInt32Array([0, 1, 3]), "4b: allies ascending, below-threshold excluded")
	w.faction_alive[1] = 0
	t.check(StackLayer.flag_factions(w, 0) == PackedInt32Array([0, 3]), "4c: dead ally excluded")
	w.faction_alive[1] = 1
	w.add_relation(0, 2, 1.0)
	w.add_relation(0, 4, 1.0)
	w.add_relation(0, 5, 1.0)
	t.check(StackLayer.flag_factions(w, 0) == PackedInt32Array([0, 1, 2, 3]), "4d: capped at 3 allies")
	t.check(StackLayer.flag_factions(w, 3) == PackedInt32Array([3, 0]), "4e: own first, then allies ascending")

	# 5. hero_texture cache
	var layer := StackLayer.new()
	t.check(layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "5a: nearest filter")
	var w2b := World.create(1)
	layer.world = w2b
	var cap := -1
	for i in range(w2b.stacks.n):
		var c: int = w2b.stacks.captain_unit[i]
		if w2b.stacks.alive[i] == 1 and c >= 0 and w2b.units.looks.has(c):
			cap = c
			break
	t.check(cap >= 0, "5pre: a captain with a look exists")
	var tex := layer.hero_texture(cap)
	t.check(tex != null and tex.get_width() == 48 and tex.get_height() == 64, "5b: hero texture 48x64")
	t.check(is_same(layer.hero_texture(cap), tex), "5c: cached")
	t.check(layer.hero_texture(-1) == null, "5d: -1 -> null")
	var lookless := w2b.units.add(0, 1, 1, false, -1)
	w2b.units.looks.erase(lookless)
	t.check(layer.hero_texture(lookless) == null, "5e: no look -> null")

	# 6. generic soldier texture for leaderless stacks, cached per colour index
	var g0 := layer.generic_texture(0)
	t.check(g0 != null and g0.get_width() == 48 and g0.get_height() == 64, "6a: generic texture 48x64")
	t.check(is_same(layer.generic_texture(0), g0), "6b: generic cached")
	t.check(not is_same(layer.generic_texture(1), g0), "6c: other faction colour -> other texture")
	t.check(is_same(layer.generic_texture(Tuning.FACTION_COLORS.size()), g0), "6d: keyed by colour index (faction % size)")
	t.check(layer.stack_texture(lookless, 0) == g0, "6e: stack_texture falls back to generic")
	t.check(layer.stack_texture(-1, 1) == layer.generic_texture(1), "6f: leaderless -> generic")
	t.check(layer.stack_texture(cap, 0) == tex, "6g: captain look wins")
	layer._tex_cache.clear()
	t.check(is_same(layer.generic_texture(0), g0), "6h: hero cache clear keeps generic cache")
	layer.free()

	t.finish()
	quit()
