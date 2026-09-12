extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")


# Blank 12x8 world seed 6, faction_count = 3, faction_alive[0..2] = 1, per
# slice m5-kingdoms-core. faction_names pre-populated to match faction_count
# (setup_blank leaves faction_names empty; World.create is the only path
# that fills it, so tests built on setup_blank supply it themselves).
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 6)
	w.faction_count = 3
	for f in range(3):
		w.faction_alive[f] = 1
	w.faction_names = ["Alpha", "Beta", "Gamma"]
	return w


func mk_stack(w: World, f: int, tx: int, ty: int, n: int) -> int:
	var c := w.map.center_of(tx, ty)
	var sid := w.stacks.add(f, c.x, c.y, "S%d" % w.stacks.n)
	for _u in range(n):
		w.units.add(f, 0, 1, false, sid)
	w.stacks.recount(w.units)
	return sid


func is_permutation(arr: PackedInt32Array) -> bool:
	if arr.size() != 9:
		return false
	var seen := {}
	for v in arr:
		if seen.has(v):
			return false
		seen[v] = true
	return true


func _init() -> void:
	var t := TestKit.new()

	# 1. on_event
	var w1 := mk_world()
	Kingdoms.on_event(w1, "win", 0)
	t.check(t.approx(w1.ktrait(0, 0), 0.52), "on_event win: aggression approx 0.52")
	Kingdoms.on_event(w1, "raze", 0)
	t.check(t.approx(w1.ktrait(0, 2), 0.55), "on_event raze: greed approx 0.55")
	t.check(t.approx(w1.ktrait(0, 3), 0.47), "on_event raze: piety approx 0.47")
	Kingdoms.on_event(w1, "settle", 0)
	t.check(t.approx(w1.ktrait(0, 4), 0.53), "on_event settle: cohesion approx 0.53")
	Kingdoms.on_event(w1, "retreat", 0)
	t.check(t.approx(w1.ktrait(0, 0), 0.50), "on_event retreat: aggression approx 0.50")
	t.check(t.approx(w1.ktrait(0, 4), 0.51), "on_event retreat: cohesion approx 0.51")
	Kingdoms.on_event(w1, "pilgrim", 0)
	t.check(t.approx(w1.ktrait(0, 3), 0.52), "on_event pilgrim: piety approx 0.52")
	var before_bogus := w1.ktraits.duplicate()
	Kingdoms.on_event(w1, "bogus", 0)
	t.check(w1.ktraits == before_bogus, "on_event bogus: no change")

	# 2. goal_weights
	var w2 := mk_world()
	var gw := Kingdoms.goal_weights(w2, 0)
	var expected2 := PackedFloat32Array([3.0, 3.0, 2.0, 1.0, 1.0, 1.0, 0.5])
	var gw_ok := true
	for i in range(7):
		if not t.approx(gw[i], expected2[i], 1e-4):
			gw_ok = false
	t.check(gw_ok, "goal_weights: all traits 0.5, no relations -> [3,3,2,1,1,1,0.5]")

	w2.add_relation(0, 1, -0.4)
	var gw2 := Kingdoms.goal_weights(w2, 0)
	t.check(t.approx(gw2[6], 0.9), "goal_weights: after add_relation(0,1,-0.4) -> AVENGE approx 0.9")

	# 3. recruit_weapon
	var w3 := mk_world()
	w3.add_ktrait(0, 0, 0.5)   # aggression 0.5 -> 1.0
	w3.add_ktrait(0, 4, -0.5)  # cohesion 0.5 -> 0.0
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 1
	var counts := [0, 0, 0, 0, 0]
	for _i in range(300):
		var wid := Kingdoms.recruit_weapon(w3, 0, rng3)
		counts[wid] += 1
	var dagger_axe: int = counts[0] + counts[3]
	var sword: int = counts[1]
	var spear_shield: int = counts[2] + counts[4]
	t.check(dagger_axe > sword, "recruit_weapon: dagger+axe count > sword count")
	t.check(spear_shield < sword * 2 + 20, "recruit_weapon: spear+shield count < sword*2+20")

	var rngA := RandomNumberGenerator.new()
	rngA.seed = 1
	var rngB := RandomNumberGenerator.new()
	rngB.seed = 1
	var seq_ok := true
	for _i in range(20):
		if Kingdoms.recruit_weapon(w3, 0, rngA) != Kingdoms.recruit_weapon(w3, 0, rngB):
			seq_ok = false
	t.check(seq_ok, "recruit_weapon: determinism, same seed -> same sequence")

	# 4. plinko_bias
	var w4 := mk_world()
	t.check(t.approx(Kingdoms.plinko_bias(w4, 0), 0.0), "plinko_bias: greed 0.5 -> approx 0")
	w4.add_ktrait(0, 2, 0.5)  # greed 0.5 -> 1.0
	t.check(t.approx(Kingdoms.plinko_bias(w4, 0), 100.0), "plinko_bias: greed 1.0 -> 100.0")

	# 5. trait_favor
	var order5 := PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 8])
	var out_tyrant := Kingdoms.trait_favor(order5, Lineage.Trait.TYRANT)
	t.check(out_tyrant[4] == Plinko.Slot.RAZE, "trait_favor TYRANT: index 4 == RAZE")
	t.check(is_permutation(out_tyrant), "trait_favor TYRANT: still a permutation")

	var out_none := Kingdoms.trait_favor(order5, -1)
	t.check(out_none == order5, "trait_favor -1: unchanged")

	var out_builder := Kingdoms.trait_favor(order5, Lineage.Trait.BUILDER)
	t.check(out_builder[4] == Plinko.Slot.SETTLE, "trait_favor BUILDER: index 4 == SETTLE (0)")

	# 6. tick
	var w6 := mk_world()
	w6.add_relation(0, 1, -0.6)
	Kingdoms.tick(w6, 10.0)
	t.check(t.approx(w6.relation(0, 1), -0.58), "tick: relation(0,1) approx -0.58 after decay")

	w6.add_ktrait(0, 1, 0.2)  # diplomacy 0.5 -> 0.7
	w6.add_ktrait(1, 1, 0.2)  # diplomacy 0.5 -> 0.7
	w6.add_town(Vector2i(2, 2), 0)
	w6.add_town(Vector2i(4, 2), 1)
	w6.recompute_borders()
	var rel01_before := w6.relation(0, 1)
	var rel02_before := w6.relation(0, 2)
	Kingdoms.tick(w6, 10.0)
	var rel01_after := w6.relation(0, 1)
	var rel02_after := w6.relation(0, 2)
	t.check(t.approx(rel01_after - rel01_before, 0.1, 0.03), "tick: bordering diplomacy (0,1) relation increased by approx 0.1")
	t.check(t.approx(rel02_after, rel02_before, 0.03), "tick: non-bordering (0,2) unchanged apart from decay")

	# 7. check_split
	var w7 := mk_world()
	w7.add_ktrait(0, 4, -0.3)  # cohesion 0.5 -> 0.2
	var big7 := mk_stack(w7, 0, 2, 2, 500)
	var small7 := mk_stack(w7, 0, 8, 2, 200)
	var town7 := w7.add_town(Vector2i(3, 3), 0)
	var bv7_before := w7.borders_version
	Kingdoms.check_split(w7)
	t.check(w7.faction_count == 4, "check_split: faction_count == 4")
	t.check(w7.stacks.faction[big7] == 3, "check_split: 500-stack faction == 3")
	var units_ok7 := true
	for u7 in range(w7.units.n):
		if w7.units.stack[u7] == big7 and w7.units.faction[u7] != 3:
			units_ok7 = false
	t.check(units_ok7, "check_split: 500-stack units faction == 3")
	t.check(w7.town_owner[town7] == 3, "check_split: town owner == 3")
	t.check(t.approx(w7.relation(0, 3), -0.6), "check_split: relation(0,3) approx -0.6")
	t.check(w7.faction_alive[3] == 1, "check_split: faction_alive[3] == 1")
	t.check(w7.faction_names.size() == 4, "check_split: faction_names.size() == 4")
	t.check(w7.borders_version > bv7_before, "check_split: borders_version increased")

	var fc7_after_first := w7.faction_count
	Kingdoms.check_split(w7)
	t.check(w7.faction_count == fc7_after_first, "check_split: calling again immediately -> no further split (cooldown)")
	t.check(small7 >= 0, "check_split: 200-stack still exists")

	# 8. check_death
	var w8 := mk_world()
	mk_stack(w8, 0, 2, 2, 5)  # faction 0 keeps an alive stack
	# faction 2 has no towns and no alive stacks (nothing added for it).
	Kingdoms.check_death(w8)
	t.check(w8.faction_alive[2] == 0, "check_death: faction_alive[2] == 0")
	t.check(String(w8.events_log[w8.events_log.size() - 1]).contains("fell"), "check_death: events_log last line contains 'fell'")
	t.check(w8.faction_alive[0] == 1, "check_death: faction_alive[0] stays 1 (has a stack)")

	t.finish()
	quit()
