class_name Kingdoms extends RefCounted
## Kingdom traits, goal weighting, relations, splits, deaths.
## Source: docs/ARCHITECTURE.md §13.4.


static func on_event(w: World, kind: String, faction: int) -> void:
	match kind:
		"win":
			w.add_ktrait(faction, 0, Tuning.KT_WIN_AGGR)
		"raze":
			w.add_ktrait(faction, 2, Tuning.KT_RAZE_GREED)
			w.add_ktrait(faction, 3, Tuning.KT_RAZE_PIETY)
		"settle":
			w.add_ktrait(faction, 4, Tuning.KT_SETTLE_COH)
		"retreat":
			w.add_ktrait(faction, 0, Tuning.KT_RETREAT_AGGR)
			w.add_ktrait(faction, 4, Tuning.KT_RETREAT_COH)
		"pilgrim":
			w.add_ktrait(faction, 3, Tuning.KT_PILGRIM_PIETY)
		_:
			pass  # fiat: unknown kind -> no-op


static func goal_weights(w: World, f: int) -> PackedFloat32Array:
	var aggr := w.ktrait(f, 0)
	var greed := w.ktrait(f, 2)
	var piety := w.ktrait(f, 3)
	var coh := w.ktrait(f, 4)

	var out := PackedFloat32Array()
	out.resize(7)
	out[Stacks.Goal.HUNT_WEAK] = 3.0 * (0.5 + aggr)
	out[Stacks.Goal.EXPAND] = 3.0 * (1.5 - aggr)
	out[Stacks.Goal.RAID] = 2.0 * (0.5 + greed)
	out[Stacks.Goal.DEFEND] = 1.0 * (0.5 + coh)
	out[Stacks.Goal.IDLE_HEAL] = 1.0
	out[Stacks.Goal.PILGRIMAGE] = Tuning.GOAL_PILGRIMAGE_BASE + piety

	# fiat: AVENGE term uses max(0, -min_relation) over alive factions g != f;
	# no alive other faction -> 0 extra.
	var min_rel := INF
	var found_other := false
	for g in range(w.faction_count):
		if g == f:
			continue
		if w.faction_alive[g] == 0:
			continue
		found_other = true
		var r := w.relation(f, g)
		if r < min_rel:
			min_rel = r
	var avenge_extra := 0.0
	if found_other:
		avenge_extra = maxf(0.0, -min_rel)
	out[Stacks.Goal.AVENGE] = Tuning.GOAL_AVENGE_BASE + avenge_extra

	return out


static func recruit_weapon(w: World, f: int, rng: RandomNumberGenerator) -> int:
	var aggr := w.ktrait(f, 0)
	var coh := w.ktrait(f, 4)
	var weights := [1.0 + aggr, 1.0, 1.0 + coh, 1.0 + aggr, 1.0 + coh]
	var total := 0.0
	for wgt in weights:
		total += wgt
	var draw := rng.randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if draw < acc:
			return i
	return weights.size() - 1


static func plinko_bias(w: World, f: int) -> float:
	return (w.ktrait(f, 2) - 0.5) * Tuning.PLINKO_BIAS_GREED


## Slot recycling: returns true if some `f < faction_count` with
## `faction_alive == 0`, or `faction_count < MAX_FACTIONS_WORLD`.
static func has_free_slot(w: World) -> bool:
	for f in range(w.faction_count):
		if w.faction_alive[f] == 0:
			return true
	return w.faction_count < Tuning.MAX_FACTIONS_WORLD


## Copy of `order` with the favoured slot moved to index 4 (CHARGER ->
## RECRUIT, CAUTIOUS -> DRILL, TYRANT -> RAZE, BUILDER -> SETTLE); unknown
## `tr` -> unchanged. Param named `tr`: `trait` is reserved in GDScript 4.
static func trait_favor(order: PackedInt32Array, tr: int) -> PackedInt32Array:
	var out := order.duplicate()
	var favored_slot := -1
	match tr:
		Lineage.Trait.CHARGER:
			favored_slot = Plinko.Slot.RECRUIT
		Lineage.Trait.CAUTIOUS:
			favored_slot = Plinko.Slot.DRILL
		Lineage.Trait.TYRANT:
			favored_slot = Plinko.Slot.RAZE
		Lineage.Trait.BUILDER:
			favored_slot = Plinko.Slot.SETTLE
		_:
			return out

	var idx := -1
	for i in range(out.size()):
		if out[i] == favored_slot:
			idx = i
			break
	if idx == -1 or idx == 4:
		return out

	var tmp := out[4]
	out[4] = out[idx]
	out[idx] = tmp
	return out


