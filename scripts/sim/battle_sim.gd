class_name BattleSim
extends RefCounted

const PHASE_NAMES := ["clear", "hash", "retarget", "forces", "integrate", "collision", "weapons", "transitions"]

var fine: SpatialHash
var coarse: SpatialHash
var max_radius: float = Tuning.BASE_RADIUS
var terrain: TerrainGrid = null
var captain_seen: PackedByteArray
var phase_us: PackedInt64Array = [0, 0, 0, 0, 0, 0, 0, 0]


func _init(s: BattleState) -> void:
	fine = SpatialHash.new()
	coarse = SpatialHash.new()
	coarse.setup(s.arena, Tuning.ENGAGE_RADIUS_MULT * Tuning.BASE_RADIUS)
	refresh_radius(s)

	captain_seen = PackedByteArray()
	captain_seen.resize(Tuning.MAX_FACTIONS)
	for f in range(Tuning.MAX_FACTIONS):
		captain_seen[f] = 1 if s.faction_captain[f] >= 0 else 0


func set_terrain(t: TerrainGrid) -> void:
	terrain = t
	t.finalize()


func reset_profile() -> void:
	phase_us.fill(0)


func refresh_radius(s: BattleState) -> void:
	var m: float = Tuning.BASE_RADIUS
	var radius := s.radius
	for i in range(s.n):
		if radius[i] > m:
			m = radius[i]
	max_radius = m
	fine.setup(s.arena, 2.0 * max_radius)


