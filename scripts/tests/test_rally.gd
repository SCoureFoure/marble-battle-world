extends SceneTree
## Tests for Rally (docs/ARCHITECTURE.md §19): desire, host choice, host
## acceptance, merge into contingents, RALLY goal hookup, contingent
## breakaway, save/load of the new fields.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 20x10 world, seed 7, factions 0 and 1 alive, time 100.
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(20, 10, 7)
	w.faction_count = 2
	w.faction_alive[0] = 1
	w.faction_alive[1] = 1
	w.faction_names = ["Alpha", "Beta"]
	w.time = 100.0
	return w


## `n_units` rank-0 units at tile (tx, ty); with `captain` one more rank-1
## captain named `cap_name`. Returns the stack id.
func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int, captain: bool = true, cap_name: String = "Toby", sname: String = "S") -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, sname)
	for _i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	if captain:
		var cap_id := w.units.add(f, 1, 1, true, id)
		Lineage.make_captain(w, cap_id, cap_name)
		w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. desire.
	var w1 := mk_world()
	var host1 := mk_stack(w1, 0, 5, 4, 60, true, "Big", "Host")
	var weak1 := mk_stack(w1, 0, 7, 4, 4, true, "Small", "Weak")
	var strong1 := mk_stack(w1, 0, 9, 4, 40, true, "Mid", "Strong")
	var none1 := mk_stack(w1, 0, 6, 4, 2, false, "", "Leaderless")
	w1.units.kills[w1.stacks.captain_unit[host1]] = 20
	t.check(t.approx(Rally.desire(w1, none1, host1, 0.0), 1.0), "case1 leaderless desire 1")
	var d_weak := Rally.desire(w1, weak1, host1, 0.0)
	var d_strong := Rally.desire(w1, strong1, host1, 0.0)
	t.check(d_weak > d_strong, "case1 weaker stack wants to join more")
	t.check(Rally.desire(w1, weak1, host1, 1.0) > d_weak, "case1 threat raises desire")
	w1.units.ambition[w1.stacks.captain_unit[weak1]] = 1.0
	t.check(Rally.desire(w1, weak1, host1, 0.0) < d_weak, "case1 ambition lowers desire")
	w1.units.ambition[w1.stacks.captain_unit[weak1]] = 0.0
	w1.stacks.gold[weak1] = 1000.0
	t.check(Rally.desire(w1, weak1, host1, 0.0) < d_weak, "case1 gold lowers desire")
	w1.stacks.gold[weak1] = 0.0
	var foe1 := mk_stack(w1, 1, 8, 5, 30, true, "Foe", "Foe")
	t.check(Rally.threat(w1, weak1) > 0.9, "case1 big enemy nearby -> threat ~1")
	w1.stacks.alive[foe1] = 0

	# 2. host choice.
	t.check(Rally.best_host(w1, weak1) == host1, "case2 weak picks the higher-renown host in range")
	t.check(Rally.can_host(w1, weak1, host1) == false, "case2 smaller stack cannot host bigger")
	var other1 := mk_stack(w1, 1, 6, 5, 80, true, "Other", "Other")
	t.check(Rally.best_host(w1, weak1) == host1, "case2 other-faction stack never hosts")
	w1.stacks.alive[other1] = 0
	w1.stacks.state[host1] = Stacks.State.BATTLE
	t.check(Rally.can_host(w1, host1, weak1) == false, "case2 host in BATTLE cannot host")
	w1.stacks.state[host1] = Stacks.State.IDLE
	var far1 := mk_stack(w1, 0, 19, 9, 200, true, "Far", "Far")
	t.check(Rally.best_host(w1, none1) != far1, "case2 host beyond RALLY_RANGE ignored")
	w1.stacks.rally_cd[weak1] = 10.0
	t.check(Rally.best_host(w1, weak1) == -1, "case2 cooldown -> no host")
	w1.stacks.rally_cd[weak1] = 0.0
	t.check(Rally.goal_weight(w1, none1) == Tuning.RALLY_LEADERLESS_WEIGHT, "case2 leaderless goal weight")
	t.check(Rally.goal_weight(w1, weak1) > 0.0, "case2 weak stack has a RALLY weight")

	# 3. acceptance.
	t.check(Rally.host_accepts(w1, host1, none1), "case3 leaderless always accepted")
	var w3 := mk_world()
	var h3 := mk_stack(w3, 0, 5, 4, 290, true, "Big", "Host")
	var j3 := mk_stack(w3, 0, 6, 4, 20, true, "Small", "Join")
	t.check(Rally.host_accepts(w3, h3, j3) == false, "case3 over STACK_CAP refused")
	var w3b := mk_world()
	var h3b := mk_stack(w3b, 0, 5, 4, 50, true, "Big", "Host")
	var j3b := mk_stack(w3b, 0, 6, 4, 5, true, "Small", "Join")
	w3b.units.ctrait[w3b.stacks.captain_unit[h3b]] = Lineage.Trait.TYRANT
	var accepted3 := 0
	for _k in range(200):
		if Rally.host_accepts(w3b, h3b, j3b):
			accepted3 += 1
	t.check(accepted3 > 140 and accepted3 < 180, "case3 TYRANT accepts ~80%% (got %d/200)" % accepted3)

	# 4. merge.
	var w4 := mk_world()
	var h4 := mk_stack(w4, 0, 5, 4, 30, true, "Big", "Host")
	var j4 := mk_stack(w4, 0, 6, 4, 6, true, "Small", "Join")
	var cap_j4: int = w4.stacks.captain_unit[j4]
	w4.stacks.gold[j4] = 12.0
	var men4: Array = []
	for u4 in range(w4.units.n):
		if w4.units.stack[u4] == j4 and u4 != cap_j4:
			men4.append(u4)
	Rally.merge(w4, h4, j4)
	t.check(w4.stacks.alive[j4] == 0, "case4 joiner stack dead")
	t.check(w4.stacks.count[h4] == 38, "case4 host count 31 + 7")
	t.check(t.approx(w4.stacks.gold[h4], 12.0), "case4 gold moved")
	var led4 := true
	for u4b in men4:
		if w4.units.stack[u4b] != h4 or w4.units.leader[u4b] != cap_j4:
			led4 = false
	t.check(led4, "case4 joiner's men are a contingent led by their captain")
	t.check(w4.units.is_captain[cap_j4] == 0 and w4.units.hero[cap_j4] == 1, "case4 joiner captain serves on as hero")
	t.check(w4.units.names[cap_j4] == "Small I", "case4 hero keeps name")
	t.check(w4.units.pledge_t[cap_j4] > w4.time, "case4 hero pledged")
	t.check(w4.stacks.captain_unit[h4] != cap_j4, "case4 host keeps its captain")

	var none4 := mk_stack(w4, 0, 5, 5, 2, false, "", "Stray")
	var stray4: Array = []
	for u4c in range(w4.units.n):
		if w4.units.stack[u4c] == none4:
			stray4.append(u4c)
	Rally.merge(w4, h4, none4)
	var own4 := true
	for u4d in stray4:
		if w4.units.leader[u4d] != -1 or w4.units.stack[u4d] != h4:
			own4 = false
	t.check(own4, "case4 leaderless men join the host's own ranks")

	# 5. pledge blocks breakaway; after it, the hero leaves with exactly their contingent.
	w4.units.career_start[cap_j4] = 0.0
	t.check(w4.stacks.count[h4] >= Tuning.BREAKAWAY_MIN_STACK, "case5 host big enough for breakaway")
	var ns_before5 := w4.stacks.n
	for _s5 in range(20):
		Heroes.check_breakaway(w4)
	t.check(w4.stacks.n == ns_before5, "case5 no breakaway while pledged")
	w4.time = w4.units.pledge_t[cap_j4] + 1.0
	var ns5 := Heroes.breakaway(w4, cap_j4, 0)
	t.check(ns5 != -1, "case5 breakaway made a stack")
	t.check(w4.stacks.count[ns5] == men4.size() + 1, "case5 new stack = hero + contingent")
	var back5 := true
	for u5 in men4:
		if w4.units.stack[u5] != ns5 or w4.units.leader[u5] != -1:
			back5 = false
	t.check(back5, "case5 contingent went with the hero, leader cleared")

	# 6. hookup: a leaderless stray next to an army folds in through WorldSim.
	var w6 := mk_world()
	var h6 := mk_stack(w6, 0, 5, 4, 30, true, "Big", "Host")
	var s6 := mk_stack(w6, 0, 8, 4, 2, false, "", "Stray")
	w6.stacks.idle_timer[h6] = 1.0e9
	var merged6 := false
	for _t6 in range(60 * 60):
		WorldSim.step(w6, Tuning.DT)
		if w6.stacks.alive[s6] == 0:
			merged6 = true
			break
	t.check(merged6, "case6 stray folded into the army within 60 s")
	t.check(w6.stacks.count[h6] == 33, "case6 host gained the stray's 2 men")

	# 7. save/load keeps leader, pledge_t, rally_target, rally_cd.
	w4.stacks.rally_cd[h4] = 7.5
	w4.stacks.rally_target[h4] = 3
	var path7 := "user://test_rally_save.bin"
	t.check(SaveGame.save(w4, path7) == OK, "case7 save ok")
	var l7 := SaveGame.load(path7)
	t.check(l7 != null, "case7 load ok")
	if l7 != null:
		t.check(l7.units.leader == w4.units.leader, "case7 leader round-trips")
		t.check(l7.units.pledge_t == w4.units.pledge_t, "case7 pledge_t round-trips")
		t.check(l7.stacks.rally_cd == w4.stacks.rally_cd and l7.stacks.rally_target == w4.stacks.rally_target, "case7 rally fields round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path7))

	t.finish()
	quit()