## Every world tick, cheap: relation decay, diplomacy drift between bordering
## factions, plinko_bias refresh, split_cooldown countdown.
static func tick(w: World, dt: float) -> void:
	for i in range(w.relations.size()):
		w.relations[i] = move_toward(w.relations[i], 0.0, Tuning.REL_DECAY * dt)

	# fiat: adjacency cache rebuilt only when borders_version changes.
	if w.borders_version != w.border_adj_version:
		_rebuild_border_adj(w)

	for a in range(w.faction_count):
		if w.faction_alive[a] == 0:
			continue
		if w.ktrait(a, 1) <= 0.6:
			continue
		for b in range(a + 1, w.faction_count):
			if w.faction_alive[b] == 0:
				continue
			if w.border_adj[a * Tuning.MAX_FACTIONS_WORLD + b] == 0:
				continue
			if w.ktrait(b, 1) <= 0.6:
				continue
			w.add_relation(a, b, Tuning.REL_DIPLOMACY_RATE * dt)

	for pf in range(w.plinko_bias.size()):
		w.plinko_bias[pf] = plinko_bias(w, pf)

	# fiat: World.split_cooldown decremented here.
	for sf in range(w.split_cooldown.size()):
		if w.split_cooldown[sf] > 0.0:
			w.split_cooldown[sf] = maxf(0.0, w.split_cooldown[sf] - dt)


## Rebuilds World.border_adj: byte (a, b) set when some tile owned by a has a
## 4-neighbour tile owned by b.
static func _rebuild_border_adj(w: World) -> void:
	w.border_adj.fill(0)
	var m := w.map
	for ty in range(m.rows):
		for tx in range(m.cols):
			var owner_a: int = m.owner[m.idx(tx, ty)]
			if owner_a < 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = tx + d.x
				var ny: int = ty + d.y
				if not m.in_bounds(nx, ny):
					continue
				var owner_b: int = m.owner[m.idx(nx, ny)]
				if owner_b < 0 or owner_b == owner_a:
					continue
				w.border_adj[owner_a * Tuning.MAX_FACTIONS_WORLD + owner_b] = 1
	w.border_adj_version = w.borders_version


## Relation fallout from a finished battle. Not covered by a numbered test in
## this slice (§13.4 lists it among the module's signatures but the slice's
## acceptance list stops at check_death); implemented best-effort.
static func on_battle_finished(w: World, inst: BattleInstance, result: Dictionary) -> void:
	var winner: int = result.get("winner", -1)
	var seen := {}
	for lf in range(inst.faction_map.size()):
		var wf: int = inst.faction_map[lf]
		if seen.has(wf):
			continue
		seen[wf] = true
		if winner != -1 and wf != winner:
			w.add_relation(wf, winner, Tuning.REL_BATTLE_LOST)

	# UNDECIDED: BattleInstance.captain_killers (§13.4) is not yet a declared
	# field on BattleInstance (battle_bridge/battle_instance.gd are out of
	# scope for this slice, owned by a concurrent doer); read defensively via
	# Object.get() so this is a no-op until that field exists.
	var killers = inst.get("captain_killers")
	if killers != null:
		for pair in killers:
			var victim_f: int = pair[0]
			var killer_f: int = pair[1]
			w.add_relation(victim_f, killer_f, Tuning.REL_CAPTAIN_KILLED)


## Slot recycling §17.6: faction slot, colour, name, ktraits (copied from
## `from_f` with cohesion reset to KTRAIT_INIT), relations reset, split_cooldown
## reset, plinko profile. Used by check_split and BattleBridge's rebirth
## mechanic (docs/ARCHITECTURE.md §13.4 last bullet). Returns the new faction
## id, or -1 if no free slot and MAX_FACTIONS_WORLD reached.
static func new_faction(w: World, from_f: int) -> int:
	# Find lowest dead slot or append.
	var g := -1
	for f in range(w.faction_count):
		if w.faction_alive[f] == 0:
			g = f
			break
	if g == -1:
		if w.faction_count >= Tuning.MAX_FACTIONS_WORLD:
			return -1
		g = w.faction_count
		w.faction_count += 1

	w.faction_color[g] = g % Tuning.FACTION_COLORS.size()
	w.faction_alive[g] = 1

	# name drawn first (affects plinko rng draw order)
	var name := NameGen.kingdom_name(w.rng)
	if w.faction_names.size() <= g:
		var old_size := w.faction_names.size()
		w.faction_names.resize(g + 1)
		for i in range(old_size, g + 1):
			w.faction_names[i] = ""
	w.faction_names[g] = name

	# copy ktraits from from_f, reset cohesion
	for k in range(5):
		w.ktraits[g * 5 + k] = w.ktraits[from_f * 5 + k]
	w.ktraits[g * 5 + 4] = Tuning.KTRAIT_INIT

	# reset relations to 0
	var M := Tuning.MAX_FACTIONS_WORLD
	for b in range(M):
		w.relations[g * M + b] = 0.0
		w.relations[b * M + g] = 0.0

	# reset split cooldown
	w.split_cooldown[g] = 0.0

	# order = identity shuffled with w.rng
	var order := PackedInt32Array()
	order.resize(Tuning.PLINKO_SLOTS)
	for k2 in range(Tuning.PLINKO_SLOTS):
		order[k2] = k2
	for k3 in range(order.size() - 1, 0, -1):
		var j := w.rng.randi_range(0, k3)
		var tmp := order[k3]
		order[k3] = order[j]
		order[j] = tmp

	if w.plinko_rows.size() <= g:
		w.plinko_rows.resize(g + 1)
	w.plinko_rows[g] = 7
	if w.plinko_bias.size() <= g:
		w.plinko_bias.resize(g + 1)
	w.plinko_bias[g] = 0.0
	if w.plinko_order.size() <= g:
		w.plinko_order.resize(g + 1)
	w.plinko_order[g] = order

	return g


