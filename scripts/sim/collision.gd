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
	var rank: PackedInt32Array = s.rank
	var spin_cap: PackedFloat32Array = s.spin_cap
	var restitution: float = Tuning.RESTITUTION
	var rpm_min: float = Tuning.RPM_MIN
	var spin_ref: float = Tuning.SPIN_REF
	var clash_min_vrel: float = Tuning.CLASH_MIN_VREL
	var clash_kick: float = Tuning.CLASH_KICK
	var clash_spin_cost: float = Tuning.CLASH_SPIN_COST
	var bump_cooldown: float = Tuning.BUMP_COOLDOWN
	var body_dmg: float = Tuning.BODY_DMG
	var ally_min_vrel: float = Tuning.ALLY_MIN_VREL
	var ally_spin_gain: float = Tuning.ALLY_SPIN_GAIN
	var ally_spin_gain_max: float = Tuning.ALLY_SPIN_GAIN_MAX
	var boost_cooldown: float = Tuning.BOOST_COOLDOWN
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
						if s.state[i] == BattleState.State.DEAD or s.state[j] == BattleState.State.DEAD:
							continue
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
						# §15.5 enemy clash / ally spin boost
						if faction_id[i] != faction_id[j]:
							if vrel < -clash_min_vrel:
								var dv: float = clash_kick * (s.spin[i] + s.spin[j]) / (2.0 * spin_ref)
								s.vx[i] -= nx * dv * wi / wsum
								s.vy[i] -= ny * dv * wi / wsum
								s.vx[j] += nx * dv * wj / wsum
								s.vy[j] += ny * dv * wj / wsum
								for pair_i in 2:
									var dealer: int = i if pair_i == 0 else j
									var victim: int = j if pair_i == 0 else i
									if s.state[dealer] == BattleState.State.ENGAGE and s.bump_cd[dealer] == 0.0 and s.state[victim] != BattleState.State.DEAD:
										var dmg: float = body_dmg * (s.spin[dealer] / spin_ref) * Tuning.RANK_MULT[rank[dealer]] * Damage.roll(s, 0.0)
										s.spin[dealer] = max(rpm_min, s.spin[dealer] - clash_spin_cost)
										s.bump_cd[dealer] = bump_cooldown
										Damage.apply(s, dealer, victim, dmg, BattleState.Event.BUMP)
						else:
							if vrel < -ally_min_vrel and s.boost_cd[i] == 0.0 and s.boost_cd[j] == 0.0:
								var gain: float = min(ally_spin_gain_max, ally_spin_gain * -vrel)
								s.spin[i] = min(spin_cap[i], s.spin[i] + gain)
								s.spin[j] = min(spin_cap[j], s.spin[j] + gain)
								s.boost_cd[i] = boost_cooldown
								s.boost_cd[j] = boost_cooldown
								s.events.append([BattleState.Event.BOOST, i, j, gain])
