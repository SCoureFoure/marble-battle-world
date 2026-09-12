extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# 1. Board shape at rows = 7.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	var r := Plinko.build(7, 0.0, rng)
	t.check(r.rows == 7, "rows == 7")
	t.check(r.pegs.size() == 60, "pegs.size() == 60")
	t.check(r.slot_order.size() == 9, "slot_order.size() == 9")
	var sorted_order := r.slot_order.duplicate()
	sorted_order.sort()
	var expected_order := PackedInt32Array()
	for i in 9:
		expected_order.append(i)
	t.check(sorted_order == expected_order, "slot_order is a permutation of 0..8")
	t.check(r.pegs[0] == Vector2(20, 60), "first peg == Vector2(20,60)")
	t.check(r.pegs[9].x == 40, "row 1 first peg x == 40")

	# 2. Peg counts at other row counts.
	var r6 := Plinko.build(6, 0.0, rng)
	t.check(r6.pegs.size() == 51, "build(6) pegs.size() == 51")
	var r10 := Plinko.build(10, 0.0, rng)
	t.check(r10.pegs.size() == 85, "build(10) pegs.size() == 85")

	# 3. A single drop.
	var d: Dictionary = r.drop(180.0, rng)
	var path: PackedVector2Array = d["path"]
	var slots: PackedInt32Array = d["slots"]
	t.check(path.size() > 5, "path.size() > 5")
	t.check(path[path.size() - 1].y >= Tuning.PLINKO_H - Tuning.PLINKO_BALL_R - 1.0, "last path point near bottom")
	t.check(slots.size() >= 1 and slots.size() <= 3, "slots.size() between 1 and 3")
	var slots_ok := true
	for sv in slots:
		if sv < 0 or sv > 8:
			slots_ok = false
	t.check(slots_ok, "every slot in 0..8")
	var x_ok := true
	for pt in path:
		if pt.x < Tuning.PLINKO_BALL_R - 1e-3 or pt.x > Tuning.PLINKO_W - Tuning.PLINKO_BALL_R + 1e-3:
			x_ok = false
	t.check(x_ok, "all path x within bounds")

	# 4. Determinism.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 11
	var board_a := Plinko.build(7, 0.0, rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 11
	var board_b := Plinko.build(7, 0.0, rng_b)
	var drop_rng_a := RandomNumberGenerator.new()
	drop_rng_a.seed = 12
	var drop_rng_b := RandomNumberGenerator.new()
	drop_rng_b.seed = 12
	var d_a: Dictionary = board_a.drop(180.0, drop_rng_a)
	var d_b: Dictionary = board_b.drop(180.0, drop_rng_b)
	t.check(d_a["slots"] == d_b["slots"], "determinism: identical slots")
	t.check(d_a["path"] == d_b["path"], "determinism: identical path")

	var path_sizes: Array = []

	# 5. Bias.
	var board_pos := Plinko.build(7, 400.0, rng)
	var total_pos := 0.0
	for i in 200:
		var drop_rng := RandomNumberGenerator.new()
		drop_rng.seed = 100 + i
		var dp: Dictionary = board_pos.drop(180.0, drop_rng)
		var p: PackedVector2Array = dp["path"]
		total_pos += p[p.size() - 1].x
		path_sizes.append(p.size())
	var mean_pos := total_pos / 200.0
	t.check(mean_pos > 220.0, "bias +400 mean x > 220")

	var board_neg := Plinko.build(7, -400.0, rng)
	var total_neg := 0.0
	for i in 200:
		var drop_rng2 := RandomNumberGenerator.new()
		drop_rng2.seed = 100 + i
		var dn: Dictionary = board_neg.drop(180.0, drop_rng2)
		var pn: PackedVector2Array = dn["path"]
		total_neg += pn[pn.size() - 1].x
		path_sizes.append(pn.size())
	var mean_neg := total_neg / 200.0
	t.check(mean_neg < 140.0, "bias -400 mean x < 140")

	# 6. Spread.
	var slot_columns := {}
	var sw: float = Tuning.PLINKO_W / Tuning.PLINKO_SLOTS
	for i in 200:
		var drop_rng3 := RandomNumberGenerator.new()
		drop_rng3.seed = 300 + i
		var ds: Dictionary = r.drop(180.0, drop_rng3)
		var ps: PackedVector2Array = ds["path"]
		var col: int = int(ps[ps.size() - 1].x / sw)
		slot_columns[col] = true
		path_sizes.append(ps.size())
	t.check(slot_columns.size() >= 5, "spread: at least 5 distinct slot columns reached")

	# 7. Termination.
	var term_ok := true
	for sz in path_sizes:
		if sz > Tuning.PLINKO_MAX_STEPS / 4 + 2:
			term_ok = false
	t.check(term_ok, "every drop in cases 5-6 terminated within the step/4 + 2 bound")

	t.finish()
	quit()
