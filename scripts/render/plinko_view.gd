class_name PlinkoView
extends CanvasLayer
## Overworld plinko drop animation viewer. Source: docs/ARCHITECTURE.md §12.6,
## .warboss-horde/slices/m4-render.md.
##
## `World.plinko_log` entries are appended by `WorldSim` per the m4-hookup
## slice's fiat shape `[stack, slots, lines, path, pegs, slot_order]` (the
## inline comment on `World.plinko_log` itself only documents the first three
## fields; `path`/`pegs`/`slot_order` are needed to animate here and are read
## from indices 3/4/5). If a shorter (pre-hookup) entry ever lands, this view
## simply skips the board draw for it (see `_draw_board`).

enum Phase { NONE = 0, DROP = 1, OUTCOME = 2 }

const VIEW_W := 180.0
const VIEW_H := 240.0
const BOARD_SCALE := 0.5
const BALL_DROP_TIME := 2.0
const OUTCOME_TIME := 3.0
const PEG_COLOR := Color(0.3, 0.3, 0.3)
const BALL_COLOR := Color(0.9, 0.2, 0.2)
const SLOT_BOX_COLOR := Color(0.15, 0.15, 0.15)
const TEXT_COLOR := Color(0.95, 0.95, 0.9)

# Index = Plinko.Slot enum value (SETTLE..CURSE).
const SLOT_LABELS := ["SET", "REC", "RAI", "RAZ", "FOR", "DRI", "HER", "HEI", "CUR"]

var world: World

var _board: _Board
var _last_log_size: int = 0
var _entry: Array = []
var _phase: int = Phase.NONE
var _phase_t: float = 0.0


func build(w: World) -> void:
	world = w
	_last_log_size = world.plinko_log.size()

	_board = _Board.new()
	_board.view = self
	_board.name = "PlinkoBoard"
	add_child(_board)

	_position_board()


func _position_board() -> void:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	_board.position = Vector2(0.0, size.y - VIEW_H)
	_board.size = Vector2(VIEW_W, VIEW_H)


func _process(delta: float) -> void:
	if world == null or _board == null:
		return

	var size := world.plinko_log.size()
	if size > _last_log_size:
		_last_log_size = size
		_entry = world.plinko_log[size - 1]
		_phase = Phase.DROP
		_phase_t = 0.0

	if _phase == Phase.NONE:
		return

	_phase_t += delta
	if _phase == Phase.DROP and _phase_t >= BALL_DROP_TIME:
		_phase = Phase.OUTCOME
		_phase_t = 0.0
	elif _phase == Phase.OUTCOME and _phase_t >= OUTCOME_TIME:
		_phase = Phase.NONE
		_phase_t = 0.0
		_entry = []

	_board.queue_redraw()


func _draw_board(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(BOARD_SCALE, BOARD_SCALE))

	if _entry.size() < 6:
		return

	var pegs: PackedVector2Array = _entry[4]
	var order: PackedInt32Array = _entry[5]

	for peg in pegs:
		ci.draw_circle(peg, 3.0, PEG_COLOR)

	var sw: float = Tuning.PLINKO_W / Tuning.PLINKO_SLOTS
	var band_y: float = Tuning.PLINKO_H - Tuning.PLINKO_SLOT_BAND
	for k in range(order.size()):
		var rect := Rect2(k * sw, band_y, sw, Tuning.PLINKO_SLOT_BAND)
		ci.draw_rect(rect, SLOT_BOX_COLOR, false, 1.0)
		var label: String = SLOT_LABELS[order[k]]
		ci.draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 4.0, rect.position.y + 16.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)

	if _phase == Phase.DROP:
		var path: PackedVector2Array = _entry[3]
		if path.size() > 0:
			var frac: float = clampf(_phase_t / BALL_DROP_TIME, 0.0, 1.0)
			var fpos: float = frac * float(path.size() - 1)
			var i0: int = int(floor(fpos))
			var i1: int = mini(i0 + 1, path.size() - 1)
			var lt: float = fpos - float(i0)
			var ball_pos: Vector2 = path[i0].lerp(path[i1], lt)
			ci.draw_circle(ball_pos, Tuning.PLINKO_BALL_R, BALL_COLOR)
	elif _phase == Phase.OUTCOME:
		var lines: Array = _entry[2]
		for li in range(lines.size()):
			ci.draw_string(ThemeDB.fallback_font, Vector2(8.0, 60.0 + li * 18.0), str(lines[li]),
				HORIZONTAL_ALIGNMENT_LEFT, int(Tuning.PLINKO_W) - 16, 14, TEXT_COLOR)


## Plain Control so `_draw()` can be overridden directly (CanvasLayer itself
## has no drawing surface).
class _Board extends Control:
	var view   # PlinkoView; untyped to avoid a self-referential class_name lookup inside this nested class.

	func _draw() -> void:
		if view != null:
			view._draw_board(self)
