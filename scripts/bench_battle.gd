extends SceneTree

func _init() -> void:
	var n := 500
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--marbles="):
			n = arg.substr("--marbles=".length()).to_int()

	var s := BattleState.new(n + 2, 1234)
	s.spawn(350, 450, 0, 1, 1, true)
	s.spawn(1250, 450, 1, 1, 1, true)
	s.spawn_block(0, n / 2, Rect2(100, 100, 500, 700), -1)
	s.spawn_block(1, n - n / 2, Rect2(1000, 100, 500, 700), -1)

	var sim := BattleSim.new(s)
	var g := TerrainGrid.new()
	g.setup(s.arena, Tuning.TERRAIN_CELL)
	TerrainGen.demo(g, s.rng)
	sim.set_terrain(g)

	for _i in range(60):
		sim.step(s, Tuning.DT)

	sim.reset_profile()

	var sum_ms := 0.0
	var max_ms := 0.0
	for _i in range(600):
		var t0 := Time.get_ticks_usec()
		sim.step(s, Tuning.DT)
		var t1 := Time.get_ticks_usec()
		var ms := (t1 - t0) / 1000.0
		sum_ms += ms
		if ms > max_ms:
			max_ms = ms

	var avg_ms := sum_ms / 600.0

	print("N=%d" % n)
	print("ALIVE=%d" % s.alive_count())
	print("DEAD=%d" % (s.n - s.alive_count()))
	print("SIM_MS_AVG=%.3f" % avg_ms)
	print("SIM_MS_MAX=%.3f" % max_ms)
	print("TIME=%.2f" % s.time)
	print("WINNER=%d" % sim.winner(s))
	for k in range(BattleSim.PHASE_NAMES.size()):
		print("PHASE %s=%.3f" % [BattleSim.PHASE_NAMES[k], sim.phase_us[k] / 600.0 / 1000.0])
	if avg_ms < 12.0:
		print("ALL_PASS (bench)")
	else:
		print("FAILURES=1 of 1")

	quit()
