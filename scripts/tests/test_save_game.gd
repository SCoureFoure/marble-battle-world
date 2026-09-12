extends SceneTree
## SaveGame.save/load. docs/ARCHITECTURE.md §14.3, .warboss-horde/slices/m6-save.md

const TestKit = preload("res://scripts/tests/test_kit.gd")

const SAVE_PATH := "user://test_save.bin"


func _init() -> void:
	var t := TestKit.new()

	# Case 1: round-trip on a lively world (may have live battles at save
	# time; a live-battle stack is expected to load back as IDLE).
	var w := World.create(42)
	for _i in range(300):
		WorldSim.step(w, Tuning.DT)

	t.check(SaveGame.save(w, SAVE_PATH) == OK, "SaveGame.save(w, path) == OK")

	var w2 := SaveGame.load(SAVE_PATH)
	t.check(w2 != null, "SaveGame.load(path) != null")

	t.check(w.map.kind == w2.map.kind, "map.kind equal")
	t.check(w.map.owner == w2.map.owner, "map.owner equal")
	t.check(w.stacks.n == w2.stacks.n, "stacks.n equal")
	t.check(w.stacks.x == w2.stacks.x, "stacks.x equal")
	t.check(w.stacks.y == w2.stacks.y, "stacks.y equal")

	var state_ok := true
	for i in range(w.stacks.n):
		var expected: int = w.stacks.state[i]
		if expected == Stacks.State.BATTLE:
			expected = Stacks.State.IDLE
		if w2.stacks.state[i] != expected:
			state_ok = false
	t.check(state_ok, "stacks.state equal (live BATTLE stacks load as IDLE)")

	t.check(w.units.n == w2.units.n, "units.n equal")
	t.check(w.units.xp == w2.units.xp, "units.xp equal")
	t.check(w.units.faction == w2.units.faction, "units.faction equal")
	t.check(w.town_owner == w2.town_owner, "town_owner equal")
	t.check(w.town_pop == w2.town_pop, "town_pop equal")
	t.check(w.ktraits == w2.ktraits, "ktraits equal")
	t.check(w.relations == w2.relations, "relations equal")
	t.check(w.faction_names == w2.faction_names, "faction_names equal")
	t.check(w.events_log.size() == w2.events_log.size(), "events_log.size() equal")
	t.check(t.approx(w.time, w2.time), "time equal")
	t.check(w.next_battle_id == w2.next_battle_id, "next_battle_id equal")
	t.check(w.rng.state == w2.rng.state, "rng.state equal")
	t.check(w2.battles.size() == 0, "loaded world has no live battles")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	# Case 2: determinism across save/load. Comparability requires saving at
	# a moment with no live battles (a live battle's marble-level state is
	# not persisted, so w and the reload would otherwise diverge).
	var w3 := World.create(42)
	for _i in range(300):
		WorldSim.step(w3, Tuning.DT)
	var settle_steps := 0
	while w3.battles.size() > 0 and settle_steps < 3000:
		WorldSim.step(w3, Tuning.DT)
		settle_steps += 1
	t.check(w3.battles.size() == 0, "w3 has settled to zero live battles before saving")

	t.check(SaveGame.save(w3, SAVE_PATH) == OK, "save at a no-battle moment == OK")
	var w4 := SaveGame.load(SAVE_PATH)
	t.check(w4 != null, "load (determinism case) != null")

	for _i in range(300):
		WorldSim.step(w3, Tuning.DT)
		WorldSim.step(w4, Tuning.DT)

	t.check(w3.stacks.x == w4.stacks.x, "stacks.x equal after 300 more steps on both (determinism)")
	t.check(w3.units.xp == w4.units.xp, "units.xp equal after 300 more steps on both (determinism)")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	# Case 3: missing file and wrong version both load() to null, no crash.
	var missing := SaveGame.load("user://test_save_missing_%d.bin" % Time.get_ticks_usec())
	t.check(missing == null, "load of a missing file returns null")

	const BAD_PATH := "user://test_save_bad_version.bin"
	var bf := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	bf.store_var({
		"version": 99,
		"seed_state": 0,
		"time": 0.0,
		"faction_count": 0,
		"next_battle_id": 0,
		"cols": 1,
		"rows": 1,
		"borders_version": 0,
	})
	bf.close()
	var bad := SaveGame.load(BAD_PATH)
	t.check(bad == null, "load of a version-99 header returns null")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_PATH))

	# Case 4: blank world, hand-built, round trip.
	var wb := World.new()
	wb.setup_blank(12, 8, 1)
	wb.add_town(Vector2i(2, 2), 0)
	var c := wb.map.center_of(2, 2)
	var sid := wb.stacks.add(0, c.x, c.y, "S0")
	wb.stacks.count[sid] = 10

	t.check(SaveGame.save(wb, SAVE_PATH) == OK, "save(blank world) == OK")
	var wb2 := SaveGame.load(SAVE_PATH)
	t.check(wb2 != null, "load(blank world) != null")
	t.check(wb2.towns.size() == 1, "blank world: towns.size() == 1")
	t.check(wb2.stacks.n == 1, "blank world: stacks.n == 1")
	t.check(wb2.map.cols == 12, "blank world: map.cols == 12")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	t.finish()
	quit()
