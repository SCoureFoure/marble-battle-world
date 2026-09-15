extends SceneTree
## Tests for Heroes.check_promote / promote / defect_chance / check_breakaway /
## breakaway_chance / breakaway / successor. See .warboss-horde/slices/m9-heroes.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 12x8 world, seed 7, faction 0 alive, named "Alpha", time 100.0.
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 7)
	w.faction_count = 1
	w.faction_alive[0] = 1
	w.faction_names = ["Alpha"]
	w.time = 100.0
	return w


## `n_units` rank-0 sword units + one rank-1 captain via
## Lineage.make_captain(w, id, "Toby"), stack named "S".
func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	for _i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	Lineage.make_captain(w, cap_id, "Toby")
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


## Sets hero `u`'s five values to `v`, bond to `b`, and all four grievances to `g`.
func set_mood(w: World, u: int, v: float, b: float, g: float) -> void:
	for k in range(5):
		w.units.vals[u * 5 + k] = v
	w.units.bond[u] = b
	for d in range(4):
		w.units.griev[u * 4 + d] = g


func _init() -> void:
	var t := TestKit.new()

	# 1. promote draw order.
	var w1 := mk_world()
	var s1 := mk_stack(w1, 0, 5, 4, 1)
	var u1 := 0  # first (and only) sword unit added, fresh world
	w1.units.kills[u1] = 25

	var m := RandomNumberGenerator.new()
	m.seed = 7
	var amb := m.randf()
	var base := NameGen.captain_name_base(m)
	var adj := NameGen.hero_epithet(m)

	t.check(Heroes.check_promote(w1, u1, false) == true, "case1 check_promote == true")
	t.check(w1.units.hero[u1] == 1, "case1 hero[u] == 1")
	t.check(w1.units.ambition[u1] == amb, "case1 ambition[u] == amb")
	t.check(w1.units.names[u1] == base + " the " + adj, "case1 names[u] == base the adj")
	var dyn1: Array = w1.units.dynasty[u1]
	t.check(dyn1[0] == base and int(dyn1[1]) == 1, "case1 dynasty[u] == [base, 1]")
	t.check(w1.units.career_start[u1] == 100.0, "case1 career_start[u] == 100.0")
	t.check(int(w1.history.get("promotions", 0)) == 1, "case1 history promotions == 1")
	var last1 := String(w1.events_log[w1.events_log.size() - 1])
	t.check(last1 == str(w1.units.names.get(u1, "Unit %d" % u1)) + " rises from the ranks of S", "case1 events_log last line")

	# 2. check_promote gates (fresh units each).
	var w2 := mk_world()

	var ua := w2.units.add(0, 2, 1, false, -1)
	w2.units.kills[ua] = 24
	t.check(Heroes.check_promote(w2, ua, false) == false, "case2a kills 24 rank 2 slew false -> false")
	t.check(w2.units.hero[ua] == 0, "case2a hero[u] == 0")

	var ub := w2.units.add(0, 0, 1, false, -1)
	w2.units.kills[ub] = 0
	t.check(Heroes.check_promote(w2, ub, true) == true, "case2b kills 0 slew true -> true")

	var uc := w2.units.add(0, 3, 1, false, -1)
	w2.units.kills[uc] = 0
	t.check(Heroes.check_promote(w2, uc, false) == true, "case2c rank 3 kills 0 -> true")

	var ud := w2.units.add(0, 0, 1, true, -1)
	w2.units.kills[ud] = 99
	t.check(Heroes.check_promote(w2, ud, false) == false, "case2d is_captain == 1 kills 99 -> false")

	var ue := w2.units.add(0, 0, 1, false, -1)
	w2.units.kills[ue] = 99
	w2.units.hero[ue] = 1
	var promotions_before2 := int(w2.history.get("promotions", 0))
	t.check(Heroes.check_promote(w2, ue, true) == false, "case2e already hero == 1 -> false")
	t.check(int(w2.history.get("promotions", 0)) == promotions_before2, "case2e promotions not incremented again")

	var uf := w2.units.add(0, 0, 1, false, -1)
	w2.units.kills[uf] = 99
	w2.units.alive[uf] = 0
	t.check(Heroes.check_promote(w2, uf, true) == false, "case2f alive == 0 kills 99 -> false")

	# 3. defect_chance.
	var w3 := mk_world()
	var s3 := mk_stack(w3, 0, 5, 4, 1)
	var h3 := 0
	var c3 := w3.stacks.captain_unit[s3]
	var f3 := w3.stacks.faction[s3]

	w3.units.ambition[h3] = 0.5
	t.check(t.approx(Heroes.defect_chance(w3, h3), 0.45), "case3 defaults, ambition 0.5, kills 0/0 -> 0.45")

	w3.units.ambition[h3] = 1.0
	w3.ktraits[f3 * 5 + 4] = 0.0
	w3.ktraits[f3 * 5 + 3] = 0.0
	t.check(t.approx(Heroes.defect_chance(w3, h3), 0.95), "case3 ambition 1.0, cohesion/piety 0.0 -> 0.95 clamped")

	w3.units.ambition[h3] = 0.0
	w3.ktraits[f3 * 5 + 4] = 1.0
	w3.ktraits[f3 * 5 + 3] = 1.0
	t.check(t.approx(Heroes.defect_chance(w3, h3), 0.05), "case3 ambition 0.0, cohesion/piety 1.0 -> 0.05 clamped")

	w3.units.ambition[h3] = 0.0
	w3.ktraits[f3 * 5 + 4] = 0.5
	w3.ktraits[f3 * 5 + 3] = 0.5
	w3.units.kills[h3] = 10
	w3.units.kills[c3] = 5
	t.check(t.approx(Heroes.defect_chance(w3, h3), 0.35), "case3 ambition 0.0 defaults, kills 10/5 -> 0.35")

	w3.units.kills[h3] = 5
	t.check(t.approx(Heroes.defect_chance(w3, h3), 0.15), "case3 ambition 0.0 defaults, kills 5/5 -> 0.15")

	# 4. breakaway loyal (force_defect = 0).
	var w4 := mk_world()
	var s4 := mk_stack(w4, 0, 5, 4, 60)
	var c4 := w4.stacks.captain_unit[s4]
	w4.units.kills[c4] = 5
	var h4 := w4.units.add(0, 0, 1, false, s4)
	w4.units.hero[h4] = 1
	w4.units.kills[h4] = 10
	var h4b := w4.units.add(0, 0, 1, false, s4)
	w4.units.hero[h4b] = 1
	w4.units.kills[h4b] = 0
	w4.stacks.recount(w4.units)
	w4.stacks.gold[s4] = 100.0
	t.check(w4.stacks.count[s4] == 63, "case4 count[s] == 63 before breakaway")

	var ns4 := Heroes.breakaway(w4, h4, 0)
	t.check(ns4 == 1, "case4 ns == 1")
	t.check(w4.stacks.faction[ns4] == 0, "case4 faction[ns] == 0")
	t.check(w4.stacks.count[ns4] == 15, "case4 count[ns] == 15")
	t.check(w4.stacks.count[s4] == 48, "case4 count[s] == 48")
	t.check(w4.stacks.captain_unit[ns4] == h4, "case4 captain_unit[ns] == h")
	t.check(w4.units.is_captain[h4] == 1, "case4 is_captain[h] == 1")
	t.check(w4.units.mentor[h4] == c4, "case4 mentor[h] == c")
	t.check(w4.units.stack[h4b] == s4, "case4 heroes never follow: stack[h2] == s")
	t.check(w4.units.stack[c4] == s4, "case4 stack[c] == s")
	t.check(t.approx(w4.stacks.gold[ns4], 100.0 * 15.0 / 63.0), "case4 gold[ns] ~= 100*15/63")
	t.check(t.approx(w4.stacks.gold[s4], 100.0 - 100.0 * 15.0 / 63.0), "case4 gold[s] ~= 100 - 100*15/63")
	var pos4 := w4.map.center_of(5, 3)
	t.check(t.approx(w4.stacks.x[ns4], pos4.x) and t.approx(w4.stacks.y[ns4], pos4.y), "case4 stack position == center_of(5,3)")
	t.check(t.approx(w4.stacks.immunity[ns4], Tuning.RETREAT_IMMUNITY), "case4 immunity[ns] == RETREAT_IMMUNITY")
	t.check(w4.stacks.immunity[s4] == 0.0, "case4 immunity[s] == 0.0")
	t.check(int(w4.history.get("breakaways", 0)) == 1, "case4 history breakaways == 1")
	t.check(int(w4.history.get("defections", 0)) == 0, "case4 history defections == 0")
	var last4 := String(w4.events_log[w4.events_log.size() - 1])
	t.check(last4 == str(w4.units.names.get(h4, "Unit %d" % h4)) + " leaves S with 14 men", "case4 last log")

	# 5. breakaway defect (force_defect = 1), same setup in a fresh world.
	var w5 := mk_world()
	var s5 := mk_stack(w5, 0, 5, 4, 60)
	var c5 := w5.stacks.captain_unit[s5]
	w5.units.kills[c5] = 5
	var h5 := w5.units.add(0, 0, 1, false, s5)
	w5.units.hero[h5] = 1
	w5.units.kills[h5] = 10
	var h5b := w5.units.add(0, 0, 1, false, s5)
	w5.units.hero[h5b] = 1
	w5.units.kills[h5b] = 0
	w5.stacks.recount(w5.units)
	w5.stacks.gold[s5] = 100.0

	var ns5 := Heroes.breakaway(w5, h5, 1)
	var g5: int = w5.stacks.faction[ns5]
	t.check(g5 != 0, "case5 g != 0")
	t.check(w5.faction_alive[g5] == 1, "case5 faction_alive[g] == 1")

	var all_g5 := true
	for id5 in range(w5.units.n):
		if w5.units.stack[id5] == ns5 and w5.units.faction[id5] != g5:
			all_g5 = false
	t.check(all_g5, "case5 all 15 units of ns have faction == g")

	t.check(t.approx(w5.relation(0, g5), -0.4), "case5 relation(0,g) ~= -0.4")
	t.check(w5.stacks.immunity[s5] == Tuning.RETREAT_IMMUNITY, "case5 immunity[s] == RETREAT_IMMUNITY")
	t.check(int(w5.history.get("defections", 0)) == 1, "case5 history defections == 1")
	var last5 := String(w5.events_log[w5.events_log.size() - 1])
	t.check(last5.begins_with(str(w5.units.names.get(h5, "Unit %d" % h5)) + " breaks from Alpha, founding the free company "), "case5 last log begins correctly")

	# 6. determinism: two fresh identical worlds.
	var w6a := mk_world()
	var s6a := mk_stack(w6a, 0, 5, 4, 60)
	var c6a := w6a.stacks.captain_unit[s6a]
	w6a.units.kills[c6a] = 5
	var h6a := w6a.units.add(0, 0, 1, false, s6a)
	w6a.units.hero[h6a] = 1
	w6a.units.kills[h6a] = 10
	var h6ab := w6a.units.add(0, 0, 1, false, s6a)
	w6a.units.hero[h6ab] = 1
	w6a.stacks.recount(w6a.units)
	w6a.stacks.gold[s6a] = 100.0
	Heroes.breakaway(w6a, h6a, 0)

	var w6b := mk_world()
	var s6b := mk_stack(w6b, 0, 5, 4, 60)
	var c6b := w6b.stacks.captain_unit[s6b]
	w6b.units.kills[c6b] = 5
	var h6b := w6b.units.add(0, 0, 1, false, s6b)
	w6b.units.hero[h6b] = 1
	w6b.units.kills[h6b] = 10
	var h6bb := w6b.units.add(0, 0, 1, false, s6b)
	w6b.units.hero[h6bb] = 1
	w6b.stacks.recount(w6b.units)
	w6b.stacks.gold[s6b] = 100.0
	Heroes.breakaway(w6b, h6b, 0)

	t.check(w6a.units.stack == w6b.units.stack, "case6 follower unit id lists match")
	t.check(w6a.rng.state == w6b.rng.state, "case6 rng.state matches")

	# 7. stack table full.
	var w7 := mk_world()
	var s7 := mk_stack(w7, 0, 5, 4, 60)
	var c7 := w7.stacks.captain_unit[s7]
	w7.units.kills[c7] = 5
	var h7 := w7.units.add(0, 0, 1, false, s7)
	w7.units.hero[h7] = 1
	w7.units.kills[h7] = 10
	w7.stacks.recount(w7.units)
	w7.stacks.gold[s7] = 100.0

	w7.stacks.n = w7.stacks.cap
	var rng_state_before7 := w7.rng.state
	var stack_before7 := w7.units.stack[h7]
	var result7 := Heroes.breakaway(w7, h7, 0)
	t.check(result7 == -1, "case7 breakaway == -1 when stack table full")
	t.check(w7.rng.state == rng_state_before7, "case7 rng.state unchanged")
	t.check(w7.units.stack[h7] == stack_before7, "case7 units.stack[h] unchanged")

	# 8. small stack.
	var w8 := mk_world()
	var s8 := mk_stack(w8, 0, 5, 4, 8)
	var h8 := w8.units.add(0, 0, 1, false, s8)
	w8.units.hero[h8] = 1
	w8.units.kills[h8] = 0
	w8.stacks.recount(w8.units)
	t.check(w8.stacks.count[s8] == 10, "case8 count[s] == 10")

	var ns8 := Heroes.breakaway(w8, h8, 0)
	t.check(w8.stacks.count[ns8] == 6, "case8 count[ns] == 6 (5 followers)")

	# 9. check_breakaway eligibility (no draws when not eligible).
	var w9a := mk_world()
	var s9a := mk_stack(w9a, 0, 5, 4, 60)
	var h9a := w9a.units.add(0, 0, 1, false, s9a)
	w9a.units.hero[h9a] = 1
	w9a.units.career_start[h9a] = w9a.time
	w9a.stacks.recount(w9a.units)
	var state_before9a := w9a.rng.state
	Heroes.check_breakaway(w9a)
	t.check(w9a.rng.state == state_before9a, "case9a hero age 0 -> no draw")

	var w9b := mk_world()
	var s9b := mk_stack(w9b, 0, 5, 4, 37)
	var h9b := w9b.units.add(0, 0, 1, false, s9b)
	w9b.units.hero[h9b] = 1
	w9b.units.career_start[h9b] = w9b.time - 100.0
	w9b.stacks.recount(w9b.units)
	t.check(w9b.stacks.count[s9b] == 39, "case9b count == 39")
	var state_before9b := w9b.rng.state
	Heroes.check_breakaway(w9b)
	t.check(w9b.rng.state == state_before9b, "case9b stack count 39 -> no draw")

	var w9c := mk_world()
	var s9c := mk_stack(w9c, 0, 5, 4, 60)
	var h9c := w9c.units.add(0, 0, 1, false, s9c)
	w9c.units.hero[h9c] = 1
	w9c.units.career_start[h9c] = w9c.time - 100.0
	w9c.stacks.recount(w9c.units)
	w9c.stacks.state[s9c] = Stacks.State.BATTLE
	var state_before9c := w9c.rng.state
	Heroes.check_breakaway(w9c)
	t.check(w9c.rng.state == state_before9c, "case9c state BATTLE -> no draw")

	var w9d := mk_world()
	var s9d := mk_stack(w9d, 0, 5, 4, 61)
	var h9d := w9d.units.add(0, 0, 1, false, s9d)
	w9d.units.hero[h9d] = 1
	w9d.units.career_start[h9d] = w9d.time - 100.0
	w9d.stacks.recount(w9d.units)
	set_mood(w9d, h9d, 0.5, 0.0, 1.0)
	t.check(w9d.stacks.count[s9d] == 63, "case9d count == 63")

	for k9 in range(1000):
		w9d.time += 1.0
		Heroes.check_breakaway(w9d)

	t.check(int(w9d.history.get("breakaways", 0)) == 1, "case9d breakaways == 1 after 1000 checks")
	t.check(w9d.stacks.n == 2, "case9d stacks.n == 2")

	# 9e. content hero (disaffection <= 0) never breaks away and draws nothing.
	var w9e := mk_world()
	var s9e := mk_stack(w9e, 0, 5, 4, 61)
	var h9e := w9e.units.add(0, 0, 1, false, s9e)
	w9e.units.hero[h9e] = 1
	w9e.units.career_start[h9e] = w9e.time - 100.0
	w9e.stacks.recount(w9e.units)
	set_mood(w9e, h9e, 0.5, 1.0, 0.0)
	var state_before9e := w9e.rng.state
	for k9e in range(1000):
		w9e.time += 1.0
		Heroes.check_breakaway(w9e)
	t.check(w9e.rng.state == state_before9e, "case9e content hero -> no draw in 1000 checks")
	t.check(int(w9e.history.get("breakaways", 0)) == 0, "case9e breakaways == 0")
	t.check(w9e.stacks.n == 1, "case9e stacks.n == 1")

	# 10. successor (build stacks by hand).
	var w10 := mk_world()

	var s10a := w10.stacks.add(0, 0.0, 0.0, "S10a")
	var u10a := w10.units.add(0, 0, 1, false, s10a)
	t.check(Heroes.successor(w10, u10a, -1) == u10a, "case10a active unit with stack -> u")

	var s10b := w10.stacks.add(0, 0.0, 0.0, "S10b")
	var u10b := w10.units.add(0, 0, 1, false, s10b)
	var c2_10b := w10.units.add(0, 1, 1, true, s10b)
	w10.stacks.captain_unit[s10b] = c2_10b
	w10.units.kill(u10b)
	t.check(Heroes.successor(w10, u10b, s10b) == c2_10b, "case10b killed u -> last_stack captain c2")

	var u10c := w10.units.add(0, 0, 1, false, -1)
	w10.units.kill(u10c)
	var s10c := w10.stacks.add(0, 0.0, 0.0, "S10c")
	w10.stacks.alive[s10c] = 0
	var stack10c := w10.stacks.add(0, 0.0, 0.0, "S10c2")
	var v1_10c := w10.units.add(0, 0, 1, false, stack10c)
	w10.units.mentor[v1_10c] = u10c
	w10.units.kills[v1_10c] = 3
	var v2_10c := w10.units.add(0, 0, 1, false, stack10c)
	w10.units.mentor[v2_10c] = u10c
	w10.units.kills[v2_10c] = 7
	t.check(Heroes.successor(w10, u10c, s10c) == v2_10c, "case10c last_stack dead, offshoot v2 more kills -> v2")

	w10.units.kills[v1_10c] = 7
	t.check(Heroes.successor(w10, u10c, s10c) == v1_10c, "case10c tie -> lower id v1")

	var u10d := w10.units.add(0, 0, 1, false, -1)
	w10.units.kill(u10d)
	t.check(Heroes.successor(w10, u10d, -1) == -1, "case10d no offshoots, last_stack -1 -> -1")

	var u10e := w10.units.add(0, 0, 1, false, -1)
	w10.units.fate[u10e] = Units.Fate.RETIRED
	w10.units.alive[u10e] = 1
	w10.units.stack[u10e] = -1
	var s10e := w10.stacks.add(0, 0.0, 0.0, "S10e")
	w10.stacks.captain_unit[s10e] = u10e
	t.check(Heroes.successor(w10, u10e, s10e) == -1, "case10e stale captain_unit == u skips step 2, falls to offshoots -> -1")

	# 11. breakaway_chance scales with disaffection, clamped.
	var w11 := mk_world()
	var s11 := mk_stack(w11, 0, 5, 4, 10)
	var h11 := w11.units.add(0, 0, 1, false, s11)
	w11.units.hero[h11] = 1
	t.check(t.approx(Dissent.kingdom_vals(w11, 0)[0], 0.5), "case11 kingdom values 0.5")
	set_mood(w11, h11, 0.5, 0.0, 0.5)
	t.check(t.approx(Heroes.breakaway_chance(w11, h11), 0.01), "case11 dis 0.25 -> 0.01")
	set_mood(w11, h11, 0.5, 0.0, 1.0)
	t.check(t.approx(Heroes.breakaway_chance(w11, h11), 0.02), "case11 dis 0.5 -> 0.02")
	set_mood(w11, h11, 0.5, 1.0, 0.0)
	t.check(t.approx(Heroes.breakaway_chance(w11, h11), 0.0), "case11 dis -0.25 -> 0.0")
	set_mood(w11, h11, 1.0, 0.0, 1.0)
	t.check(t.approx(Heroes.breakaway_chance(w11, h11), 0.02), "case11 dis 1.0 clamps -> 0.02")
	set_mood(w11, h11, 0.5, 0.5, 0.75)
	t.check(t.approx(Heroes.breakaway_chance(w11, h11), 0.01), "case11 dis 0.25 (bond 0.5, griev 0.75) -> 0.01")

	# 12. breakaway relief by motive, stored.
	# 12a: loyal, equal strengths
	var w12a := mk_world()
	var s12a := mk_stack(w12a, 0, 5, 4, 60)
	var h12a := w12a.units.add(0, 0, 1, false, s12a)
	w12a.units.hero[h12a] = 1
	w12a.units.career_start[h12a] = w12a.time - 100.0
	w12a.stacks.recount(w12a.units)
	set_mood(w12a, h12a, 0.5, 0.0, 0.0)
	w12a.units.griev[h12a * 4 + 0] = 0.2
	w12a.units.griev[h12a * 4 + 1] = 0.8
	w12a.units.griev[h12a * 4 + 2] = 0.4
	w12a.units.griev[h12a * 4 + 3] = 0.6

	t.check(Dissent.top_grievance(w12a, h12a) == 1, "case12a top grievance wealth")
	t.check(w12a.units.left_for[h12a] == -1, "case12a never left -> -1")
	var ns12a := Heroes.breakaway(w12a, h12a, 0)
	t.check(ns12a != -1, "case12a breakaway != -1")
	t.check(w12a.units.left_for[h12a] == 1, "case12a left_for == 1")
	t.check(t.approx(w12a.units.griev[h12a * 4 + 0], 0.2), "case12a griev d=0")
	t.check(t.approx(w12a.units.griev[h12a * 4 + 1], 0.4), "case12a griev d=1")
	t.check(t.approx(w12a.units.griev[h12a * 4 + 2], 0.4), "case12a griev d=2")
	t.check(t.approx(w12a.units.griev[h12a * 4 + 3], 0.6), "case12a griev d=3")
	var last12a := String(w12a.events_log[w12a.events_log.size() - 1])
	t.check(last12a.ends_with(", seeking wealth"), "case12a log ends_with seeking wealth")
	t.check(last12a.begins_with(str(w12a.units.names.get(h12a, "Unit %d" % h12a)) + " leaves S with "), "case12a log begins_with hero name and leaves")

	# 12b: strength beats raw grievance, defecting
	var w12b := mk_world()
	var s12b := mk_stack(w12b, 0, 5, 4, 60)
	var h12b := w12b.units.add(0, 0, 1, false, s12b)
	w12b.units.hero[h12b] = 1
	w12b.units.career_start[h12b] = w12b.time - 100.0
	w12b.stacks.recount(w12b.units)
	set_mood(w12b, h12b, 0.5, 0.0, 0.0)
	w12b.units.vals[h12b * 5 + 0] = 1.0
	w12b.units.vals[h12b * 5 + 2] = 0.2
	w12b.units.griev[h12b * 4 + 0] = 0.5
	w12b.units.griev[h12b * 4 + 1] = 0.8
	w12b.units.griev[h12b * 4 + 2] = 0.0
	w12b.units.griev[h12b * 4 + 3] = 0.0

	t.check(Dissent.top_grievance(w12b, h12b) == 0, "case12b strength-weighted: glory (0.5) beats wealth (0.16)")
	var ns12b := Heroes.breakaway(w12b, h12b, 1)
	t.check(w12b.units.left_for[h12b] == 0, "case12b left_for == 0")
	t.check(t.approx(w12b.units.griev[h12b * 4 + 0], 0.25), "case12b griev d=0")
	t.check(t.approx(w12b.units.griev[h12b * 4 + 1], 0.8), "case12b griev d=1")
	var last12b := String(w12b.events_log[w12b.events_log.size() - 1])
	t.check(last12b.ends_with(", seeking glory"), "case12b log ends_with seeking glory")
	t.check(last12b.contains(" breaks from Alpha, founding the free company "), "case12b log contains breaks from Alpha")

	# 12c: tie -> lowest index
	var w12c := mk_world()
	var s12c := mk_stack(w12c, 0, 5, 4, 60)
	var h12c := w12c.units.add(0, 0, 1, false, s12c)
	w12c.units.hero[h12c] = 1
	w12c.units.career_start[h12c] = w12c.time - 100.0
	w12c.stacks.recount(w12c.units)
	set_mood(w12c, h12c, 0.5, 0.0, 0.3)

	t.check(Dissent.top_grievance(w12c, h12c) == 0, "case12c tie -> lowest index")

	# 12d: no grievance
	var w12d := mk_world()
	var s12d := mk_stack(w12d, 0, 5, 4, 60)
	var h12d := w12d.units.add(0, 0, 1, false, s12d)
	w12d.units.hero[h12d] = 1
	w12d.units.career_start[h12d] = w12d.time - 100.0
	w12d.stacks.recount(w12d.units)
	set_mood(w12d, h12d, 0.5, 0.0, 0.0)

	t.check(Dissent.top_grievance(w12d, h12d) == -1, "case12d top_grievance == -1")
	var ns12d := Heroes.breakaway(w12d, h12d, 0)
	t.check(w12d.units.left_for[h12d] == Dissent.LEFT_OTHER, "case12d left_for == LEFT_OTHER")
	t.check(w12d.units.left_for[h12d] == 4, "case12d left_for == 4")
	var last12d := String(w12d.events_log[w12d.events_log.size() - 1])
	t.check(not last12d.contains("seeking"), "case12d log does NOT contain seeking")
	t.check(t.approx(w12d.units.griev[h12d * 4 + 0], 0.0), "case12d griev d=0")
	t.check(t.approx(w12d.units.griev[h12d * 4 + 1], 0.0), "case12d griev d=1")
	t.check(t.approx(w12d.units.griev[h12d * 4 + 2], 0.0), "case12d griev d=2")
	t.check(t.approx(w12d.units.griev[h12d * 4 + 3], 0.0), "case12d griev d=3")

	t.finish()
	quit()
