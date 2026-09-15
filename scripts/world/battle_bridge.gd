class_name BattleBridge extends RefCounted
## Overworld <-> arena bridge. Source: docs/ARCHITECTURE.md §11.5 and
## .warboss-horde/slices/m3-arena-from-tile.md.

# start/join/finish: see slice m3-bridge


## d = from - tile_center; dominant axis picks 0/1 (x) or 2/3 (y); a tie on
## |dx| == |dy| goes to the x axis. If the preferred edge is taken, try the
## opposite edge on the same axis, then the two edges of the other axis, in
## that order. -1 when all four are taken.
static func edge_for(tile_center: Vector2, from: Vector2, taken: PackedInt32Array) -> int:
	var d := from - tile_center
	var preferred: int
	var opposite: int
	var other: Array
	if absf(d.x) >= absf(d.y):
		preferred = 0 if d.x < 0 else 1
		opposite = 1 - preferred
		other = [2, 3]
	else:
		preferred = 2 if d.y < 0 else 3
		opposite = 5 - preferred
		other = [0, 1]
	for e in [preferred, opposite, other[0], other[1]]:
		if not taken.has(e):
			return e
	return -1


static func spawn_rect(edge: int) -> Rect2:
	match edge:
		0:
			return Rect2(40, 100, 360, 700)
		1:
			return Rect2(1200, 100, 360, 700)
		2:
			return Rect2(300, 40, 1000, 240)
		3:
			return Rect2(300, 620, 1000, 240)
		_:
			return Rect2()


## Alive units of `stack`, i.e. Units.alive[u] == 1 and Units.stack[u] == stack.
static func _live_units(units: Units, stack: int) -> Array:
	var out: Array = []
	for u in range(units.n):
		if units.stack[u] == stack and units.alive[u] == 1:
			out.append(u)
	return out


## RETREAT_TILES steps along -HOME_DIR[edge] from `tile`, clamped into map
## bounds, then nudged to the nearest passable tile by ring search (Chebyshev
## radius 1..4). UNDECIDED: no test in this slice exercises the no-own-town
## fallback path, so the "else stay" reading (keep the clamped-but-maybe-
## impassable tile when the ring search finds nothing within radius 4) is
## unverified against acceptance criteria.
static func _retreat_fallback_tile(world: World, tile: Vector2i, edge: int) -> Vector2i:
	var dir: Vector2 = -Tuning.HOME_DIR[edge]
	var tx := clampi(tile.x + roundi(dir.x * Tuning.RETREAT_TILES), 0, world.map.cols - 1)
	var ty := clampi(tile.y + roundi(dir.y * Tuning.RETREAT_TILES), 0, world.map.rows - 1)
	var start_tile := Vector2i(tx, ty)
	if world.map.passable(start_tile.x, start_tile.y):
		return start_tile
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := start_tile.x + dx
				var cy := start_tile.y + dy
				if world.map.in_bounds(cx, cy) and world.map.passable(cx, cy):
					return Vector2i(cx, cy)
	return start_tile


static func start(world: World, stack_a: int, stack_b: int) -> BattleInstance:
	var tile := world.stack_tile(stack_a)
	var inst := BattleInstance.new(world.next_battle_id, tile)
	world.next_battle_id += 1

	inst.faction_map = PackedInt32Array([-1, -1, -1, -1])
	inst.edge_of_faction = PackedInt32Array([-1, -1, -1, -1])

	var count_a := _live_units(world.units, stack_a).size()
	var count_b := _live_units(world.units, stack_b).size()
	var cap := mini(Tuning.MAX_BATTLE_MARBLES, count_a + count_b + Tuning.BATTLE_EXTRA_CAP)
	inst.state = BattleState.new(cap, world.rng.randi())

	inst.terrain = TerrainGrid.new()
	inst.terrain.setup(inst.state.arena, Tuning.TERRAIN_CELL)

	join(inst, world, stack_a)
	join(inst, world, stack_b)

	var edges_used := PackedInt32Array()
	for e in range(4):
		if inst.edge_of_faction[e] != -1:
			edges_used.append(e)

	var idx := world.map.idx(tile.x, tile.y)
	TerrainGen.from_tile(inst.terrain, world.map.kind[idx], edges_used, inst.state.rng)

	inst.sim = BattleSim.new(inst.state)
	inst.sim.set_terrain(inst.terrain)
	inst.started = world.time
	world.battles.append(inst)

	return inst


