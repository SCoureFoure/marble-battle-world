extends SceneTree
## Tests for Dissent step 2: drives (drive_strength/grievance), per-unit and
## per-town grievance readings, bond erosion, and the seam's call-site hooks
## in PlinkoOutcomes/TownSim/Economy/Settling. Observe-only: nothing in the
## sim reads these for decisions in this step.
## Source: .warboss-horde/slices/dissent2-seam.md.

const Kit = preload("res://scripts/tests/test_kit.gd")


## Five copies of `x`.
func _five(x: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, x, x, x, x])


## Writes `w.units.vals[u*5+k] = arr[k]` for k 0..4.
func _set_vals(w: World, u: int, arr: PackedFloat32Array) -> void:
	for k in range(5):
		w.units.vals[u * 5 + k] = arr[k]


## Writes `w.units.griev[u*4+d] = arr[d]` for d 0..3.
func _set_griev(w: World, u: int, arr: PackedFloat32Array) -> void:
	for d in range(4):
		w.units.griev[u * 4 + d] = arr[d]


func _init() -> void:
	var t := Kit.new()

	# 1. Units.new fields + recycle.
	var u1 := Units.new(3)
	t.check(u1.griev.size() == 12, "G1: Units.new(3) griev.size() == 12")
	var griev1_ok := true
	for i in range(u1.griev.size()):
		var v: float = u1.griev[i]
		if not t.approx(v, 0.0):
			griev1_ok = false
	t.check(griev1_ok, "G1b: Units.new(3) griev all 0.0")

	u1.add(0, 0, 0, false, -1)
	u1.add(0, 0, 0, false, -1)
	u1.add(0, 0, 0, false, -1)
	for k in range(4):
		u1.griev[1 * 4 + k] = 0.6
	u1.alive[1] = 0
	u1.reusable[1] = 1
	var rid1 := u1.add(0, 0, 0, false, -1)
	t.check(rid1 == 1, "G1c: recycle returns slot 1")
	var reset1_ok := true
	for k in range(4):
		var v2: float = u1.griev[1 * 4 + k]
		if not t.approx(v2, 0.0):
			reset1_ok = false
	t.check(reset1_ok, "G1d: recycled griev[4..7] reset to 0.0")

	# 2. add_town / sync_town_arrays town_griev.
	var w2 := World.new()
	w2.setup_blank(20, 20, 7)
	var t2a := w2.add_town(Vector2i(3, 3), 0)
	t.check(t.approx(w2.town_griev[t2a], 0.0), "G2: add_town town_griev[t] == 0.0")

	w2.towns.append(Vector2(5, 5))
	w2.town_owner.append(0)
	w2.sync_town_arrays()
	t.check(w2.town_griev.size() == w2.towns.size(), "G2b: sync_town_arrays sizes town_griev to towns.size()")
	var last2 := w2.towns.size() - 1
	t.check(t.approx(w2.town_griev[last2], 0.0), "G2c: sync_town_arrays new entry 0.0")

	# 3. drive_strength.
	var w3 := World.new()
	w3.setup_blank(20, 20, 7)
	var u3 := w3.units.add(0, 1, 1, true, -1)
	_set_vals(w3, u3, PackedFloat32Array([0.8, 0.1, 0.6, 0.3, 0.2]))
	t.check(t.approx(Dissent.drive_strength(w3, u3, 0), 0.8), "G3: drive_strength d0 == 0.8")
	t.check(t.approx(Dissent.drive_strength(w3, u3, 1), 0.6), "G3b: drive_strength d1 == 0.6")
	t.check(t.approx(Dissent.drive_strength(w3, u3, 2), 0.3), "G3c: drive_strength d2 == 0.3")
	t.check(t.approx(Dissent.drive_strength(w3, u3, 3), 0.2), "G3d: drive_strength d3 == 0.2")

	# 4. grievance.
	_set_griev(w3, u3, PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	t.check(t.approx(Dissent.grievance(w3, u3), 0.8 / 1.9), "G4: grievance approx 0.8/1.9")

	var u4b := w3.units.add(0, 1, 1, true, -1)
	t.check(t.approx(Dissent.grievance(w3, u4b), 0.0), "G4b: grievance vals all 0 -> 0.0")

	# 5. seed_unit resets griev.
	var w5 := World.new()
	w5.setup_blank(20, 20, 7)
	var u5 := w5.units.add(0, 1, 1, true, -1)
	_set_griev(w5, u5, PackedFloat32Array([0.7, 0.7, 0.7, 0.7]))
	Dissent.seed_unit(w5, u5, _five(0.5))
	var g5_ok := true
	for k in range(4):
		var v3: float = w5.units.griev[u5 * 4 + k]
		if not t.approx(v3, 0.0):
			g5_ok = false
	t.check(g5_ok, "G5: seed_unit resets griev to 0.0")

	# 6. tick rise.
	var w6 := World.new()
	w6.setup_blank(20, 20, 7)
	var cpos6 := w6.map.center_of(5, 4)
	var s6 := w6.stacks.add(0, cpos6.x, cpos6.y, "S6")
	var c6 := w6.units.add(0, 1, 1, true, s6)
	Lineage.make_captain(w6, c6, "Toby")
	_set_vals(w6, c6, _five(0.5))
	_set_griev(w6, c6, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	w6.units.bond[c6] = 0.5
	w6.stacks.captain_unit[s6] = c6
	w6.stacks.count[s6] = 10
	w6.stacks.gold[s6] = 0.0

	Dissent.tick(w6)
	t.check(t.approx(w6.units.griev[c6 * 4 + 0], 0.00085), "G6: tick g0 approx 0.00085")
	t.check(t.approx(w6.units.griev[c6 * 4 + 1], 0.00085), "G6b: tick g1 approx 0.00085")
	t.check(t.approx(w6.units.griev[c6 * 4 + 2], 0.0004), "G6c: tick g2 approx 0.0004")
	t.check(t.approx(w6.units.griev[c6 * 4 + 3], 0.00085), "G6d: tick g3 approx 0.00085")
	t.check(t.approx(w6.units.bond[c6], 0.501), "G6e: tick bond approx 0.501")

	# 7. wealth comfort drain.
	var w7 := World.new()
	w7.setup_blank(20, 20, 7)
	var cpos7 := w7.map.center_of(5, 4)
	var s7 := w7.stacks.add(0, cpos7.x, cpos7.y, "S7")
	var c7 := w7.units.add(0, 1, 1, true, s7)
	Lineage.make_captain(w7, c7, "Toby")
	_set_vals(w7, c7, _five(0.5))
	_set_griev(w7, c7, PackedFloat32Array([0.0, 0.5, 0.0, 0.0]))
	w7.units.bond[c7] = 0.5
	w7.stacks.captain_unit[s7] = c7
	w7.stacks.count[s7] = 10
	w7.stacks.gold[s7] = 20.0

	Dissent.tick(w7)
	t.check(t.approx(w7.units.griev[c7 * 4 + 1], 0.4983), "G7: tick wealth comfort g1 approx 0.4983")

	# 8. no change: LORD, RETIRED hero, plain soldier.
	var w8 := World.new()
	w8.setup_blank(20, 20, 7)
	var lord8 := w8.units.add(0, 1, 1, false, -1)
	w8.units.fate[lord8] = Units.Fate.LORD
	_set_vals(w8, lord8, _five(0.5))
	_set_griev(w8, lord8, PackedFloat32Array([0.3, 0.3, 0.3, 0.3]))

	var retired8 := w8.units.add(0, 0, 1, false, -1)
	w8.units.hero[retired8] = 1
	w8.units.fate[retired8] = Units.Fate.RETIRED
	_set_vals(w8, retired8, _five(0.5))
	_set_griev(w8, retired8, PackedFloat32Array([0.3, 0.3, 0.3, 0.3]))

	var cpos8 := w8.map.center_of(5, 4)
	var s8 := w8.stacks.add(0, cpos8.x, cpos8.y, "S8")
	var soldier8 := w8.units.add(0, 0, 1, false, s8)
	_set_vals(w8, soldier8, _five(0.5))
	_set_griev(w8, soldier8, PackedFloat32Array([0.3, 0.3, 0.3, 0.3]))

	Dissent.tick(w8)
	var g8_ok := true
	for k in range(4):
		if not t.approx(w8.units.griev[lord8 * 4 + k], 0.3):
			g8_ok = false
		if not t.approx(w8.units.griev[retired8 * 4 + k], 0.3):
			g8_ok = false
		if not t.approx(w8.units.griev[soldier8 * 4 + k], 0.3):
			g8_ok = false
	t.check(g8_ok, "G8: tick leaves LORD/RETIRED/soldier griev unchanged")

	# 9. events.
	var w9 := World.new()
	w9.setup_blank(20, 20, 7)
	var cpos9 := w9.map.center_of(5, 4)
	var s9 := w9.stacks.add(0, cpos9.x, cpos9.y, "S9")
	var c9 := w9.units.add(0, 1, 1, true, s9)

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "win", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 0], 0.3), "G9: win g0 approx 0.3")

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "retreat", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 0], 0.65), "G9b: retreat g0 approx 0.65")

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "raze", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 1], 0.4), "G9c: raze g1 approx 0.4")
	t.check(t.approx(w9.units.griev[c9 * 4 + 2], 1.0), "G9d: raze g2 == 1.0 (clamped)")

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "raid", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 1], 0.4), "G9e: raid g1 approx 0.4")
	var vals9_ok := true
	for k in range(5):
		var v4: float = w9.units.vals[c9 * 5 + k]
		if not t.approx(v4, 0.5):
			vals9_ok = false
	t.check(vals9_ok, "G9f: raid leaves vals five 0.5")

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "pilgrim", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 2], 0.2), "G9g: pilgrim g2 approx 0.2")

	_set_griev(w9, c9, PackedFloat32Array([0.8, 0.8, 0.8, 0.8]))
	_set_vals(w9, c9, _five(0.5))
	Dissent.on_stack_event(w9, "settle", s9)
	t.check(t.approx(w9.units.griev[c9 * 4 + 3], 0.5), "G9h: settle g3 approx 0.5")

	_set_vals(w9, c9, _five(0.5))
	w9.units.vals[c9 * 5 + 3] = 0.2
	_set_griev(w9, c9, PackedFloat32Array([0.0, 0.0, 0.1, 0.0]))
	Dissent.on_stack_event(w9, "raze", s9)
	# Raze lowers piety by KT_RAZE_PIETY * HERO_EVENT_SCALE (0.2 -> 0.14) before the Faith spike reads it.
	t.check(t.approx(w9.units.griev[c9 * 4 + 2], 0.17), "G9i: raze with faith strength 0.2 (0.14 after the deed), g2 0.1 -> g2 approx 0.17")

	# 10. unit_disaffection with grievance term.
	var w10 := World.new()
	w10.setup_blank(20, 20, 7)
	var u10 := w10.units.add(0, 1, 1, true, -1)
	_set_vals(w10, u10, _five(0.5))
	_set_griev(w10, u10, PackedFloat32Array([1.0, 1.0, 1.0, 1.0]))
	w10.units.bond[u10] = 0.0
	t.check(t.approx(Dissent.unit_disaffection(w10, u10), 0.5), "G10: unit_disaffection bond 0 -> 0.5")
	w10.units.bond[u10] = 1.0
	t.check(t.approx(Dissent.unit_disaffection(w10, u10), 0.25), "G10b: unit_disaffection bond 1 -> 0.25")

	# 11. bond erosion.
	var w11 := World.new()
	w11.setup_blank(20, 20, 7)
	var cpos11 := w11.map.center_of(5, 4)
	var s11 := w11.stacks.add(0, cpos11.x, cpos11.y, "S11")
	var c11 := w11.units.add(0, 1, 1, true, s11)
	Lineage.make_captain(w11, c11, "Toby")
	_set_vals(w11, c11, _five(0.5))
	_set_griev(w11, c11, PackedFloat32Array([1.0, 1.0, 1.0, 1.0]))
	w11.units.bond[c11] = 0.5
	w11.stacks.captain_unit[s11] = c11
	w11.stacks.count[s11] = 10
	w11.stacks.gold[s11] = 100.0

	Dissent.tick(w11)
	t.check(t.approx(w11.units.bond[c11], 0.498), "G11: tick bond erosion approx 0.498")

	# 12. on_town_event.
	var w12 := World.new()
	w12.setup_blank(20, 20, 7)
	var t12a := w12.add_town(Vector2i(1, 1), 0)
	Dissent.on_town_event(w12, "raid", t12a)
	t.check(t.approx(w12.town_griev[t12a], 0.4), "G12: on_town_event raid -> 0.4")
	Dissent.on_town_event(w12, "raze", t12a)
	t.check(t.approx(w12.town_griev[t12a], 1.0), "G12b: on_town_event raze -> 1.0 (clamped)")

	var t12b := w12.add_town(Vector2i(2, 2), 0)
	Dissent.on_town_event(w12, "levy", t12b, 5.0)
	t.check(t.approx(w12.town_griev[t12b], 0.01), "G12c: on_town_event levy amount 5 -> 0.01")

	var t12c := w12.add_town(Vector2i(3, 3), 0)
	Dissent.on_town_event(w12, "tax", t12c)
	t.check(t.approx(w12.town_griev[t12c], 0.05), "G12d: on_town_event tax -> 0.05")

	var t12d := w12.add_town(Vector2i(4, 4), 0)
	Dissent.on_town_event(w12, "bogus", t12d)
	t.check(t.approx(w12.town_griev[t12d], 0.0), "G12e: on_town_event bogus -> unchanged")

	# 13. town calm + town_disaffection with town_griev term.
	var w13 := World.new()
	w13.setup_blank(20, 20, 7)
	var t13a := w13.add_town(Vector2i(1, 1), 0)
	w13.town_griev[t13a] = 0.3

	var t13b := w13.add_town(Vector2i(2, 2), -1)
	w13.town_griev[t13b] = 0.3

	var t13c := w13.add_town(Vector2i(3, 3), 0)
	w13.town_griev[t13c] = 0.3
	w13.town_state[t13c] = 1

	Dissent.tick(w13)
	t.check(t.approx(w13.town_griev[t13a], 0.2995), "G13: town calm owned INTACT -> 0.2995")
	t.check(t.approx(w13.town_griev[t13b], 0.3), "G13b: town owner -1 unchanged")
	t.check(t.approx(w13.town_griev[t13c], 0.3), "G13c: town owned RAIDED (state 1) unchanged")

	var t13d := w13.add_town(Vector2i(4, 4), 0)
	for k in range(5):
		w13.town_vals[t13d * 5 + k] = 0.5
	w13.town_griev[t13d] = 0.4
	t.check(t.approx(Dissent.town_disaffection(w13, t13d), 0.2), "G13d: town_disaffection with griev 0.4 -> approx 0.2")

	# 14. hooks.
	var w14 := World.new()
	w14.setup_blank(20, 20, 7)

	# 14a. PlinkoOutcomes._raid.
	var town14a := w14.add_town(Vector2i(5, 5), 1)
	var cpos14a := w14.map.center_of(5, 5)
	var s14a := w14.stacks.add(0, cpos14a.x, cpos14a.y, "S14a")
	var cap14a := w14.units.add(0, 1, 1, true, s14a)
	w14.stacks.captain_unit[s14a] = cap14a
	_set_vals(w14, cap14a, _five(0.5))
	_set_griev(w14, cap14a, PackedFloat32Array([0.0, 0.8, 0.0, 0.0]))

	PlinkoOutcomes._raid(w14, s14a, 0)
	t.check(t.approx(w14.town_griev[town14a], 0.4), "G14a: PlinkoOutcomes._raid town_griev approx 0.4")
	t.check(t.approx(w14.units.griev[cap14a * 4 + 1], 0.4), "G14ab: PlinkoOutcomes._raid captain g1 0.8 -> 0.4")

	# 14b. PlinkoOutcomes._raze.
	var town14b := w14.add_town(Vector2i(10, 10), 1)
	var cpos14b := w14.map.center_of(10, 10)
	var s14b := w14.stacks.add(0, cpos14b.x, cpos14b.y, "S14b")
	var cap14b := w14.units.add(0, 1, 1, true, s14b)
	w14.stacks.captain_unit[s14b] = cap14b

	PlinkoOutcomes._raze(w14, s14b, 0)
	t.check(t.approx(w14.town_griev[town14b], 0.8), "G14b: PlinkoOutcomes._raze town_griev approx 0.8")

	# 14c. TownSim._recruit.
	var t14c := w14.add_town(Vector2i(15, 15), 0)
	w14.town_pop[t14c] = 10.0
	w14.town_recruit[t14c] = 1.5

	TownSim._recruit(w14, t14c, 0.0)
	t.check(t.approx(w14.town_griev[t14c], 0.002), "G14c: TownSim._recruit exactly 1 recruit -> town_griev approx 0.002")

	# 14d. Economy.restock.
	var w14d := World.new()
	w14d.setup_blank(20, 20, 7)
	var t14d := w14d.add_town(Vector2i(7, 7), 0)
	w14d.town_gold[t14d] = 5.0
	w14d.town_pop[t14d] = 10.0
	var cpos14d := w14d.map.center_of(7, 7)
	var s14d := w14d.stacks.add(0, cpos14d.x, cpos14d.y, "S14d")
	w14d.stacks.gold[s14d] = 0.0
	w14d.stacks.count[s14d] = 1
	w14d.units.add(0, 0, 1, false, s14d)

	Economy.restock(w14d, s14d, t14d)
	t.check(w14d.town_griev[t14d] >= 0.05, "G14d: Economy.restock town_griev[t] >= 0.05")

	# 14e. Settling.found_town.
	var w14e := World.new()
	w14e.setup_blank(20, 20, 7)
	w14e.faction_count = 1
	w14e.faction_alive[0] = 1
	w14e.faction_names = ["Alpha"]
	var cpos14e := w14e.map.center_of(5, 4)
	var s14e := w14e.stacks.add(0, cpos14e.x, cpos14e.y, "S14e")
	var cap14e := w14e.units.add(0, 1, 1, true, s14e)
	Lineage.make_captain(w14e, cap14e, "Toby")
	_set_griev(w14e, cap14e, PackedFloat32Array([0.0, 0.0, 0.0, 0.9]))
	w14e.stacks.captain_unit[s14e] = cap14e
	w14e.stacks.count[s14e] = 1

	var town14e := Settling.found_town(w14e, s14e, w14e.stack_tile(s14e))
	t.check(town14e >= 0, "G14e: found_town succeeds")
	t.check(t.approx(w14e.units.griev[cap14e * 4 + 3], 0.0), "G14eb: found_town resets captain g3 to 0.0")

	# 15. save/load round-trip of griev and town_griev.
	var w15 := World.new()
	w15.setup_blank(20, 20, 7)
	var u15 := w15.units.add(0, 1, 1, true, -1)
	_set_griev(w15, u15, PackedFloat32Array([0.1, 0.2, 0.3, 0.4]))
	var t15 := w15.add_town(Vector2i(2, 2), 0)
	w15.town_griev[t15] = 0.55

	const SAVE_PATH15 := "user://test_grievance.sav"
	var save_ok15: bool = SaveGame.save(w15, SAVE_PATH15) == OK
	var w15b: World = SaveGame.load(SAVE_PATH15)
	t.check(save_ok15 and w15b != null, "G15: save/load succeeds")
	var griev15_ok := true
	for k in range(4):
		if not t.approx(w15b.units.griev[u15 * 4 + k], w15.units.griev[u15 * 4 + k]):
			griev15_ok = false
	t.check(griev15_ok, "G15b: units.griev round-trip")
	t.check(t.approx(w15b.town_griev[t15], w15.town_griev[t15]), "G15c: town_griev round-trip")

	# 16. World smoke: grievance rises over simulated time.
	var w16 := World.create(3)
	var cap16 := -1
	for u in range(w16.units.n):
		if w16.units.alive[u] == 1 and w16.units.is_captain[u] == 1:
			cap16 = u
			break
	t.check(cap16 >= 0, "G16: found an alive captain")

	for _i in range(120):
		WorldSim.step(w16, Tuning.DT)

	t.check(w16.units.griev[cap16 * 4 + 0] > 0.0, "G16b: first captain's g0 > 0.0 after 120 steps")

	t.finish()
	quit()
