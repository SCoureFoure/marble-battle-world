extends SceneTree
## Units/Stacks slot recycling: store-level reuse, SlotSweep reference checks,
## save/load of gen/reusable, render invalidation by gen.
## Source: .warboss-horde/slices/slot-stores.md, slot-sweep.md, slot-save.md, slot-render.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# --- U: Units store ---
	var u := Units.new(3)
	t.check(u.add(0, 0, 0, false, -1) == 0 and u.add(0, 0, 0, false, -1) == 1 and u.add(0, 0, 0, false, -1) == 2, "U1: appends 0,1,2")
	t.check(u.gen.size() == 3 and u.gen[0] == 0 and u.reusable.size() == 3 and u.reusable[1] == 0 and u.left_for.size() == 3 and u.left_for[0] == -1, "U1b: gen/reusable arrays zeroed")
	u.kill(1)
	u.names[1] = "Old"
	u.looks[1] = {"build": "x"}
	u.dynasty[1] = ["Old", 1]
	u.ctrait[1] = 2
	u.c_fights[1] = 5
	u.c_retreats[1] = 1
	u.c_razes[1] = 1
	u.c_settles[1] = 1
	u.kills[1] = 9
	u.hero[1] = 1
	u.left_for[1] = 2
	u.reusable[1] = 1
	var id := u.add(3, 2, 1, true, 7)
	t.check(id == 1 and u.n == 3 and u.gen[1] == 1 and u.reusable[1] == 0, "U2: full store reuses marked slot, gen bumps")
	t.check(u.alive[1] == 1 and u.faction[1] == 3 and u.rank[1] == 2 and u.weapon[1] == 1 and u.is_captain[1] == 1 and u.stack[1] == 7, "U2b: new occupant fields")
	t.check(u.ctrait[1] == -1 and u.c_fights[1] == 0 and u.c_retreats[1] == 0 and u.c_razes[1] == 0 and u.c_settles[1] == 0
		and u.kills[1] == 0 and u.hero[1] == 0 and u.left_for[1] == -1, "U2c: old occupant traits/counters cleared")
	t.check(not u.names.has(1) and not u.looks.has(1) and not u.dynasty.has(1), "U2d: old name/look/dynasty erased")
	u.kill(0)
	u.kill(2)
	u.reusable[2] = 1
	u.reusable[0] = 1
	t.check(u.add(0, 0, 0, false, -1) == 0 and u.gen[0] == 1 and u.reusable[2] == 1, "U3: lowest reusable slot first")
	# has_room: space below cap, or a reusable slot once full
	var hr := Units.new(2)
	t.check(hr.has_room(), "H1: empty store has room")
	hr.add(0, 0, 0, false, -1)
	hr.add(0, 0, 0, false, -1)
	t.check(not hr.has_room(), "H2: full, nothing reusable -> no room")
	hr.kill(0)
	t.check(not hr.has_room(), "H3: dead but unmarked -> no room")
	hr.reusable[0] = 1
	t.check(hr.has_room(), "H4: full with a reusable slot -> room")
	var hs2 := Stacks.new(1)
	hs2.add(0, 0.0, 0.0, "a")
	t.check(not hs2.has_room(), "H5: stacks full -> no room")
	hs2.alive[0] = 0
	hs2.reusable[0] = 1
	t.check(hs2.has_room(), "H6: stacks reusable -> room")
	var u4 := Units.new(4)
	u4.add(0, 0, 0, false, -1)
	u4.add(0, 0, 0, false, -1)
	u4.kill(0)
	u4.reusable[0] = 1
	t.check(u4.add(0, 0, 0, false, -1) == 2 and u4.gen[0] == 0, "U4: below cap always appends (no reuse)")

	# --- S: Stacks store ---
	var s := Stacks.new(2)
	s.add(0, 1.0, 1.0, "A")
	s.add(0, 2.0, 2.0, "B")
	s.alive[0] = 0
	s.rally_target[0] = 1
	s.captain_unit[0] = 5
	s.path[0] = PackedVector2Array([Vector2(1, 1)])
	s.path_i[0] = 3
	s.gold[0] = 9.0
	s.state[0] = Stacks.State.MOVING
	s.count[0] = 4
	s.reusable[0] = 1
	var sid := s.add(4, 10.0, 20.0, "Neo")
	t.check(sid == 0 and s.n == 2 and s.gen[0] == 1 and s.reusable[0] == 0 and s.alive[0] == 1, "S1: full stack store reuses slot")
	t.check(s.names.size() == 2 and s.names[0] == "Neo" and s.path.size() == 2 and (s.path[0] as PackedVector2Array).size() == 0 and s.path_i[0] == 0, "S1b: names/path replaced in place")
	t.check(s.rally_target[0] == -1 and s.captain_unit[0] == -1 and s.gold[0] == 0.0 and s.state[0] == Stacks.State.IDLE
		and s.count[0] == 0 and s.faction[0] == 4 and s.x[0] == 10.0 and s.prev_y[0] == 20.0, "S1c: fields reset")

	# --- W: SlotSweep reference checks ---
	var w := World.new()
	w.setup_blank(8, 8, 1)
	w.units = Units.new(10)
	w.stacks = Stacks.new(5)
	var s0 := w.stacks.add(0, 0.0, 0.0, "s0")
	var s1 := w.stacks.add(0, 0.0, 0.0, "s1")
	var s2 := w.stacks.add(0, 0.0, 0.0, "s2")
	var s3 := w.stacks.add(0, 0.0, 0.0, "s3")
	var s4 := w.stacks.add(0, 0.0, 0.0, "s4")
	var u_free := w.units.add(0, 0, 0, false, s1)      # 0: dies, unreferenced
	var u_cap := w.units.add(0, 0, 0, true, s0)       # 1: dead captain of alive s0
	var u_lord := w.units.add(0, 0, 0, false, s0)     # 2: dead town lord
	var u_mentor := w.units.add(0, 0, 0, false, s0)   # 3: dead mentor of alive unit
	var u_leader := w.units.add(0, 0, 0, false, s0)   # 4: dead leader of alive unit
	var u_alive := w.units.add(0, 0, 0, false, s0)    # 5: alive
	var u_battle := w.units.add(0, 0, 0, false, s0)   # 6: dead but in an active battle
	w.units.kill(u_free)
	w.stacks.captain_unit[s0] = u_cap
	w.units.kill(u_cap)
	var town := w.add_town(Vector2i(1, 1), 0)
	w.town_lord[town] = u_lord
	w.units.kill(u_lord)
	w.units.mentor[u_alive] = u_mentor
	w.units.kill(u_mentor)
	w.units.leader[u_alive] = u_leader
	w.units.kill(u_leader)
	w.units.kill(u_battle)
	# stacks: s1 dead unreferenced; s2 dead in reinforce; s3 dead rally target of alive s0; s4 dead in active battle
	w.stacks.alive[s1] = 0
	w.stacks.alive[s2] = 0
	w.reinforce[s2] = 3
	w.stacks.alive[s3] = 0
	w.stacks.rally_target[s0] = s3
	w.stacks.alive[s4] = 0
	var inst := BattleInstance.new(1, Vector2i(2, 2))
	inst.stack_ids = PackedInt32Array([s4])
	inst.unit_of = PackedInt32Array([u_battle])
	w.battles.append(inst)
	SlotSweep.sweep(w)
	t.check(w.units.reusable[u_free] == 1, "W1: dead unreferenced unit marked")
	t.check(w.units.reusable[u_cap] == 0, "W2: dead captain of alive stack kept")
	t.check(w.units.reusable[u_lord] == 0, "W3: dead town lord kept")
	t.check(w.units.reusable[u_mentor] == 0, "W4: dead mentor of alive unit kept")
	t.check(w.units.reusable[u_leader] == 0, "W5: dead leader of alive unit kept")
	t.check(w.units.reusable[u_alive] == 0, "W6: alive unit never marked")
	t.check(w.units.reusable[u_battle] == 0, "W7: unit in active battle kept")
	t.check(w.stacks.reusable[s1] == 1, "W8: dead unreferenced stack marked")
	t.check(w.stacks.reusable[s2] == 0, "W9: stack in reinforce kept")
	t.check(w.stacks.reusable[s3] == 0, "W10: rally target of alive stack kept")
	t.check(w.stacks.reusable[s4] == 0, "W11: stack in active battle kept")
	t.check(w.stacks.reusable[s0] == 0, "W12: alive stack never marked")
	# a dead stack still holding an alive unit is kept
	w.stacks.alive[s0] = 0
	SlotSweep.sweep(w)
	t.check(w.stacks.reusable[s0] == 0, "W13: dead stack with alive member kept")
	# references removed -> recomputed on next sweep
	w.stacks.alive[s0] = 1
	w.reinforce.erase(s2)
	w.battles.clear()
	w.town_lord[town] = -1
	SlotSweep.sweep(w)
	t.check(w.stacks.reusable[s2] == 1 and w.stacks.reusable[s4] == 1 and w.units.reusable[u_lord] == 1 and w.units.reusable[u_battle] == 1, "W14: cleared references free slots")
	w.units.reusable[u_free] = 1
	w.units.alive[u_free] = 1
	SlotSweep.sweep(w)
	t.check(w.units.reusable[u_free] == 0, "W15: sweep recomputes (revived slot unmarked)")

	# --- G: maybe_sweep gating ---
	var g := World.new()
	g.setup_blank(8, 8, 1)
	g.units = Units.new(1000)
	g.stacks = Stacks.new(1000)
	var gs := g.stacks.add(0, 0.0, 0.0, "g")
	var gu := g.units.add(0, 0, 0, false, gs)
	g.units.kill(gu)
	g.time = 5.0
	SlotSweep.maybe_sweep(g, 1.0 / 60.0)
	t.check(g.units.reusable[gu] == 0, "G1: far below cap -> no sweep")
	var h := World.new()
	h.setup_blank(8, 8, 1)
	h.units = Units.new(4)
	h.stacks = Stacks.new(4)
	var hs := h.stacks.add(0, 0.0, 0.0, "h")
	var hu := h.units.add(0, 0, 0, false, hs)
	h.units.kill(hu)
	h.time = 5.5
	SlotSweep.maybe_sweep(h, 1.0 / 60.0)
	t.check(h.units.reusable[hu] == 0, "G2: near cap but mid-second -> no sweep")
	h.time = 6.0
	SlotSweep.maybe_sweep(h, 1.0 / 60.0)
	t.check(h.units.reusable[hu] == 1, "G3: near cap on a whole-second boundary -> sweep")

	# --- D: determinism unaffected, sweep hooked into WorldSim ---
	var da := World.create(7)
	var db := World.create(7)
	for k in range(300):
		WorldSim.step(da, Tuning.DT)
		WorldSim.step(db, Tuning.DT)
	t.check(da.stacks.x == db.stacks.x and da.units.n == db.units.n and da.rng.state == db.rng.state, "D1: deterministic")

	# --- L: save/load round-trip of gen + reusable ---
	var sl := World.create(3)
	sl.units.gen[2] = 4
	sl.units.reusable[3] = 1
	sl.stacks.gen[1] = 2
	sl.stacks.reusable[0] = 1
	const SAVE_PATH := "user://test_slot_reuse.bin"
	var save_ok: bool = SaveGame.save(sl, SAVE_PATH) == OK
	var ld: World = SaveGame.load(SAVE_PATH)
	t.check(save_ok and ld != null and ld.units.gen[2] == 4 and ld.units.reusable[3] == 1 and ld.stacks.gen[1] == 2 and ld.stacks.reusable[0] == 1, "L1: gen/reusable saved")
	t.check(ld.units.gen.size() == ld.units.cap and ld.stacks.reusable.size() == ld.stacks.cap, "L2: arrays sized to cap")

	# --- R: render invalidation by gen ---
	var rw := World.create(1)
	var cap_u := -1
	var cap_s := -1
	for i in range(rw.stacks.n):
		var c: int = rw.stacks.captain_unit[i]
		if rw.stacks.alive[i] == 1 and c >= 0 and rw.units.looks.has(c):
			cap_u = c
			cap_s = i
			break
	t.check(cap_u >= 0, "Rpre: captain with look")
	var layer := StackLayer.new()
	layer.world = rw
	var tex1 := layer.hero_texture(cap_u)
	t.check(tex1 != null and is_same(layer.hero_texture(cap_u), tex1), "R1: cached while gen unchanged")
	rw.units.gen[cap_u] += 1
	t.check(layer.hero_texture(cap_u) != null and not is_same(layer.hero_texture(cap_u), tex1), "R2: gen bump -> new texture")
	layer.free()
	var sp := SpectatePanel.new()
	sp.build(rw)
	sp.show_stack(cap_s, Vector2(10, 10))
	var win1: InfoWindow = sp.window_for("s%d" % cap_s)
	rw.stacks.gen[cap_s] += 1
	sp.refresh_now()
	t.check("Fallen" in win1._body.text and win1._follow.disabled, "R3: stack window shows Fallen after gen bump")
	sp.show_stack(cap_s, Vector2(10, 10))
	t.check(sp.window_count() == 1 and not is_same(sp.window_for("s%d" % cap_s), win1), "R4: reopening a recycled stack opens a fresh window")
	sp.show_unit(rw, cap_u, Vector2(20, 20))
	var winu: InfoWindow = sp.window_for("u%d" % cap_u)
	rw.units.gen[cap_u] += 1
	sp.refresh_now()
	t.check("Fallen" in winu._body.text, "R5: unit window shows Fallen after gen bump")
	sp.free()

	t.finish()
	quit()
