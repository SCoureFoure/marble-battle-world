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
	var rng := s.rng

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

		# separation (same faction, live, within range)
		var k := fine.gather(px[i], py[i])
		var scratch := fine.scratch
		for idx in range(k):
			var j := scratch[idx]
			if j == i:
				continue
			if state[j] == BattleState.State.DEAD:
				continue
			if faction_id[j] != f:
				continue
			var sdx := px[j] - px[i]
			var sdy := py[j] - py[i]
			var sdist := sqrt(sdx * sdx + sdy * sdy)
			var sep_range := Tuning.SEPARATION_RANGE_MULT * (r + radius[j])
			if sdist < sep_range:
				var smag := Tuning.K_SEPARATION * (1.0 - sdist / sep_range)
				if sdist > 0.0:
					s.ax[i] -= smag * sdx / sdist
					s.ay[i] -= smag * sdy / sdist
				else:
					var ang := rng.randf() * TAU
					s.ax[i] += smag * cos(ang)
					s.ay[i] += smag * sin(ang)

		# retreat: pull toward the faction's home edge
		if retreating:
			var home: Vector2 = Tuning.HOME_DIR[f % 4]
			s.ax[i] += Tuning.K_ATTR * home.x
			s.ay[i] += Tuning.K_ATTR * home.y
