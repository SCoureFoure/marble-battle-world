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
		inst.unit_of.append(i)

	if prev_captain >= 0:
		state.faction_captain[e] = prev_captain

	stacks.state[stack] = Stacks.State.BATTLE
	stacks.battle_id[stack] = inst.id
	inst.stack_ids.append(stack)

	if inst.sim != null:
		inst.sim.refresh_radius(state)

	return true


static func finish(inst: BattleInstance, world: World) -> Dictionary:
	var state := inst.state
	var units := world.units
	var stacks := world.stacks

	var dead_count := 0
	for i in range(state.n):
		var u: int = inst.unit_of[i]
		units.xp[u] = state.xp[i]
		units.kills[u] = state.kills[i]
		units.rank[u] = state.rank[i]
		var truly_dead: bool = state.state[i] == BattleState.State.DEAD and state.fled[i] == 0
		if truly_dead:
			dead_count += 1
			units.kill(u)
		else:
			units.hp_frac[u] = state.hp[i] / state.hp_max[i]

	stacks.recount(units)

	var local_winner: int = inst.sim.winner(state)
	var winner_world: int = -1
	if local_winner >= 0:
		winner_world = inst.faction_map[local_winner]

	# UNDECIDED: the fiat event format "%s beat %s at (%d,%d)" doesn't say
	# which stack's name fills each %s when a side has several stacks (or
	# what to log for a stalemate, local_winner == -2) — using the first
	# winning stack's name vs the first losing stack's name, and skipping
	# the event entirely when there is no winner.
	var winner_name := ""
	var loser_name := ""

	for stack in inst.stack_ids:
		var wf: int = stacks.faction[stack]
		var e := -1
		for ei in range(4):
			if inst.faction_map[ei] == wf:
				e = ei
				break

		var is_winner: bool = local_winner >= 0 and e == local_winner
		if is_winner:
			if winner_name == "":
				winner_name = stacks.names[stack]
			stacks.state[stack] = Stacks.State.IDLE
			stacks.idle_timer[stack] = Tuning.IDLE_AFTER_BATTLE
		else:
			if loser_name == "":
				loser_name = stacks.names[stack]
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

	world.scars.append([inst.tile.x, inst.tile.y, dead_count, world.time])

	if winner_world != -1:
		world.events_log.append("%s beat %s at (%d,%d)" % [winner_name, loser_name, inst.tile.x, inst.tile.y])
		if world.events_log.size() > 200:
			world.events_log.pop_front()

	world.battles.erase(inst)

	return {
		"winner": winner_world,
		"tile": inst.tile,
		"dead": dead_count,
		"duration": world.time - inst.started
	}
