class_name Heroes extends RefCounted
## Hero promotion, breakaway/defection, and follow-legacy succession.
## docs/ARCHITECTURE.md §17.4.


## False if `alive == 0`, `hero == 1` or `is_captain == 1`. Otherwise promotes
## (and returns true) when `kills >= HERO_KILLS`, `rank >= LEGEND_RANK`, or
## `slew_leader` is true; else false.
static func check_promote(w: World, u: int, slew_leader: bool) -> bool:
	if w.units.alive[u] == 0 or w.units.hero[u] == 1 or w.units.is_captain[u] == 1:
		return false

	if w.units.kills[u] >= Tuning.HERO_KILLS or w.units.rank[u] >= Tuning.LEGEND_RANK or slew_leader:
		promote(w, u)
		return true

	return false


## Draw order (determinism): ambition, then captain_name_base, then hero_epithet.
static func promote(w: World, u: int) -> void:
	w.units.ambition[u] = w.rng.randf()
	var base := NameGen.captain_name_base(w.rng)
	var adj := NameGen.hero_epithet(w.rng)

	w.units.hero[u] = 1
	w.units.career_start[u] = w.time
	w.units.dynasty[u] = [base, 1]
	w.units.names[u] = "%s the %s" % [base, adj]

	var stack_id: int = w.units.stack[u]
	var stack_name := "the wilds"  # fiat: log's stack name when stack[u] < 0
	if stack_id >= 0:
		stack_name = String(w.stacks.names[stack_id])
	w.log_event("%s rises from the ranks of %s" % [w.units.names[u], stack_name])
	w.bump("promotions")


static func defect_chance(w: World, u: int) -> float:
	var f: int = w.units.faction[u]
	var s: int = w.units.stack[u]
	var cap: int = w.stacks.captain_unit[s] if s >= 0 else -1

	var outshine := 0.0
	if cap >= 0 and w.units.kills[u] > w.units.kills[cap]:
		outshine = 1.0

	var val := Tuning.DEFECT_BASE + Tuning.DEFECT_AMBITION * w.units.ambition[u] \
		- Tuning.DEFECT_COHESION * (w.ktrait(f, 4) - 0.5) \
		- Tuning.DEFECT_PIETY * (w.ktrait(f, 3) - 0.5) \
		+ Tuning.DEFECT_OUTSHINE * outshine
	return clampf(val, 0.05, 0.95)


## Called once per world second by the caller. Draws nothing for ineligible
## units (checked before any rng use).
static func check_breakaway(w: World) -> void:
	var n0: int = w.units.n
	for u in range(n0):
		if w.units.alive[u] == 0 or w.units.hero[u] == 0 or w.units.is_captain[u] == 1:
			continue
		if w.units.fate[u] != Units.Fate.ACTIVE:
			continue

		var s: int = w.units.stack[u]
		if s < 0 or w.stacks.alive[s] == 0:
			continue
		if w.stacks.state[s] != Stacks.State.IDLE and w.stacks.state[s] != Stacks.State.MOVING:
			continue
		if w.stacks.count[s] < Tuning.BREAKAWAY_MIN_STACK:
			continue
		if w.time - w.units.career_start[u] < Tuning.BREAKAWAY_DELAY:
			continue
		if w.time < w.units.pledge_t[u]:
			continue

		if w.rng.randf() < Tuning.BREAKAWAY_RATE:
			breakaway(w, u)