static func join(inst: BattleInstance, world: World, stack: int) -> bool:
	var stacks := world.stacks
	var units := world.units
	var state := inst.state
	var wf: int = stacks.faction[stack]

	var e := -1
	for ei in range(4):
		if inst.faction_map[ei] == wf:
			e = ei
			break

	# Allies (§13.5): a joining stack whose world faction isn't yet mapped
	# reuses an already-mapped local index if it's allied with the faction
	# holding that index, instead of taking a new edge.
	if e == -1:
		for ei_a in range(4):
			if inst.faction_map[ei_a] != -1 and world.allied(inst.faction_map[ei_a], wf):
				e = ei_a
				break

	var is_new_faction := e == -1
	if is_new_faction:
		var taken := PackedInt32Array()
		for ei2 in range(4):
			if inst.faction_map[ei2] != -1:
				taken.append(ei2)
		var tile_center := world.map.center_of(inst.tile.x, inst.tile.y)
		var from := Vector2(stacks.prev_x[stack], stacks.prev_y[stack])
		e = edge_for(tile_center, from, taken)
		if e == -1:
			return false

	var live := _live_units(units, stack)
	if state.n + live.size() > state.cap:
		return false

	if is_new_faction:
		inst.faction_map[e] = wf
		inst.edge_of_faction[e] = e

	if not inst.side_factions[e].has(wf):
		inst.side_factions[e].append(wf)

	var prev_captain := state.faction_captain[e]

	for u in live:
		var rect := spawn_rect(e)
		var x: float = rect.position.x + state.rng.randf() * rect.size.x
		var y: float = rect.position.y + state.rng.randf() * rect.size.y
		var rank: int = units.rank[u]
		var weapon: int = units.weapon[u]
		var captain_flag: bool = units.is_captain[u] == 1
		var i := state.spawn(x, y, e, rank, weapon, captain_flag)
		state.hp[i] = state.hp_max[i] * units.hp_frac[u]
		state.xp[i] = units.xp[u]
		state.kills[i] = units.kills[u]
		state.spin_cap[i] += Tuning.DRILL_SPIN_BONUS * units.drill[u]
		inst.unit_of.append(u)   # marble index i -> world unit id u (i == unit_of.size() before append)

	if prev_captain >= 0:
		state.faction_captain[e] = prev_captain

	stacks.state[stack] = Stacks.State.BATTLE
	stacks.battle_id[stack] = inst.id
	inst.stack_ids.append(stack)

	if inst.sim != null:
		inst.sim.refresh_radius(state)

	return true


## Local faction index `e` holding world faction `wf`: any local index whose
## side_factions contains `wf` (primary or allied joiners alike, §13.5).
static func _side_of(inst: BattleInstance, wf: int) -> int:
	for e in range(inst.side_factions.size()):
		var arr: PackedInt32Array = inst.side_factions[e]
		if arr.has(wf):
			return e
	return -1


