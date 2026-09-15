extends SceneTree
## Late-game stall probe: how fast one faction takes over and why nothing stops it.
## Usage: godot --headless --path . --script res://tools/stall_probe.gd -- --seed=1 --seconds=6000
## Prints one PROBE line every 300 world seconds, then PROBE_DONE.

func _init() -> void:
	var seed := 1
	var seconds := 6000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = arg.substr(7).to_int()
		elif arg.begins_with("--seconds="):
			seconds = arg.substr(10).to_int()

	var w := World.create(seed)
	var prev_alive := PackedByteArray()
	prev_alive.resize(Tuning.MAX_FACTIONS_WORLD)
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		prev_alive[f] = w.faction_alive[f]
	var births := 0
	var max_battle_id := -1
	var battles_started := 0
	var t0 := Time.get_ticks_usec()

	for tick in range(seconds * 60):
		WorldSim.step(w, Tuning.DT)
		if (tick + 1) % 60 == 0:
			for f2 in range(Tuning.MAX_FACTIONS_WORLD):
				if prev_alive[f2] == 0 and w.faction_alive[f2] == 1:
					births += 1
				prev_alive[f2] = w.faction_alive[f2]
			for b in w.battles:
				var inst: BattleInstance = b
				if inst.id > max_battle_id:
					battles_started += 1
					max_battle_id = inst.id
		if (tick + 1) % 60 == 0 and _store_full(w.units.n, w.units.cap, w.units.reusable) and _store_full(w.stacks.n, w.stacks.cap, w.stacks.reusable):
			_line(w, births, battles_started, t0)
			print("PROBE_ABORT capacity units_n=%d stacks_n=%d (full, nothing reusable)" % [w.units.n, w.stacks.n])
			break
		if (tick + 1) % 18000 == 0:
			_line(w, births, battles_started, t0)

	print("PROBE_DONE")
	quit()


func _store_full(n: int, cap: int, reusable: PackedByteArray) -> bool:
	if n < cap:
		return false
	for i in range(cap):
		if reusable[i] == 1:
			return false
	return true


func _sum(a: PackedInt32Array) -> int:
	var total := 0
	for v in a:
		total += v
	return total


func _line(w: World, births: int, battles_started: int, t0: int) -> void:
	var towns_by := PackedInt32Array()
	towns_by.resize(Tuning.MAX_FACTIONS_WORLD)
	var owned := 0
	for i in range(w.towns.size()):
		var o: int = w.town_owner[i]
		if o >= 0:
			towns_by[o] += 1
			owned += 1
	var units_by := PackedInt32Array()
	units_by.resize(Tuning.MAX_FACTIONS_WORLD)
	var units_alive := 0
	for u in range(w.units.n):
		if w.units.alive[u] == 1:
			units_by[w.units.faction[u]] += 1
			units_alive += 1
	var top := 0
	var second_towns := 0
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		if towns_by[f] > towns_by[top]:
			top = f
	for f3 in range(Tuning.MAX_FACTIONS_WORLD):
		if f3 != top and towns_by[f3] > second_towns:
			second_towns = towns_by[f3]
	var alive := 0
	var real := 0
	for f4 in range(w.faction_count):
		if w.faction_alive[f4] == 1:
			alive += 1
			if towns_by[f4] > 0 or units_by[f4] >= 30:
				real += 1
	var stacks_alive := 0
	var at_cap := 0
	var top_stacks := 0
	for s in range(w.stacks.n):
		if w.stacks.alive[s] == 1:
			stacks_alive += 1
			if w.stacks.count[s] >= Tuning.STACK_CAP:
				at_cap += 1
			if w.stacks.faction[s] == top:
				top_stacks += 1
	var top_tension := Dissent.tension(w, top)
	var top_members := 0
	var top_bond_sum := 0.0
	var top_glory_sum := 0.0
	var top_wealth_sum := 0.0
	var top_faith_sum := 0.0
	var top_land_sum := 0.0
	var top_griev_sum := 0.0
	for u_m in range(w.units.n):
		if Dissent.member(w, u_m) and w.units.faction[u_m] == top:
			top_members += 1
			top_bond_sum += w.units.bond[u_m]
			top_glory_sum += w.units.griev[u_m * 4 + 0]
			top_wealth_sum += w.units.griev[u_m * 4 + 1]
			top_faith_sum += w.units.griev[u_m * 4 + 2]
			top_land_sum += w.units.griev[u_m * 4 + 3]
			top_griev_sum += Dissent.grievance(w, u_m)
	var top_bond := 0.0 if top_members == 0 else top_bond_sum / float(top_members)
	var top_glory := 0.0 if top_members == 0 else top_glory_sum / float(top_members)
	var top_wealth := 0.0 if top_members == 0 else top_wealth_sum / float(top_members)
	var top_faith := 0.0 if top_members == 0 else top_faith_sum / float(top_members)
	var top_land := 0.0 if top_members == 0 else top_land_sum / float(top_members)
	var top_griev := 0.0 if top_members == 0 else top_griev_sum / float(top_members)
	var top_town_dis_sum := 0.0
	var top_town_dis_count := 0
	for t_dis in range(w.towns.size()):
		if w.town_owner[t_dis] == top:
			top_town_dis_sum += Dissent.town_disaffection(w, t_dis)
			top_town_dis_count += 1
	var top_town_dis := 0.0 if top_town_dis_count == 0 else top_town_dis_sum / float(top_town_dis_count)
	var top_town_griev_sum := 0.0
	var top_town_griev_count := 0
	for t_griev in range(w.towns.size()):
		if w.town_owner[t_griev] == top:
			top_town_griev_sum += w.town_griev[t_griev]
			top_town_griev_count += 1
	var top_town_griev := 0.0 if top_town_griev_count == 0 else top_town_griev_sum / float(top_town_griev_count)
	var max_tension := 0.0
	var max_tension_f := -1
	for f_max in range(w.faction_count):
		if w.faction_alive[f_max] == 1:
			var tension := Dissent.tension(w, f_max)
			if tension > max_tension:
				max_tension = tension
				max_tension_f = f_max
	print("PROBE t=%d factions_alive=%d real_factions=%d faction_count=%d towns=%d owned=%d top=%d top_towns=%d second_towns=%d top_unit_share=%.2f top_cohesion=%.2f top_split_cd=%.0f top_tension=%.3f top_members=%d top_bond=%.2f top_town_dis=%.3f max_tension=%.3f max_tension_f=%d top_griev=%.3f top_glory=%.2f top_wealth=%.2f top_faith=%.2f top_land=%.2f top_town_griev=%.3f stacks=%d top_stacks=%d at_cap=%d units=%d battles_now=%d battles_started=%d faction_births=%d breakaways=%d foundings=%d stacks_n=%d stack_recycles=%d units_n=%d unit_recycles=%d wall_s=%.0f" % [
		int(w.time), alive, real, w.faction_count, w.towns.size(), owned, top, towns_by[top], second_towns,
		float(units_by[top]) / maxf(1.0, float(units_alive)), w.ktrait(top, 4), w.split_cooldown[top],
		top_tension, top_members, top_bond, top_town_dis, max_tension, max_tension_f, top_griev, top_glory, top_wealth, top_faith, top_land, top_town_griev,
		stacks_alive, top_stacks, at_cap, units_alive, w.battles.size(), battles_started, births,
		int(w.history.get("breakaways", 0)), int(w.history.get("foundings", 0)),
		w.stacks.n, _sum(w.stacks.gen), w.units.n, _sum(w.units.gen),
		(Time.get_ticks_usec() - t0) / 1000000.0,
	])