## Splits `u` (a hero) and a share of `u`'s stack into a new stack, loyal or
## defecting. Returns the new stack id, or -1 with no change and no rng
## draws when the stack table is full. `force_defect` (0/1) overrides the
## roll's *result* in step 4 (the roll is still drawn); -1 uses the roll.
static func breakaway(w: World, u: int, force_defect: int = -1) -> int:
	if w.stacks.n >= w.stacks.cap:
		return -1

	# 1.
	var s: int = w.units.stack[u]
	var f: int = w.stacks.faction[s]
	var c: int = w.stacks.count[s]
	var parent_cap: int = w.stacks.captain_unit[s]

	# 2.
	var want: int = mini(maxi(roundi(c * Tuning.FOLLOW_FRAC + w.units.kills[u] * Tuning.FOLLOW_PER_KILL), Tuning.BREAKAWAY_MIN_FOLLOWERS), c / 2)

	# 3. A hero who rallied in with a contingent (§19) leaves with exactly those
	# men (no rng draws). Otherwise pool = alive units of s, not captain, not
	# hero, ascending id, and `want` of them are drawn.
	var followers: Array = []
	for id0 in range(w.units.n):
		if w.units.stack[id0] == s and w.units.alive[id0] == 1 and w.units.leader[id0] == u and w.units.is_captain[id0] == 0:
			followers.append(id0)

	if followers.is_empty():
		var pool: Array = []
		for id in range(w.units.n):
			if w.units.stack[id] == s and w.units.alive[id] == 1 and w.units.is_captain[id] == 0 and w.units.hero[id] == 0:
				pool.append(id)

		var take: int = mini(want, pool.size())
		for k in range(take):
			var j: int = w.rng.randi_range(k, pool.size() - 1)
			var tmp = pool[k]
			pool[k] = pool[j]
			pool[j] = tmp
		for k2 in range(take):
			followers.append(pool[k2])

	# 4.
	var roll: bool = w.rng.randf() < defect_chance(w, u)
	var defect: bool = roll
	if force_defect == 0:
		defect = false
	elif force_defect == 1:
		defect = true

	var g: int = f
	var did_defect := false
	if defect:
		var g2: int = Kingdoms.new_faction(w, f)
		if g2 != -1:
			g = g2
			w.add_relation(f, g, Tuning.DEFECT_RELATION)
			did_defect = true

	# 5.
	var tile: Vector2i = w.stack_tile(s)
	var neighbours: Array = World._passable_neighbours(w.map, tile)
	if neighbours.size() > 0:
		tile = neighbours[0]
	var centre: Vector2 = w.map.center_of(tile.x, tile.y)
	var ns: int = w.stacks.add(g, centre.x, centre.y, NameGen.stack_name(w.rng))

	# 6.
	w.units.stack[u] = ns
	w.units.faction[u] = g
	w.units.leader[u] = -1
	for fu in followers:
		w.units.stack[fu] = ns
		w.units.faction[fu] = g
		w.units.leader[fu] = -1
	w.units.is_captain[u] = 1
	w.units.mentor[u] = parent_cap
	w.stacks.captain_unit[ns] = u

	# 7.
	var moved: int = followers.size() + 1
	var share: float = w.stacks.gold[s] * moved / c
	w.stacks.gold[s] -= share
	w.stacks.gold[ns] += share
	w.stacks.recount(w.units)

	# 8.
	w.stacks.immunity[ns] = Tuning.RETREAT_IMMUNITY
	if g != f:
		w.stacks.immunity[s] = Tuning.RETREAT_IMMUNITY

	# 9.
	if did_defect:
		w.log_event("%s breaks from %s, founding the free company %s" % [w.units.names.get(u, "Unit %d" % u), str(w.faction_names[f]), str(w.faction_names[g])])
		w.bump("breakaways")
		w.bump("defections")
	else:
		w.log_event("%s leaves %s with %d men" % [w.units.names.get(u, "Unit %d" % u), str(w.stacks.names[s]), followers.size()])
		w.bump("breakaways")

	return ns


## Follow-legacy successor: an active unit with a stack, else the dead
## captain's successor on `last_stack`, else the mentee (offshoot) with the
## most kills, else -1.
static func successor(w: World, u: int, last_stack: int) -> int:
	if u >= 0 and w.units.alive[u] == 1 and w.units.fate[u] == Units.Fate.ACTIVE and w.units.stack[u] >= 0:
		return u

	if last_stack >= 0 and last_stack < w.stacks.n and w.stacks.alive[last_stack] == 1:
		var c: int = w.stacks.captain_unit[last_stack]
		if c >= 0 and c != u and w.units.alive[c] == 1:
			return c

	var best := -1
	var best_kills := -1
	for id in range(w.units.n):
		if w.units.mentor[id] == u and w.units.alive[id] == 1 and w.units.fate[id] == Units.Fate.ACTIVE and w.units.stack[id] >= 0:
			if w.units.kills[id] > best_kills:
				best_kills = w.units.kills[id]
				best = id
	if best != -1:
		return best

	return -1
