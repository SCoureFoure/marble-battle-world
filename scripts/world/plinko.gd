class_name Plinko
extends RefCounted
## Plinko board build + headless drop. Source: docs/ARCHITECTURE.md §12.2.

enum Slot { SETTLE = 0, RECRUIT = 1, RAID = 2, RAZE = 3, FORGE = 4, DRILL = 5, HERO_TRIAL = 6, HEIR = 7, CURSE = 8 }

var rows: int
var pegs: PackedVector2Array          # board space, (0,0) top-left, width PLINKO_W, height PLINKO_H
var slot_order: PackedInt32Array      # length PLINKO_SLOTS, a permutation of Slot values
var bias: float                       # constant horizontal acceleration, world units/s^2


static func build(rows_: int, bias_: float, rng: RandomNumberGenerator) -> Plinko:
	var b := Plinko.new()
	b.rows = rows_
	b.bias = bias_

	var sw: float = Tuning.PLINKO_W / Tuning.PLINKO_SLOTS
	var row_gap: float = (Tuning.PLINKO_H - 120.0) / rows_
	var pegs_out := PackedVector2Array()
	for r in rows_:
		var y: float = 60.0 + r * row_gap
		if r % 2 == 0:
			for k in Tuning.PLINKO_SLOTS:
				var x: float = sw / 2.0 + k * sw
				pegs_out.append(Vector2(x, y))
		else:
			for k in (Tuning.PLINKO_SLOTS - 1):
				var x: float = sw + k * sw
				pegs_out.append(Vector2(x, y))
	b.pegs = pegs_out

	var order := PackedInt32Array()
	order.resize(Tuning.PLINKO_SLOTS)
	for i in Tuning.PLINKO_SLOTS:
		order[i] = i
	for i in range(Tuning.PLINKO_SLOTS - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	b.slot_order = order

	return b


func drop(x0: float, rng: RandomNumberGenerator) -> Dictionary:
	var w: float = Tuning.PLINKO_W
	var h: float = Tuning.PLINKO_H
	var r: float = Tuning.PLINKO_BALL_R
	var peg_r: float = Tuning.PLINKO_PEG_R
	var restitution: float = Tuning.PLINKO_RESTITUTION
	var dt: float = Tuning.PLINKO_DT
	var sw: float = w / Tuning.PLINKO_SLOTS
	var band_y: float = h - Tuning.PLINKO_SLOT_BAND
	var board_pegs := pegs
	var order := slot_order

	var p := Vector2(x0 + rng.randf_range(-2.0, 2.0), r)
	var v := Vector2(0.0, 0.0)
	var path := PackedVector2Array()
	var slots := PackedInt32Array()
	var steps := 0

	while true:
		v.y += Tuning.PLINKO_GRAVITY * dt
		v.x += bias * dt
		p += v * dt

		if p.x < r:
			p.x = r
			v.x = -v.x * restitution
		elif p.x > w - r:
			p.x = w - r
			v.x = -v.x * restitution

		for peg in board_pegs:
			var d: Vector2 = p - peg
			var dist: float = d.length()
			var rsum: float = peg_r + r
			if dist < rsum and dist > 0.0:
				var n: Vector2 = d / dist
				p = peg + n * rsum
				var vn: float = v.dot(n)
				v -= n * vn * (1.0 + restitution)
				v.x += rng.randf_range(-15.0, 15.0)

		if p.y >= band_y:
			var k: int = clampi(int(p.x / sw), 0, Tuning.PLINKO_SLOTS - 1)
			var sv: int = order[k]
			if not slots.has(sv) and slots.size() < Tuning.PLINKO_MAX_OUTCOMES:
				slots.append(sv)

		steps += 1
		if steps % 4 == 0:
			path.append(p)

		if p.y >= h - r:
			break
		if steps >= Tuning.PLINKO_MAX_STEPS:
			if slots.size() == 0:
				var k2: int = clampi(int(p.x / sw), 0, Tuning.PLINKO_SLOTS - 1)
				slots.append(order[k2])
			break

	path.append(p)

	return {"path": path, "slots": slots}