## Nearest RUIN tile to (x, y) by world distance; (-1, -1) when none exists.
static func _nearest_ruin_tile(world: World, x: float, y: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for ty in range(world.map.rows):
		for tx in range(world.map.cols):
			if world.map.kind[world.map.idx(tx, ty)] != WorldMap.Kind.RUIN:
				continue
			var d: float = Vector2(x, y).distance_to(world.map.center_of(tx, ty))
			if d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best


## Safe read of faction name by index, guarded against out-of-bounds.
static func _fname(world: World, f: int) -> String:
	if f < world.faction_names.size():
		return world.faction_names[f]
	else:
		return "Faction %d" % f


## Rebirth / mercenaries (docs/ARCHITECTURE.md §13.4 last bullet). Runs after
## the winner/loser pass in `finish`. A losing stack whose only remaining
## attached members are this battle's fled survivors (stacks.count ==
## fled_survivors.size()), with no other alive stack of the same world
## faction and no towns owned by that faction, is "the last stack destroyed":
## its survivors are re-homed instead of marching home with an empty shell.
## UNDECIDED: only runs when the battle had a winner (winner_world != -1,
## needed for the mercenary branch's "join the winner stack"); §13.4 doesn't
## say what a stalemate should do here, so that case is left as ordinary
## (attached, un-retired) survivors.
static func _process_rebirth(world: World, inst: BattleInstance, winner_world: int, winner_stack: int, fled_survivors: Dictionary) -> void:
	if winner_world == -1:
		return
	var stacks := world.stacks
	var units := world.units

	for stack in inst.stack_ids:
		if stacks.faction[stack] == winner_world:
			continue
		var fled_list: Array = fled_survivors.get(stack, [])
		if fled_list.is_empty():
			continue
		if stacks.count[stack] != fled_list.size():
			continue

		var wf: int = stacks.faction[stack]

		var other_alive := false
		for k in range(stacks.n):
			if k != stack and stacks.alive[k] == 1 and stacks.faction[k] == wf:
				other_alive = true
				break
		if other_alive:
			continue

		var has_town := false
		for ti in range(world.towns.size()):
			if world.town_owner[ti] == wf:
				has_town = true
				break
		if has_town:
			continue

		var founder := -1
		var founder_rank := -1
		for u in fled_list:
			if units.rank[u] > founder_rank:
				founder_rank = units.rank[u]
				founder = u

		var ruin := Vector2i(-1, -1)
		if founder_rank >= Tuning.LEGEND_RANK:
			ruin = _nearest_ruin_tile(world, stacks.x[stack], stacks.y[stack])

		var did_found := false
		if founder_rank >= Tuning.LEGEND_RANK and ruin != Vector2i(-1, -1) and stacks.has_room():
			var g := Kingdoms.new_faction(world, wf)
			if g != -1:
				did_found = true
				var center := world.map.center_of(ruin.x, ruin.y)
				var new_stack := stacks.add(g, center.x, center.y, NameGen.stack_name(world.rng))
				for u2 in fled_list:
					units.faction[u2] = g
					units.stack[u2] = new_stack
				if units.is_captain[founder] == 0:
					Lineage.make_captain(world, founder, NameGen.captain_name_base(world.rng))
				stacks.captain_unit[new_stack] = founder
				var founder_name: String = units.names.get(founder, "Unit %d" % founder)
				world.log_event("%s founds %s" % [founder_name, _fname(world, g)])

		if not did_found:
			for u2 in fled_list:
				units.faction[u2] = winner_world
				units.stack[u2] = winner_stack
			world.log_event("%s's survivors join %s as mercenaries" % [stacks.names[stack], _fname(world, winner_world)])

		stacks.recount(units)
		if stacks.count[stack] == 0:
			stacks.alive[stack] = 0


static func finish(inst: BattleInstance, world: World) -> Dictionary:
	var state := inst.state
	var units := world.units
	var stacks := world.stacks

	# fiat (m5-lineage): remember each stack's captain unit id before the
	# copy-back, so Lineage.on_battle_finished can detect a captain's death
	# after Units.kill has already run below.
	var captain_before := PackedInt32Array()
	for stack_id in inst.stack_ids:
		captain_before.append(stacks.captain_unit[stack_id])
	inst.captain_before = captain_before

	var dead_count := 0
	var stack_survivors := {}     # stack id -> surviving-marble count (this battle)
	var fled_survivors := {}      # stack id -> Array[unit id] that fled this battle
	var kills_gain := {}          # home stack id -> int kill delta this battle (M9, §17.3 Economy.loot)
	for i in range(state.n):
		var u: int = inst.unit_of[i]
		var home_stack: int = units.stack[u]
		kills_gain[home_stack] = int(kills_gain.get(home_stack, 0)) + (state.kills[i] - units.kills[u])
		units.xp[u] = state.xp[i]
		units.kills[u] = state.kills[i]
		units.rank[u] = state.rank[i]
		var truly_dead: bool = state.state[i] == BattleState.State.DEAD and state.fled[i] == 0
		if truly_dead:
			dead_count += 1
			units.kill(u)
		else:
			units.hp_frac[u] = state.hp[i] / state.hp_max[i]
			stack_survivors[home_stack] = stack_survivors.get(home_stack, 0) + 1
			if state.fled[i] == 1:
				if not fled_survivors.has(home_stack):
					fled_survivors[home_stack] = []
				fled_survivors[home_stack].append(u)

	stacks.recount(units)

	# Hero promotion (§17.4/§17.8, M9): marbles ascending, alive unit ->
	# check_promote; slew_leader = true when it's in this battle's slayers.
	for i in range(state.n):
		var pu: int = inst.unit_of[i]
		if units.alive[pu] == 1:
			Heroes.check_promote(world, pu, inst.slayers.has(pu))

	var local_winner: int = inst.sim.winner(state)
	var winner_side: int = local_winner if local_winner >= 0 else -1

	# world faction of the winning-side stack with the most survivors (§13.5).
	var winner_world := -1
	var winner_stack := -1
	if winner_side != -1:
		var best_surv := -1
		for stack in inst.stack_ids:
			var wf_c: int = stacks.faction[stack]
			if _side_of(inst, wf_c) != winner_side:
				continue
			var surv: int = stack_survivors.get(stack, 0)
			if surv > best_surv:
				best_surv = surv
				winner_stack = stack
		if winner_stack != -1:
			winner_world = stacks.faction[winner_stack]

	# UNDECIDED: the fiat event format "%s beat %s at (%d,%d)" doesn't say
	# which stack's name fills each %s when a side has several stacks (or
	# what to log for a stalemate, local_winner == -2) — using the first
	# winning stack's name vs the first losing stack's name, and skipping
	# the event entirely when there is no winner.
	var winner_name := ""
	var loser_name := ""

	if winner_world != -1:
		Kingdoms.on_event(world, "win", winner_world)
	var retreated_factions := {}
	var winner_stacks: Array = []
	var loser_stacks: Array = []

	for stack in inst.stack_ids:
		var wf: int = stacks.faction[stack]
		var e := _side_of(inst, wf)

		var is_winner: bool = winner_side != -1 and e == winner_side
		if is_winner:
			winner_stacks.append(stack)
			if winner_name == "":
				winner_name = stacks.names[stack]
			stacks.state[stack] = Stacks.State.IDLE
			stacks.idle_timer[stack] = Tuning.IDLE_AFTER_BATTLE
		else:
			loser_stacks.append(stack)
			if loser_name == "":
				loser_name = stacks.names[stack]
			if not retreated_factions.has(wf):
				retreated_factions[wf] = true
				Kingdoms.on_event(world, "retreat", wf)
			stacks.state[stack] = Stacks.State.RETREATING
			stacks.immunity[stack] = Tuning.RETREAT_IMMUNITY
			var town_id := world.nearest_town(stacks.x[stack], stacks.y[stack], wf, 0)
			var goal_tile: Vector2i
			if town_id != -1:
				goal_tile = Vector2i(int(world.towns[town_id].x), int(world.towns[town_id].y))
			else:
				goal_tile = _retreat_fallback_tile(world, inst.tile, e)
			stacks.goal_tx[stack] = goal_tile.x
			stacks.goal_ty[stack] = goal_tile.y
			stacks.path[stack] = world.pathing.find(world.stack_tile(stack), goal_tile)
			stacks.path_i[stack] = 0

		if stacks.count[stack] == 0:
			stacks.alive[stack] = 0

	if winner_side != -1:
		Economy.loot(world, winner_stacks, loser_stacks, kills_gain)

	world.scars.append([inst.tile.x, inst.tile.y, dead_count, world.time])

	if winner_world != -1:
		world.events_log.append("%s beat %s at (%d,%d)" % [winner_name, loser_name, inst.tile.x, inst.tile.y])
		if world.events_log.size() > 200:
			world.events_log.pop_front()

	# Runs after the "beat" line above so a rebirth/mercenary line (if any)
	# is the newest events_log entry.
	_process_rebirth(world, inst, winner_world, winner_stack, fled_survivors)

	world.battles.erase(inst)

	var result := {
		"winner": winner_world,
		"winner_side": winner_side,
		"tile": inst.tile,
		"dead": dead_count,
		"duration": world.time - inst.started
	}

	Lineage.on_battle_finished(world, inst, result)
	Kingdoms.on_battle_finished(world, inst, result)

	return result