func step(s: BattleState, dt: float) -> void:
	var t0 := Time.get_ticks_usec()

	if terrain != null and terrain.dirty:
		terrain.finalize()

	s.ax.fill(0.0)
	s.ay.fill(0.0)
	s.events.clear()

	# zero faction sums, then accumulate live positions per faction
	for fac in range(s.faction_count):
		s.faction_alive[fac] = 0
		s.faction_cx[fac] = 0.0
		s.faction_cy[fac] = 0.0

	var px := s.px
	var py := s.py
	var state := s.state
	var faction_id := s.faction_id

	for i in range(s.n):
		if state[i] == BattleState.State.DEAD:
			continue
		var f := faction_id[i]
		s.faction_alive[f] += 1
		s.faction_cx[f] += px[i]
		s.faction_cy[f] += py[i]

	for fac2 in range(s.faction_count):
		var count := s.faction_alive[fac2]
		if count > 0:
			s.faction_cx[fac2] = s.faction_cx[fac2] / count
			s.faction_cy[fac2] = s.faction_cy[fac2] / count

	var t1 := Time.get_ticks_usec()
	phase_us[0] += t1 - t0

	fine.build(s.px, s.py, s.state, s.n)
	coarse.build(s.px, s.py, s.state, s.n)

	var t2 := Time.get_ticks_usec()
	phase_us[1] += t2 - t1

	Forces.retarget(s, coarse, s.tick)

	var t3 := Time.get_ticks_usec()
	phase_us[2] += t3 - t2

	Forces.accumulate(s, fine)

	var t4 := Time.get_ticks_usec()
	phase_us[3] += t4 - t3

	var radius := s.radius
	var arena := s.arena
	var kind: PackedByteArray = terrain.kind if terrain else PackedByteArray()

	integrate(s, dt, true)

	# tower ownership + auras (once per tower cell per tick, before applying auras)
	if terrain:
		var any_tower: bool = false
		for ti0 in range(s.n):
			if s.state[ti0] == BattleState.State.DEAD:
				continue
			var tc0: int = terrain.cell_at(s.px[ti0], s.py[ti0])
			if terrain.kind[tc0] == TerrainGrid.Kind.TOWER:
				any_tower = true
				break

		if any_tower:
			var tower_present := {}
			for ti in range(s.n):
				if s.state[ti] == BattleState.State.DEAD:
					continue
				var tc: int = terrain.cell_at(s.px[ti], s.py[ti])
				if terrain.kind[tc] != TerrainGrid.Kind.TOWER:
					continue
				if not tower_present.has(tc):
					tower_present[tc] = {}
				tower_present[tc][faction_id[ti]] = true

			for tc2 in tower_present.keys():
				var present: Dictionary = tower_present[tc2]
				if present.size() == 1:
					for tf in present.keys():
						terrain.owner[tc2] = tf

			for ti2 in range(s.n):
				if s.state[ti2] == BattleState.State.DEAD:
					continue
				var tc3: int = terrain.cell_at(s.px[ti2], s.py[ti2])
				if terrain.kind[tc3] != TerrainGrid.Kind.TOWER:
					continue
				if terrain.owner[tc3] == faction_id[ti2]:
					s.spin[ti2] = minf(s.spin_cap[ti2], s.spin[ti2] + Tuning.TOWER_SPIN_REGEN * dt)
					s.hp[ti2] = minf(s.hp_max[ti2], s.hp[ti2] + Tuning.TOWER_HEAL * dt)

	var t5 := Time.get_ticks_usec()
	phase_us[4] += t5 - t4

	Collision.resolve(s, fine, dt)

	var t6 := Time.get_ticks_usec()
	phase_us[5] += t6 - t5

	Weapons.tick(s, fine, dt)

	var t7 := Time.get_ticks_usec()
	phase_us[6] += t7 - t6

	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var k: int = kind[terrain.cell_at(s.px[i], s.py[i])] if terrain else TerrainGrid.Kind.PLAIN
		s.spin[i] = clampf(s.spin[i] + Tuning.SPIN_RATE[k] * dt, Tuning.RPM_MIN, s.spin_cap[i])
		s.bump_cd[i] = maxf(0.0, s.bump_cd[i] - dt)
		s.boost_cd[i] = maxf(0.0, s.boost_cd[i] - dt)
		s.recoil_t[i] = maxf(0.0, s.recoil_t[i] - dt)

	# transitions: captain aura, ENGAGE -> RETREAT, RETREAT at home edge -> fled
	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var f2: int = faction_id[i]

		var cap: int = s.faction_captain[f2]
		if cap >= 0:
			var adx := s.px[i] - s.px[cap]
			var ady := s.py[i] - s.py[cap]
			var adist := sqrt(adx * adx + ady * ady)
			if adist <= Tuning.CAPTAIN_AURA_MULT * radius[cap]:
				s.morale[i] = minf(1.0, s.morale[i] + Tuning.CAPTAIN_MORALE_REGEN * dt)

		if s.state[i] == BattleState.State.ENGAGE:
			if s.morale[i] < Tuning.RETREAT_THRESHOLD or s.hp[i] < Tuning.RETREAT_HP_FRAC * s.hp_max[i]:
				s.state[i] = BattleState.State.RETREAT

		if s.state[i] == BattleState.State.RETREAT:
			var home: Vector2 = Tuning.HOME_DIR[f2 % 4]
			var r2 := radius[i]
			var at_edge := false
			if home.x < 0.0:
				at_edge = s.px[i] <= arena.position.x + r2
			elif home.x > 0.0:
				at_edge = s.px[i] >= arena.end.x - r2
			elif home.y < 0.0:
				at_edge = s.py[i] <= arena.position.y + r2
			else:
				at_edge = s.py[i] >= arena.end.y - r2
			if at_edge:
				s.fled[i] = 1
				s.state[i] = BattleState.State.DEAD
				s.faction_alive[f2] -= 1
				s.events.append([BattleState.Event.FLED, i, -1])

	var t8 := Time.get_ticks_usec()
	phase_us[7] += t8 - t7

	s.tick += 1
	s.time += dt


