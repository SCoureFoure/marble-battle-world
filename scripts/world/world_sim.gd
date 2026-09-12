class_name WorldSim extends RefCounted
## Overworld tick: AI, movement, collisions, reinforcements, battles.
## Source: docs/ARCHITECTURE.md §11.6.

static func step_world(w: World, dt: float) -> void:
	w.time += dt
	var st := w.stacks

	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.ai_timer[i] > 0.0:
			st.ai_timer[i] -= dt
		if st.immunity[i] > 0.0:
			st.immunity[i] -= dt
		if st.idle_timer[i] > 0.0:
			st.idle_timer[i] -= dt

	TownSim.step(w, dt)
	Kingdoms.tick(w, dt)

	w.meta_timer += dt
	while w.meta_timer >= 1.0:
		w.meta_timer -= 1.0
		Kingdoms.check_split(w)
		Kingdoms.check_death(w)

	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.state[i] == Stacks.State.IDLE and st.idle_timer[i] <= 0.0 and st.ai_timer[i] <= 0.0:
			pick_goal(w, i)

	move_stacks(w, dt)
	check_collisions(w)
	reinforce(w)

	for i in range(st.n):
		if st.alive[i] == 1 and st.count[i] == 0 and st.state[i] != Stacks.State.BATTLE:
			st.alive[i] = 0


static func step(w: World, dt: float) -> void:
	step_world(w, dt)
	step_battles(w)


static func pick_goal(w: World, i: int) -> void:
	var st := w.stacks
	var fi := st.faction[i]
	var weights: PackedFloat32Array = Kingdoms.goal_weights(w, fi)
	var total := 0.0
	for wgt in weights:
		total += wgt
	var draw: float = w.rng.randf() * total
	var acc := 0.0
	var goal := 0
	for g in range(weights.size()):
		acc += weights[g]
		if draw < acc:
			goal = g
			break

	if not set_goal(w, i, goal):
		# UNDECIDED: whether a failed set_goal should still write st.goal[i] = goal
		# (the goal actually drawn) before falling back — the fiat text only says
		# "falls back to IDLE_HEAL for this tick", so IDLE_HEAL is written here.
		st.goal[i] = Stacks.Goal.IDLE_HEAL
		st.state[i] = Stacks.State.IDLE
	st.ai_timer[i] = Tuning.AI_TICK


# Applies one named goal to stack `i`. Returns false (no change besides the
# attempt) when the goal has no reachable target.
static func set_goal(w: World, i: int, goal: int) -> bool:
	var st := w.stacks
	var fi := st.faction[i]
	var target_tile := Vector2i(-1, -1)

	match goal:
		Stacks.Goal.HUNT_WEAK:
			var j := w.nearest_enemy_stack(i, true)
			if j == -1:
				j = w.nearest_enemy_stack(i, false)
			if j == -1:
				return false
			target_tile = w.stack_tile(j)
		Stacks.Goal.EXPAND:
			var town_e := w.nearest_town(st.x[i], st.y[i], fi, 2)
			if town_e == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_e].x), int(w.towns[town_e].y))
		Stacks.Goal.RAID:
			var town_r := w.nearest_town(st.x[i], st.y[i], fi, 1)
			if town_r == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_r].x), int(w.towns[town_r].y))
		Stacks.Goal.DEFEND:
			var town_d := w.nearest_town(st.x[i], st.y[i], fi, 0)
			if town_d == -1:
				return false
			target_tile = Vector2i(int(w.towns[town_d].x), int(w.towns[town_d].y))
		Stacks.Goal.IDLE_HEAL:
			return false
		Stacks.Goal.PILGRIMAGE:
			var holy := _nearest_holy_tile(w, st.x[i], st.y[i])
			if holy == Vector2i(-1, -1):
				return false
			target_tile = holy
		Stacks.Goal.AVENGE:
			var hated := _most_hated_faction(w, fi)
			if hated == -1:
				return false
			var enemy_stack := _nearest_stack_of_faction(w, i, hated)
			if enemy_stack == -1:
				return false
			target_tile = w.stack_tile(enemy_stack)
		_:
			return false

	var from_tile := w.stack_tile(i)
	var p := w.pathing.find(from_tile, target_tile)
	if p.size() == 0:
		return false

	st.goal[i] = goal
	st.goal_tx[i] = target_tile.x
	st.goal_ty[i] = target_tile.y
	st.path[i] = p
	st.path_i[i] = 0
	st.state[i] = Stacks.State.MOVING
	return true


