class_name PlinkoOutcomes
## Overworld plinko outcome effects. Source: docs/ARCHITECTURE.md §12.3.
## Slot values mirror the future Plinko.Slot enum (§12.2), not part of this slice.

enum Slot { SETTLE = 0, RECRUIT = 1, RAID = 2, RAZE = 3, FORGE = 4, DRILL = 5, HERO_TRIAL = 6, HEIR = 7, CURSE = 8 }


static func apply(w: World, stack: int, slot: int) -> String:
	var f: int = w.stacks.faction[stack]
	match slot:
		Slot.SETTLE:
			return _settle(w, stack, f)
		Slot.RECRUIT:
			return _recruit(w, stack, f)
		Slot.RAID:
			return _raid(w, stack, f)
		Slot.RAZE:
			return _raze(w, stack, f)
		Slot.FORGE:
			return _forge(w, stack)
		Slot.DRILL:
			return _drill(w, stack)
		Slot.HERO_TRIAL:
			return _hero_trial(w, stack)
		Slot.HEIR:
			return _heir(w, stack)
		Slot.CURSE:
			return _curse(w, stack)
		_:
			return "%s: took nothing" % w.stacks.names[stack]


# Nearest town (any state) whose owner is not `f`, preferring neutral,
# within RAID_RANGE. "Nearest" = world-unit distance from the stack
# position to map.center_of(town); range check = Chebyshev tile distance.
static func _settle_target(w: World, stack: int, f: int) -> int:
	var pos := Vector2(w.stacks.x[stack], w.stacks.y[stack])
	var stile := w.stack_tile(stack)
	var best_neutral := -1
	var best_neutral_d := INF
	var best_enemy := -1
	var best_enemy_d := INF
	for i in range(w.towns.size()):
		var owner: int = w.town_owner[i]
		if owner == f:
			continue
		var ttile := Vector2i(int(w.towns[i].x), int(w.towns[i].y))
		var cheb := maxi(absi(stile.x - ttile.x), absi(stile.y - ttile.y))
		if cheb > Tuning.RAID_RANGE:
			continue
		var d: float = pos.distance_to(w.map.center_of(ttile.x, ttile.y))
		if owner == -1:
			if d < best_neutral_d:
				best_neutral_d = d
				best_neutral = i
		else:
			if d < best_enemy_d:
				best_enemy_d = d
				best_enemy = i
	if best_neutral != -1:
		return best_neutral
	return best_enemy


# Nearest enemy town (owner not -1, not f) within RAID_RANGE.
static func _enemy_target(w: World, stack: int, f: int) -> int:
	var pos := Vector2(w.stacks.x[stack], w.stacks.y[stack])
	var stile := w.stack_tile(stack)
	var best := -1
	var best_d := INF
	for i in range(w.towns.size()):
		var owner: int = w.town_owner[i]
		if owner == -1 or owner == f:
			continue
		var ttile := Vector2i(int(w.towns[i].x), int(w.towns[i].y))
		var cheb := maxi(absi(stile.x - ttile.x), absi(stile.y - ttile.y))
		if cheb > Tuning.RAID_RANGE:
			continue
		var d: float = pos.distance_to(w.map.center_of(ttile.x, ttile.y))
		if d < best_d:
			best_d = d
			best = i
	return best


# Nearest own INTACT town within TOWN_RECRUIT_RANGE.
static func _own_intact_target(w: World, stack: int, f: int) -> int:
	var pos := Vector2(w.stacks.x[stack], w.stacks.y[stack])
	var stile := w.stack_tile(stack)
	var best := -1
	var best_d := INF
	for i in range(w.towns.size()):
		if w.town_owner[i] != f or w.town_state[i] != 0:
			continue
		var ttile := Vector2i(int(w.towns[i].x), int(w.towns[i].y))
		var cheb := maxi(absi(stile.x - ttile.x), absi(stile.y - ttile.y))
		if cheb > Tuning.TOWN_RECRUIT_RANGE:
			continue
		var d: float = pos.distance_to(w.map.center_of(ttile.x, ttile.y))
		if d < best_d:
			best_d = d
			best = i
	return best


static func _settle(w: World, stack: int, f: int) -> String:
	var town := _settle_target(w, stack, f)
	if town != -1:
		w.town_owner[town] = f
		w.town_state[town] = 0
		w.recompute_borders()
	for u in range(w.units.n):
		if w.units.stack[u] == stack and w.units.alive[u] == 1:
			w.units.hp_frac[u] = 1.0
	return "%s: SETTLE took %d" % [w.stacks.names[stack], town]