## Splits an overgrown, low-cohesion faction's largest stack into a new
## faction. At most once per SPLIT-cooldown window per faction.
static func check_split(w: World) -> void:
	var initial_count := w.faction_count
	for f in range(initial_count):
		if w.faction_alive[f] == 0:
			continue
		if w.split_cooldown[f] > 0.0:
			continue
		if not has_free_slot(w):
			continue
		if w.ktrait(f, 4) >= Tuning.SPLIT_COHESION:
			continue

		var alive_units := 0
		for u in range(w.units.n):
			if w.units.alive[u] == 1 and w.units.faction[u] == f:
				alive_units += 1
		if alive_units <= Tuning.SPLIT_UNITS:
			continue

		var biggest := -1
		var biggest_count := -1
		for i in range(w.stacks.n):
			if w.stacks.alive[i] == 1 and w.stacks.faction[i] == f and w.stacks.count[i] > biggest_count:
				biggest_count = w.stacks.count[i]
				biggest = i
		if biggest == -1:
			continue

		var g := new_faction(w, f)

		w.stacks.faction[biggest] = g
		for u2 in range(w.units.n):
			if w.units.stack[u2] == biggest:
				w.units.faction[u2] = g

		var stile := w.map.tile_of(w.stacks.x[biggest], w.stacks.y[biggest])
		var flipped_town := -1
		var best_d := 1 << 30
		for ti in range(w.towns.size()):
			if w.town_owner[ti] != f:
				continue
			var ttile := Vector2i(int(w.towns[ti].x), int(w.towns[ti].y))
			var d: int = maxi(absi(stile.x - ttile.x), absi(stile.y - ttile.y))
			if d <= 6 and d < best_d:
				best_d = d
				flipped_town = ti
		if flipped_town != -1:
			w.town_owner[flipped_town] = g

		w.add_relation(f, g, -0.6)

		# UNDECIDED: §13.4 says "both stacks get immunity = RETREAT_IMMUNITY"
		# without naming a second stack when the old faction has more than
		# one remaining stack; literal reading applied here: the split stack
		# plus every other alive stack still on the old faction.
		w.stacks.immunity[biggest] = Tuning.RETREAT_IMMUNITY
		for i2 in range(w.stacks.n):
			if i2 != biggest and w.stacks.alive[i2] == 1 and w.stacks.faction[i2] == f:
				w.stacks.immunity[i2] = Tuning.RETREAT_IMMUNITY

		w.split_cooldown[f] = 30.0

		var old_name := String(w.faction_names[f]) if f < w.faction_names.size() else "Faction %d" % f
		w.log_event("Kingdom %s splits from %s" % [w.faction_names[g], old_name])

		w.recompute_borders()


## An alive faction with zero towns and zero alive stacks falls; logs once
## (flagged by the faction_alive flip, so a dead faction is never re-logged).
static func check_death(w: World) -> void:
	for f in range(w.faction_count):
		if w.faction_alive[f] == 0:
			continue

		var has_town := false
		for ti in range(w.towns.size()):
			if w.town_owner[ti] == f:
				has_town = true
				break
		if has_town:
			continue

		var has_stack := false
		for i in range(w.stacks.n):
			if w.stacks.alive[i] == 1 and w.stacks.faction[i] == f:
				has_stack = true
				break
		if has_stack:
			continue

		w.faction_alive[f] = 0
		var name := String(w.faction_names[f]) if f < w.faction_names.size() else "Faction %d" % f
		w.log_event("Kingdom %s fell" % name)
