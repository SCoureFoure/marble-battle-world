extends SceneTree
## Parse-error guard for the M3 world scene scripts (visual, judged by
## screenshot — see .warboss-horde/slices/m3-world-scene.md).

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	var paths := [
		"res://scripts/world_scene.gd",
		"res://scripts/render/map_layer.gd",
		"res://scripts/render/stack_layer.gd",
		"res://scripts/render/battle_view.gd",
		"res://scripts/render/ledger_panel.gd",
		"res://scripts/render/plinko_view.gd",
	]
	for p in paths:
		var script: GDScript = load(p)
		t.check(script is GDScript and script.can_instantiate(), "%s loads and can_instantiate" % p)

	t.finish()
	quit()
