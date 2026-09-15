extends SceneTree
## Tests for Dissent (values, bond, disaffection, power, tension), the
## Units.vals/bond and World.town_vals fields, and the seam's call-site hooks
## in Lineage/Heroes/Settling/PlinkoOutcomes/WorldSim. Observe-only: nothing
## in the sim reads these for decisions in this step.
## Source: .warboss-horde/slices/dissent-seam.md.

const Kit = preload("res://scripts/tests/test_kit.gd")


## Five copies of `x`.
func _five(x: float) -> PackedFloat32Array:
	return PackedFloat32Array([x, x, x, x, x])


## Writes `w.units.vals[u*5+k] = arr[k]` for k 0..4.
func _set_vals(w: World, u: int, arr: PackedFloat32Array) -> void:
	for k in range(5):
		w.units.vals[u * 5 + k] = arr[k]


func _init() -> void:
	var t := Kit.new()

	# 1. event_deltas.
	var raze1: PackedFloat32Array = Dissent.event_deltas("raze")
	t.check(t.approx(raze1[0], 0.0) and t.approx(raze1[1], 0.0) and t.approx(raze1[2], 0.05)
		and t.approx(raze1[3], -0.03) and t.approx(raze1[4], 0.0), "D1: event_deltas(raze)")

	var bogus1: PackedFloat32Array = Dissent.event_deltas("bogus")
	var bogus1_ok := true
	for k in range(5):
		var v: float = bogus1[k]
		if not t.approx(v, 0.0):
			bogus1_ok = false
	t.check(bogus1_ok, "D1b: event_deltas(bogus) -> five 0.0")

	var retreat1: PackedFloat32Array = Dissent.event_deltas("retreat")
	t.check(t.approx(retreat1[0], -0.02) and t.approx(retreat1[1], 0.0) and t.approx(retreat1[2], 0.0)
		and t.approx(retreat1[3], 0.0) and t.approx(retreat1[4], -0.02), "D1c: event_deltas(retreat)")

	# 2. distance.
	var d2: float = Dissent.distance(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]), PackedFloat32Array([1.0, 0.5, 0.0, 0.0, 0.0]))
	t.check(t.approx(d2, 0.3), "D2: distance == 0.3")

	# 3. kingdom_vals.
	var w3a := World.new()
	var kv3a: PackedFloat32Array = Dissent.kingdom_vals(w3a, 0)
	var kv3a_ok := true
	for k in range(5):
		var v: float = kv3a[k]
		if not t.approx(v, 0.5):
			kv3a_ok = false
	t.check(kv3a_ok, "D3: kingdom_vals(World.new(), 0) -> five 0.5 (ktraits empty)")

	var w3b := World.new()
	w3b.setup_blank(20, 20, 7)
	var kv3b: PackedFloat32Array = Dissent.kingdom_vals(w3b, -1)
	var kv3b_ok := true
	for k in range(5):
		var v: float = kv3b[k]
		if not t.approx(v, 0.5):
			kv3b_ok = false
	t.check(kv3b_ok, "D3b: kingdom_vals(w, -1) -> five 0.5")

	w3b.ktraits[1 * 5 + 2] = 0.9
	var kv3c: PackedFloat32Array = Dissent.kingdom_vals(w3b, 1)
	t.check(t.approx(kv3c[2], 0.9), "D3c: kingdom_vals(w, 1)[2] == 0.9")

	# 4. Units.new fields.
	var u4d := Units.new(4)
	t.check(u4d.vals.size() == 20, "D4: Units.new(4) vals.size() == 20")
	t.check(u4d.bond.size() == 4, "D4b: Units.new(4) bond.size() == 4")
	var vals4_ok := true
	for i in range(u4d.vals.size()):
		var v: float = u4d.vals[i]
		if not t.approx(v, 0.0):
			vals4_ok = false
	t.check(vals4_ok, "D4c: Units.new(4) vals all 0.0")
	var bond4_ok := true
	for i in range(u4d.bond.size()):
		var v2: float = u4d.bond[i]
		if not t.approx(v2, 0.0):
			bond4_ok = false
	t.check(bond4_ok, "D4d: Units.new(4) bond all 0.0")

	# 5. Recycle resets vals/bond.
	var u5 := Units.new(2)
	u5.add(0, 0, 0, false, -1)
	u5.add(0, 0, 0, false, -1)
	for k in range(5):
		u5.vals[5 + k] = 0.7
	u5.bond[1] = 0.9
	u5.alive[1] = 0
	u5.reusable[1] = 1
	var rid5 := u5.add(0, 0, 0, false, -1)
	t.check(rid5 == 1, "D5: recycle returns 1")
	var reset5_ok := true
	for k in range(5):
		var v: float = u5.vals[5 + k]
		if not t.approx(v, 0.0):
			reset5_ok = false
	t.check(reset5_ok, "D5b: recycled vals[5..9] reset to 0.0")
	t.check(t.approx(u5.bond[1], 0.0), "D5c: recycled bond[1] reset to 0.0")

	# 6. seed_unit determinism + no w.rng draw.
	var w6a := World.new()
	w6a.setup_blank(20, 20, 7)
	var u6a := w6a.units.add(0, 1, 1, false, -1)
	var s0_6a: int = w6a.rng.state
	Dissent.seed_unit(w6a, u6a, _five(0.5))
	t.check(w6a.rng.state == s0_6a, "D6: seed_unit draws no w.rng")
	var range6_ok := true
	var any_diff6 := false
	for k in range(5):
		var v: float = w6a.units.vals[u6a * 5 + k]
		if v < 0.35 or v > 0.65:
			range6_ok = false
		if not t.approx(v, 0.5):
			any_diff6 = true
	t.check(range6_ok, "D6b: seeded vals within [0.35,0.65]")
	t.check(any_diff6, "D6c: at least one seeded val != 0.5")
	t.check(t.approx(w6a.units.bond[u6a], 0.5), "D6d: bond[u] == BOND_INIT")

	var w6b := World.new()
	w6b.setup_blank(20, 20, 7)
	var u6b := w6b.units.add(0, 1, 1, false, -1)
	Dissent.seed_unit(w6b, u6b, _five(0.5))
	var same6_ok := true
	for k in range(5):
		var va: float = w6a.units.vals[u6a * 5 + k]
		var vb: float = w6b.units.vals[u6b * 5 + k]
		if not t.approx(va, vb):
			same6_ok = false
	t.check(same6_ok, "D6e: identical second world gives identical seeded values")

	# 7. seed_unit clamp.
	var w7 := World.new()
	w7.setup_blank(20, 20, 7)
	var u7 := w7.units.add(0, 1, 1, false, -1)
	Dissent.seed_unit(w7, u7, _five(1.0))
	var clamp7_ok := true
	for k in range(5):
		var v: float = w7.units.vals[u7 * 5 + k]
		if v < 0.85 or v > 1.0:
			clamp7_ok = false
	t.check(clamp7_ok, "D7: seed_unit clamps to [0.85,1.0] when src == 1.0")

	# 8. make_captain seeds from kingdom.
	var w8 := World.new()
	w8.setup_blank(20, 20, 7)
	w8.ktraits[0 * 5 + 2] = 0.9
	var u8 := w8.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w8, u8, "Toby")
	var v8_2: float = w8.units.vals[u8 * 5 + 2]
	var v8_0: float = w8.units.vals[u8 * 5 + 0]
	t.check(v8_2 >= 0.75 and v8_2 <= 1.0, "D8: make_captain vals[2] in [0.75,1.0]")
	t.check(v8_0 >= 0.35 and v8_0 <= 0.65, "D8b: make_captain vals[0] in [0.35,0.65]")
	t.check(t.approx(w8.units.bond[u8], 0.5), "D8c: make_captain bond == 0.5")

	# 9. promote seeds from kingdom.
	var w9 := World.new()
	w9.setup_blank(20, 20, 7)
	w9.ktraits[0 * 5 + 3] = 0.1
	var cpos9 := w9.map.center_of(5, 4)
	var s9 := w9.stacks.add(0, cpos9.x, cpos9.y, "S9")
	var u9 := w9.units.add(0, 0, 1, false, s9)
	Heroes.promote(w9, u9)
	var v9_3: float = w9.units.vals[u9 * 5 + 3]
	t.check(v9_3 >= 0.0 and v9_3 <= 0.25, "D9: promote vals[3] in [0.0,0.25]")
	t.check(t.approx(w9.units.bond[u9], 0.5), "D9b: promote bond == 0.5")

	# 10. succeed seeds a non-hero heir, leaves a hero heir's vals alone.
	var w10a := World.new()
	w10a.setup_blank(20, 20, 7)
	var cpos10a := w10a.map.center_of(5, 4)
	var s10a := w10a.stacks.add(0, cpos10a.x, cpos10a.y, "S10a")
	var cap10a := w10a.units.add(0, 1, 1, true, s10a)
	Lineage.make_captain(w10a, cap10a, "Toby")
	_set_vals(w10a, cap10a, _five(0.9))
	var h10a := w10a.units.add(0, 0, 1, false, s10a)
	w10a.units.kills[h10a] = 5
	w10a.units.kill(cap10a)
	Lineage.succeed(w10a, s10a, cap10a)
	t.check(w10a.stacks.captain_unit[s10a] == h10a, "D10: succeed captain_unit == heir")
	var seeded10_ok := true
	for k in range(5):
		var v: float = w10a.units.vals[h10a * 5 + k]
		if v < 0.75 or v > 1.0:
			seeded10_ok = false
	t.check(seeded10_ok, "D10b: heir vals in [0.75,1.0]")
	t.check(t.approx(w10a.units.bond[h10a], 0.5), "D10c: heir bond == 0.5")

	var w10b := World.new()
	w10b.setup_blank(20, 20, 7)
	var cpos10b := w10b.map.center_of(5, 4)
	var s10b := w10b.stacks.add(0, cpos10b.x, cpos10b.y, "S10b")
	var cap10b := w10b.units.add(0, 1, 1, true, s10b)
	Lineage.make_captain(w10b, cap10b, "Toby")
	var h10b := w10b.units.add(0, 0, 1, false, s10b)
	w10b.units.kills[h10b] = 5
	w10b.units.hero[h10b] = 1
	_set_vals(w10b, h10b, _five(0.2))
	w10b.units.kill(cap10b)
	Lineage.succeed(w10b, s10b, cap10b)
	var stay10_ok := true
	for k in range(5):
		var v: float = w10b.units.vals[h10b * 5 + k]
		if not t.approx(v, 0.2):
			stay10_ok = false
	t.check(stay10_ok, "D10d: hero heir vals stay 0.2 after succeed")

	# 11. on_stack_event.
	var w11 := World.new()
	w11.setup_blank(20, 20, 7)
	var cpos11 := w11.map.center_of(5, 4)
	var s11 := w11.stacks.add(0, cpos11.x, cpos11.y, "S11")
	var cap11 := w11.units.add(0, 1, 1, true, s11)
	_set_vals(w11, cap11, _five(0.5))
	w11.units.bond[cap11] = 0.5
	var h11 := w11.units.add(0, 0, 1, false, s11)
	w11.units.hero[h11] = 1
	_set_vals(w11, h11, _five(0.5))
	w11.units.bond[h11] = 0.5
	var p11 := w11.units.add(0, 0, 1, false, s11)
	var d11 := w11.units.add(0, 0, 1, false, s11)
	w11.units.hero[d11] = 1
	_set_vals(w11, d11, _five(0.5))
	w11.units.kill(d11)
	var os11 := w11.stacks.add(0, cpos11.x, cpos11.y, "OS11")
	var o11 := w11.units.add(0, 0, 1, false, os11)
	w11.units.hero[o11] = 1
	_set_vals(w11, o11, _five(0.5))

	Dissent.on_stack_event(w11, "raze", s11)
	t.check(t.approx(w11.units.vals[cap11 * 5 + 2], 0.6), "D11: raze c[2] == 0.6")
	t.check(t.approx(w11.units.vals[cap11 * 5 + 3], 0.44), "D11b: raze c[3] == 0.44")
	t.check(t.approx(w11.units.vals[h11 * 5 + 2], 0.6), "D11c: raze h[2] same as c")
	t.check(t.approx(w11.units.vals[h11 * 5 + 3], 0.44), "D11d: raze h[3] same as c")
	t.check(t.approx(w11.units.bond[cap11], 0.5), "D11e: raze leaves c bond at 0.5")
	var p11_ok := true
	for k in range(5):
		var v: float = w11.units.vals[p11 * 5 + k]
		if not t.approx(v, 0.0):
			p11_ok = false
	t.check(p11_ok, "D11f: raze leaves plain soldier vals at 0.0")
	var d11_ok := true
	for k in range(5):
		var v: float = w11.units.vals[d11 * 5 + k]
		if not t.approx(v, 0.5):
			d11_ok = false
	t.check(d11_ok, "D11g: raze leaves dead hero vals at 0.5")
	var o11_ok := true
	for k in range(5):
		var v: float = w11.units.vals[o11 * 5 + k]
		if not t.approx(v, 0.5):
			o11_ok = false
	t.check(o11_ok, "D11h: raze leaves other-stack hero vals at 0.5")

	Dissent.on_stack_event(w11, "win", s11)
	t.check(t.approx(w11.units.vals[cap11 * 5 + 0], 0.54), "D11i: win c[0] == 0.54")
	t.check(t.approx(w11.units.bond[cap11], 0.52), "D11j: win c bond == 0.52")

	Dissent.on_stack_event(w11, "retreat", s11)
	t.check(t.approx(w11.units.vals[cap11 * 5 + 0], 0.5), "D11k: retreat c[0] == 0.5")
	t.check(t.approx(w11.units.vals[cap11 * 5 + 4], 0.46), "D11l: retreat c[4] == 0.46")
	t.check(t.approx(w11.units.bond[cap11], 0.49), "D11m: retreat c bond == 0.49")

	# 12. tick bond.
	var w12 := World.new()
	w12.setup_blank(20, 20, 7)
	var cpos12 := w12.map.center_of(5, 4)
	var s12 := w12.stacks.add(0, cpos12.x, cpos12.y, "S12")
	var cap12 := w12.units.add(0, 1, 1, true, s12)
	w12.units.bond[cap12] = 0.5
	var retired12 := w12.units.add(0, 0, 1, false, -1)
	w12.units.hero[retired12] = 1
	w12.units.fate[retired12] = Units.Fate.RETIRED
	w12.units.bond[retired12] = 0.5
	var soldier12 := w12.units.add(0, 0, 1, false, s12)
	var lord12 := w12.units.add(0, 0, 1, false, -1)
	w12.units.fate[lord12] = Units.Fate.LORD
	w12.units.bond[lord12] = 0.5

	Dissent.tick(w12)
	t.check(t.approx(w12.units.bond[cap12], 0.501), "D12: tick captain bond -> 0.501")
	t.check(t.approx(w12.units.bond[retired12], 0.5), "D12b: tick RETIRED hero bond unchanged")
	t.check(t.approx(w12.units.bond[soldier12], 0.0), "D12c: tick plain soldier bond unchanged")
	t.check(t.approx(w12.units.bond[lord12], 0.5), "D12d: tick LORD bond unchanged")

	# 13. tick towns.
	var w13 := World.new()
	w13.setup_blank(20, 20, 7)
	var t0_13 := w13.add_town(Vector2i(1, 1), 0)
	for k in range(5):
		w13.town_vals[t0_13 * 5 + k] = 0.0
	w13.town_lord[t0_13] = -1

	var t1_13 := w13.add_town(Vector2i(2, 2), 0)
	for k in range(5):
		w13.town_vals[t1_13 * 5 + k] = 0.0
	var lord13 := w13.units.add(0, 1, 1, false, -1)
	_set_vals(w13, lord13, _five(1.0))
	w13.town_lord[t1_13] = lord13

	var t2_13 := w13.add_town(Vector2i(3, 3), -1)
	for k in range(5):
		w13.town_vals[t2_13 * 5 + k] = 0.0

	var t3_13 := w13.add_town(Vector2i(4, 4), 0)
	for k in range(5):
		w13.town_vals[t3_13 * 5 + k] = 0.0
	var dead_lord13 := w13.units.add(0, 1, 1, false, -1)
	_set_vals(w13, dead_lord13, _five(1.0))
	w13.units.kill(dead_lord13)
	w13.town_lord[t3_13] = dead_lord13

	Dissent.tick(w13)

	var t0_ok := true
	for k in range(5):
		if not t.approx(w13.town_vals[t0_13 * 5 + k], 0.002):
			t0_ok = false
	t.check(t0_ok, "D13: town t0 (no lord) -> 0.002")

	var t1_ok := true
	for k in range(5):
		if not t.approx(w13.town_vals[t1_13 * 5 + k], 0.006):
			t1_ok = false
	t.check(t1_ok, "D13b: town t1 (alive lord) -> 0.006")

	var t2_ok := true
	for k in range(5):
		if not t.approx(w13.town_vals[t2_13 * 5 + k], 0.0):
			t2_ok = false
	t.check(t2_ok, "D13c: town t2 (owner -1) unchanged")

	var t3_ok := true
	for k in range(5):
		if not t.approx(w13.town_vals[t3_13 * 5 + k], 0.002):
			t3_ok = false
	t.check(t3_ok, "D13d: town t3 (dead lord) -> 0.002")

	# 14. add_town seeds town_vals; sync_town_arrays fills KTRAIT_INIT.
	var w14 := World.new()
	w14.setup_blank(20, 20, 7)
	w14.ktraits[1 * 5 + 0] = 0.8
	var t14a := w14.add_town(Vector2i(3, 3), 1)
	t.check(t.approx(w14.town_vals[t14a * 5 + 0], 0.8), "D14: add_town seeds vals[0] from owner ktrait")
	t.check(t.approx(w14.town_vals[t14a * 5 + 1], 0.5), "D14b: add_town seeds vals[1] from owner ktrait (default 0.5)")

	var t14b := w14.add_town(Vector2i(10, 10), -1)
	var t14b_ok := true
	for k in range(5):
		if not t.approx(w14.town_vals[t14b * 5 + k], 0.5):
			t14b_ok = false
	t.check(t14b_ok, "D14c: add_town owner -1 -> five KTRAIT_INIT")

	w14.towns.append(Vector2(15, 15))
	w14.town_owner.append(0)
	w14.sync_town_arrays()
	t.check(w14.town_vals.size() == w14.towns.size() * 5, "D14d: sync_town_arrays sizes town_vals to towns*5")
	var last14_ok := true
	var last14_t := w14.towns.size() - 1
	for k in range(5):
		if not t.approx(w14.town_vals[last14_t * 5 + k], 0.5):
			last14_ok = false
	t.check(last14_ok, "D14e: sync_town_arrays fills new entries with KTRAIT_INIT")

	# 15. found_town copies lord values.
	var w15 := World.new()
	w15.setup_blank(20, 20, 7)
	w15.faction_count = 1
	w15.faction_alive[0] = 1
	w15.faction_names = ["Alpha"]
	var cpos15 := w15.map.center_of(5, 4)
	var s15 := w15.stacks.add(0, cpos15.x, cpos15.y, "S15")
	var cap15 := w15.units.add(0, 1, 1, true, s15)
	Lineage.make_captain(w15, cap15, "Toby")
	_set_vals(w15, cap15, _five(0.9))
	w15.stacks.captain_unit[s15] = cap15
	w15.stacks.count[s15] = 1
	var t15 := Settling.found_town(w15, s15, w15.stack_tile(s15))
	t.check(t15 >= 0, "D15: found_town succeeds")
	var vals15_ok := true
	for k in range(5):
		if not t.approx(w15.town_vals[t15 * 5 + k], 0.9):
			vals15_ok = false
	t.check(vals15_ok, "D15b: found_town copies lord vals into town_vals")

	# 16. disaffection.
	var w16 := World.new()
	w16.setup_blank(20, 20, 7)
	var cap16 := w16.units.add(0, 1, 1, true, -1)
	_set_vals(w16, cap16, PackedFloat32Array([1.0, 0.5, 0.5, 0.5, 0.5]))
	w16.units.bond[cap16] = 0.4
	t.check(t.approx(Dissent.unit_disaffection(w16, cap16), 0.0), "D16: unit_disaffection bond 0.4 -> 0.0")
	w16.units.bond[cap16] = 0.0
	t.check(t.approx(Dissent.unit_disaffection(w16, cap16), 0.1), "D16b: unit_disaffection bond 0.0 -> 0.1")

	var town16a := w16.add_town(Vector2i(1, 1), -1)
	t.check(t.approx(Dissent.town_disaffection(w16, town16a), 0.0), "D16c: town_disaffection owner -1 -> 0.0")

	var town16b := w16.add_town(Vector2i(2, 2), 0)
	for k in range(5):
		w16.town_vals[town16b * 5 + k] = 0.0
	t.check(t.approx(Dissent.town_disaffection(w16, town16b), 0.5), "D16d: town_disaffection owner 0 vals 0 -> 0.5")

	# 17. power.
	var w17 := World.new()
	w17.setup_blank(20, 20, 7)
	var lord17 := w17.units.add(0, 1, 1, false, -1)
	w17.units.fate[lord17] = Units.Fate.LORD
	t.check(t.approx(Dissent.unit_power(w17, lord17), Tuning.POWER_LORD), "D17: unit_power LORD == POWER_LORD")

	var cpos17 := w17.map.center_of(5, 4)
	var s17 := w17.stacks.add(0, cpos17.x, cpos17.y, "S17")
	w17.stacks.count[s17] = 40
	var cap17 := w17.units.add(0, 1, 1, true, s17)
	w17.stacks.captain_unit[s17] = cap17
	t.check(t.approx(Dissent.unit_power(w17, cap17), 40.0), "D17b: unit_power captain == stack count")

	var hero17 := w17.units.add(0, 0, 1, false, -1)
	w17.units.hero[hero17] = 1
	t.check(t.approx(Dissent.unit_power(w17, hero17), Tuning.POWER_HERO), "D17c: unit_power hero (not captain) == POWER_HERO")

	var town17 := w17.add_town(Vector2i(1, 1), 0)
	w17.town_pop[town17] = 50.0
	t.check(t.approx(Dissent.town_power(w17, town17), 50.0), "D17d: town_power == town_pop")

	# 18. tension.
	var w18 := World.new()
	w18.setup_blank(20, 20, 7)
	var cpos18 := w18.map.center_of(5, 4)
	var s18 := w18.stacks.add(0, cpos18.x, cpos18.y, "S18")
	w18.stacks.count[s18] = 40
	var cap18 := w18.units.add(0, 1, 1, true, s18)
	w18.stacks.captain_unit[s18] = cap18
	_set_vals(w18, cap18, PackedFloat32Array([1.0, 0.5, 0.5, 0.5, 0.5]))
	w18.units.bond[cap18] = 0.0

	var hero18 := w18.units.add(0, 0, 1, false, -1)
	w18.units.hero[hero18] = 1
	_set_vals(w18, hero18, _five(0.5))
	w18.units.bond[hero18] = 0.5

	var town18 := w18.add_town(Vector2i(1, 1), 0)
	w18.town_pop[town18] = 50.0
	for k in range(5):
		w18.town_vals[town18 * 5 + k] = 0.0

	var retired18 := w18.units.add(0, 0, 1, false, -1)
	w18.units.fate[retired18] = Units.Fate.RETIRED
	_set_vals(w18, retired18, _five(0.0))

	var soldier18 := w18.units.add(0, 0, 1, false, s18)

	t.check(t.approx(Dissent.tension(w18, 0), 29.0 / 95.0), "D18: tension faction 0 == 29/95")
	t.check(t.approx(Dissent.tension(w18, 3), 0.0), "D18b: tension faction 3 (no members) == 0.0")

	# 19. save/load round-trip (reusing the world from case 18).
	const SAVE_PATH := "user://test_dissent.sav"
	var save_ok19: bool = SaveGame.save(w18, SAVE_PATH) == OK
	var w19: World = SaveGame.load(SAVE_PATH)
	t.check(save_ok19 and w19 != null, "D19: save/load succeeds")
	var cap_vals19_ok := true
	for k in range(5):
		if not t.approx(w19.units.vals[cap18 * 5 + k], w18.units.vals[cap18 * 5 + k]):
			cap_vals19_ok = false
	t.check(cap_vals19_ok, "D19b: captain vals round-trip")
	t.check(t.approx(w19.units.bond[hero18], w18.units.bond[hero18]), "D19c: hero bond round-trip")
	var town_vals19_ok := true
	for k in range(5):
		if not t.approx(w19.town_vals[town18 * 5 + k], w18.town_vals[town18 * 5 + k]):
			town_vals19_ok = false
	t.check(town_vals19_ok, "D19d: town_vals round-trip")

	# 20. hooks smoke: PlinkoOutcomes._raze and WorldSim._on_arrive(PILGRIMAGE).
	var w20 := World.new()
	w20.setup_blank(20, 20, 7)
	var cpos20 := w20.map.center_of(5, 4)
	var s20 := w20.stacks.add(0, cpos20.x, cpos20.y, "S20")
	var cap20 := w20.units.add(0, 1, 1, true, s20)
	w20.stacks.captain_unit[s20] = cap20
	_set_vals(w20, cap20, _five(0.5))

	PlinkoOutcomes._raze(w20, s20, 0)
	t.check(t.approx(w20.units.vals[cap20 * 5 + 2], 0.6), "D20: PlinkoOutcomes._raze bumps captain vals[2] to 0.6")

	w20.stacks.goal[s20] = Stacks.Goal.PILGRIMAGE
	var before20: float = w20.units.vals[cap20 * 5 + 3]
	# UNDECIDED: the contract phrase "captain vals[3] approx 0.5 + 0.1 more
	# than before the call" reads as two things (an absolute ~0.5 and a +0.1
	# delta) that can't both hold here, since the preceding _raze call already
	# moved vals[3] to 0.44. Only the unambiguous delta ("0.1 more than before
	# the call") is checked below.
	WorldSim._on_arrive(w20, s20)
	var after20: float = w20.units.vals[cap20 * 5 + 3]
	t.check(t.approx(after20, before20 + 0.1), "D20b: WorldSim._on_arrive PILGRIMAGE bumps captain vals[3] by 0.1")

	# 21. World smoke.
	var a21 := World.create(3)
	var b21 := World.create(3)
	t.check(a21.units.vals == b21.units.vals, "D21: World.create determinism, vals match")

	var caps21_ok := true
	var first_cap21 := -1
	for u in range(a21.units.n):
		if a21.units.alive[u] == 1 and a21.units.is_captain[u] == 1:
			if first_cap21 == -1:
				first_cap21 = u
			if not t.approx(a21.units.bond[u], 0.5):
				caps21_ok = false
			for k in range(5):
				var v: float = a21.units.vals[u * 5 + k]
				if v < 0.0 or v > 1.0:
					caps21_ok = false
	t.check(caps21_ok, "D21b: every alive captain has bond ~0.5 and vals in [0,1]")
	t.check(first_cap21 >= 0, "D21c: found at least one alive captain")

	for _i in range(120):
		WorldSim.step(a21, Tuning.DT)

	t.check(a21.units.bond[first_cap21] > 0.5, "D21d: first captain's bond increased after 120 steps")

	t.finish()
	quit()
