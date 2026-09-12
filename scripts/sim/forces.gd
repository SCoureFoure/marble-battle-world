class_name Forces
extends RefCounted

# Retarget: for each live marble on its staggered tick, pick the nearest
# live enemy within engage range using the coarse spatial hash.
static func retarget(s: BattleState, coarse: SpatialHash, tick: int) -> void:
	var px := s.px
	var py := s.py
	var state := s.state
	var faction_id := s.faction_id
	var radius := s.radius
	var target_id := s.target_id

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


# Accumulate: sum attraction, cohesion, separation and retreat accelerations
# into s.ax/ay for every live marble. Does not zero ax/ay (BattleSim does).
static func accumulate(s: BattleState, fine: SpatialHash) -> void:
	var px := s.px
	var py := s.py
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

	for i in range(s.n):
		if state[i] == BattleState.State.DEAD:
			continue

		var r := radius[i]
		var f := faction_id[i]
		var retreating := state[i] == BattleState.State.RETREAT

		# attraction
		var t := target_id[i]
		if t >= 0 and state[t] != BattleState.State.DEAD:
			var dx := px[t] - px[i]
			var dy := py[t] - py[i]
			var dist := sqrt(dx * dx + dy * dy)
			if dist > 0.0:
				var mag := Tuning.K_ATTR * aggression[i] * morale[i]
				if retreating:
					mag = -mag
				s.ax[i] += mag * dx / dist
				s.ay[i] += mag * dy / dist

		# advance: pull toward nearest enemy faction centroid when no target
		if state[i] == BattleState.State.ENGAGE and target_id[i] == -1:
			var best_g := -1
			var best_dist := 0.0
			for g in range(s.faction_count):
				if g == f:
					continue
				if faction_alive[g] <= 0:
					continue
				var cdx := faction_cx[g] - px[i]
				var cdy := faction_cy[g] - py[i]
				var cdist := sqrt(cdx * cdx + cdy * cdy)
				if best_g == -1 or cdist < best_dist or (cdist == best_dist and g < best_g):
					best_g = g
					best_dist = cdist
			if best_g >= 0 and best_dist > 0.0:
				var cdx := faction_cx[best_g] - px[i]
				var cdy := faction_cy[best_g] - py[i]
				s.ax[i] += Tuning.K_ADVANCE * cdx / best_dist
				s.ay[i] += Tuning.K_ADVANCE * cdy / best_dist

		# cohesion (the captain is its own anchor: no term at all)
		if faction_captain[f] != i:
			var cap := faction_captain[f]
			var anchor_x: float
			var anchor_y: float
			if cap >= 0 and state[cap] != BattleState.State.DEAD:
				anchor_x = px[cap]
				anchor_y = py[cap]
			else:
				anchor_x = faction_cx[f]
				anchor_y = faction_cy[f]
			var adx := anchor_x - px[i]
			var ady := anchor_y - py[i]
			var adist := sqrt(adx * adx + ady * ady)
			if adist > 4.0 * r:
				s.ax[i] += Tuning.K_COHESION * adx / adist
				s.ay[i] += Tuning.K_COHESION * ady / adist

		# retreat: pull toward the faction's home edge
		if retreating:
			var home: Vector2 = Tuning.HOME_DIR[f % 4]
			s.ax[i] += Tuning.K_ATTR * home.x
			s.ay[i] += Tuning.K_ATTR * home.y

	# separation (same faction, live, within range): second pass over the
	# grid's cells, visiting each unordered pair once.
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