static func _recruit(w: World, stack: int, f: int) -> String:
	var tier := w.stacks.tier(stack)
	var n: int = Tuning.RECRUIT_N[tier]
	var town := _own_intact_target(w, stack, f)
	if town != -1:
		n = mini(n, int(floor(w.town_pop[town])))
		w.town_pop[town] -= n
	else:
		n = n / 2
	var added := 0
	for _i in range(n):
		if w.stacks.count[stack] >= Tuning.STACK_CAP:
			break
		var weapon := w.rng.randi_range(0, 4)
		w.units.add(f, 0, weapon, false, stack)
		w.stacks.count[stack] += 1
		added += 1
	return "%s: RECRUIT took %d" % [w.stacks.names[stack], added]


static func _raid(w: World, stack: int, f: int) -> String:
	var town := _enemy_target(w, stack, f)
	if town != -1:
		w.town_state[town] = 1
		w.town_owner[town] = -1
		w.town_pop[town] *= 0.5
		w.town_timer[town] = Tuning.RAID_RECOVER
		for u in range(w.units.n):
			if w.units.stack[u] == stack and w.units.alive[u] == 1:
				w.units.xp[u] += 5
		w.recompute_borders()
	return "%s: RAID took %d" % [w.stacks.names[stack], town]


static func _raze(w: World, stack: int, f: int) -> String:
	var town := _enemy_target(w, stack, f)
	if town != -1:
		w.town_state[town] = 2
		w.town_owner[town] = -1
		w.town_pop[town] = 0.0
		w.town_timer[town] = Tuning.RAZE_RECOVER
		var t := Vector2i(int(w.towns[town].x), int(w.towns[town].y))
		w.map.kind[w.map.idx(t.x, t.y)] = WorldMap.Kind.RUIN
		w.recompute_borders()
	return "%s: RAZE took %d" % [w.stacks.names[stack], town]


static func _forge(w: World, stack: int) -> String:
	var candidates: Array = []
	for u in range(w.units.n):
		if w.units.stack[u] == stack and w.units.alive[u] == 1:
			candidates.append(u)
	candidates.sort_custom(func(a, b):
		if w.units.rank[a] != w.units.rank[b]:
			return w.units.rank[a] < w.units.rank[b]
		return a < b
	)
	var promoted := 0
	for u in candidates:
		if promoted >= Tuning.FORGE_N:
			break
		w.units.rank[u] = mini(3, w.units.rank[u] + 1)
		promoted += 1
	return "%s: FORGE took %d" % [w.stacks.names[stack], promoted]


static func _drill(w: World, stack: int) -> String:
	var n := 0
	for u in range(w.units.n):
		if w.units.stack[u] == stack and w.units.alive[u] == 1:
			w.units.drill[u] = mini(3, w.units.drill[u] + 1)
			n += 1
	return "%s: DRILL took %d" % [w.stacks.names[stack], n]


static func _hero_trial(w: World, stack: int) -> String:
	var cap := w.stacks.captain_unit[stack]
	if cap != -1 and w.units.alive[cap] == 1:
		w.units.xp[cap] += Tuning.HERO_XP
		w.units.rank[cap] = mini(3, w.units.rank[cap] + 1)
	return "%s: HERO_TRIAL took captain" % w.stacks.names[stack]


# UNDECIDED: tie-break when multiple alive units share the highest kill
# count is unspecified by §12.3; the lowest unit id (first found) wins.
static func _heir(w: World, stack: int) -> String:
	var cap := w.stacks.captain_unit[stack]
	var captain_dead: bool = cap == -1 or w.units.alive[cap] == 0
	if captain_dead:
		var best := -1
		var best_kills := -1
		for u in range(w.units.n):
			if w.units.stack[u] == stack and w.units.alive[u] == 1:
				if w.units.kills[u] > best_kills:
					best_kills = w.units.kills[u]
					best = u
		if best != -1:
			w.units.is_captain[best] = 1
			w.units.names[best] = NameGen.captain_name(w.rng)
			w.stacks.captain_unit[stack] = best
	return "%s: HEIR took heir" % w.stacks.names[stack]


static func _curse(w: World, stack: int) -> String:
	var count := w.stacks.count[stack]
	var n_kill := int(ceil(Tuning.CURSE_FRAC * count))
	var candidates: Array = []
	for u in range(w.units.n):
		if w.units.stack[u] == stack and w.units.alive[u] == 1 and w.units.is_captain[u] == 0:
			candidates.append(u)
	candidates.sort_custom(func(a, b):
		if w.units.xp[a] != w.units.xp[b]:
			return w.units.xp[a] < w.units.xp[b]
		return a < b
	)
	var killed := 0
	for u in candidates:
		if killed >= n_kill:
			break
		w.units.kill(u)
		killed += 1
	w.stacks.recount(w.units)
	return "%s: CURSE took %d" % [w.stacks.names[stack], killed]
