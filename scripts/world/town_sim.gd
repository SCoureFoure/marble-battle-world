class_name TownSim extends RefCounted
## Town growth, recruitment, raid/raze recovery, occupation capture.
## Source: docs/ARCHITECTURE.md §12.4.

const STATE_INTACT := 0
const STATE_RAIDED := 1
const STATE_RAZED := 2
const CAPTURE_TIME := 3.0   # fiat: seconds an IDLE stack must occupy a neutral town to capture it


static func step(w: World, dt: float) -> void:
	w.sync_town_arrays()
	for i in range(w.towns.size()):
		match w.town_state[i]:
			STATE_INTACT:
				w.town_pop[i] = minf(Tuning.TOWN_POP_MAX, w.town_pop[i] + Tuning.TOWN_POP_GROWTH * dt)
				if w.town_owner[i] != -1:
					_recruit(w, i, dt)
			STATE_RAIDED:
				# fiat: RAID sets town_timer to RAID_RECOVER; TownSim only
				# decrements and flips state at 0 (owner already -1 from RAID).
				w.town_timer[i] -= dt
				if w.town_timer[i] <= 0.0:
					w.town_state[i] = STATE_INTACT
			STATE_RAZED:
				w.town_timer[i] -= dt
				if w.town_timer[i] <= 0.0:
					w.town_state[i] = STATE_INTACT
					w.town_pop[i] = Tuning.TOWN_POP_START / 2.0
					w.town_owner[i] = -1
					var tile := Vector2i(int(w.towns[i].x), int(w.towns[i].y))
					w.map.kind[w.map.idx(tile.x, tile.y)] = WorldMap.Kind.TOWN
					w.recompute_borders()

	_capture(w, dt)


static func _recruit(w: World, town_id: int, dt: float) -> void:
	var f := w.town_owner[town_id]
	w.town_recruit[town_id] += Tuning.TOWN_RECRUIT_RATE * dt
	while w.town_recruit[town_id] >= 1.0 and w.town_pop[town_id] >= 1.0:
		var target := _recruit_target(w, town_id, f)
		# Stack or unit table full: hold the recruit (capped at one pending) instead
		# of writing through a -1 id.
		if (target == -1 and not w.stacks.has_room()) or not w.units.has_room():
			w.town_recruit[town_id] = minf(w.town_recruit[town_id], 1.0)
			break
		w.town_recruit[town_id] -= 1.0
		w.town_pop[town_id] -= 1.0

		if target == -1:
			var tile := Vector2i(int(w.towns[town_id].x), int(w.towns[town_id].y))
			var c := w.map.center_of(tile.x, tile.y)
			target = w.stacks.add(f, c.x, c.y, NameGen.stack_name(w.rng))
			w.stacks.goal[target] = Stacks.Goal.DEFEND

		var weapon := Kingdoms.recruit_weapon(w, f, w.rng)
		w.units.add(f, 0, weapon, false, target)
		w.stacks.count[target] += 1


# fiat: nearest alive own stack (world-unit distance) within
# TOWN_RECRUIT_RANGE tiles (Chebyshev) with state != BATTLE and
# count < STACK_CAP; a garrison created by a prior recruit this call (or an
# earlier step) is simply the nearest such stack and gets reused.
static func _recruit_target(w: World, town_id: int, f: int) -> int:
	var tile := Vector2i(int(w.towns[town_id].x), int(w.towns[town_id].y))
	var c := w.map.center_of(tile.x, tile.y)
	var best := -1
	var best_dist := INF
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 0:
			continue
		if w.stacks.faction[i] != f:
			continue
		if w.stacks.state[i] == Stacks.State.BATTLE:
			continue
		if w.stacks.count[i] >= Tuning.STACK_CAP:
			continue
		var st := w.stack_tile(i)
		var cheb: int = maxi(absi(st.x - tile.x), absi(st.y - tile.y))
		if cheb > Tuning.TOWN_RECRUIT_RANGE:
			continue
		var d := Vector2(w.stacks.x[i], w.stacks.y[i]).distance_to(c)
		if d < best_dist:
			best_dist = d
			best = i
	return best


# fiat: an alive stack with state == IDLE, idle_timer <= 0, standing on a
# neutral INTACT town tile accumulates that town's town_timer by dt; at
# >= CAPTURE_TIME the stack's faction captures the town. RAIDED/RAZED towns
# reuse town_timer for recovery instead, so this applies only to INTACT
# neutral towns.
static func _capture(w: World, dt: float) -> void:
	for i in range(w.towns.size()):
		if w.town_state[i] != STATE_INTACT or w.town_owner[i] != -1:
			continue
		var tile := Vector2i(int(w.towns[i].x), int(w.towns[i].y))
		var capturer := -1
		for si in range(w.stacks.n):
			if w.stacks.alive[si] == 0:
				continue
			if w.stacks.state[si] != Stacks.State.IDLE:
				continue
			if w.stacks.idle_timer[si] > 0.0:
				continue
			if w.stack_tile(si) != tile:
				continue
			capturer = si
			# UNDECIDED: tie-break when multiple stacks (possibly of
			# different factions) are IDLE on the same neutral town tile in
			# the same step — first stack index found wins.
			break
		if capturer == -1:
			continue
		w.town_timer[i] += dt
		if w.town_timer[i] >= CAPTURE_TIME:
			w.town_owner[i] = w.stacks.faction[capturer]
			w.town_timer[i] = 0.0
			w.recompute_borders()
