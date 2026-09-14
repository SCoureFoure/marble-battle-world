class_name BattleAftermath
extends RefCounted
## Cosmetic post-battle phase for the battle being watched
## (docs/ARCHITECTURE.md §18). BattleView starts it once BattleBridge.finish
## has dropped the instance from world.battles; from then on nothing in the
## world reads this BattleState, so moving marbles here changes no result.
## Winners chase nearby fleeing marbles for CHASE_TIME, then circle their
## rally point with twirling weapons and pulsing spin glow; everyone else runs
## for their home edge and vanishes there. Never damages: BattleSim.integrate
## runs without hazards, Weapons.tick never runs, and bump_cd is pinned so
## Collision.resolve deals no body damage.

const CHASE_TIME := 2.5
const CHASE_RANGE := 240.0
const CHASERS_PER_FLEER := 2
const DRIVE := 40.0             # same scale as Tuning.K_ATTR
const CHASE_CAP := 170.0        # speed caps along the drive, as Forces step 5
const FLEE_CAP := 100.0
const ORBIT_CAP := 70.0
const RING_BASE := 40.0         # outer ring radius = RING_BASE + RING_PER_SQRT * sqrt(winners)
const RING_PER_SQRT := 10.0
const RING_MIN_MULT := 3.0      # inner ring radius = RING_MIN_MULT * rally marble radius
const RING_PULL := 40.0         # radial error (px) that gives a full-strength pull
const WEAPON_TWIRL := 8.0       # rad/s
const GLOW_PERIOD := 0.8        # s, spin-glow pulse
const NO_DAMAGE_CD := 1.0e9

var s: BattleState
var sim: BattleSim
var winner: int                  # local side; < 0 = stalemate
var time: float = 0.0
var chase_of: PackedInt32Array   # per marble: fleeing marble it chases, -1 none
var orbit_r: PackedFloat32Array  # per marble: celebration ring radius, -1 until first set
var rally: Vector2               # winners' centroid at start; used while no live captain
var celebrants: int = 0


func _init(state: BattleState, battle_sim: BattleSim, winner_side: int) -> void:
	s = state
	sim = battle_sim
	winner = winner_side
	chase_of = PackedInt32Array()
	chase_of.resize(s.n)
	chase_of.fill(-1)
	orbit_r = PackedFloat32Array()
	orbit_r.resize(s.n)
	orbit_r.fill(-1.0)

	var sx := 0.0
	var sy := 0.0
	for i in range(s.n):
		s.bump_cd[i] = NO_DAMAGE_CD
		if s.state[i] != BattleState.State.DEAD and is_celebrant(i):
			celebrants += 1
			sx += s.px[i]
			sy += s.py[i]
	if celebrants > 0:
		rally = Vector2(sx / celebrants, sy / celebrants)
	else:
		rally = s.arena.get_center()

	_assign_chasers()


func is_celebrant(i: int) -> bool:
	return winner >= 0 and s.faction_id[i] == winner


## Losers always flee; in a stalemate only marbles already retreating do.
func is_fleer(i: int) -> bool:
	if is_celebrant(i):
		return false
	return winner >= 0 or s.state[i] == BattleState.State.RETREAT


## Each live fleer, in index order, takes up to CHASERS_PER_FLEER of the
## nearest unassigned non-captain winners within CHASE_RANGE.
func _assign_chasers() -> void:
	if winner < 0:
		return
	var mask := PackedInt32Array()
	mask.resize(s.n)
	for i in range(s.n):
		var can_chase: bool = s.state[i] != BattleState.State.DEAD and is_celebrant(i) and s.is_captain[i] == 0
		mask[i] = BattleState.State.ENGAGE if can_chase else BattleState.State.DEAD
	var grid := SpatialHash.new()
	grid.setup(s.arena, CHASE_RANGE)
	grid.build(s.px, s.py, mask, s.n)

	for f in range(s.n):
		if s.state[f] == BattleState.State.DEAD or not is_fleer(f):
			continue
		for _pick in range(CHASERS_PER_FLEER):
			var found := grid.gather(s.px[f], s.py[f])
			var best := -1
			var best_d2 := CHASE_RANGE * CHASE_RANGE
			for e in range(found):
				var j: int = grid.scratch[e]
				if chase_of[j] != -1:
					continue
				var dx := s.px[j] - s.px[f]
				var dy := s.py[j] - s.py[f]
				var d2 := dx * dx + dy * dy
				if d2 < best_d2:
					best_d2 = d2
					best = j
			if best == -1:
				break
			chase_of[best] = f


