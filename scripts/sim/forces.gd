class_name Forces
extends RefCounted

# Power of marble k (§16.1): hp scaled by spin and rank, used to size wanted
# attacker counts in the retarget score.
static func power(s, k) -> float:
	return s.hp[k] * (s.spin[k] / Tuning.SPIN_REF + 0.25) * Tuning.RANK_MULT[s.rank[k]]


# Retarget: rebuild s.attackers from the current target assignments, then for
# each live marble on its staggered tick either pick the nearest live enemy
# (RETREAT: old rule, never counted) or the lowest-scored candidate (ENGAGE,
# §16.3), updating attackers immediately so later marbles this tick see it.
static func retarget(s: BattleState, coarse: SpatialHash, tick: int) -> void:
	var px := s.px
	var py := s.py
	var state := s.state
	var faction_id := s.faction_id
	var radius := s.radius
	var target_id := s.target_id
	var is_captain := s.is_captain
	var hp := s.hp
	var hp_max := s.hp_max

	s.attackers.fill(0)
	for i in range(s.n):
		if state[i] == BattleState.State.ENGAGE and target_id[i] >= 0 and state[target_id[i]] != BattleState.State.DEAD:
			s.attackers[target_id[i]] += 1

	for i in range(s.n):
		if state[i] == BattleState.State.DEAD:
			continue

		if (i + tick) % Tuning.ENGAGE_RETARGET_TICKS != 0:
			var t := target_id[i]
			if t >= 0 and state[t] == BattleState.State.DEAD:
				s.target_id[i] = -1
			continue

		var k := coarse.gather(px[i], py[i])
		var scratch := coarse.scratch
		var engage_radius := Tuning.ENGAGE_RADIUS_MULT * radius[i]

		if state[i] == BattleState.State.RETREAT:
			# RETREAT keeps the old nearest-enemy rule and is never counted.
			var best := -1
			var best_dist := 0.0
			for idx in range(k):
				var j := scratch[idx]
				if j == i:
					continue
				if state[j] == BattleState.State.DEAD:
					continue
				if faction_id[j] == faction_id[i]:
					continue
				var dx := px[j] - px[i]
				var dy := py[j] - py[i]
				var dist := sqrt(dx * dx + dy * dy)
				if dist > engage_radius:
					continue
				if best == -1 or dist < best_dist or (dist == best_dist and j < best):
					best = j
					best_dist = dist
			s.target_id[i] = best
			continue

		# ENGAGE: scored retarget (§16.3).
		var old_target := target_id[i]
		var own_power := power(s, i)
		var best_j := -1
		var best_score := 0.0
		for idx in range(k):
			var j := scratch[idx]
			if j == i:
				continue
			if state[j] == BattleState.State.DEAD:
				continue
			if faction_id[j] == faction_id[i]:
				continue
			var dx := px[j] - px[i]
			var dy := py[j] - py[i]
			var dist := sqrt(dx * dx + dy * dy)
			if dist > engage_radius:
				continue
			var att := s.attackers[j] - (1 if old_target == j else 0)
			var want := 1
			if power(s, j) > Tuning.OUTMATCH_RATIO * own_power:
				want = 2
			if is_captain[j] == 1:
				want += 1
			var score: float = dist / radius[i] + Tuning.CROWD_PENALTY * maxi(0, att + 1 - want)
			if hp[j] < Tuning.FINISH_HP_FRAC * hp_max[j]:
				score -= Tuning.FINISH_BONUS
			if j == old_target:
				score -= Tuning.STICKY_BONUS
			if best_j == -1 or score < best_score or (score == best_score and j < best_j):
				best_j = j
				best_score = score

		if best_j != old_target:
			if old_target >= 0 and old_target < s.n and state[old_target] != BattleState.State.DEAD:
				s.attackers[old_target] -= 1
			if best_j >= 0:
				s.attackers[best_j] += 1
			s.target_id[i] = best_j


