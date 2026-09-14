class_name Rally extends RefCounted
## Stacks merging by choice (docs/ARCHITECTURE.md §19). A weaker stack may
## pick the RALLY goal, march to a stronger army of its own faction and ask to
## join; the host's captain accepts or refuses. On a merge the joiner's men
## become a contingent (Units.leader = their captain) and that captain serves
## on as a hero, pledged for RALLY_PLEDGE_TIME before they may break away with
## their contingent. Leaderless stacks always want to join and are always
## accepted, and their men simply join the host's own ranks.


static func has_leader(w: World, s: int) -> bool:
	var c: int = w.stacks.captain_unit[s]
	return c >= 0 and w.units.alive[c] == 1


static func renown(w: World, u: int) -> float:
	return float(w.units.kills[u]) + 10.0 * w.units.rank[u]


## Enemy (non-allied) men within RALLY_THREAT_TILES of `s`, relative to its
## own size and RALLY_THREAT_RATIO, clamped to 0..1.
static func threat(w: World, s: int) -> float:
	var st := w.stacks
	var tile := w.stack_tile(s)
	var f: int = st.faction[s]
	var enemy := 0
	for j in range(st.n):
		if st.alive[j] == 0 or j == s:
			continue
		var g: int = st.faction[j]
		if g == f or w.allied(f, g):
			continue
		var tj := w.stack_tile(j)
		if maxi(absi(tj.x - tile.x), absi(tj.y - tile.y)) > Tuning.RALLY_THREAT_TILES:
			continue
		enemy += st.count[j]
	return clampf(float(enemy) / maxf(1.0, float(st.count[s])) / Tuning.RALLY_THREAT_RATIO, 0.0, 1.0)


## How much stack `s` wants to serve under `host`, 0..1. `threat_s` is
## threat(w, s), passed in so a host search computes it once. Leaderless -> 1.
## Pulls toward joining: few men, nearby threat, a host captain of greater
## renown, kingdom cohesion. Pulls against: the captain's ambition, kingdom
## aggression, gold in hand.
static func desire(w: World, s: int, host: int, threat_s: float) -> float:
	if not has_leader(w, s):
		return 1.0
	var st := w.stacks
	var f: int = st.faction[s]
	var cap_s: int = st.captain_unit[s]
	var d := 0.0
	d += Tuning.RALLY_W_WEAK * (1.0 - clampf(float(st.count[s]) / Tuning.RALLY_WEAK_COUNT, 0.0, 1.0))
	d += Tuning.RALLY_W_THREAT * threat_s
	if has_leader(w, host):
		var gap := (renown(w, st.captain_unit[host]) - renown(w, cap_s)) / Tuning.RALLY_RENOWN_SCALE
		d += Tuning.RALLY_W_RENOWN * clampf(gap, -1.0, 1.0)
	d += Tuning.RALLY_W_COHESION * (w.ktrait(f, 4) - 0.5)
	d -= Tuning.RALLY_W_AMBITION * w.units.ambition[cap_s]
	d -= Tuning.RALLY_W_AGGR * (w.ktrait(f, 0) - 0.5)
	d -= Tuning.RALLY_W_GOLD * clampf(st.gold[s] / Tuning.RALLY_GOLD_SCALE, 0.0, 1.0)
	return clampf(d, 0.0, 1.0)


## `host` could take `s` in right now: alive, same faction, led by a live
## captain, IDLE or MOVING and not itself rallying, room under STACK_CAP, and
## strictly bigger (ties: lower id hosts) so two stacks never chase each other.
static func can_host(w: World, host: int, s: int) -> bool:
	var st := w.stacks
	if host == s or host < 0 or st.alive[host] == 0 or st.faction[host] != st.faction[s]:
		return false
	if not has_leader(w, host):
		return false
	if st.state[host] != Stacks.State.IDLE and st.state[host] != Stacks.State.MOVING:
		return false
	if st.goal[host] == Stacks.Goal.RALLY:
		return false
	if st.count[host] + st.count[s] > Tuning.STACK_CAP:
		return false
	return st.count[host] > st.count[s] or (st.count[host] == st.count[s] and host < s)


## Best host within RALLY_RANGE tiles (Chebyshev) for `s`: highest desire,
## ties -> nearest, then lowest id. -1 when none or `s` is on cooldown.
static func best_host(w: World, s: int) -> int:
	var st := w.stacks
	if st.rally_cd[s] > 0.0:
		return -1
	var tile := w.stack_tile(s)
	var threat_s := -1.0
	var best := -1
	var best_d := -1.0
	var best_dist := 0
	for h in range(st.n):
		if not can_host(w, h, s):
			continue
		var th := w.stack_tile(h)
		var dist: int = maxi(absi(th.x - tile.x), absi(th.y - tile.y))
		if dist > Tuning.RALLY_RANGE:
			continue
		if threat_s < 0.0:
			threat_s = threat(w, s)
		var d := desire(w, s, h, threat_s)
		if best == -1 or d > best_d or (d == best_d and dist < best_dist):
			best = h
			best_d = d
			best_dist = dist
	return best


