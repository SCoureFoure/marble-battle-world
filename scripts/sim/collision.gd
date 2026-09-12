class_name Collision
extends RefCounted

static func resolve(s: BattleState, fine: SpatialHash, dt: float) -> void:
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var k := fine.gather(s.px[i], s.py[i])
		for t in range(k):
			var j := fine.scratch[t]
			if j <= i:
				continue
			if s.state[j] == BattleState.State.DEAD:
				continue
			var dx := s.px[j] - s.px[i]
			var dy := s.py[j] - s.py[i]
			var dist := sqrt(dx * dx + dy * dy)
			var rsum := s.radius[i] + s.radius[j]
			if dist >= rsum:
				continue
			var nx: float
			var ny: float
			var overlap: float
			if dist > 0.0:
				nx = dx / dist
				ny = dy / dist
				overlap = rsum - dist
			else:
				var a := s.rng.randf() * TAU
				nx = cos(a)
				ny = sin(a)
				overlap = rsum
			var wi := 1.0 / s.mass[i]
			var wj := 1.0 / s.mass[j]
			var wsum := wi + wj
			# position correction, split by inverse mass
			s.px[i] -= nx * overlap * wi / wsum
			s.py[i] -= ny * overlap * wi / wsum
			s.px[j] += nx * overlap * wj / wsum
			s.py[j] += ny * overlap * wj / wsum
			# velocity: only if approaching
			var vrel := (s.vx[j] - s.vx[i]) * nx + (s.vy[j] - s.vy[i]) * ny
			if vrel < 0.0:
				var imp := -(1.0 + Tuning.RESTITUTION) * vrel / wsum
				s.vx[i] -= nx * imp * wi
				s.vy[i] -= ny * imp * wi
				s.vx[j] += nx * imp * wj
				s.vy[j] += ny * imp * wj
			# spin transfer: faster steals from slower
			if s.spin[i] > s.spin[j]:
				var amt := Tuning.SPIN_TRANSFER * s.spin[j]
				s.spin[i] = min(s.spin_cap[i], s.spin[i] + amt)
				s.spin[j] -= amt
			elif s.spin[j] > s.spin[i]:
				var amt := Tuning.SPIN_TRANSFER * s.spin[i]
				s.spin[j] = min(s.spin_cap[j], s.spin[j] + amt)
				s.spin[i] -= amt
			# enemy contact cost
			if s.faction_id[i] != s.faction_id[j]:
				s.spin[i] = max(Tuning.RPM_MIN, s.spin[i] - Tuning.SPIN_HIT_COST * dt)
				s.spin[j] = max(Tuning.RPM_MIN, s.spin[j] - Tuning.SPIN_HIT_COST * dt)
