class_name Economy extends RefCounted
## Gold accrual, recruit pricing, restocking, looting, raiding.
## Source: docs/ARCHITECTURE.md §17.3.


static func accrue(w: World, dt: float) -> void:
	w.sync_town_arrays()
	for t in range(w.towns.size()):
		if w.town_state[t] == 0:
			w.town_gold[t] = minf(Tuning.TOWN_GOLD_MAX, w.town_gold[t] + Tuning.TOWN_TAX_PER_POP * w.town_pop[t] * dt)


static func price(w: World, f: int, t: int) -> float:
	var owner := w.town_owner[t]
	if owner == f:
		return Tuning.RECRUIT_COST * Tuning.PRICE_MULT_OWN
	if owner == -1:
		return Tuning.RECRUIT_COST * Tuning.PRICE_MULT_NEUTRAL
	if w.allied(f, owner):
		return Tuning.RECRUIT_COST * Tuning.PRICE_MULT_ALLY
	return -1.0


static func _buy_floor() -> float:
	return Tuning.RECRUIT_COST * Tuning.PRICE_MULT_NEUTRAL * Tuning.RESTOCK_MIN_BUY


static func _tax_floor() -> float:
	return Tuning.RECRUIT_COST * Tuning.RESTOCK_MIN_BUY


## Alive units of stack s, ascending id (fiat, .warboss-horde/slices/m9-economy.md).
static func _alive_units(w: World, s: int) -> Array:
	var out: Array = []
	for u in range(w.units.n):
		if w.units.alive[u] == 1 and w.units.stack[u] == s:
			out.append(u)
	return out


static func wants_restock(w: World, s: int) -> bool:
	var f := w.stacks.faction[s]
	var count := w.stacks.count[s]
	var gold := w.stacks.gold[s]

	if count < Tuning.RESTOCK_BELOW * Tuning.STACK_CAP:
		var can_afford := gold >= _buy_floor()
		if not can_afford:
			for t in range(w.towns.size()):
				if w.town_owner[t] == f and w.town_state[t] == 0 and w.town_gold[t] >= _tax_floor():
					can_afford = true
					break
		if can_afford:
			return true

	var wounded := 0
	for u in _alive_units(w, s):
		if w.units.hp_frac[u] < 0.5:
			wounded += 1
	if wounded >= maxi(1, count / 4) and gold >= Tuning.HEAL_COST * wounded:
		return true

	return false


static func restock_target(w: World, s: int) -> int:
	var f := w.stacks.faction[s]
	var narrow := w.stacks.gold[s] < _buy_floor()
	var pos := Vector2(w.stacks.x[s], w.stacks.y[s])
	var best := -1
	var best_dist := INF

	for t in range(w.towns.size()):
		if w.town_state[t] != 0:
			continue
		var p := price(w, f, t)
		if p < 0:
			continue
		if w.town_pop[t] < 1.0:
			continue
		if narrow and not (w.town_owner[t] == f and w.town_gold[t] >= _tax_floor()):
			continue
		var c := w.map.center_of(int(w.towns[t].x), int(w.towns[t].y))
		var d := pos.distance_to(c)
		if d < best_dist:
			best_dist = d
			best = t

	return best


static func goal_bonus(w: World, s: int, weights: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in weights:
		out.append(v)

	if w.stacks.gold[s] < Tuning.POOR_GOLD:
		out[Stacks.Goal.RAID] += Tuning.POOR_RAID_BONUS
		out[Stacks.Goal.HUNT_WEAK] += Tuning.POOR_RAID_BONUS * 0.5

	out.append(Tuning.RESTOCK_WEIGHT if wants_restock(w, s) else 0.0)
	out.append(0.0)  # FOUND is never drawn (fiat)
	return out


static func restock(w: World, s: int, t: int) -> String:
	var f := w.stacks.faction[s]
	var p := price(w, f, t)
	if p < 0 or w.town_state[t] != 0:
		return ""

	# (1) collect accrued gold if this is the stack's own town.
	if w.town_owner[t] == f:
		if w.town_gold[t] > 0.0:
			Dissent.on_town_event(w, "tax", t)
		w.stacks.gold[s] += w.town_gold[t]
		w.town_gold[t] = 0.0

	# (2) heal wounded, ascending id, until gold runs out.
	var healed := 0
	for u in _alive_units(w, s):
		if w.units.hp_frac[u] < 1.0:
			if w.stacks.gold[s] >= Tuning.HEAL_COST:
				w.stacks.gold[s] -= Tuning.HEAL_COST
				w.units.hp_frac[u] = 1.0
				healed += 1
			else:
				break

	# (3) buy as many recruits as gold, town pop and stack cap allow.
	var n := mini(int(w.stacks.gold[s] / p), mini(int(w.town_pop[t]), Tuning.STACK_CAP - w.stacks.count[s]))
	var added := 0
	for _i in range(n):
		var uid := w.units.add(f, 0, Kingdoms.recruit_weapon(w, f, w.rng), false, s)
		if uid == -1:
			break
		added += 1
	w.stacks.count[s] += added
	w.stacks.gold[s] -= added * p
	w.town_pop[t] -= added
	if w.town_owner[t] == f and added > 0:
		Dissent.on_town_event(w, "levy", t, float(added))
	if w.town_owner[t] != f:
		w.town_gold[t] = minf(Tuning.TOWN_GOLD_MAX, w.town_gold[t] + added * p)

	if added + healed > 0:
		w.bump("restocks")

	return "%s restocks at town %d: +%d recruits, %d healed" % [w.stacks.names[s], t, added, healed]


static func loot(w: World, winners: Array, losers: Array, kills_by_stack: Dictionary) -> void:
	var alive_winners: Array = []
	for s in winners:
		if w.stacks.alive[s] == 1:
			alive_winners.append(s)
	if alive_winners.is_empty():
		return

	var pool := 0.0
	for s in losers:
		var take: float = w.stacks.gold[s] * Tuning.LOOT_FRAC
		pool += take
		w.stacks.gold[s] -= take

	var total := 0
	for s in alive_winners:
		total += w.stacks.count[s]

	for s in alive_winners:
		var share: float
		if total == 0:
			share = pool / alive_winners.size()
		else:
			share = pool * w.stacks.count[s] / total
		var bounty: float = Tuning.BOUNTY_PER_KILL * float(kills_by_stack.get(s, 0))
		w.stacks.gold[s] += share + bounty


static func raid_gold(w: World, s: int, t: int) -> float:
	var g := w.town_gold[t] * Tuning.RAID_GOLD_FRAC
	w.town_gold[t] -= g
	w.stacks.gold[s] += g
	return g
