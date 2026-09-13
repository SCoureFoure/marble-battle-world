class_name Weapons
extends RefCounted

static func tick(s: BattleState, fine: SpatialHash, dt: float) -> void:
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue

		# 1. advance weapon angle
		s.weapon_angle[i] = fposmod(s.weapon_angle[i] + s.spin[i] * Tuning.SPIN_TO_RAD * dt, TAU)

		# 2. advance cooldown
		s.hit_cd[i] = maxf(0.0, s.hit_cd[i] - dt)

		if s.state[i] != BattleState.State.ENGAGE or s.hit_cd[i] != 0.0 or s.target_id[i] < 0:
			continue

		# 3. hit test: gather candidates around the weapon tip, pick nearest live enemy
		var w: int = s.weapon_id[i]
		var a: float = s.weapon_angle[i]
		var r_i: float = s.radius[i]
		var reach: float = Tuning.WEAPON_REACH[w]
		var hx: float = s.px[i] + cos(a) * reach * r_i
		var hy: float = s.py[i] + sin(a) * reach * r_i
		var hr: float = Tuning.WEAPON_HIT_R[w] * r_i

		var k := fine.gather(hx, hy)
		var best_j := -1
		var best_dist := 0.0
		for t in range(k):
			var cand: int = fine.scratch[t]
			if s.state[cand] == BattleState.State.DEAD:
				continue
			if s.faction_id[cand] == s.faction_id[i]:
				continue
			var dx: float = s.px[cand] - hx
			var dy: float = s.py[cand] - hy
			var dist := sqrt(dx * dx + dy * dy)
			if dist >= hr + s.radius[cand]:
				continue
			if best_j == -1 or dist < best_dist or (dist == best_dist and cand < best_j):
				best_j = cand
				best_dist = dist

		if best_j == -1:
			s.hit_cd[i] = Tuning.WEAPON_RECHECK
			continue

		# 4. roll (no fumble branch)
		var m: float = Damage.roll(s, Tuning.WEAPON_CRIT_CHANCE[w])

		# 5. damage (with shield facing check)
		var dmg: float = Tuning.WEAPON_DMG[w] * Tuning.WEAPON_DMG_MULT * (s.spin[i] / Tuning.SPIN_REF) * Tuning.RANK_MULT[s.rank[i]] * m
		if s.weapon_id[best_j] == 4:
			var fdx: float = s.px[i] - s.px[best_j]
			var fdy: float = s.py[i] - s.py[best_j]
			var flen := sqrt(fdx * fdx + fdy * fdy)
			if flen > 0.0:
				var aj: float = s.weapon_angle[best_j]
				var dot := (fdx / flen) * cos(aj) + (fdy / flen) * sin(aj)
				if dot > Tuning.SHIELD_FACING_DOT:
					dmg *= Tuning.SHIELD_DMG_MULT

		# 6. knockback (velocity impulse, mass-independent) and recoil, spins before step 7
		var resist: float = maxf(Tuning.KB_SPIN_RESIST_MIN, s.spin[best_j] / Tuning.SPIN_REF)
		var kb: float = Tuning.WEAPON_KB[w] * (s.spin[i] / Tuning.SPIN_REF) / resist
		var kdx: float = s.px[best_j] - s.px[i]
		var kdy: float = s.py[best_j] - s.py[i]
		var klen := sqrt(kdx * kdx + kdy * kdy)
		if klen > 0.0:
			s.vx[best_j] += (kdx / klen) * kb
			s.vy[best_j] += (kdy / klen) * kb
			s.vx[i] -= (kdx / klen) * kb * Tuning.RECOIL_FRAC
			s.vy[i] -= (kdy / klen) * kb * Tuning.RECOIL_FRAC

		# 7. spin cost
		s.spin[i] = maxf(Tuning.RPM_MIN, s.spin[i] - Tuning.HIT_SPIN_COST_ATTACKER)
		s.spin[best_j] = maxf(Tuning.RPM_MIN, s.spin[best_j] - Tuning.HIT_SPIN_COST_DEFENDER)

		# 8. cooldown; damage/xp/kill/rank-up via Damage.apply
		s.hit_cd[i] = Tuning.WEAPON_COOLDOWN[w]
		Damage.apply(s, i, best_j, dmg, BattleState.Event.HIT)
