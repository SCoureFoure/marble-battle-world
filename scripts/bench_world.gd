extends SceneTree

func _init() -> void:
	var w := World.create(1234)

	while w.stacks.n < 200:
		var faction := w.rng.randi_range(0, Tuning.N_FACTIONS - 1)
		var tx := 0
		var ty := 0
		while true:
			tx = w.rng.randi_range(0, w.map.cols - 1)
			ty = w.rng.randi_range(0, w.map.rows - 1)
			if w.map.passable(tx, ty):
				break
		var c := w.map.center_of(tx, ty)
		var stack_id := w.stacks.add(faction, c.x, c.y, NameGen.stack_name(w.rng))
		for _u in range(40):
			var weapon := w.rng.randi_range(0, 4)
			w.units.add(faction, 0, weapon, false, stack_id)
		w.stacks.count[stack_id] = 40

	var battles_live_max := 0
	var world_us := 0.0
	var battle_us := 0.0
	var live_sum := 0.0
	var world_max_ms := 0.0
	var ticks := 1800

	for _i in range(ticks):
		var t0 := Time.get_ticks_usec()
		WorldSim.step_world(w, Tuning.DT)
		var t1 := Time.get_ticks_usec()
		var world_tick_us: float = t1 - t0
		world_us += world_tick_us
		var world_tick_ms := world_tick_us / 1000.0
		if world_tick_ms > world_max_ms:
			world_max_ms = world_tick_ms

		var t2 := Time.get_ticks_usec()
		WorldSim.step_battles(w)
		var t3 := Time.get_ticks_usec()
		var battle_tick_us: float = t3 - t2
		battle_us += battle_tick_us

		live_sum += w.battles.size()
		if w.battles.size() > battles_live_max:
			battles_live_max = w.battles.size()

	var world_avg_ms := world_us / 1000.0 / ticks
	var battle_avg_ms := battle_us / 1000.0 / ticks
	var live_avg: float = live_sum / ticks
	var battle_ms_per_live := battle_avg_ms / maxf(1.0, live_avg)

	var alive_stacks := 0
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 1:
			alive_stacks += 1

	print("STACKS=%d" % alive_stacks)
	print("BATTLES_STARTED=%d" % w.next_battle_id)
	print("BATTLES_LIVE_MAX=%d" % battles_live_max)
	print("WORLD_MS_AVG=%.3f" % world_avg_ms)
	print("BATTLE_MS_AVG=%.3f" % battle_avg_ms)
	print("BATTLES_LIVE_AVG=%.1f" % live_avg)
	print("BATTLE_MS_PER_LIVE=%.3f" % battle_ms_per_live)
	print("WORLD_MS_MAX=%.3f" % world_max_ms)
	if world_avg_ms < 4.0:
		print("ALL_PASS (bench)")
	else:
		print("FAILURES=1 of 1")

	quit()
