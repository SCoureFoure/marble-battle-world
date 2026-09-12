class_name Collision
extends RefCounted

static func resolve(s: BattleState, fine: SpatialHash, dt: float) -> void:
	var cols: int = fine.cols
	var rows: int = fine.rows
	var cs: PackedInt32Array = fine.cell_start
	var en: PackedInt32Array = fine.entries
	var radius: PackedFloat32Array = s.radius
	var mass: PackedFloat32Array = s.mass
	var faction_id: PackedInt32Array = s.faction_id
	var spin_cap: PackedFloat32Array = s.spin_cap
	var restitution: float = Tuning.RESTITUTION
	var spin_transfer: float = Tuning.SPIN_TRANSFER
	var rpm_min: float = Tuning.RPM_MIN
	var spin_hit_cost: float = Tuning.SPIN_HIT_COST
	for cy in rows:
		for cx in cols:
			var c: int = cy * cols + cx
			var a0: int = cs[c]
			var a1: int = cs[c + 1]
			if a0 == a1:
				continue
			for k in 5:
				var d: int
				match k:
					0: d = c
					1: d = c + 1 if cx + 1 < cols else -1
					2: d = c + cols - 1 if (cx > 0 and cy + 1 < rows) else -1
					3: d = c + cols if cy + 1 < rows else -1
					_: d = c + cols + 1 if (cx + 1 < cols and cy + 1 < rows) else -1
				if d < 0:
					continue
				var b0: int = cs[d]
				var b1: int = cs[d + 1]
				if b0 == b1:
					continue
				for p in range(a0, a1):
					var i: int = en[p]
					var q0: int = p + 1 if k == 0 else b0
					for q in range(q0, b1):
						var j: int = en[q]
						# PAIR: existing per-pair body, unchanged.
						var dx := s.px[j] - s.px[i]
						var dy := s.py[j] - s.py[i]
						var dist := sqrt(dx * dx + dy * dy)
						var rsum := radius[i] + radius[j]
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
						var wi := 1.0 / mass[i]
						var wj := 1.0 / mass[j]
						var wsum := wi + wj
						# position correction, split by inverse mass
						s.px[i] -= nx * overlap * wi / wsum
						s.py[i] -= ny * overlap * wi / wsum
						s.px[j] += nx * overlap * wj / wsum
						s.py[j] += ny * overlap * wj / wsum
						# velocity: only if approaching
						var vrel := (s.vx[j] - s.vx[i]) * nx + (s.vy[j] - s.vy[i]) * ny
						if vrel < 0.0:
							var imp := -(1.0 + restitution) * vrel / wsum
							s.vx[i] -= nx * imp * wi
							s.vy[i] -= ny * imp * wi
							s.vx[j] += nx * imp * wj
							s.vy[j] += ny * imp * wj
						# spin transfer: faster steals from slower
						if s.spin[i] > s.spin[j]:
							var amt := spin_transfer * s.spin[j]
							s.spin[i] = min(spin_cap[i], s.spin[i] + amt)
							s.spin[j] -= amt
						elif s.spin[j] > s.spin[i]:
							var amt := spin_transfer * s.spin[i]
							s.spin[j] = min(spin_cap[j], s.spin[j] + amt)
							s.spin[i] -= amt
						# enemy contact cost
						if faction_id[i] != faction_id[j]:
							s.spin[i] = max(rpm_min, s.spin[i] - spin_hit_cost * dt)
							s.spin[j] = max(rpm_min, s.spin[j] - spin_hit_cost * dt)
