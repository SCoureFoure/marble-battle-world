extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()
	t.check(true, "true passes")
	t.check(t.approx(1.0, 1.00001), "approx within eps")
	t.check(not t.approx(1.0, 1.1), "approx outside eps")
	var inner := TestKit.new()
	inner.check(false, "inner deliberate fail")
	t.check(inner.fails == 1 and inner.count == 1, "kit counts a failure")
	t.finish()
	quit()
