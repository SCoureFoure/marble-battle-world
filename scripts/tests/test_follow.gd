extends SceneTree
## Tests for Follow.step. See .warboss-horde/slices/m9-ui.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


## Blank 12x8 world, seed 31, faction 0 alive, named "Alpha".
func mk_world() -> World:
	var w := World.new()
	w.setup_blank(12, 8, 31)
	w.faction_count = 1
	w.faction_alive[0] = 1
	w.faction_names = ["Alpha"]
	return w


## Stack s0 with captain c (Lineage.make_captain(w, c, "Toby")) and 5 units.
## Returns [stack_id, captain_id].
func mk_stack(w: World, f: int, tx: int, ty: int) -> Array:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	for _i in range(5):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	Lineage.make_captain(w, cap_id, "Toby")
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return [id, cap_id]


func _init() -> void:
	var t := TestKit.new()

	var w := mk_world()
	var s0_cap := mk_stack(w, 0, 5, 4)
	var s0: int = s0_cap[0]
	var c: int = s0_cap[1]

	# 1. unit == -1.
	t.check(Follow.step(w, -1, -1) == [-1, -1, ""], "case1 not following -> [-1, -1, '']")

	# 2. active.
	t.check(Follow.step(w, c, s0) == [c, s0, ""], "case2 active unit -> [c, s0, '']")

	# 3. heir.
	w.units.kill(c)
	Lineage._succeed(w, s0, c)
	var h: int = w.stacks.captain_unit[s0]
	var expect3 := [h, s0, "The tale passes to " + String(w.units.names[h])]
	var events_before3 := w.events_log.size()
	t.check(Follow.step(w, c, s0) == expect3, "case3 heir -> tale passes to heir")

	# 4. end: fresh world, captain c in s0, killed, stack dead, no mentor links.
	var w4 := mk_world()
	var s4_cap := mk_stack(w4, 0, 5, 4)
	var s4: int = s4_cap[0]
	var c4: int = s4_cap[1]
	w4.units.kill(c4)
	w4.stacks.alive[s4] = 0
	var events_before4 := w4.events_log.size()
	t.check(Follow.step(w4, c4, s4) == [-1, -1, "The tale of Toby I ends"], "case4 end -> tale ends")

	# 5. offshoot: fresh world, c killed, stack dead; second stack s1 with
	# unit v, mentor = c, kills = 4.
	var w5 := mk_world()
	var s5_cap := mk_stack(w5, 0, 5, 4)
	var s5: int = s5_cap[0]
	var c5: int = s5_cap[1]
	w5.units.kill(c5)
	w5.stacks.alive[s5] = 0
	var s1 := w5.stacks.add(0, 0.0, 0.0, "S1")
	var v := w5.units.add(0, 0, 1, false, s1)
	w5.units.mentor[v] = c5
	w5.units.kills[v] = 4
	var expect5 := [v, s1, "The tale passes to " + String(w5.units.names.get(v, "Unit %d" % v))]
	var events_before5 := w5.events_log.size()
	t.check(Follow.step(w5, c5, s5) == expect5, "case5 offshoot -> tale passes to v")

	# 6. no writes: events_log.size() unchanged across all calls above.
	t.check(w.events_log.size() == events_before3, "case6 no writes: w events_log unchanged by step calls")
	t.check(w4.events_log.size() == events_before4, "case6 no writes: w4 events_log unchanged")
	t.check(w5.events_log.size() == events_before5, "case6 no writes: w5 events_log unchanged")

	t.finish()
	quit()
