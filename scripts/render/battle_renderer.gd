class_name BattleRenderer
extends Node2D

var state: BattleState
var bodies: MultiMeshInstance2D
var weapons: MultiMeshInstance2D
var hp_bars: MultiMeshInstance2D
var _buf: PackedFloat32Array
var _weapon_buf: PackedFloat32Array
var _hp_buf: PackedFloat32Array


func _ready() -> void:
	bodies = MultiMeshInstance2D.new()
	bodies.name = "Bodies"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = false
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


static func build_buffer(s: BattleState) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(s.n * 12)
	for i in range(s.n):
		var b := i * 12
		var sc: float = 0.0 if s.state[i] == BattleState.State.DEAD else s.radius[i]
		var c: Color = Tuning.FACTION_COLORS[s.faction_id[i] % Tuning.FACTION_COLORS.size()]
		buf[b] = sc
		buf[b + 1] = 0.0
		buf[b + 2] = 0.0
		buf[b + 3] = s.px[i]
		buf[b + 4] = 0.0
		buf[b + 5] = sc
		buf[b + 6] = 0.0
		buf[b + 7] = s.py[i]
		buf[b + 8] = c.r
		buf[b + 9] = c.g
		buf[b + 10] = c.b
		buf[b + 11] = s.rank[i] / 3.0 + (2.0 if s.is_captain[i] == 1 else 0.0)
	return buf


static func build_weapon_buffer(s: BattleState) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(s.n * 12)
	for i in range(s.n):
		var b := i * 12
		var w: int = s.weapon_id[i]
		buf[b + 8] = w / 4.0
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
		var blen: float = Tuning.WEAPON_REACH[w] * r
		var thick: float = 0.25 * r
		var c: float = cos(a)
		var sn: float = sin(a)
		var hl: float = 0.5 * blen
		var ht: float = 0.5 * thick
		var ox: float = s.px[i] + c * 0.5 * blen
		var oy: float = s.py[i] + sn * 0.5 * blen
		buf[b] = hl * c
		buf[b + 1] = -ht * sn
		buf[b + 3] = ox
		buf[b + 4] = hl * sn
		buf[b + 5] = ht * c
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


func refresh() -> void:
	if state == null:
		return
	if state.n != bodies.multimesh.instance_count:
		bodies.multimesh.instance_count = state.n
		weapons.multimesh.instance_count = state.n
		hp_bars.multimesh.instance_count = state.n
	_buf = build_buffer(state)
	RenderingServer.multimesh_set_buffer(bodies.multimesh.get_rid(), _buf)
	_weapon_buf = build_weapon_buffer(state)
	RenderingServer.multimesh_set_buffer(weapons.multimesh.get_rid(), _weapon_buf)
	_hp_buf = build_hp_buffer(state)
	RenderingServer.multimesh_set_buffer(hp_bars.multimesh.get_rid(), _hp_buf)


func _process(_dt: float) -> void:
	refresh()
