class_name Lineage extends RefCounted
## Captain lineage: Roman numerals, captain creation, legend naming,
## succession and behaviour-counter traits. docs/ARCHITECTURE.md §13.3.

enum Trait { CHARGER = 0, CAUTIOUS = 1, TYRANT = 2, BUILDER = 3 }


static func numeral(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var num := n
	var result := ""
	for i in range(vals.size()):
		var v: int = vals[i]
		var s: String = syms[i]
		while num >= v:
			result += s
			num -= v
	return result


## Captain creation everywhere goes through this: sets dynasty [name_base, 1]
## and names[u] = name_base + " I". career_start = w.time (M9).
static func make_captain(w: World, u: int, name_base: String) -> void:
	w.units.is_captain[u] = 1
	w.units.dynasty[u] = [name_base, 1]
	w.units.names[u] = name_base + " I"
	w.units.career_start[u] = w.time
	Looks.ensure(w, u)


## Called by the bridge copy-back when rank becomes LEGEND_RANK.
static func check_legend(w: World, u: int) -> void:
	if w.units.rank[u] != Tuning.LEGEND_RANK:
		return
	w.units.names[u] = NameGen.legend_name(w.rng, w.units.kills[u])


## After any behaviour-counter change: the largest counter >= TRAIT_THRESHOLD
## sets ctrait (fights -> CHARGER, retreats -> CAUTIOUS, razes -> TYRANT,
## settles -> BUILDER). Never downgrades: only changes when a different
## counter strictly exceeds the current ctrait's own counter value (a tie
## leaves ctrait unchanged).
static func update_trait(w: World, u: int) -> void:
	var counters := {
		Trait.CHARGER: w.units.c_fights[u],
		Trait.CAUTIOUS: w.units.c_retreats[u],
		Trait.TYRANT: w.units.c_razes[u],
		Trait.BUILDER: w.units.c_settles[u]
	}
	var current: int = w.units.ctrait[u]
	var current_count := 0
	if current != -1:
		current_count = counters[current]

	var best_trait := -1
	var best_count := -1
	for trait_id in counters:
		var c: int = counters[trait_id]
		if c < Tuning.TRAIT_THRESHOLD:
			continue
		if c > best_count:
			best_count = c
			best_trait = trait_id

	if best_trait != -1 and best_count > current_count:
		w.units.ctrait[u] = best_trait


## Behaviour counters, captains only. Called by PlinkoOutcomes SETTLE/RAZE.
static func note_settle(w: World, captain_unit: int) -> void:
	if captain_unit == -1:
		return
	w.units.c_settles[captain_unit] += 1
	update_trait(w, captain_unit)


static func note_raze(w: World, captain_unit: int) -> void:
	if captain_unit == -1:
		return
	w.units.c_razes[captain_unit] += 1
	update_trait(w, captain_unit)


## Called by BattleBridge.finish at the end, before returning, for every
## stack that took part in `inst`. `inst.captain_before` (parallel to
## `inst.stack_ids`) holds each stack's captain unit id as it was before the
## copy-back, so a captain's death (Units.kill already ran) can be detected
## here.
static func on_battle_finished(w: World, inst: BattleInstance, result: Dictionary) -> void:
	for idx in range(inst.stack_ids.size()):
		var stack: int = inst.stack_ids[idx]
		var captain_before: int = inst.captain_before[idx]
		var captain_alive: bool = captain_before != -1 and w.units.alive[captain_before] == 1

		if captain_alive:
			w.units.c_fights[captain_before] += 1
			update_trait(w, captain_before)
			if w.stacks.state[stack] == Stacks.State.RETREATING:
				w.units.c_retreats[captain_before] += 1
				update_trait(w, captain_before)
		elif captain_before != -1:
			_succeed(w, stack, captain_before)


## Heir = alive unit of `stack`, not the (already dead/retired) captain, with
## the most kills; ties -> lowest id. No candidate -> captain_unit = -1 (the
## stack dies anyway once its count reaches 0). `verb` customises the log
## line ("fell" on combat death; Settling passes "retires" / "settles").
static func succeed(w: World, stack: int, old_captain: int, verb: String = "fell") -> void:
	var best := -1
	var best_kills := -1
	for u in range(w.units.n):
		if w.units.stack[u] == stack and w.units.alive[u] == 1 and w.units.is_captain[u] == 0:
			if w.units.kills[u] > best_kills:
				best_kills = w.units.kills[u]
				best = u

	if best == -1:
		w.stacks.captain_unit[stack] = -1
		return

	var dyn: Array = w.units.dynasty.get(old_captain, ["", 0])
	var name: String = dyn[0]
	var old_numeral: int = int(dyn[1])
	var new_numeral := old_numeral + 1

	w.units.is_captain[best] = 1
	w.units.rank[best] = maxi(1, w.units.rank[old_captain] - Tuning.HEIR_RANK_DROP)
	w.units.xp[best] = w.units.xp[old_captain] / 2
	w.units.ctrait[best] = w.units.ctrait[old_captain]
	w.units.c_fights[best] = 0
	w.units.c_retreats[best] = 0
	w.units.c_razes[best] = 0
	w.units.c_settles[best] = 0
	w.units.career_start[best] = w.time
	w.units.dynasty[best] = [name, new_numeral]
	w.units.names[best] = "%s %s" % [name, numeral(new_numeral)]
	w.stacks.captain_unit[stack] = best
	Looks.ensure(w, best)

	w.log_event("%s %s %s; %s rises" % [name, numeral(old_numeral), verb, w.units.names[best]])


## One-line wrapper kept for the combat-death call site: verb "fell".
static func _succeed(w: World, stack: int, dead_captain: int) -> void:
	succeed(w, stack, dead_captain, "fell")
