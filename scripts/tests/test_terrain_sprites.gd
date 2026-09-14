extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	t.check(TerrainLayer.sprite_path(TerrainGrid.Kind.ROCK, 0) == "res://assets/art/rpg/rock_1.png", "TerrainLayer.sprite_path(TerrainGrid.Kind.ROCK, 0) == \"res://assets/art/rpg/rock_1.png\"")
	t.check(TerrainLayer.sprite_path(TerrainGrid.Kind.ROCK, 7) == "res://assets/art/rpg/rock_2.png", "TerrainLayer.sprite_path(TerrainGrid.Kind.ROCK, 7) == \"res://assets/art/rpg/rock_2.png\"")
	t.check(TerrainLayer.sprite_path(TerrainGrid.Kind.TOWER, 99) == "res://assets/art/rpg/column_tall.png", "TerrainLayer.sprite_path(TerrainGrid.Kind.TOWER, 99) == \"res://assets/art/rpg/column_tall.png\"")
	t.check(TerrainLayer.sprite_path(TerrainGrid.Kind.PLAIN, 3) == "", "TerrainLayer.sprite_path(TerrainGrid.Kind.PLAIN, 3) == \"\"")
	t.check(TerrainLayer.decorates(TerrainGrid.Kind.WATER, 0) == true, "TerrainLayer.decorates(TerrainGrid.Kind.WATER, 0) == true")
	t.check(TerrainLayer.decorates(TerrainGrid.Kind.WATER, 1) == false, "TerrainLayer.decorates(TerrainGrid.Kind.WATER, 1) == false")
	t.check(TerrainLayer.decorates(TerrainGrid.Kind.WATER, 3) == true, "TerrainLayer.decorates(TerrainGrid.Kind.WATER, 3) == true")
	t.check(TerrainLayer.decorates(TerrainGrid.Kind.ROCK, 1) == true, "TerrainLayer.decorates(TerrainGrid.Kind.ROCK, 1) == true")
	t.check(TerrainLayer.decorates(TerrainGrid.Kind.PLAIN, 0) == false, "TerrainLayer.decorates(TerrainGrid.Kind.PLAIN, 0) == false")

	# Check every sprite file exists
	var all_exist := true
	for kind_key in TerrainLayer.SPRITES:
		var file_list = TerrainLayer.SPRITES[kind_key]
		for file_name in file_list:
			if not ResourceLoader.exists(TerrainLayer.ART + file_name):
				all_exist = false
	t.check(all_exist, "every sprite file exists")

	# Draw smoke test
	var g := TerrainGrid.new()
	g.setup(Rect2(0, 0, 400, 200), Tuning.TERRAIN_CELL)
	for i in range(10):
		var kind = [TerrainGrid.Kind.MUD, TerrainGrid.Kind.COBBLE, TerrainGrid.Kind.ICE, TerrainGrid.Kind.WATER, TerrainGrid.Kind.ROCK, TerrainGrid.Kind.TREE, TerrainGrid.Kind.TOWER, TerrainGrid.Kind.FIRE, TerrainGrid.Kind.SPIKE, TerrainGrid.Kind.FLOWERS][i]
		g.set_cell(i, 0, kind)
	g.finalize()
	var layer := TerrainLayer.new()
	layer.grid = g
	var tex := layer._texture(TerrainLayer.sprite_path(TerrainGrid.Kind.ROCK, 0))
	t.check(tex != null and tex.get_width() > 0, "draw smoke: texture loads and has width")
	layer.free()

	t.finish()
	quit()