func step(dt: float) -> void:
	s.events.clear()
	s.ax.fill(0.0)
	s.ay.fill(0.0)
	time += dt

	var cap_i := -1
	if winner >= 0:
		cap_i = s.faction_captain[winner]
		if cap_i >= 0 and s.state[cap_i] == BattleState.State.DEAD:
			cap_i = -1
	var centre := rally
	var ring_min := RING_MIN_MULT * Tuning.BASE_RADIUS
	if cap_i >= 0:
		centre = Vector2(s.px[cap_i], s.py[cap_i])
		ring_min = RING_MIN_MULT * s.radius[cap_i]
	var ring_max := maxf(ring_min, RING_BASE + RING_PER_SQRT * sqrt(float(celebrants)))

	for i in range(s.n):
		if s.state[i] == BattleState.State.DEAD:
			continue
		s.bump_cd[i] = NO_DAMAGE_CD
		if is_celebrant(i):
			s.weapon_angle[i] = fposmod(s.weapon_angle[i] + WEAPON_TWIRL * dt, TAU)
			s.spin[i] = s.spin_cap[i] * (0.55 + 0.45 * sin(time * TAU / GLOW_PERIOD + i * 0.7))
			var t := chase_of[i]
			if t >= 0 and (time >= CHASE_TIME or s.state[t] == BattleState.State.DEAD):
				chase_of[i] = -1
				t = -1
			if t >= 0:
				_drive(i, s.px[t] - s.px[i], s.py[t] - s.py[i], CHASE_CAP)
			elif i != cap_i:
				var rx := s.px[i] - centre.x
				var ry := s.py[i] - centre.y
				var d := sqrt(rx * rx + ry * ry)
				if d > 1e-3:
					if orbit_r[i] < 0.0:
						orbit_r[i] = clampf(d, ring_min, ring_max)
					var ux := rx / d
					var uy := ry / d
					var pull := clampf((d - orbit_r[i]) / RING_PULL, -1.5, 1.5)
					# tangent (-uy, ux) plus a radial pull back onto the ring
					_drive(i, -uy - ux * pull, ux - uy * pull, ORBIT_CAP)
		elif is_fleer(i):
			var home: Vector2 = Tuning.HOME_DIR[s.faction_id[i] % 4]
			_drive(i, home.x, home.y, FLEE_CAP)

	sim.integrate(s, dt, false)
	sim.fine.build(s.px, s.py, s.state, s.n)
	Collision.resolve(s, sim.fine, dt)

	for i2 in range(s.n):
		if s.state[i2] == BattleState.State.DEAD:
			continue
		s.boost_cd[i2] = maxf(0.0, s.boost_cd[i2] - dt)
		if is_fleer(i2) and _at_home_edge(i2):
			s.fled[i2] = 1
			s.state[i2] = BattleState.State.DEAD
			s.events.append([BattleState.Event.FLED, i2, -1])

	s.tick += 1
	s.time += dt


## Forces step 5 style: push along (dx, dy) at DRIVE only while the velocity
## along that direction is under `cap`.
func _drive(i: int, dx: float, dy: float, cap: float) -> void:
	var mag := sqrt(dx * dx + dy * dy)
	if mag <= 0.0:
		return
	var dir_x := dx / mag
	var dir_y := dy / mag
	if s.vx[i] * dir_x + s.vy[i] * dir_y < cap:
		s.ax[i] += DRIVE * dir_x
		s.ay[i] += DRIVE * dir_y


func _at_home_edge(i: int) -> bool:
	var home: Vector2 = Tuning.HOME_DIR[s.faction_id[i] % 4]
	var r := s.radius[i]
	if home.x < 0.0:
		return s.px[i] <= s.arena.position.x + r
	if home.x > 0.0:
		return s.px[i] >= s.arena.end.x - r
	if home.y < 0.0:
		return s.py[i] <= s.arena.position.y + r
	return s.py[i] >= s.arena.end.y - r


## [title, subtitle] for the result banner. `side` is BattleSim.winner's local
## side; < 0 is a stalemate. Subtitle lists the winning side's stacks.
static func banner_lines(inst: BattleInstance, w: World, side: int) -> PackedStringArray:
	if side < 0 or side >= inst.faction_map.size():
		return PackedStringArray(["STALEMATE", ""])
	var wf: int = inst.faction_map[side]
	var fname := "Side %d" % side
	if wf >= 0 and wf < w.faction_names.size():
		fname = String(w.faction_names[wf])
	var members: PackedInt32Array = inst.side_factions[side]
	var stack_names := PackedStringArray()
	for k in range(inst.stack_ids.size()):
		var st: int = inst.stack_ids[k]
		if members.has(w.stacks.faction[st]):
			stack_names.append(String(w.stacks.names[st]))
	return PackedStringArray(["%s VICTORY" % fname.to_upper(), ", ".join(stack_names)])
