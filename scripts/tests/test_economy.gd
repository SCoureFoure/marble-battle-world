extends SceneTree
## Tests for Economy (gold, restock, loot). See .warboss-horde/slices/m9-economy.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 12x8 world, seed 3; 3 factions, all alive.
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 3)
	w.faction_count = 3
	w.faction_alive[0] = 1
	w.faction_alive[1] = 1
	w.faction_alive[2] = 1
	return w


## stacks.add(f, centre), n rank-0 sword units, stacks.recount.
func mk_stack(w: World, f: int, tx: int, ty: int, n: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	for _i in range(n):
		w.units.add(f, 0, 1, false, id)
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. accrue: taxed towns tick up, clipped to TOWN_GOLD_MAX, RAIDED towns stay put.
	var w1 := mk_world()
	var tA1 := w1.add_town(Vector2i(1, 1), 0)
	w1.town_pop[tA1] = 100.0
	w1.town_gold[tA1] = 0.0
	w1.town_state[tA1] = 0
	var tB1 := w1.add_town(Vector2i(3, 1), 0)
	w1.town_pop[tB1] = 100.0
	w1.town_gold[tB1] = 0.0
	w1.town_state[tB1] = 1
	var tC1 := w1.add_town(Vector2i(5, 1), 0)
	w1.town_pop[tC1] = 200.0
	w1.town_gold[tC1] = 499.9
	w1.town_state[tC1] = 0

	Economy.accrue(w1, 1.0)
	t.check(t.approx(w1.town_gold[tA1], 0.2), "case1 intact town gold == 0.2")
	t.check(t.approx(w1.town_gold[tB1], 0.0), "case1 RAIDED town stays 0.0")
	t.check(t.approx(w1.town_gold[tC1], 500.0), "case1 clipped to TOWN_GOLD_MAX")

	# 2. price: own, neutral, ally (relation >= threshold), enemy (-1.0).
	var w2 := mk_world()
	var t2own := w2.add_town(Vector2i(1, 1), 0)
	t.check(t.approx(Economy.price(w2, 0, t2own), 2.0), "case2 own town price == 2.0")

	var t2neutral := w2.add_town(Vector2i(3, 1), -1)
	t.check(t.approx(Economy.price(w2, 0, t2neutral), 3.0), "case2 neutral town price == 3.0")

	var t2ally := w2.add_town(Vector2i(5, 1), 1)
	w2.add_relation(0, 1, 0.6)
	t.check(t.approx(Economy.price(w2, 0, t2ally), 2.5), "case2 ally town price == 2.5")

	var t2enemy := w2.add_town(Vector2i(7, 1), 2)
	t.check(t.approx(Economy.price(w2, 0, t2enemy), -1.0), "case2 enemy town price == -1.0")

	# 3. restock own town: collects town gold, no healing needed, buys to town_pop cap.
	var w3 := mk_world()
	var s3 := mk_stack(w3, 0, 1, 1, 10)
	w3.stacks.gold[s3] = 0.0
	var t3 := w3.add_town(Vector2i(1, 1), 0)
	w3.town_pop[t3] = 50.0
	w3.town_gold[t3] = 30.0
	w3.town_state[t3] = 0

	var res3 := Economy.restock(w3, s3, t3)
	t.check(res3 == "S restocks at town %d: +15 recruits, 0 healed" % t3, "case3 return string")
	t.check(w3.stacks.count[s3] == 25, "case3 count == 25")
	t.check(t.approx(w3.stacks.gold[s3], 0.0), "case3 gold == 0.0")
	t.check(t.approx(w3.town_pop[t3], 35.0), "case3 town_pop == 35.0")
	t.check(t.approx(w3.town_gold[t3], 0.0), "case3 town_gold == 0.0")
	t.check(int(w3.history.get("restocks", 0)) == 1, "case3 history[restocks] == 1")
	t.check(w3.units.n == 25, "case3 units.n == 25")
	var all_new3 := true
	for u3 in range(w3.units.n):
		if w3.units.stack[u3] == s3 and (w3.units.faction[u3] != 0 or w3.units.rank[u3] != 0):
			all_new3 = false
	t.check(all_new3, "case3 all units faction 0, rank 0, stack s3")

	# 4. restock neutral: heals first, then buys, capped by town_pop.
	var w4 := mk_world()
	var s4 := mk_stack(w4, 0, 1, 1, 10)
	for u4 in range(3):
		w4.units.hp_frac[u4] = 0.4
	w4.stacks.gold[s4] = 20.0
	var t4 := w4.add_town(Vector2i(3, 1), -1)
	w4.town_pop[t4] = 4.0
	w4.town_gold[t4] = 0.0
	w4.town_state[t4] = 0

	var res4 := Economy.restock(w4, s4, t4)
	t.check(w4.stacks.count[s4] == 14, "case4 count == 14")
	t.check(t.approx(w4.stacks.gold[s4], 7.4), "case4 gold ~= 7.4")
	t.check(t.approx(w4.town_pop[t4], 0.0), "case4 town_pop == 0.0")
	t.check(t.approx(w4.town_gold[t4], 12.0), "case4 town_gold ~= 12.0")
	for u4b in range(3):
		t.check(t.approx(w4.units.hp_frac[u4b], 1.0), "case4 healed unit %d" % u4b)
	t.check(res4.ends_with("+4 recruits, 3 healed"), "case4 return ends +4 recruits, 3 healed")

	# 5. refusals: enemy town, own-but-RAIDED town, and no-op neutral (no funds).
	var w5 := mk_world()
	var s5 := mk_stack(w5, 0, 1, 1, 10)
	w5.stacks.gold[s5] = 50.0
	var t5enemy := w5.add_town(Vector2i(3, 1), 1)
	var pop5enemy := w5.town_pop[t5enemy]
	var res5enemy := Economy.restock(w5, s5, t5enemy)
	t.check(res5enemy == "", "case5 enemy town returns empty string")
	t.check(t.approx(w5.stacks.gold[s5], 50.0), "case5 enemy: gold unchanged")
	t.check(w5.stacks.count[s5] == 10, "case5 enemy: count unchanged")
	t.check(t.approx(w5.town_pop[t5enemy], pop5enemy), "case5 enemy: town_pop unchanged")

	var t5raided := w5.add_town(Vector2i(5, 1), 0)
	w5.town_state[t5raided] = 1
	var res5raided := Economy.restock(w5, s5, t5raided)
	t.check(res5raided == "", "case5 own town RAIDED returns empty string")

	var t5nofund := w5.add_town(Vector2i(7, 1), -1)
	w5.town_pop[t5nofund] = 50.0
	w5.stacks.gold[s5] = 1.0
	var count5nofund := w5.stacks.count[s5]
	var res5nofund := Economy.restock(w5, s5, t5nofund)
	t.check(res5nofund.ends_with("+0 recruits, 0 healed"), "case5 no funds: +0/0")
	t.check(w5.stacks.count[s5] == count5nofund, "case5 no funds: count unchanged")
	t.check(int(w5.history.get("restocks", 0)) == 0, "case5 history[restocks] unchanged")

	# 6. heal runs out: gold exhausts mid-heal, later wounded stay wounded.
	var w6 := mk_world()
	var s6 := mk_stack(w6, 0, 1, 1, 10)
	for u6 in range(5):
		w6.units.hp_frac[u6] = 0.3
	w6.stacks.gold[s6] = 0.5
	var t6 := w6.add_town(Vector2i(3, 1), -1)
	w6.town_pop[t6] = 0.0
	var count6 := w6.stacks.count[s6]

	Economy.restock(w6, s6, t6)
	t.check(t.approx(w6.units.hp_frac[0], 1.0), "case6 unit 0 healed")
	t.check(t.approx(w6.units.hp_frac[1], 1.0), "case6 unit 1 healed")
	t.check(t.approx(w6.units.hp_frac[2], 0.3), "case6 unit 2 still 0.3")
	t.check(t.approx(w6.stacks.gold[s6], 0.1), "case6 gold ~= 0.1")
	t.check(w6.stacks.count[s6] == count6, "case6 count unchanged")

	# 7. wants_restock: low-count+afford, wounded+afford, exact boundaries.
	var w7a := mk_world()
	var s7a := mk_stack(w7a, 0, 1, 1, 10)
	w7a.stacks.gold[s7a] = 15.0
	t.check(Economy.wants_restock(w7a, s7a) == true, "case7a gold 15, no own town -> true")
	w7a.stacks.gold[s7a] = 14.9
	t.check(Economy.wants_restock(w7a, s7a) == false, "case7a gold 14.9 -> false")

	var w7b := mk_world()
	var s7b := mk_stack(w7b, 0, 1, 1, 10)
	w7b.stacks.gold[s7b] = 0.0
	var t7b := w7b.add_town(Vector2i(3, 1), 0)
	w7b.town_gold[t7b] = 10.0
	t.check(Economy.wants_restock(w7b, s7b) == true, "case7b own town gold 10 -> true")
	w7b.town_gold[t7b] = 9.9
	t.check(Economy.wants_restock(w7b, s7b) == false, "case7b own town gold 9.9 -> false")

	var w7c := mk_world()
	var s7c := mk_stack(w7c, 0, 1, 1, 120)
	w7c.stacks.gold[s7c] = 1000.0
	t.check(Economy.wants_restock(w7c, s7c) == false, "case7c 120 units, none wounded -> false")

	var w7d := mk_world()
	var s7d := mk_stack(w7d, 0, 1, 1, 120)
	for u7d in range(30):
		w7d.units.hp_frac[u7d] = 0.3
	w7d.stacks.gold[s7d] = 6.0
	t.check(Economy.wants_restock(w7d, s7d) == true, "case7d 30 wounded, gold 6 -> true")
	w7d.stacks.gold[s7d] = 5.9
	t.check(Economy.wants_restock(w7d, s7d) == false, "case7d gold 5.9 -> false")

	# 8. restock_target: enemy excluded, nearest wins, narrowed to own town when poor,
	# pop floor excludes candidates, ties go to the lowest id.
	var w8 := mk_world()
	var s8 := mk_stack(w8, 0, 1, 1, 10)
	w8.stacks.gold[s8] = 100.0
	var tA8 := w8.add_town(Vector2i(3, 1), 1)
	var tB8 := w8.add_town(Vector2i(6, 1), -1)
	w8.town_pop[tB8] = 50.0
	var tC8 := w8.add_town(Vector2i(1, 7), 0)

	t.check(Economy.restock_target(w8, s8) == tB8, "case8 gold 100 -> nearest (B)")

	w8.stacks.gold[s8] = 5.0
	w8.town_gold[tC8] = 10.0
	t.check(Economy.restock_target(w8, s8) == tC8, "case8 poor, own town funded -> C")
	w8.town_gold[tC8] = 0.0
	t.check(Economy.restock_target(w8, s8) == -1, "case8 poor, own town unfunded -> -1")

	w8.stacks.gold[s8] = 100.0
	w8.town_pop[tB8] = 0.5
	t.check(Economy.restock_target(w8, s8) == tC8, "case8 B excluded by pop -> C")

	var w8b := mk_world()
	var s8b := mk_stack(w8b, 0, 5, 4, 10)
	w8b.stacks.gold[s8b] = 100.0
	var d0_8b := w8b.add_town(Vector2i(3, 4), -1)
	var d1_8b := w8b.add_town(Vector2i(7, 4), -1)
	t.check(Economy.restock_target(w8b, s8b) == d0_8b, "case8 tie -> lowest id")
	t.check(d1_8b == d0_8b + 1, "case8 sanity: d1 is the other town")

	# 9. goal_bonus: poor-gold bonus on RAID/HUNT_WEAK, RESTOCK_WEIGHT term, FOUND
	# always 0, input weights not mutated.
	var weights9 := PackedFloat32Array([1, 1, 1, 1, 1, 1, 1])

	var w9a := mk_world()
	var s9a := mk_stack(w9a, 0, 1, 1, 200)
	w9a.stacks.gold[s9a] = 100.0
	var out9a := Economy.goal_bonus(w9a, s9a, weights9)
	t.check(out9a.size() == 9, "case9a size == 9")
	t.check(t.approx(out9a[7], 0.0), "case9a [7] == 0.0")
	t.check(t.approx(out9a[8], 0.0), "case9a [8] == 0.0")
	t.check(t.approx(out9a[2], 1.0), "case9a [2] == 1.0")
	t.check(t.approx(out9a[0], 1.0), "case9a [0] == 1.0")

	var w9b := mk_world()
	var s9b := mk_stack(w9b, 0, 1, 1, 10)
	w9b.stacks.gold[s9b] = 10.0
	var out9b := Economy.goal_bonus(w9b, s9b, weights9)
	t.check(t.approx(out9b[2], 3.0), "case9b [2] == 3.0")
	t.check(t.approx(out9b[0], 2.0), "case9b [0] == 2.0")
	t.check(t.approx(out9b[7], 0.0), "case9b [7] == 0.0")

	# UNDECIDED: contract line 43 ("10 units, gold 15 -> [7] == 4.0, [2] == 1.0")
	# expects no poor-gold bonus at gold 15, but the verbatim §17.3 formula
	# ("if gold[s] < POOR_GOLD" with POOR_GOLD == 20.0) triggers the bonus at
	# gold 15 (3.0, not 1.0). Implemented per the formula (fork tag: intent
	# §17.3 verbatim); asserting the formula's literal output for [2].
	var w9c := mk_world()
	var s9c := mk_stack(w9c, 0, 1, 1, 10)
	w9c.stacks.gold[s9c] = 15.0
	var out9c := Economy.goal_bonus(w9c, s9c, weights9)
	t.check(t.approx(out9c[7], 4.0), "case9c [7] == 4.0")
	t.check(t.approx(out9c[2], 3.0), "case9c [2] == 3.0 (formula; see UNDECIDED note)")

	var weights9_ok := true
	for wi9 in range(weights9.size()):
		if not t.approx(weights9[wi9], 1.0):
			weights9_ok = false
	t.check(weights9_ok, "case9 input array not mutated")

	# 10. loot: losers pay LOOT_FRAC into a pool, winners split by count share
	# plus a per-kill bounty; dead winners mean nothing happens.
	var w10 := mk_world()
	var w1_10 := mk_stack(w10, 0, 1, 1, 30)
	w10.stacks.gold[w1_10] = 0.0
	var w2_10 := mk_stack(w10, 0, 3, 1, 10)
	w10.stacks.gold[w2_10] = 10.0
	var l1_10 := mk_stack(w10, 1, 5, 1, 5)
	w10.stacks.gold[l1_10] = 40.0
	var l2_10 := mk_stack(w10, 1, 7, 1, 5)
	w10.stacks.gold[l2_10] = 20.0

	Economy.loot(w10, [w1_10, w2_10], [l1_10, l2_10], {w1_10: 4})
	t.check(t.approx(w10.stacks.gold[l1_10], 20.0), "case10 l1 gold == 20.0")
	t.check(t.approx(w10.stacks.gold[l2_10], 10.0), "case10 l2 gold == 10.0")
	t.check(t.approx(w10.stacks.gold[w1_10], 24.5), "case10 w1 gold == 24.5")
	t.check(t.approx(w10.stacks.gold[w2_10], 17.5), "case10 w2 gold == 17.5")

	var w10b := mk_world()
	var w1_10b := mk_stack(w10b, 0, 1, 1, 30)
	w10b.stacks.alive[w1_10b] = 0
	var w2_10b := mk_stack(w10b, 0, 3, 1, 10)
	w10b.stacks.alive[w2_10b] = 0
	var l1_10b := mk_stack(w10b, 1, 5, 1, 5)
	w10b.stacks.gold[l1_10b] = 40.0
	var l2_10b := mk_stack(w10b, 1, 7, 1, 5)
	w10b.stacks.gold[l2_10b] = 20.0

	Economy.loot(w10b, [w1_10b, w2_10b], [l1_10b, l2_10b], {})
	t.check(t.approx(w10b.stacks.gold[l1_10b], 40.0), "case10b winners dead: l1 unchanged")
	t.check(t.approx(w10b.stacks.gold[l2_10b], 20.0), "case10b winners dead: l2 unchanged")

	# 11. raid_gold: full RAID_GOLD_FRAC transfer from town to stack.
	var w11 := mk_world()
	var s11 := mk_stack(w11, 0, 1, 1, 10)
	w11.stacks.gold[s11] = 5.0
	var t11 := w11.add_town(Vector2i(3, 1), -1)
	w11.town_gold[t11] = 50.0

	var g11 := Economy.raid_gold(w11, s11, t11)
	t.check(t.approx(g11, 50.0), "case11 returns 50.0")
	t.check(t.approx(w11.town_gold[t11], 0.0), "case11 town_gold == 0.0")
	t.check(t.approx(w11.stacks.gold[s11], 55.0), "case11 stack gold == 55.0")

	t.finish()
	quit()
