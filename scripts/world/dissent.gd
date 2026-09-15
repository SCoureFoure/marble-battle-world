class_name Dissent extends RefCounted
## Values, bond and disaffection of heroes, captains, lords and towns (§20).

enum Drive { GLORY = 0, WEALTH = 2, FAITH = 3, LAND = 4 }
const DRIVE_AXES := [0, 2, 3, 4]  # grievance index d -> value axis (GLORY, WEALTH, FAITH, LAND)
const LEFT_OTHER := 4  # Units.left_for value: broke away with no positive grievance
const DRIVE_WORDS := ["glory", "wealth", "faith", "land"]  # grievance index d -> log word


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


## Unit `u`'s value-axis strength for drive `d` (§20.2).
static func drive_strength(w: World, u: int, d: int) -> float:
	var axis: int = DRIVE_AXES[d]
	return w.units.vals[u * 5 + axis]


## Unit `u`'s overall grievance: drive-strength-weighted average of its per-drive grievances (§20.2).
static func grievance(w: World, u: int) -> float:
	var sw := 0.0
	for d in range(4):
		sw += drive_strength(w, u, d)
	if sw <= 0.0001:
		return 0.0
	var g := 0.0
	for d in range(4):
		g += drive_strength(w, u, d) * w.units.griev[u * 4 + d]
	return g / sw


## Grievance index d (0..3) with the largest drive_strength * griev; ties keep the lowest d; -1 if none is > 0 (§20.3).
static func top_grievance(w: World, u: int) -> int:
	var best := -1
	var best_p := 0.0
	for d in range(4):
		var p: float = drive_strength(w, u, d) * w.units.griev[u * 4 + d]
		if p > best_p:
			best_p = p
			best = d
	return best


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
	for d in range(4):
		w.units.griev[u * 4 + d] = 0.0


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
		match kind:
			"win":
				w.units.griev[u * 4 + 0] = clampf(w.units.griev[u * 4 + 0] - Tuning.GLORY_WIN, 0.0, 1.0)
			"retreat":
				w.units.griev[u * 4 + 0] = clampf(w.units.griev[u * 4 + 0] - Tuning.GLORY_FOUGHT, 0.0, 1.0)
			"raze":
				w.units.griev[u * 4 + 1] = clampf(w.units.griev[u * 4 + 1] - Tuning.WEALTH_RAID, 0.0, 1.0)
				w.units.griev[u * 4 + 2] = clampf(w.units.griev[u * 4 + 2] + Tuning.FAITH_SACRILEGE * drive_strength(w, u, 2), 0.0, 1.0)
			"raid":
				w.units.griev[u * 4 + 1] = clampf(w.units.griev[u * 4 + 1] - Tuning.WEALTH_RAID, 0.0, 1.0)
			"pilgrim":
				w.units.griev[u * 4 + 2] = clampf(w.units.griev[u * 4 + 2] - Tuning.FAITH_PILGRIM, 0.0, 1.0)
			"settle":
				w.units.griev[u * 4 + 3] = clampf(w.units.griev[u * 4 + 3] - Tuning.LAND_SETTLE, 0.0, 1.0)


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
		var s: int = w.units.stack[u]
		var gpm: float = w.stacks.gold[s] / maxf(1.0, float(w.stacks.count[s])) if s >= 0 else 0.0
		w.units.griev[u * 4 + 0] = clampf(w.units.griev[u * 4 + 0] + Tuning.GRIEV_RISE * drive_strength(w, u, 0), 0.0, 1.0)
		if gpm < Tuning.WEALTH_COMFORT:
			w.units.griev[u * 4 + 1] = clampf(w.units.griev[u * 4 + 1] + Tuning.GRIEV_RISE * drive_strength(w, u, 1), 0.0, 1.0)
		else:
			w.units.griev[u * 4 + 1] = clampf(w.units.griev[u * 4 + 1] - Tuning.WEALTH_COMFORT_DRAIN, 0.0, 1.0)
		w.units.griev[u * 4 + 2] = clampf(w.units.griev[u * 4 + 2] + Tuning.GRIEV_RISE_FAITH * drive_strength(w, u, 2), 0.0, 1.0)
		w.units.griev[u * 4 + 3] = clampf(w.units.griev[u * 4 + 3] + Tuning.GRIEV_RISE * drive_strength(w, u, 3), 0.0, 1.0)
		w.units.bond[u] = clampf(w.units.bond[u] - Tuning.BOND_GRIEV_DECAY * grievance(w, u), 0.0, 1.0)

	for t in range(w.towns.size()):
		var owner: int = w.town_owner[t]
		if owner < 0:
			continue
		if w.town_state[t] == 0:
			w.town_griev[t] = maxf(0.0, w.town_griev[t] - Tuning.TOWN_GRIEV_CALM)
		var lord: int = w.town_lord[t]
		if lord >= 0 and lord < w.units.n and w.units.alive[lord] == 1:
			for k in range(5):
				w.town_vals[t * 5 + k] = move_toward(w.town_vals[t * 5 + k], w.units.vals[lord * 5 + k], Tuning.TOWN_LORD_PULL)
		var kvals := kingdom_vals(w, owner)
		for k in range(5):
			w.town_vals[t * 5 + k] = move_toward(w.town_vals[t * 5 + k], kvals[k], Tuning.TOWN_REALM_PULL)


## Distance between unit `u`'s values and its kingdom's, offset by bond and raised by grievance (may be negative).
static func unit_disaffection(w: World, u: int) -> float:
	return distance(unit_vals(w, u), kingdom_vals(w, w.units.faction[u])) - Tuning.BOND_WEIGHT * w.units.bond[u] + Tuning.GRIEV_WEIGHT * grievance(w, u)


## Distance between town `t`'s values and its owner kingdom's, raised by grievance; 0.0 if unowned.
static func town_disaffection(w: World, t: int) -> float:
	if w.town_owner[t] < 0:
		return 0.0
	return distance(town_vals(w, t), kingdom_vals(w, w.town_owner[t])) + Tuning.GRIEV_WEIGHT * w.town_griev[t]


## Applies grievance delta for town-level event `kind` to town `t`.
static func on_town_event(w: World, kind: String, t: int, amount: float = 1.0) -> void:
	match kind:
		"raid":
			w.town_griev[t] = clampf(w.town_griev[t] + Tuning.TOWN_GRIEV_RAID, 0.0, 1.0)
		"raze":
			w.town_griev[t] = clampf(w.town_griev[t] + Tuning.TOWN_GRIEV_RAZE, 0.0, 1.0)
		"levy":
			w.town_griev[t] = clampf(w.town_griev[t] + Tuning.TOWN_GRIEV_LEVY * amount, 0.0, 1.0)
		"tax":
			w.town_griev[t] = clampf(w.town_griev[t] + Tuning.TOWN_GRIEV_TAX, 0.0, 1.0)


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