## Tick step 6: forces -> velocity, terrain slope/friction, speed clamp, move,
## arena walls, obstacle push-out, then hazard damage when `apply_hazards`.
## BattleAftermath reuses it with apply_hazards = false, so the post-battle
## replay moves marbles the same way but can never kill one.
func integrate(s: BattleState, dt: float, apply_hazards: bool) -> void:
	var faction_id := s.faction_id
	var radius := s.radius
	var arena := s.arena
	var left := arena.position.x
	var right := arena.end.x
	var top := arena.position.y
	var bottom := arena.end.y

	var ox: float = terrain.origin.x if terrain else 0.0
	var oy: float = terrain.origin.y if terrain else 0.0
	var inv_cell: float = 1.0 / terrain.cell if terrain else 0.0
	var cols: int = terrain.cols if terrain else 0
	var rows: int = terrain.rows if terrain else 0
	var kind: PackedByteArray = terrain.kind if terrain else PackedByteArray()
	var friction: PackedFloat32Array = terrain.friction if terrain else PackedFloat32Array()
	var near_solid: PackedByteArray = terrain.near_solid if terrain else PackedByteArray()
	var slope_x: PackedFloat32Array = terrain.slope_x if terrain else PackedFloat32Array()
	var slope_y: PackedFloat32Array = terrain.slope_y if terrain else PackedFloat32Array()
	var fr_plain: float = pow(Tuning.DRAG_KEEP_PER_S[0], dt)

	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var r := radius[i]

		var c: int = -1
		if terrain:
			var cx: int = clampi(int((s.px[i] - ox) * inv_cell), 0, cols - 1)
			var cy: int = clampi(int((s.py[i] - oy) * inv_cell), 0, rows - 1)
			c = cy * cols + cx

		var vx: float = s.vx[i] + s.ax[i] * Tuning.FORCE_SCALE * dt
		var vy: float = s.vy[i] + s.ay[i] * Tuning.FORCE_SCALE * dt
		if terrain:
			vx += slope_x[c] * Tuning.FORCE_SCALE * dt
			vy += slope_y[c] * Tuning.FORCE_SCALE * dt
		var fr: float = friction[c] if terrain else fr_plain
		vx *= fr
		vy *= fr

		var speed := sqrt(vx * vx + vy * vy)
		if speed > Tuning.MAX_SPEED:
			vx *= Tuning.MAX_SPEED / speed
			vy *= Tuning.MAX_SPEED / speed
		s.px[i] += vx * dt
		s.py[i] += vy * dt

		if s.px[i] < left + r:
			s.px[i] = left + r
			vx = absf(vx) * Tuning.RESTITUTION
		if s.px[i] > right - r:
			s.px[i] = right - r
			vx = -absf(vx) * Tuning.RESTITUTION
		if s.py[i] < top + r:
			s.py[i] = top + r
			vy = absf(vy) * Tuning.RESTITUTION
		if s.py[i] > bottom - r:
			s.py[i] = bottom - r
			vy = -absf(vy) * Tuning.RESTITUTION

		# obstacles: 3x3 terrain cells around the marble's (post wall-clamp) cell
		if terrain:
			var mcx: int = clampi(int((s.px[i] - ox) * inv_cell), 0, cols - 1)
			var mcy: int = clampi(int((s.py[i] - oy) * inv_cell), 0, rows - 1)
			c = mcy * cols + mcx
			if near_solid[c] == 1:
				for gx in range(mcx - 1, mcx + 2):
					if gx < 0 or gx >= cols:
						continue
					for gy in range(mcy - 1, mcy + 2):
						if gy < 0 or gy >= rows:
							continue
						var oc: int = gy * cols + gx
						if not TerrainGrid.is_solid(kind[oc]):
							continue
						var centre := terrain.cell_center(oc)
						var obs_r: float = Tuning.TERRAIN_CELL * Tuning.OBSTACLE_RADIUS_FRAC
						var odx := s.px[i] - centre.x
						var ody := s.py[i] - centre.y
						var odist := sqrt(odx * odx + ody * ody)
						if odist < obs_r + r:
							var nx: float
							var ny: float
							if odist > 0.0:
								nx = odx / odist
								ny = ody / odist
							else:
								nx = 1.0
								ny = 0.0
							s.px[i] = centre.x + nx * (obs_r + r)
							s.py[i] = centre.y + ny * (obs_r + r)
							var vn := vx * nx + vy * ny
							if vn < 0.0:
								vx -= (1.0 + Tuning.RESTITUTION) * vn * nx
								vy -= (1.0 + Tuning.RESTITUTION) * vn * ny

		s.vx[i] = vx
		s.vy[i] = vy

		# hazard, re-evaluated at the (possibly obstacle-pushed) new position
		if apply_hazards and terrain:
			c = terrain.cell_at(s.px[i], s.py[i])
			var k1: int = terrain.kind[c]
			var dps: float = Tuning.HAZARD_DPS[k1]
			if dps > 0.0:
				s.hp[i] -= dps * dt
				if s.hp[i] <= 0.0:
					s.hp[i] = 0.0
					s.state[i] = BattleState.State.DEAD
					s.faction_alive[faction_id[i]] -= 1
					s.events.append([BattleState.Event.KILL, -1, i])


func winner(s: BattleState) -> int:
	var engaged: PackedByteArray = PackedByteArray()
	engaged.resize(s.faction_count)
	for i in range(s.n):
		if s.state[i] == BattleState.State.ENGAGE:
			engaged[s.faction_id[i]] = 1

	var count := 0
	var found := -1
	for f in range(s.faction_count):
		if engaged[f] == 1:
			count += 1
			found = f

	if count == 0:
		return -2
	if count == 1:
		return found
	if s.time >= Tuning.T_MAX_BATTLE:
		return -2
	return -1
