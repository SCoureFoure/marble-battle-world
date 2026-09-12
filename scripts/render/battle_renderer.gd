class_name BattleRenderer
extends Node2D

var state: BattleState
var bodies: MultiMeshInstance2D
var _buf: PackedFloat32Array


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
		buf[b + 11] = s.rank[i] / 3.0
	return buf


func attach(s: BattleState) -> void:
	state = s
	bodies.multimesh.instance_count = s.n


func refresh() -> void:
	if state == null:
		return
	if state.n != bodies.multimesh.instance_count:
		bodies.multimesh.instance_count = state.n
	_buf = build_buffer(state)
	RenderingServer.multimesh_set_buffer(bodies.multimesh.get_rid(), _buf)


func _process(_dt: float) -> void:
	refresh()
