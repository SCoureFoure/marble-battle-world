class_name Settling extends RefCounted
## Captain aging, town founding, retirement. docs/ARCHITECTURE.md §17.5.


## First tile at Chebyshev distance r from the stack's tile (r = 0..FOUND_SEARCH,
## scanned ty ascending then tx ascending within each ring) that is in bounds,
## PLAINS, and at least FOUND_MIN_SPACING from every existing town. None found
## -> Vector2i(-1, -1).
static func found_site(w: World, s: int) -> Vector2i:
	var o := w.stack_tile(s)

	for r in range(Tuning.FOUND_SEARCH + 1):
		var candidates: Array[Vector2i] = []
		if r == 0:
			candidates.append(o)
		else:
			for ty in range(o.y - r, o.y + r + 1):
				if absi(ty - o.y) == r:
					for tx in range(o.x - r, o.x + r + 1):
						candidates.append(Vector2i(tx, ty))
				else:
					candidates.append(Vector2i(o.x - r, ty))
					candidates.append(Vector2i(o.x + r, ty))

		for c in candidates:
			if not w.map.in_bounds(c.x, c.y):
				continue
			if w.map.kind[w.map.idx(c.x, c.y)] != WorldMap.Kind.PLAINS:
				continue
			var far_enough := true
			for ti in range(w.towns.size()):
				var tt := Vector2i(int(w.towns[ti].x), int(w.towns[ti].y))
				if maxi(absi(c.x - tt.x), absi(c.y - tt.y)) < Tuning.FOUND_MIN_SPACING:
					far_enough = false
					break
			if far_enough:
				return c

	return Vector2i(-1, -1)


## Once per world second: captains age; goal FOUND stacks path in or found;
## HERO_LIFESPAN-old captains with a rich/big-enough stack found a town else
## retire.
static func check_aging(w: World) -> void:
	var n0 := w.stacks.n
	for s in range(n0):
		if w.stacks.alive[s] == 0:
			continue
		if w.stacks.state[s] == Stacks.State.BATTLE:
			continue
		var cap: int = w.stacks.captain_unit[s]
		if cap < 0:
			continue
		if w.units.alive[cap] == 0:
			continue

		var age := w.time - w.units.career_start[cap]

		if w.stacks.goal[s] == Stacks.Goal.FOUND:
			if age >= Tuning.HERO_LIFESPAN + Tuning.FOUND_GRACE:
				retire(w, s)
			elif w.stacks.state[s] == Stacks.State.IDLE:
				var site := Vector2i(w.stacks.goal_tx[s], w.stacks.goal_ty[s])
				if w.stack_tile(s) == site:
					found_town(w, s, site)
				else:
					var path := w.pathing.find(w.stack_tile(s), site)
					if path.size() == 0:
						retire(w, s)
					else:
						w.stacks.path[s] = path
						w.stacks.path_i[s] = 0
						w.stacks.state[s] = Stacks.State.MOVING
			continue

		if age < Tuning.HERO_LIFESPAN:
			continue

		var score: float = w.stacks.gold[s] + w.stacks.count[s] * Tuning.FOUND_UNIT_VALUE
		var site2 := found_site(w, s)
		if score >= Tuning.FOUND_SCORE and site2 != Vector2i(-1, -1):
			if w.stack_tile(s) == site2:
				found_town(w, s, site2)
			else:
				var path2 := w.pathing.find(w.stack_tile(s), site2)
				if path2.size() > 0:
					w.stacks.goal[s] = Stacks.Goal.FOUND
					w.stacks.goal_tx[s] = site2.x
					w.stacks.goal_ty[s] = site2.y
					w.stacks.path[s] = path2
					w.stacks.path_i[s] = 0
					w.stacks.state[s] = Stacks.State.MOVING
				else:
					retire(w, s)
		else:
			retire(w, s)


## Founds a town at `tile` for the stack `s`'s captain. Guards: `tile` already
## a town, or any town within Chebyshev < FOUND_MIN_SPACING -> -1, no change.
## `captain_unit == -1` still founds the town (using the stack name in the
## log) but skips the lord/succession step. Returns the new town id.
static func found_town(w: World, s: int, tile: Vector2i) -> int:
	if w.town_at(tile) != -1:
		return -1
	for ti in range(w.towns.size()):
		var tt := Vector2i(int(w.towns[ti].x), int(w.towns[ti].y))
		if maxi(absi(tile.x - tt.x), absi(tile.y - tt.y)) < Tuning.FOUND_MIN_SPACING:
			return -1

	var f: int = w.stacks.faction[s]
	var cap: int = w.stacks.captain_unit[s]

	var owner := f
	var has_own_town := false
	for ti2 in range(w.towns.size()):
		if w.town_owner[ti2] == f:
			has_own_town = true
			break
	if not has_own_town:
		var o: int = w.map.owner[w.map.idx(tile.x, tile.y)]
		if o >= 0 and o != f and w.allied(f, o):
			owner = o

	var t := w.add_town(tile, owner)
	w.town_gold[t] = minf(Tuning.TOWN_GOLD_MAX, w.stacks.gold[s])
	w.stacks.gold[s] = 0.0
	w.town_lord[t] = cap

	if owner != f:
		w.stacks.faction[s] = owner
		for u in range(w.units.n):
			if w.units.stack[u] == s:
				w.units.faction[u] = owner

	var log_name: String
	if cap >= 0:
		log_name = str(w.units.names.get(cap, "Unit %d" % cap))
	else:
		log_name = String(w.stacks.names[s])
	w.log_event("%s settles at (%d,%d), founding a town of %s" % [log_name, tile.x, tile.y, w.faction_names[owner]])
	w.bump("foundings")

	if cap >= 0:
		w.units.fate[cap] = Units.Fate.LORD
		w.units.is_captain[cap] = 0
		w.units.stack[cap] = -1
		Lineage.succeed(w, s, cap, "settles")

	w.stacks.goal[s] = Stacks.Goal.DEFEND
	w.stacks.state[s] = Stacks.State.IDLE
	w.stacks.idle_timer[s] = Tuning.FOUND_IDLE
	w.stacks.path[s] = PackedVector2Array()
	w.stacks.path_i[s] = 0
	w.stacks.recount(w.units)
	Kingdoms.on_event(w, "settle", owner)
	w.recompute_borders()
	w.pathing.refresh(w.map)
	return t


## Retires the stack's captain: fate RETIRED, hands off to an heir (or
## leaderless if none). No captain -> no change.
static func retire(w: World, s: int) -> void:
	var cap: int = w.stacks.captain_unit[s]
	if cap < 0:
		return

	w.log_event("%s retires" % str(w.units.names.get(cap, "Unit %d" % cap)))
	w.bump("retirements")

	w.units.fate[cap] = Units.Fate.RETIRED
	w.units.is_captain[cap] = 0
	w.units.stack[cap] = -1
	Lineage.succeed(w, s, cap, "retires")

	w.stacks.goal[s] = Stacks.Goal.IDLE_HEAL
	w.stacks.state[s] = Stacks.State.IDLE
	w.stacks.recount(w.units)
