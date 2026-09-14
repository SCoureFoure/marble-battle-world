class_name BattleRenderer
extends Node2D

const SPARK_POOL := 256

var state: BattleState
var bodies: MultiMeshInstance2D
var weapons: MultiMeshInstance2D
var hp_bars: MultiMeshInstance2D
var sparks: MultiMeshInstance2D
var _buf: PackedFloat32Array
var _weapon_buf: PackedFloat32Array
var _hp_buf: PackedFloat32Array
var _spark_buf: PackedFloat32Array

# spark pool render-only state, allocated in _init() so headless tests can
# call BattleRenderer.new() then ingest/advance/build_spark_buffer without
# adding this node to a tree.
var spark_x: PackedFloat32Array
var spark_y: PackedFloat32Array
var spark_r: PackedFloat32Array
var spark_age: PackedFloat32Array
var spark_life: PackedFloat32Array
var spark_kind: PackedInt32Array
var spark_head: int = 0
var _last_tick: int = -1

# per-marble weapon-hit flash, grown to s.n on demand; decayed to 0 by advance()
var weapon_flash: PackedFloat32Array

# local faction index -> Tuning.FACTION_COLORS index; empty = identity (battle_scene)
var palette: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	spark_x = PackedFloat32Array()
	spark_x.resize(SPARK_POOL)
	spark_y = PackedFloat32Array()
	spark_y.resize(SPARK_POOL)
	spark_r = PackedFloat32Array()
	spark_r.resize(SPARK_POOL)
	spark_age = PackedFloat32Array()
	spark_age.resize(SPARK_POOL)
	spark_life = PackedFloat32Array()
	spark_life.resize(SPARK_POOL)
	spark_kind = PackedInt32Array()
	spark_kind.resize(SPARK_POOL)
	weapon_flash = PackedFloat32Array()


func _ready() -> void:
	bodies = MultiMeshInstance2D.new()
	bodies.name = "Bodies"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mm.mesh = q
	bodies.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/marble_body.gdshader")
	bodies.material = mat
	add_child(bodies)

	weapons = MultiMeshInstance2D.new()
	weapons.name = "Weapons"
	var wmm := MultiMesh.new()
	wmm.transform_format = MultiMesh.TRANSFORM_2D
	wmm.use_colors = false
	wmm.use_custom_data = true
	var wq := QuadMesh.new()
	wq.size = Vector2(2, 2)
	wmm.mesh = wq
	weapons.multimesh = wmm
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/marble_weapon.gdshader")
	weapons.material = wmat
	add_child(weapons)

	hp_bars = MultiMeshInstance2D.new()
	hp_bars.name = "HpBars"
	var hmm := MultiMesh.new()
	hmm.transform_format = MultiMesh.TRANSFORM_2D
	hmm.use_colors = false
	hmm.use_custom_data = true
	var hq := QuadMesh.new()
	hq.size = Vector2(2, 2)
	hmm.mesh = hq
	hp_bars.multimesh = hmm
	var hmat := ShaderMaterial.new()
	hmat.shader = load("res://shaders/hp_bar.gdshader")
	hp_bars.material = hmat
	add_child(hp_bars)

	sparks = MultiMeshInstance2D.new()
	sparks.name = "Sparks"
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_2D
	smm.use_colors = false
	smm.use_custom_data = true
	var sq := QuadMesh.new()
	sq.size = Vector2(2, 2)
	smm.mesh = sq
	smm.instance_count = SPARK_POOL
	sparks.multimesh = smm
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/spark.gdshader")
	sparks.material = smat
	add_child(sparks)


## Colour for local battle faction `f`. `palette` maps local faction index ->
## Tuning.FACTION_COLORS index (the world faction's colour, set by BattleView);
## an empty palette or a -1 entry falls back to the local index itself.
static func faction_color(f: int, palette: PackedInt32Array) -> Color:
	var ci: int = f
	if f >= 0 and f < palette.size() and palette[f] >= 0:
		ci = palette[f]
	return Tuning.FACTION_COLORS[ci % Tuning.FACTION_COLORS.size()]


static func build_buffer(s: BattleState, palette: PackedInt32Array = PackedInt32Array()) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(s.n * 16)
	for i in range(s.n):
		var b := i * 16
		var dead: bool = s.state[i] == BattleState.State.DEAD
		var sc: float = 0.0 if dead else s.radius[i]
		var c: Color = faction_color(s.faction_id[i], palette)
		var g: float = 0.0
		if not dead and s.spin_cap[i] > 0.0:
			g = clampf(s.spin[i] / s.spin_cap[i], 0.0, 1.0)
		buf[b] = sc
		buf[b + 1] = 0.0
		buf[b + 2] = 0.0
		buf[b + 3] = s.px[i]
		buf[b + 4] = 0.0
		buf[b + 5] = sc
		buf[b + 6] = 0.0
		buf[b + 7] = s.py[i]
		buf[b + 8] = g
		buf[b + 9] = 0.0
		buf[b + 10] = 0.0
		buf[b + 11] = 1.0
		buf[b + 12] = c.r
		buf[b + 13] = c.g
		buf[b + 14] = c.b
		buf[b + 15] = s.rank[i] / 3.0 + (2.0 if s.is_captain[i] == 1 else 0.0)
	return buf


