extends SceneTree

func _init() -> void:
	var seed := 1
	var seconds := 1800

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = arg.substr("--seed=".length()).to_int()
		elif arg.begins_with("--seconds="):
			seconds = arg.substr("--seconds=".length()).to_int()

	var w := World.create(seed)
	var ticks := seconds * 60

	var window_start_us := Time.get_ticks_usec()
	var tick_count := 0

	for tick in range(ticks):
		WorldSim.step(w, Tuning.DT)
		tick_count += 1

		# Check for early abort
		if w.units.n >= w.units.cap - 64:
			var t_abort := Time.get_ticks_usec()
			_print_hist(w, tick_count, window_start_us, t_abort)
			print("BENCH_ABORT units_full")
			_print_log_and_done(w)
			quit()
			return

		if w.stacks.n >= w.stacks.cap - 4:
			var t_abort := Time.get_ticks_usec()
			_print_hist(w, tick_count, window_start_us, t_abort)
			print("BENCH_ABORT stacks_full")
			_print_log_and_done(w)
			quit()
			return

		# Print every 18000 ticks (300 world seconds)
		if (tick + 1) % 18000 == 0:
			var t_now := Time.get_ticks_usec()
			_print_hist(w, tick_count, window_start_us, t_now)
			window_start_us = t_now
			tick_count = 0

	# Print final window
	var t_final := Time.get_ticks_usec()
	if tick_count > 0:
		_print_hist(w, tick_count, window_start_us, t_final)

	_print_log_and_done(w)
	quit()


func _print_hist(w: World, window_ticks: int, window_start_us: int, window_end_us: int) -> void:
	var wall_us: float = float(window_end_us - window_start_us)
	var ms_per_tick := (wall_us / 1000.0) / float(window_ticks)

	var factions_alive := 0
	for f in range(w.faction_count):
		if w.faction_alive[f] == 1:
			factions_alive += 1

	var stacks_alive := 0
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 1:
			stacks_alive += 1

	var units_alive := 0
	for i in range(w.units.n):
		if w.units.alive[i] == 1:
			units_alive += 1

	var gold_stacks := 0.0
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 1:
			gold_stacks += w.stacks.gold[i]

	var gold_towns := 0.0
	for i in range(w.towns.size()):
		gold_towns += w.town_gold[i]

	print("HIST t=%d factions_alive=%d faction_count=%d stacks_alive=%d stacks_n=%d units_n=%d units_alive=%d towns=%d battles=%d promotions=%d breakaways=%d defections=%d foundings=%d retirements=%d restocks=%d gold_stacks=%.0f gold_towns=%.0f ms_per_tick=%.3f" % [
		int(w.time),
		factions_alive,
		w.faction_count,
		stacks_alive,
		w.stacks.n,
		w.units.n,
		units_alive,
		w.towns.size(),
		w.battles.size(),
		int(w.history.get("promotions", 0)),
		int(w.history.get("breakaways", 0)),
		int(w.history.get("defections", 0)),
		int(w.history.get("foundings", 0)),
		int(w.history.get("retirements", 0)),
		int(w.history.get("restocks", 0)),
		gold_stacks,
		gold_towns,
		ms_per_tick
	])


func _print_log_and_done(w: World) -> void:
	var start := maxi(0, w.events_log.size() - 15)
	for i in range(start, w.events_log.size()):
		print("LOG " + w.events_log[i])
	print("BENCH_DONE")
