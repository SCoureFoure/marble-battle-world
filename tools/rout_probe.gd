extends SceneTree

func _init() -> void:
	for n: int in [30, 100, 250]:
		_run(n)

	print("ALL_PASS (probe)")
	quit()


func _run(n: int) -> void:
	var capacity: int = 2 * n + 2
	var seed: int = 1000 + n
	var s: BattleState = BattleState.new(capacity, seed)

	# Spawn captains
	s.spawn(350, 450, 0, 1, 1, true)
	s.spawn(1250, 450, 1, 1, 1, true)

	# Spawn soldier blocks
	s.spawn_block(0, n, Rect2(100, 100, 500, 700), -1)
	s.spawn_block(1, n, Rect2(1000, 100, 500, 700), -1)

	# Create sim without terrain
	var sim: BattleSim = BattleSim.new(s)

	# Track first retreat time per faction
	var t_first_retreat: PackedFloat32Array = PackedFloat32Array()
	t_first_retreat.resize(2)
	t_first_retreat.fill(-1.0)

	# Run battle until winner or time > 200.0
	while sim.winner(s) == -1 and s.time <= 200.0:
		sim.step(s, Tuning.DT)

		# Check for first retreat after each step
		for f: int in range(2):
			if t_first_retreat[f] < 0.0:
				for i: int in range(s.n):
					if s.faction_id[i] == f and (s.state[i] == BattleState.State.RETREAT or s.fled[i] == 1):
						t_first_retreat[f] = s.time
						break

	# Count stats per faction
	for f: int in range(2):
		var total: int = 0
		var killed: int = 0
		var fled: int = 0
		var retreat: int = 0
		var engage: int = 0

		for i: int in range(s.n):
			if s.faction_id[i] == f:
				total += 1
				if s.state[i] == BattleState.State.DEAD and s.fled[i] == 0:
					killed += 1
				if s.fled[i] == 1:
					fled += 1
				if s.state[i] == BattleState.State.RETREAT:
					retreat += 1
				if s.state[i] == BattleState.State.ENGAGE:
					engage += 1

		var killed_pct: float = 100.0 * float(killed) / float(total) if total > 0 else 0.0
		var winner_result: int = sim.winner(s)

		print("N=%d side=%d winner=%d time=%.1f total=%d killed=%d fled=%d retreat=%d engage=%d killed_pct=%.0f first_retreat=%.1f" % [
			n, f, winner_result, s.time, total, killed, fled, retreat, engage, killed_pct, t_first_retreat[f]
		])