# Accumulate: sum attraction/recoil, spread advance, cohesion (untargeted
# only) and retreat into a per-marble drive, cap it by cruise/charge/retreat
# speed against the current velocity, then add the surviving drive into
# s.ax/ay. Separation (§6, range 2.0) is a second, uncapped pass.
static func accumulate(s: BattleState, fine: SpatialHash) -> void:
	var px := s.px
	var py := s.py
	var vx := s.vx
	var vy := s.vy
	var radius := s.radius
	var state := s.state
	var faction_id := s.faction_id
	var target_id := s.target_id
	var aggression := s.aggression
	var morale := s.morale
	var faction_captain := s.faction_captain
	var faction_cx := s.faction_cx
	var faction_cy := s.faction_cy
	var faction_alive := s.faction_alive
	var recoil_t := s.recoil_t

	for i in range(s.n):
		if state[i] == BattleState.State.DEAD:
			continue

		var r := radius[i]
		var f := faction_id[i]
		var retreating := state[i] == BattleState.State.RETREAT
		var t := target_id[i]
		var target_live := t >= 0 and state[t] != BattleState.State.DEAD

		var target_dx := 0.0
		var target_dy := 0.0
		var target_dist := 0.0
		if target_live:
			target_dx = px[t] - px[i]
			target_dy = py[t] - py[i]
			target_dist = sqrt(target_dx * target_dx + target_dy * target_dy)

		var dx := 0.0
		var dy := 0.0

		# 1: ENGAGE with a live target: recoil back-off or attraction.
		if not retreating and target_live and target_dist > 0.0:
			if recoil_t[i] > 0.0:
				dx -= Tuning.K_RECOIL * target_dx / target_dist
				dy -= Tuning.K_RECOIL * target_dy / target_dist
			else:
				var attr_mag := Tuning.K_ATTR * aggression[i] * morale[i]
				dx += attr_mag * target_dx / target_dist
				dy += attr_mag * target_dy / target_dist

		# 2: ENGAGE with no target: advance with spread toward the nearest
		# live enemy faction centroid, aimed along a line through it.
		if state[i] == BattleState.State.ENGAGE and t == -1:
			var best_g := -1
			var best_gdist := 0.0
			for g in range(s.faction_count):
				if g == f:
					continue
				if faction_alive[g] <= 0:
					continue
				var gdx := faction_cx[g] - px[i]
				var gdy := faction_cy[g] - py[i]
				var gdist := sqrt(gdx * gdx + gdy * gdy)
				if best_g == -1 or gdist < best_gdist or (gdist == best_gdist and g < best_g):
					best_g = g
					best_gdist = gdist
			if best_g >= 0:
				var cg := Vector2(faction_cx[best_g], faction_cy[best_g])
				var cf := Vector2(faction_cx[f], faction_cy[f])
				var pi_pos := Vector2(px[i], py[i])
				var aim := cg
				var gap := cg - cf
				if gap.length() >= 1e-3:
					var gap_u := gap.normalized()
					var gap_w := Vector2(-gap_u.y, gap_u.x)
					var lat := (pi_pos - cf).dot(gap_w)
					aim = cg + gap_w * lat * Tuning.SPREAD_KEEP
				var aim_vec := aim - pi_pos
				var aim_dist := aim_vec.length()
				if aim_dist > 0.0:
					dx += Tuning.K_ADVANCE * aim_vec.x / aim_dist
					dy += Tuning.K_ADVANCE * aim_vec.y / aim_dist

		# 3: cohesion, only when untargeted.
		if t == -1 and faction_captain[f] != i:
			var captain_idx := faction_captain[f]
			var anchor_x: float
			var anchor_y: float
			if captain_idx >= 0 and state[captain_idx] != BattleState.State.DEAD:
				anchor_x = px[captain_idx]
				anchor_y = py[captain_idx]
			else:
				anchor_x = faction_cx[f]
				anchor_y = faction_cy[f]
			var coh_dx := anchor_x - px[i]
			var coh_dy := anchor_y - py[i]
			var coh_dist := sqrt(coh_dx * coh_dx + coh_dy * coh_dy)
			if coh_dist > 4.0 * r:
				dx += Tuning.K_COHESION * coh_dx / coh_dist
				dy += Tuning.K_COHESION * coh_dy / coh_dist

		# 4: RETREAT: attraction sign flip plus home-edge pull.
		if retreating:
			if target_live and target_dist > 0.0:
				var retreat_mag := Tuning.K_ATTR * aggression[i] * morale[i]
				dx -= retreat_mag * target_dx / target_dist
				dy -= retreat_mag * target_dy / target_dist
			var home: Vector2 = Tuning.HOME_DIR[f % 4]
			dx += Tuning.K_ATTR * home.x
			dy += Tuning.K_ATTR * home.y

		# 5: cap the drive against the current velocity; drop it if over cap.
		var cap: float = Tuning.CRUISE_SPEED
		if retreating:
			cap = Tuning.RETREAT_SPEED
		elif recoil_t[i] > 0.0 or (target_live and target_dist < Tuning.STRIKE_RANGE_MULT * r):
			cap = Tuning.CHARGE_SPEED
		if dx != 0.0 or dy != 0.0:
			var drive_len := sqrt(dx * dx + dy * dy)
			var dir_x := dx / drive_len
			var dir_y := dy / drive_len
			var v_par := vx[i] * dir_x + vy[i] * dir_y
			if v_par < cap:
				s.ax[i] += dx
				s.ay[i] += dy

	# separation (same faction, live, within range): second pass over the
	# grid's cells, visiting each unordered pair once. Never capped.
	_accumulate_separation(s, fine)


# Separation: for every unordered near pair sharing a faction, apply the
# same-magnitude push to both sides at once (equal and opposite).
static func _accumulate_separation(s: BattleState, fine: SpatialHash) -> void:
	var cols: int = fine.cols
	var rows: int = fine.rows
	var cs: PackedInt32Array = fine.cell_start
	var en: PackedInt32Array = fine.entries
	var radius: PackedFloat32Array = s.radius
	var faction_id: PackedInt32Array = s.faction_id
	var sep_range_mult: float = Tuning.SEPARATION_RANGE_MULT
	var k_sep: float = Tuning.K_SEPARATION
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
						# PAIR: same-faction only; magnitude formula matches §6, applied
						# from both sides at once. Coincident marbles draw one random
						# direction per pair and push apart with opposite signs.
						if faction_id[i] != faction_id[j]:
							continue
						var dx := s.px[j] - s.px[i]
						var dy := s.py[j] - s.py[i]
						var dist := sqrt(dx * dx + dy * dy)
						var sep_range := sep_range_mult * (radius[i] + radius[j])
						if dist >= sep_range:
							continue
						var smag := k_sep * (1.0 - dist / sep_range)
						if dist > 0.0:
							s.ax[i] -= smag * dx / dist
							s.ay[i] -= smag * dy / dist
							s.ax[j] += smag * dx / dist
							s.ay[j] += smag * dy / dist
						else:
							var ang := s.rng.randf() * TAU
							var ux := cos(ang)
							var uy := sin(ang)
							s.ax[i] += smag * ux
							s.ay[i] += smag * uy
							s.ax[j] -= smag * ux
							s.ay[j] -= smag * uy