## True when `s` stands on or next to (Chebyshev <= 1) an intact town of its
## own faction: a captainless stack there is that town's garrison and holds.
static func guards_own_town(w: World, s: int) -> bool:
	var tile := w.stack_tile(s)
	var f: int = w.stacks.faction[s]
	for ti in range(w.towns.size()):
		if w.town_owner[ti] != f or w.town_state[ti] != TownSim.STATE_INTACT:
			continue
		if maxi(absi(int(w.towns[ti].x) - tile.x), absi(int(w.towns[ti].y) - tile.y)) <= 1:
			return true
	return false


## pick_goal weight for RALLY (index Stacks.Goal.RALLY). 0 without a host or
## below RALLY_MIN_DESIRE; a leaderless garrison of its own town -> 0; other
## leaderless stacks with a host -> RALLY_LEADERLESS_WEIGHT.
static func goal_weight(w: World, s: int) -> float:
	var leaderless := not has_leader(w, s)
	if leaderless and guards_own_town(w, s):
		return 0.0
	var host := best_host(w, s)
	if host == -1:
		return 0.0
	if leaderless:
		return Tuning.RALLY_LEADERLESS_WEIGHT
	var d := desire(w, s, host, threat(w, s))
	if d < Tuning.RALLY_MIN_DESIRE:
		return 0.0
	return Tuning.RALLY_GOAL_WEIGHT * d


## The host captain's decision; draws one rng value only for a led joiner.
## Base RALLY_ACCEPT_BASE; TYRANT +RALLY_ACCEPT_TRAIT (absorbs rivals);
## CAUTIOUS + trait x free room; BUILDER + trait x the joiner's gold;
## CHARGER / no trait +0; -RALLY_ACCEPT_RIVAL when the joiner's captain has
## more renown than the host's.
static func host_accepts(w: World, host: int, s: int) -> bool:
	if not can_host(w, host, s):
		return false
	if not has_leader(w, s):
		return true
	var st := w.stacks
	var cap_h: int = st.captain_unit[host]
	var p := Tuning.RALLY_ACCEPT_BASE
	match w.units.ctrait[cap_h]:
		Lineage.Trait.TYRANT:
			p += Tuning.RALLY_ACCEPT_TRAIT
		Lineage.Trait.CAUTIOUS:
			p += Tuning.RALLY_ACCEPT_TRAIT * (1.0 - float(st.count[host]) / Tuning.STACK_CAP)
		Lineage.Trait.BUILDER:
			p += Tuning.RALLY_ACCEPT_TRAIT * clampf(st.gold[s] / Tuning.RALLY_GOLD_SCALE, 0.0, 1.0)
	if renown(w, st.captain_unit[s]) > renown(w, cap_h):
		p -= Tuning.RALLY_ACCEPT_RIVAL
	return w.rng.randf() < clampf(p, 0.0, 1.0)


## Folds `s` into `host`: every alive unit moves; a led joiner's men get
## leader = its captain (units already in a contingent keep theirs), the
## captain becomes a pledged hero; a leaderless joiner's men get leader -1.
## Gold moves, `s` dies.
static func merge(w: World, host: int, s: int) -> void:
	var st := w.stacks
	var un := w.units
	var cap_s := -1
	if has_leader(w, s):
		cap_s = st.captain_unit[s]
	var moved := 0
	for u in range(un.n):
		if un.alive[u] == 0 or un.stack[u] != s:
			continue
		un.stack[u] = host
		moved += 1
		if u == cap_s:
			continue
		if cap_s == -1:
			un.leader[u] = -1
		elif un.leader[u] == -1:
			un.leader[u] = cap_s

	if cap_s >= 0:
		un.is_captain[cap_s] = 0
		un.hero[cap_s] = 1
		un.leader[cap_s] = -1
		un.pledge_t[cap_s] = w.time + Tuning.RALLY_PLEDGE_TIME
		w.log_event("%s brings %s (%d) under %s" % [
			un.names.get(cap_s, "Unit %d" % cap_s), st.names[s], moved, st.names[host]])
		w.bump("rallies")
	else:
		w.log_event("%s (%d) folds into %s" % [st.names[s], moved, st.names[host]])
		w.bump("folds")

	st.gold[host] += st.gold[s]
	st.gold[s] = 0.0
	st.captain_unit[s] = -1
	st.rally_target[s] = -1
	st.goal[s] = Stacks.Goal.IDLE_HEAL
	st.state[s] = Stacks.State.IDLE
	st.path[s] = PackedVector2Array()
	st.path_i[s] = 0
	w.reinforce.erase(s)
	st.recount(un)
	st.alive[s] = 0


## A RALLY march ended (path done, or already next to the host when the goal
## was set). Within 1 tile of a host that can still take it, the host
## decides: accept -> merge; refuse -> RALLY_COOLDOWN. A host that moved on
## just leaves `s` IDLE for the AI to choose again.
static func arrive(w: World, s: int) -> void:
	var st := w.stacks
	var host: int = st.rally_target[s]
	st.rally_target[s] = -1
	st.goal[s] = Stacks.Goal.IDLE_HEAL
	if host < 0 or not can_host(w, host, s):
		return
	var th := w.stack_tile(host)
	var ts := w.stack_tile(s)
	if maxi(absi(th.x - ts.x), absi(th.y - ts.y)) > 1:
		return
	if host_accepts(w, host, s):
		merge(w, host, s)
	else:
		st.rally_cd[s] = Tuning.RALLY_COOLDOWN
		w.log_event("%s turns away %s" % [st.names[host], st.names[s]])
		w.bump("refusals")