static func build_weapon_buffer(s: BattleState, flash: PackedFloat32Array = PackedFloat32Array()) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(s.n * 12)
	for i in range(s.n):
		var b := i * 12
		var w: int = s.weapon_id[i]
		var reach: float = Tuning.WEAPON_REACH[w]
		var hit_r: float = Tuning.WEAPON_HIT_R[w]
		buf[b + 8] = w / 4.0
		buf[b + 9] = flash[i] if i < flash.size() else 0.0
		buf[b + 10] = reach / (reach + hit_r)
		buf[b + 11] = (reach + hit_r) / (2.0 * hit_r)
		if s.state[i] == BattleState.State.DEAD:
			buf[b] = 0.0
			buf[b + 1] = 0.0
			buf[b + 3] = s.px[i]
			buf[b + 4] = 0.0
			buf[b + 5] = 0.0
			buf[b + 7] = s.py[i]
			continue
		var r: float = s.radius[i]
		var a: float = s.weapon_angle[i]
		var l_full: float = (reach + hit_r) * r      # centre to far edge of the hit circle
		var h_half: float = hit_r * r                # half thickness = hit radius
		var c: float = cos(a)
		var sn: float = sin(a)
		var hl: float = 0.5 * l_full
		var ox: float = s.px[i] + c * hl
		var oy: float = s.py[i] + sn * hl
		buf[b] = hl * c
		buf[b + 1] = -h_half * sn
		buf[b + 3] = ox
		buf[b + 4] = hl * sn
		buf[b + 5] = h_half * c
		buf[b + 7] = oy
	return buf


static func build_hp_buffer(s: BattleState) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(s.n * 12)
	for i in range(s.n):
		var b := i * 12
		var r: float = s.radius[i]
		var hp_max: float = s.hp_max[i]
		var hidden: bool = s.hp[i] >= hp_max or s.state[i] == BattleState.State.DEAD
		buf[b] = 0.0 if hidden else r
		buf[b + 3] = s.px[i]
		buf[b + 5] = 0.0 if hidden else 1.5
		buf[b + 7] = s.py[i] - r - 4.0
		buf[b + 8] = (s.hp[i] / hp_max) if hp_max > 0.0 else 0.0
	return buf


func attach(s: BattleState) -> void:
	state = s
	bodies.multimesh.instance_count = s.n
	weapons.multimesh.instance_count = s.n
	hp_bars.multimesh.instance_count = s.n
	if weapon_flash.size() < s.n:
		weapon_flash.resize(s.n)


func ingest(s: BattleState) -> void:
	if s.tick == _last_tick:
		return
	_last_tick = s.tick
	if weapon_flash.size() < s.n:
		weapon_flash.resize(s.n)
	for ev in s.events:
		var etype: int = ev[0]
		if etype == BattleState.Event.HIT:
			var hit_actor: int = ev[1]
			if hit_actor >= 0 and hit_actor < weapon_flash.size():
				weapon_flash[hit_actor] = 0.15
		if etype != BattleState.Event.HIT and etype != BattleState.Event.BUMP and etype != BattleState.Event.BOOST:
			continue
		var actor: int = ev[1]
		var target: int = ev[2]
		if actor < 0 or target < 0:
			continue
		var dmg: float = ev[3] if ev.size() > 3 else 8.0
		var x: float = (s.px[actor] + s.px[target]) * 0.5
		var y: float = (s.py[actor] + s.py[target]) * 0.5
		var r: float
		var life: float
		var kind: int
		if etype == BattleState.Event.HIT:
			r = clampf(6.0 + 1.2 * dmg, 6.0, 28.0)
			life = 0.25
			kind = 0
		elif etype == BattleState.Event.BUMP:
			r = clampf(4.0 + 1.0 * dmg, 4.0, 14.0)
			life = 0.25
			kind = 1
		else:
			r = 6.0
			life = 0.18
			kind = 2
		spark_x[spark_head] = x
		spark_y[spark_head] = y
		spark_r[spark_head] = r
		spark_age[spark_head] = 0.0
		spark_life[spark_head] = life
		spark_kind[spark_head] = kind
		spark_head = (spark_head + 1) % SPARK_POOL


func advance(dt: float) -> void:
	for k in range(SPARK_POOL):
		if spark_life[k] <= 0.0:
			continue
		spark_age[k] += dt
		if spark_age[k] >= spark_life[k]:
			spark_life[k] = 0.0
	for k in range(weapon_flash.size()):
		weapon_flash[k] = maxf(0.0, weapon_flash[k] - dt)


func build_spark_buffer() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(SPARK_POOL * 12)
	for k in range(SPARK_POOL):
		if spark_life[k] <= 0.0:
			continue
		var b := k * 12
		var life: float = spark_life[k]
		var age: float = spark_age[k]
		var sc: float = spark_r[k] * (0.4 + 0.6 * age / life)
		buf[b] = sc
		buf[b + 3] = spark_x[k]
		buf[b + 5] = sc
		buf[b + 7] = spark_y[k]
		buf[b + 8] = spark_kind[k] / 2.0
		buf[b + 9] = 1.0 - age / life
	return buf


func refresh() -> void:
	if state == null:
		return
	if state.n != bodies.multimesh.instance_count:
		bodies.multimesh.instance_count = state.n
		weapons.multimesh.instance_count = state.n
		hp_bars.multimesh.instance_count = state.n
	if weapon_flash.size() < state.n:
		weapon_flash.resize(state.n)
	_buf = build_buffer(state, palette)
	RenderingServer.multimesh_set_buffer(bodies.multimesh.get_rid(), _buf)
	_weapon_buf = build_weapon_buffer(state, weapon_flash)
	RenderingServer.multimesh_set_buffer(weapons.multimesh.get_rid(), _weapon_buf)
	_hp_buf = build_hp_buffer(state)
	RenderingServer.multimesh_set_buffer(hp_bars.multimesh.get_rid(), _hp_buf)
	_spark_buf = build_spark_buffer()
	RenderingServer.multimesh_set_buffer(sparks.multimesh.get_rid(), _spark_buf)


func _process(dt: float) -> void:
	advance(dt)
	refresh()
