class_name SaveGame extends RefCounted
## World persistence. docs/ARCHITECTURE.md §14.3.
##
## File layout: header Dictionary, then one Dictionary per group via
## store_var, in order: map, units, stacks, towns, meta, logs. Live battles
## are not persisted: stacks caught mid-BATTLE are written as IDLE (copies,
## the live World is never mutated by save).

static func save(w: World, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()

	f.store_var({
		"version": Tuning.SAVE_VERSION,
		"seed_state": w.rng.state,
		"time": w.time,
		"faction_count": w.faction_count,
		"next_battle_id": w.next_battle_id,
		"cols": w.map.cols,
		"rows": w.map.rows,
		"borders_version": w.borders_version,
	})

	f.store_var({
		"kind": w.map.kind,
		"owner": w.map.owner,
	})

	f.store_var({
		"n": w.units.n,
		"cap": w.units.cap,
		"faction": w.units.faction,
		"rank": w.units.rank,
		"xp": w.units.xp,
		"kills": w.units.kills,
		"weapon": w.units.weapon,
		"stack": w.units.stack,
		"hp_frac": w.units.hp_frac,
		"alive": w.units.alive,
		"is_captain": w.units.is_captain,
		"drill": w.units.drill,
		"ctrait": w.units.ctrait,
		"c_fights": w.units.c_fights,
		"c_retreats": w.units.c_retreats,
		"c_razes": w.units.c_razes,
		"c_settles": w.units.c_settles,
		"dynasty": w.units.dynasty,
		"names": w.units.names,
		"hero": w.units.hero,
		"career_start": w.units.career_start,
		"ambition": w.units.ambition,
		"mentor": w.units.mentor,
		"fate": w.units.fate,
		"leader": w.units.leader,
		"pledge_t": w.units.pledge_t,
		"looks": w.units.looks,
	})

	# Live battles are not persisted: a stack caught in BATTLE is written as
	# IDLE with a fresh retreat immunity and no battle id. These are copies —
	# `w.stacks` itself is never touched.
	var stack_state := w.stacks.state.duplicate()
	var stack_battle_id := w.stacks.battle_id.duplicate()
	var stack_immunity := w.stacks.immunity.duplicate()
	for i in range(w.stacks.n):
		if stack_state[i] == Stacks.State.BATTLE:
			stack_state[i] = Stacks.State.IDLE
			stack_battle_id[i] = -1
			stack_immunity[i] = Tuning.RETREAT_IMMUNITY

	f.store_var({
		"n": w.stacks.n,
		"cap": w.stacks.cap,
		"x": w.stacks.x,
		"y": w.stacks.y,
		"prev_x": w.stacks.prev_x,
		"prev_y": w.stacks.prev_y,
		"faction": w.stacks.faction,
		"count": w.stacks.count,
		"state": stack_state,
		"goal": w.stacks.goal,
		"battle_id": stack_battle_id,
		"captain_unit": w.stacks.captain_unit,
		"goal_tx": w.stacks.goal_tx,
		"goal_ty": w.stacks.goal_ty,
		"ai_timer": w.stacks.ai_timer,
		"immunity": stack_immunity,
		"idle_timer": w.stacks.idle_timer,
		"path": w.stacks.path,
		"path_i": w.stacks.path_i,
		"names": w.stacks.names,
		"alive": w.stacks.alive,
		"gold": w.stacks.gold,
		"rally_target": w.stacks.rally_target,
		"rally_cd": w.stacks.rally_cd,
	})

	f.store_var({
		"towns": w.towns,
		"town_owner": w.town_owner,
		"town_state": w.town_state,
		"town_pop": w.town_pop,
		"town_recruit": w.town_recruit,
		"town_timer": w.town_timer,
		"town_gold": w.town_gold,
		"town_lord": w.town_lord,
	})

	f.store_var({
		"ktraits": w.ktraits,
		"relations": w.relations,
		"faction_alive": w.faction_alive,
		"faction_color": w.faction_color,
		"faction_names": w.faction_names,
		"plinko_rows": w.plinko_rows,
		"plinko_bias": w.plinko_bias,
		"plinko_order": w.plinko_order,
		"split_cooldown": w.split_cooldown,
	})

	var plinko_log_trimmed: Array = w.plinko_log.slice(maxi(0, w.plinko_log.size() - 10), w.plinko_log.size())
	f.store_var({
		"events_log": w.events_log,
		"plinko_log": plinko_log_trimmed,
		"scars": w.scars,
		"history": w.history,
	})

	f.close()
	return OK


static func load(path: String) -> World:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null

	var header: Dictionary = f.get_var()
	if int(header.get("version", -1)) != Tuning.SAVE_VERSION:
		push_error("SaveGame.load: version mismatch (file=%s, expected=%s)" % [header.get("version", -1), Tuning.SAVE_VERSION])
		f.close()
		return null

	var map_dict: Dictionary = f.get_var()
	var units_dict: Dictionary = f.get_var()
	var stacks_dict: Dictionary = f.get_var()
	var towns_dict: Dictionary = f.get_var()
	var meta_dict: Dictionary = f.get_var()
	var logs_dict: Dictionary = f.get_var()
	f.close()

	var w := World.new()
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = 0
	w.rng.state = header["seed_state"]
	w.time = header["time"]
	w.faction_count = header["faction_count"]
	w.next_battle_id = header["next_battle_id"]
	w.borders_version = header["borders_version"]

	# WorldMap.rng is only ever drawn from during WorldGen.generate (M3); a
	# loaded map never regenerates, so its seed is irrelevant here.
	w.map = WorldMap.new(header["cols"], header["rows"], 0)
	w.map.kind = map_dict["kind"]
	w.map.owner = map_dict["owner"]

	w.units = Units.new(int(units_dict["cap"]))
	w.units.n = units_dict["n"]
	w.units.faction = units_dict["faction"]
	w.units.rank = units_dict["rank"]
	w.units.xp = units_dict["xp"]
	w.units.kills = units_dict["kills"]
	w.units.weapon = units_dict["weapon"]
	w.units.stack = units_dict["stack"]
	w.units.hp_frac = units_dict["hp_frac"]
	w.units.alive = units_dict["alive"]
	w.units.is_captain = units_dict["is_captain"]
	w.units.drill = units_dict["drill"]
	w.units.ctrait = units_dict["ctrait"]
	w.units.c_fights = units_dict["c_fights"]
	w.units.c_retreats = units_dict["c_retreats"]
	w.units.c_razes = units_dict["c_razes"]
	w.units.c_settles = units_dict["c_settles"]
	w.units.dynasty = units_dict["dynasty"]
	w.units.names = units_dict["names"]
	w.units.hero = units_dict["hero"]
	w.units.career_start = units_dict["career_start"]
	w.units.ambition = units_dict["ambition"]
	w.units.mentor = units_dict["mentor"]
	w.units.fate = units_dict["fate"]
	# §19 fields; older saves lack them and keep Units.new defaults.
	if units_dict.has("leader"):
		w.units.leader = units_dict["leader"]
		w.units.pledge_t = units_dict["pledge_t"]
	if units_dict.has("looks"):
		w.units.looks = units_dict["looks"]

	w.stacks = Stacks.new(int(stacks_dict["cap"]))
	w.stacks.n = stacks_dict["n"]
	w.stacks.x = stacks_dict["x"]
	w.stacks.y = stacks_dict["y"]
	w.stacks.prev_x = stacks_dict["prev_x"]
	w.stacks.prev_y = stacks_dict["prev_y"]
	w.stacks.faction = stacks_dict["faction"]
	w.stacks.count = stacks_dict["count"]
	w.stacks.state = stacks_dict["state"]
	w.stacks.goal = stacks_dict["goal"]
	w.stacks.battle_id = stacks_dict["battle_id"]
	w.stacks.captain_unit = stacks_dict["captain_unit"]
	w.stacks.goal_tx = stacks_dict["goal_tx"]
	w.stacks.goal_ty = stacks_dict["goal_ty"]
	w.stacks.ai_timer = stacks_dict["ai_timer"]
	w.stacks.immunity = stacks_dict["immunity"]
	w.stacks.idle_timer = stacks_dict["idle_timer"]
	w.stacks.path = stacks_dict["path"]
	w.stacks.path_i = stacks_dict["path_i"]
	w.stacks.names = stacks_dict["names"]
	w.stacks.alive = stacks_dict["alive"]
	w.stacks.gold = stacks_dict["gold"]
	if stacks_dict.has("rally_target"):
		w.stacks.rally_target = stacks_dict["rally_target"]
		w.stacks.rally_cd = stacks_dict["rally_cd"]

	w.towns = towns_dict["towns"]
	w.town_owner = towns_dict["town_owner"]
	w.town_state = towns_dict["town_state"]
	w.town_pop = towns_dict["town_pop"]
	w.town_recruit = towns_dict["town_recruit"]
	w.town_timer = towns_dict["town_timer"]
	w.town_gold = towns_dict["town_gold"]
	w.town_lord = towns_dict["town_lord"]

	w.ktraits = meta_dict["ktraits"]
	w.relations = meta_dict["relations"]
	w.faction_alive = meta_dict["faction_alive"]
	w.faction_color = meta_dict["faction_color"]
	w.faction_names = meta_dict["faction_names"]
	w.plinko_rows = meta_dict["plinko_rows"]
	w.plinko_bias = meta_dict["plinko_bias"]
	w.plinko_order = meta_dict["plinko_order"]
	w.split_cooldown = meta_dict["split_cooldown"]

	w.events_log = logs_dict["events_log"]
	w.plinko_log = logs_dict["plinko_log"]
	w.scars = logs_dict["scars"]
	w.history = logs_dict["history"]

	# Live battles are never persisted (see save()): the loaded world starts
	# with none in flight.
	w.battles = []
	w.reinforce = {}

	w.border_adj = PackedByteArray()
	w.border_adj.resize(Tuning.MAX_FACTIONS_WORLD * Tuning.MAX_FACTIONS_WORLD)
	w.border_adj_version = -1

	w.pathing = Pathing.new(w.map)

	w.sync_town_arrays()
	w.recompute_borders()

	return w
