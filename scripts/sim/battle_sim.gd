class_name BattleSim
extends RefCounted

var fine: SpatialHash
var coarse: SpatialHash
var max_radius: float = Tuning.BASE_RADIUS


func _init(s: BattleState) -> void:
	fine = SpatialHash.new()
	coarse = SpatialHash.new()
	coarse.setup(s.arena, Tuning.ENGAGE_RADIUS_MULT * Tuning.BASE_RADIUS)
	refresh_radius(s)


func refresh_radius(s: BattleState) -> void:
	var m: float = Tuning.BASE_RADIUS
	var radius := s.radius
	for i in range(s.n):
		if radius[i] > m:
			m = radius[i]
	max_radius = m
	fine.setup(s.arena, 2.0 * max_radius)


func step(s: BattleState, dt: float) -> void:
	s.ax.fill(0.0)
	s.ay.fill(0.0)

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

	fine.build(s.px, s.py, s.state, s.n)
	coarse.build(s.px, s.py, s.state, s.n)

	Forces.retarget(s, coarse, s.tick)
	Forces.accumulate(s, fine)

	var radius := s.radius
	var arena := s.arena
	var left := arena.position.x
	var right := arena.end.x
	var top := arena.position.y
	var bottom := arena.end.y

	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		var vx := (s.vx[i] + s.ax[i] * dt) * Tuning.FRICTION
		var vy := (s.vy[i] + s.ay[i] * dt) * Tuning.FRICTION
		var speed := sqrt(vx * vx + vy * vy)
		if speed > Tuning.MAX_SPEED:
			vx *= Tuning.MAX_SPEED / speed
			vy *= Tuning.MAX_SPEED / speed
		s.px[i] += vx * dt
		s.py[i] += vy * dt
		var r := radius[i]
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
		s.vx[i] = vx
		s.vy[i] = vy

	Collision.resolve(s, fine, dt)

	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		s.spin[i] = maxf(Tuning.RPM_MIN, s.spin[i] - Tuning.SPIN_DECAY * dt)

	s.tick += 1
	s.time += dt


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
