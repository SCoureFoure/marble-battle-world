extends SceneTree
## World scene UI helpers: left-drag threshold, camera clamp, panel toggle.
## Source: .warboss-horde/slices/world-scene-ui.md. Layout is judged by capture.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()
	var S: GDScript = load("res://scripts/world_scene.gd")
	t.check(S != null and S.can_instantiate(), "0: world_scene loads")

	# 1. is_drag: strictly greater than 6 px
	t.check(S.is_drag(Vector2(0, 0), Vector2(6, 0)) == false, "1a: exactly 6 px is a click")
	t.check(S.is_drag(Vector2(0, 0), Vector2(5, 5)) == true, "1b: 7.07 px is a drag")
	t.check(S.is_drag(Vector2(10, 10), Vector2(10, 10)) == false, "1c: no motion")

	# 2. clamp_to_map
	var ms := Vector2(640, 480)
	t.check(S.clamp_to_map(Vector2(-10, 500), ms) == Vector2(0, 480), "2a: clamps both axes")
	t.check(S.clamp_to_map(Vector2(300, 200), ms) == Vector2(300, 200), "2b: inside unchanged")
	t.check(S.clamp_to_map(Vector2(700, -1), ms) == Vector2(640, 0), "2c: clamps other corners")

	# 3. set_panels_visible
	var a := CanvasLayer.new()
	var b := CanvasLayer.new()
	S.set_panels_visible([a, null, b], false)
	t.check(a.visible == false and b.visible == false, "3a: hide, null skipped")
	S.set_panels_visible([a, b], true)
	t.check(a.visible == true and b.visible == true, "3b: show")
	a.free()
	b.free()

	# 4. constants
	t.check(S.DRAG_THRESHOLD == 6.0, "4a: DRAG_THRESHOLD")
	t.check(S.TIME_CONTROLS_POS == Vector2(8, 28), "4b: TIME_CONTROLS_POS")

	t.finish()
	quit()
