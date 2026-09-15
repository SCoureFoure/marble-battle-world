class_name BattleLod extends RefCounted
## Statistical stand-in for BattleSim.step when a battle is not being
## watched. Source: docs/ARCHITECTURE.md §14.2.
## Operates on the same BattleState; positions are left untouched (fiat:
## "no positions change under LOD").

const CHUNK_SIZE := 8.0


static func step(inst: BattleInstance, dt: float) -> void:
	var s := inst.state
	s.events.clear()

	if inst.lod_xp_acc.size() < s.n:
		var old_size := inst.lod_xp_acc.size()
		inst.lod_xp_acc.resize(s.n)
		for i in range(old_size, s.n):
			inst.lod_xp_acc[i] = 0.0

	# 1. per-local-side damage rate (Lanchester scale), ENGAGE marbles only.
	var rate := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var live_count := PackedInt32Array([0, 0, 0, 0])
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var fid: int = s.faction_id[i]
		if fid < 0 or fid >= 4:
			continue
		live_count[fid] += 1
		if s.state[i] != BattleState.State.ENGAGE:
			continue
		var wid: int = s.weapon_id[i]
		rate[fid] += (s.spin[i] / Tuning.SPIN_REF) * Tuning.RANK_MULT[s.rank[i]] * Tuning.WEAPON_DMG[wid] / Tuning.WEAPON_COOLDOWN[wid]
	for fid2 in range(4):
		rate[fid2] *= Tuning.LOD_K

	# 2. distribute each side's damage over live enemy sides, in chunks of
	# roughly CHUNK_SIZE, onto uniformly-drawn targets/attackers.
	# Per-side lists are built once (ascending marble index) and kept in sync
	# by removing each marble as it dies, so every draw sees exactly the list a
	# fresh scan would give. Morale hits from deaths are tallied per side and
	# applied once after this pass: all hits are negative and clamped at 0, so
	# the sum equals applying them one death at a time for every marble still
	# alive, and nothing reads morale before step 3.
	var engage: Array = [[], [], [], []]
	var targets_of: Array = [[], [], [], []]
	for i in range(s.n):
		var st: int = s.state[i]
		if st == BattleState.State.DEAD:
			continue
		var fid3: int = s.faction_id[i]
		if fid3 < 0 or fid3 >= 4:
			continue
		targets_of[fid3].append(i)
		if st == BattleState.State.ENGAGE:
			engage[fid3].append(i)
	var deaths := PackedInt32Array([0, 0, 0, 0])
	var captain_deaths := PackedInt32Array([0, 0, 0, 0])

	for side in range(4):
		if rate[side] <= 0.0:
			continue
		var attackers: Array = engage[side]
		if attackers.is_empty():
			continue

		var total_enemy := 0
		for oc in range(4):
			if oc != side:
				total_enemy += live_count[oc]
		if total_enemy == 0:
			continue

		var d: float = rate[side] * dt
		for other in range(4):
			if other == side or live_count[other] == 0:
				continue
			var d_other: float = d * float(live_count[other]) / float(total_enemy)
			if d_other <= 0.0:
				continue
			var chunks: int = maxi(1, int(ceil(d_other / CHUNK_SIZE)))
			var chunk: float = d_other / float(chunks)
			var targets: Array = targets_of[other]
			for _c in range(chunks):
				if targets.is_empty():
					break
				var ti: int = s.rng.randi_range(0, targets.size() - 1)
				var t: int = targets[ti]
				var ai: int = s.rng.randi_range(0, attackers.size() - 1)
				var a: int = attackers[ai]
				var was_engaged: bool = s.state[t] == BattleState.State.ENGAGE
				var died := _apply_hit(s, inst, a, t, chunk)
				if died:
					targets.remove_at(ti)
					if was_engaged:
						engage[other].erase(t)
					deaths[other] += 1
					if s.is_captain[t] == 1:
						captain_deaths[other] += 1

	for m in range(s.n):
		if s.state[m] == BattleState.State.DEAD:
			continue
		var fm: int = s.faction_id[m]
		if fm < 0 or fm >= 4 or deaths[fm] == 0:
			continue
		var hit: float = deaths[fm] * s.ally_death_hit(fm) + captain_deaths[fm] * Tuning.MORALE_HIT_CAPTAIN_DEAD
		s.morale[m] = maxf(0.0, s.morale[m] + hit)

	# 3. spin decay, morale/hp retreat trigger (as BattleSim step 10), and
	# the hit_cd-as-flee-timer for RETREAT marbles (fiat).
	# UNDECIDED: §14.2 step 3 only names "spin decay, morale/hp retreat
	# triggers" from BattleSim step 10; captain-aura morale regen (the other
	# half of step 10) is not mentioned and is omitted here.
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		s.spin[i] = maxf(Tuning.RPM_MIN, s.spin[i] - Tuning.SPIN_DECAY * dt)

		if s.state[i] == BattleState.State.ENGAGE:
			if s.morale[i] < Tuning.RETREAT_THRESHOLD or s.hp[i] < Tuning.RETREAT_HP_FRAC * s.hp_max[i]:
				s.state[i] = BattleState.State.RETREAT

		if s.state[i] == BattleState.State.RETREAT:
			s.hit_cd[i] += dt
			if s.hit_cd[i] >= Tuning.LOD_FLEE_TIME:
				var f: int = s.faction_id[i]
				s.fled[i] = 1
				s.state[i] = BattleState.State.DEAD
				s.faction_alive[f] -= 1
				s.events.append([BattleState.Event.FLED, i, -1])

	s.tick += 1
	s.time += dt


## Applies `chunk` damage from attacker `a` to target `t`; returns true when
## `t` dies. Mirrors Weapons.tick steps 7-9 (damage/xp/kill/rank-up). The
## caller applies the death's morale hit to `t`'s side (batched per tick).
static func _apply_hit(s: BattleState, inst: BattleInstance, a: int, t: int, chunk: float) -> bool:
	s.hp[t] -= chunk

	inst.lod_xp_acc[a] += chunk * Tuning.LOD_XP_PER_DMG
	var whole := int(floor(inst.lod_xp_acc[a]))
	if whole >= 1:
		s.xp[a] += whole
		inst.lod_xp_acc[a] -= float(whole)

	s.events.append([BattleState.Event.HIT, a, t])

	var died := false
	if s.hp[t] <= 0.0:
		died = true
		s.state[t] = BattleState.State.DEAD
		s.hp[t] = 0.0
		s.kills[a] += 1
		s.xp[a] += Tuning.XP_PER_KILL
		var ft: int = s.faction_id[t]
		s.faction_alive[ft] -= 1
		s.events.append([BattleState.Event.KILL, a, t])
		if s.is_captain[t] == 1:
			s.faction_captain[ft] = -1
			s.events.append([BattleState.Event.CAPTAIN_DEAD, a, t])

	while s.rank[a] < 3 and s.xp[a] >= Tuning.RANK_XP[s.rank[a] + 1]:
		s.rank[a] += 1
		var rk: int = s.rank[a]
		s.spin_cap[a] = Tuning.SPIN_CAP[rk]
		var old_hp_max: float = s.hp_max[a]
		s.hp_max[a] = Tuning.HP_BASE * Tuning.RANK_MULT[rk]
		s.hp[a] += s.hp_max[a] - old_hp_max
		s.mass[a] = s.radius[a] * s.radius[a] * Tuning.RANK_MULT[rk]
		s.events.append([BattleState.Event.LEVEL, a, rk])

	return died