## PILGRIMAGE target: nearest RUIN or GRAVEYARD tile by world distance.
static func _nearest_holy_tile(w: World, x: float, y: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for ty in range(w.map.rows):
		for tx in range(w.map.cols):
			var k: int = w.map.kind[w.map.idx(tx, ty)]
			if k != WorldMap.Kind.RUIN and k != WorldMap.Kind.GRAVEYARD:
				continue
			var d: float = Vector2(x, y).distance_to(w.map.center_of(tx, ty))
			if d < best_d:
				best_d = d
				best = Vector2i(tx, ty)
	return best


## AVENGE target faction: alive faction g != f with the lowest relation(f, g);
## none with relation < 0 -> -1 (§13.4: "nearest stack of the most-hated
## faction ... none -> falls back").
static func _most_hated_faction(w: World, f: int) -> int:
	var best := -1
	var best_rel := INF
	for g in range(Tuning.MAX_FACTIONS_WORLD):
		if g == f or w.faction_alive[g] == 0:
			continue
		var r := w.relation(f, g)
		if r < best_rel:
			best_rel = r
			best = g
	if best == -1 or best_rel >= 0.0:
		return -1
	return best


## Nearest alive stack of world faction `target_f` to stack `i` (world
## distance).
static func _nearest_stack_of_faction(w: World, i: int, target_f: int) -> int:
	var st := w.stacks
	var best := -1
	var best_d := INF
	for j in range(st.n):
		if st.alive[j] == 0 or st.faction[j] != target_f:
			continue
		var d := Vector2(st.x[i], st.y[i]).distance_to(Vector2(st.x[j], st.y[j]))
		if d < best_d:
			best_d = d
			best = j
	return best


static func move_stacks(w: World, dt: float) -> void:
	var st := w.stacks
	var map := w.map
	for i in range(st.n):
		if st.alive[i] == 0:
			continue
		if st.state[i] != Stacks.State.MOVING and st.state[i] != Stacks.State.RETREATING:
			continue

		st.prev_x[i] = st.x[i]
		st.prev_y[i] = st.y[i]

		var p: PackedVector2Array = st.path[i]
		if st.path_i[i] >= p.size():
			if st.goal[i] == Stacks.Goal.PILGRIMAGE:
				Kingdoms.on_event(w, "pilgrim", st.faction[i])
			st.state[i] = Stacks.State.IDLE
			continue

		var target: Vector2 = p[st.path_i[i]]
		var tile := map.tile_of(st.x[i], st.y[i])
		var cost: float = map.cost_at(tile.x, tile.y)
		if cost <= 0.0:
			cost = 1.0
		var speed: float = Tuning.STACK_SPEED / cost
		if st.state[i] == Stacks.State.RETREATING:
			speed *= Tuning.RETREAT_SPEED_MULT

		var to_target := target - Vector2(st.x[i], st.y[i])
		var dist := to_target.length()
		if dist < 2.0:
			st.x[i] = target.x
			st.y[i] = target.y
			st.path_i[i] += 1
			if st.path_i[i] >= p.size():
				if st.goal[i] == Stacks.Goal.PILGRIMAGE:
					Kingdoms.on_event(w, "pilgrim", st.faction[i])
				st.state[i] = Stacks.State.IDLE
		else:
			var dir := to_target / dist
			st.x[i] += dir.x * speed * dt
			st.y[i] += dir.y * speed * dt


static func check_collisions(w: World) -> void:
	var st := w.stacks

	var hash := SpatialHash.new()
	hash.setup(Rect2(0.0, 0.0, w.map.cols * Tuning.TILE, w.map.rows * Tuning.TILE), 64.0)

	var hstate := PackedInt32Array()
	hstate.resize(st.n)
	for i in range(st.n):
		hstate[i] = 0 if (st.alive[i] == 1 and st.state[i] != Stacks.State.BATTLE) else 2
	hash.build(st.x, st.y, hstate, st.n)

	var started_tiles := {}
	var min_dist: float = 2.0 * Tuning.STACK_RADIUS

	for i in range(st.n):
		if hstate[i] != 0:
			continue
		var k := hash.gather(st.x[i], st.y[i])
		for idx in range(k):
			var j: int = hash.scratch[idx]
			if j <= i:
				continue
			if hstate[j] != 0:
				continue
			if st.faction[i] == st.faction[j]:
				continue
			if st.immunity[i] > 0.0 or st.immunity[j] > 0.0:
				continue

			var dx: float = st.x[i] - st.x[j]
			var dy: float = st.y[i] - st.y[j]
			if dx * dx + dy * dy >= min_dist * min_dist:
				continue

			var tile_i := w.stack_tile(i)
			var tile_j := w.stack_tile(j)
			var existing: BattleInstance = _live_battle_at(w, tile_i)
			if existing == null:
				existing = _live_battle_at(w, tile_j)

			if existing != null:
				if st.state[i] != Stacks.State.BATTLE:
					BattleBridge.join(existing, w, i)
				if st.state[j] != Stacks.State.BATTLE:
					BattleBridge.join(existing, w, j)
			else:
				var key := "%d_%d" % [tile_i.x, tile_i.y]
				if started_tiles.has(key):
					continue
				var inst := BattleBridge.start(w, i, j)
				if inst != null:
					if not w.battles.has(inst):
						w.battles.append(inst)
					started_tiles[key] = true


static func reinforce(w: World) -> void:
	var st := w.stacks

	for battle in w.battles:
		var inst: BattleInstance = battle
		var involved := {}
		for lf in range(inst.faction_map.size()):
			involved[inst.faction_map[lf]] = true

		for i in range(st.n):
			if st.alive[i] == 0:
				continue
			if not involved.has(st.faction[i]):
				continue
			if st.state[i] != Stacks.State.IDLE and st.state[i] != Stacks.State.MOVING:
				continue

			var tile := w.stack_tile(i)
			var cheb: int = max(abs(tile.x - inst.tile.x), abs(tile.y - inst.tile.y))
			if cheb > Tuning.REINFORCE_TILES:
				continue
			if w.reinforce.get(i, -1) == inst.id:
				continue

			var p := w.pathing.find(tile, inst.tile)
			if p.size() == 0:
				continue

			st.goal_tx[i] = inst.tile.x
			st.goal_ty[i] = inst.tile.y
			st.path[i] = p
			st.path_i[i] = 0
			st.state[i] = Stacks.State.MOVING
			w.reinforce[i] = inst.id

	# Arrival: a MOVING stack whose tile equals a live battle tile joins it
	# (or, on refusal, sits out IDLE with retreat immunity).
	for i in range(st.n):
		if st.alive[i] == 0 or st.state[i] != Stacks.State.MOVING:
			continue
		var tile2 := w.stack_tile(i)
		for battle2 in w.battles:
			var inst2: BattleInstance = battle2
			if inst2.tile != tile2:
				continue
			var joined := BattleBridge.join(inst2, w, i)
			if not joined:
				st.state[i] = Stacks.State.IDLE
				st.immunity[i] = Tuning.RETREAT_IMMUNITY
			break


static func step_battles(w: World) -> void:
	var remaining: Array = []
	for battle in w.battles:
		var inst: BattleInstance = battle
		if inst.id == w.watched_battle:
			inst.sim.step(inst.state, Tuning.DT)
		else:
			BattleLod.step(inst, Tuning.DT)

		# Captain kills (§13.4: BattleInstance.captain_killers, relations).
		for ev in inst.state.events:
			if ev[0] != BattleState.Event.CAPTAIN_DEAD:
				continue
			var actor: int = ev[1]
			var target: int = ev[2]
			if actor == -1:
				continue
			var victim_f: int = inst.faction_map[inst.state.faction_id[target]]
			var killer_f: int = inst.faction_map[inst.state.faction_id[actor]]
			inst.captain_killers.append([victim_f, killer_f])

		var win := inst.sim.winner(inst.state)
		if win != -1:
			BattleBridge.finish(inst, w)
			_run_plinko(w, inst)
		else:
			remaining.append(inst)
	w.battles = remaining


## After a finish: one plinko drop per winner-side stack with a living
## captain (docs/ARCHITECTURE.md §12.3/§12.4/§13.5 fork tags). Winners are
## identified by state == IDLE (set by BattleBridge.finish); each stack drops
## on its own faction's board, slot order favoured by its captain's ctrait.
static func _run_plinko(w: World, inst: BattleInstance) -> void:
	var st := w.stacks
	for stack in inst.stack_ids:
		if st.alive[stack] == 0 or st.state[stack] != Stacks.State.IDLE:
			continue
		var f: int = st.faction[stack]
		var captain: int = st.captain_unit[stack]
		if captain < 0 or w.units.alive[captain] != 1:
			continue

		var board := Plinko.build(w.plinko_rows[f], w.plinko_bias[f], w.rng)
		board.slot_order = Kingdoms.trait_favor(w.plinko_order[f], w.units.ctrait[captain])
		var d := board.drop(Tuning.PLINKO_W * 0.5, w.rng)

		var lines: Array = []
		for slot in d["slots"]:
			lines.append(PlinkoOutcomes.apply(w, stack, slot))

		w.plinko_log.append([stack, d["slots"], lines, d["path"], board.pegs, board.slot_order])
		if w.plinko_log.size() > 50:
			w.plinko_log.pop_front()


static func _live_battle_at(w: World, tile: Vector2i) -> BattleInstance:
	for battle in w.battles:
		var inst: BattleInstance = battle
		if inst.tile == tile:
			return inst
	return null
