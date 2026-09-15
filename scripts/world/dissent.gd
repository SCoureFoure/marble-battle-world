class_name Dissent extends RefCounted
## Values, bond and disaffection of heroes, captains, lords and towns (§20).

enum Drive { GLORY = 0, WEALTH = 2, FAITH = 3, LAND = 4 }


## Kingdom-event value deltas per axis, keyed by event kind.
static func event_deltas(kind: String) -> PackedFloat32Array:
	match kind:
		"win":
			return PackedFloat32Array([Tuning.KT_WIN_AGGR, 0.0, 0.0, 0.0, 0.0])
		"raze":
			return PackedFloat32Array([0.0, 0.0, Tuning.KT_RAZE_GREED, Tuning.KT_RAZE_PIETY, 0.0])
		"settle":
			return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, Tuning.KT_SETTLE_COH])
		"retreat":
			return PackedFloat32Array([Tuning.KT_RETREAT_AGGR, 0.0, 0.0, 0.0, Tuning.KT_RETREAT_COH])
		"pilgrim":
			return PackedFloat32Array([0.0, 0.0, 0.0, Tuning.KT_PILGRIM_PIETY, 0.0])
		_:
			return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])


## Kingdom `f`'s values on the 5 axes, or five KTRAIT_INIT if `f` is invalid.
static func kingdom_vals(w: World, f: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if f < 0 or w.ktraits.size() < (f + 1) * 5:
		for _k in range(5):
			out.append(Tuning.KTRAIT_INIT)
		return out
	for k in range(5):
		out.append(w.ktraits[f * 5 + k])
	return out


## Unit `u`'s values on the 5 axes.
static func unit_vals(w: World, u: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(5):
		out.append(w.units.vals[u * 5 + k])
	return out


## Town `t`'s values on the 5 axes.
static func town_vals(w: World, t: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(5):
		out.append(w.town_vals[t * 5 + k])
	return out


## Mean absolute difference between two value vectors.
static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sum := 0.0
	for k in range(5):
		sum += absf(a[k] - b[k])
	return sum / 5.0


## Deterministic per-unit noise from a hash-seeded local RNG; never touches w.rng beyond reading .state.
static func noise(w: World, u: int) -> PackedFloat32Array:
	var st: int = w.rng.state if w.rng != null else 0
	var r := RandomNumberGenerator.new()
	r.seed = hash([st, u, w.units.gen[u]])
	var out := PackedFloat32Array()
	for _k in range(5):
		out.append(r.randf() * 2.0 - 1.0)
	return out


## Seeds unit `u`'s values from `src` plus seed noise, and resets bond to BOND_INIT.
static func seed_unit(w: World, u: int, src: PackedFloat32Array) -> void:
	var n := noise(w, u)
	for k in range(5):
		w.units.vals[u * 5 + k] = clampf(src[k] + Tuning.VALUE_SEED_SPREAD * n[k], 0.0, 1.0)
	w.units.bond[u] = Tuning.BOND_INIT


## True if unit `u` is an alive lord, or an alive active hero/captain.
static func member(w: World, u: int) -> bool:
	if w.units.alive[u] != 1:
		return false
	if w.units.fate[u] == Units.Fate.LORD:
		return true
	return w.units.fate[u] == Units.Fate.ACTIVE and (w.units.hero[u] == 1 or w.units.is_captain[u] == 1)


## Applies event `kind`'s value deltas (scaled) and bond change to every hero/captain in `stack`.
static func on_stack_event(w: World, kind: String, stack: int) -> void:
	var d := event_deltas(kind)
	for u in range(w.units.n):
		if w.units.stack[u] != stack:
			continue
		if w.units.alive[u] != 1:
			continue
		if w.units.hero[u] != 1 and w.units.is_captain[u] != 1:
			continue
		for k in range(5):
			w.units.vals[u * 5 + k] = clampf(w.units.vals[u * 5 + k] + d[k] * Tuning.HERO_EVENT_SCALE, 0.0, 1.0)
		if kind == "win":
			w.units.bond[u] = clampf(w.units.bond[u] + Tuning.BOND_WIN, 0.0, 1.0)
		elif kind == "retreat":
			w.units.bond[u] = clampf(w.units.bond[u] - Tuning.BOND_LOSS, 0.0, 1.0)


## Once-per-world-second update: member bond drifts toward 1.0; town values pull toward their lord and owner kingdom.
static func tick(w: World) -> void:
	for u in range(w.units.n):
		if w.units.alive[u] != 1:
			continue
		if w.units.fate[u] != Units.Fate.ACTIVE:
			continue
		if w.units.hero[u] != 1 and w.units.is_captain[u] != 1:
			continue
		w.units.bond[u] = move_toward(w.units.bond[u], 1.0, Tuning.BOND_SERVICE_RATE)

	for t in range(w.towns.size()):
		var owner: int = w.town_owner[t]
		if owner < 0:
			continue
		var lord: int = w.town_lord[t]
		if lord >= 0 and lord < w.units.n and w.units.alive[lord] == 1:
			for k in range(5):
				w.town_vals[t * 5 + k] = move_toward(w.town_vals[t * 5 + k], w.units.vals[lord * 5 + k], Tuning.TOWN_LORD_PULL)
		var kvals := kingdom_vals(w, owner)
		for k in range(5):
			w.town_vals[t * 5 + k] = move_toward(w.town_vals[t * 5 + k], kvals[k], Tuning.TOWN_REALM_PULL)


## Distance between unit `u`'s values and its kingdom's, offset by bond (may be negative).
static func unit_disaffection(w: World, u: int) -> float:
	return distance(unit_vals(w, u), kingdom_vals(w, w.units.faction[u])) - Tuning.BOND_WEIGHT * w.units.bond[u]


## Distance between town `t`'s values and its owner kingdom's; 0.0 if unowned.
static func town_disaffection(w: World, t: int) -> float:
	if w.town_owner[t] < 0:
		return 0.0
	return distance(town_vals(w, t), kingdom_vals(w, w.town_owner[t]))


## Political weight of unit `u`: lords and heroes fixed, captains scale with their stack's count.
static func unit_power(w: World, u: int) -> float:
	if w.units.fate[u] == Units.Fate.LORD:
		return Tuning.POWER_LORD
	if w.units.is_captain[u] == 1 and w.units.stack[u] >= 0:
		return float(w.stacks.count[w.units.stack[u]])
	return Tuning.POWER_HERO


## Political weight of town `t`: its population.
static func town_power(w: World, t: int) -> float:
	return w.town_pop[t]


## Population-weighted average of positive disaffection across faction `f`'s members and towns.
static func tension(w: World, f: int) -> float:
	var num := 0.0
	var den := 0.0
	for u in range(w.units.n):
		if not member(w, u):
			continue
		if w.units.faction[u] != f:
			continue
		var p := unit_power(w, u)
		var dis := unit_disaffection(w, u)
		num += p * maxf(0.0, dis)
		den += p
	for t in range(w.towns.size()):
		if w.town_owner[t] != f:
			continue
		var pt := town_power(w, t)
		var dist := town_disaffection(w, t)
		num += pt * maxf(0.0, dist)
		den += pt
	if den == 0.0:
		return 0.0
	return num / den
