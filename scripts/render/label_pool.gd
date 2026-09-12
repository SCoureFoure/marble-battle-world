class_name LabelPool
extends Node2D
## Pooled world-space Labels: 0..15 captains, 16..49 popups.
## Source: .warboss-horde/slices/m2-renderer.md §4.

const POOL_SIZE := 50
const CAPTAIN_SLOTS := 16
const POPUP_LIFETIME := 1.0
const POPUP_RISE := 30.0

var _labels: Array[Label] = []
var _popup_start_x: PackedFloat32Array
var _popup_start_y: PackedFloat32Array
var _popup_t0: PackedFloat32Array
var _popup_active: PackedByteArray
var _next_popup_slot: int = CAPTAIN_SLOTS


func _ready() -> void:
	_labels.resize(POOL_SIZE)
	_popup_start_x.resize(POOL_SIZE)
	_popup_start_y.resize(POOL_SIZE)
	_popup_t0.resize(POOL_SIZE)
	_popup_active.resize(POOL_SIZE)
	for i in range(POOL_SIZE):
		var l := Label.new()
		l.visible = false
		add_child(l)
		_labels[i] = l


func set_captain(slot: int, text: String, pos: Vector2) -> void:
	var l := _labels[slot]
	l.text = text
	# UNDECIDED: contract's offset "pos + Vector2(-20, -r - 18)" references a
	# radius `r` that is not in scope here (set_captain has no radius param,
	# and battle_scene.gd's call site in §5 also only passes `pos`); using
	# the literal Vector2(-20, -18) offset (dropping the unresolved -r term).
	l.position = pos + Vector2(-20, -18)
	l.visible = true


func hide_captain(slot: int) -> void:
	_labels[slot].visible = false


func popup(text: String, pos: Vector2, color: Color) -> void:
	var slot := _next_popup_slot
	_next_popup_slot += 1
	if _next_popup_slot >= POOL_SIZE:
		_next_popup_slot = CAPTAIN_SLOTS
	var l := _labels[slot]
	l.text = text
	l.modulate = color
	l.position = pos
	l.visible = true
	_popup_start_x[slot] = pos.x
	_popup_start_y[slot] = pos.y
	_popup_t0[slot] = Time.get_ticks_msec()
	_popup_active[slot] = 1


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	for slot in range(CAPTAIN_SLOTS, POOL_SIZE):
		if _popup_active[slot] == 0:
			continue
		var age: float = (now - _popup_t0[slot]) / 1000.0
		if age >= POPUP_LIFETIME:
			_labels[slot].visible = false
			_popup_active[slot] = 0
			continue
		var l := _labels[slot]
		l.position = Vector2(_popup_start_x[slot], _popup_start_y[slot] - POPUP_RISE * age)
		l.modulate.a = 1.0 - age
