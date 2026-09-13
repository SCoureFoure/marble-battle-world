class_name Damage extends RefCounted

static var force_mult: float = -1.0

static func roll(s: BattleState, crit_chance: float) -> float:
	if force_mult >= 0.0:
		return force_mult

	var m: float = clampf(s.rng.randfn(1.0, Tuning.DMG_SIGMA), Tuning.DMG_MULT_MIN, Tuning.DMG_MULT_MAX)

	if crit_chance > 0.0 and s.rng.randf() < crit_chance:
		m *= Tuning.CRIT_MULT

	return m

static func apply(s: BattleState, attacker: int, victim: int, dmg: float, event_type: int) -> void:
	# 7. apply damage, xp, event
	s.hp[victim] -= dmg
	s.xp[attacker] += Tuning.XP_PER_HIT
	s.events.append([event_type, attacker, victim, dmg])

	# Set recoil for attacker on HIT or BUMP
	if (event_type == BattleState.Event.HIT or event_type == BattleState.Event.BUMP) and attacker >= 0:
		s.recoil_t[attacker] = Tuning.RECOIL_TIME

	# 8. kill check
	if s.hp[victim] <= 0.0:
		s.state[victim] = BattleState.State.DEAD
		s.hp[victim] = 0.0
		s.kills[attacker] += 1
		s.xp[attacker] += Tuning.XP_PER_KILL
		var fj: int = s.faction_id[victim]
		s.faction_alive[fj] -= 1
		s.events.append([BattleState.Event.KILL, attacker, victim])
		var captain_dead: bool = s.is_captain[victim] == 1
		for m in range(s.n):
			if s.state[m] != BattleState.State.DEAD and s.faction_id[m] == fj:
				s.morale[m] = maxf(0.0, s.morale[m] + Tuning.MORALE_HIT_ALLY_DEATH)
				if captain_dead:
					s.morale[m] = maxf(0.0, s.morale[m] + Tuning.MORALE_HIT_CAPTAIN_DEAD)
		if captain_dead:
			s.faction_captain[fj] = -1
			s.events.append([BattleState.Event.CAPTAIN_DEAD, attacker, victim])

	# 9. rank-up check (after xp changes)
	while s.rank[attacker] < 3 and s.xp[attacker] >= Tuning.RANK_XP[s.rank[attacker] + 1]:
		s.rank[attacker] += 1
		var rk: int = s.rank[attacker]
		s.spin_cap[attacker] = Tuning.SPIN_CAP[rk]
		var old_hp_max: float = s.hp_max[attacker]
		s.hp_max[attacker] = Tuning.HP_BASE * Tuning.RANK_MULT[rk]
		s.hp[attacker] += s.hp_max[attacker] - old_hp_max
		s.mass[attacker] = s.radius[attacker] * s.radius[attacker] * Tuning.RANK_MULT[rk]
		s.events.append([BattleState.Event.LEVEL, attacker, rk])
