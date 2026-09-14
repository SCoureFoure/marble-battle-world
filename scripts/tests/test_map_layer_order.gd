extends SceneTree
## Tests for MapLayer child ordering and show_behind_parent. See .warboss-horde/slices/map-town-visibility.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	var w := World.create(42)
	var ml := MapLayer.new()
	root.add_child(ml)
	ml.build(w)

	# 1. MapSprite exists and is a Sprite2D.
	t.check(ml.get_node("MapSprite") is Sprite2D, "MapSprite is Sprite2D")

	# 2. MapSprite has show_behind_parent == true.
	t.check((ml.get_node("MapSprite") as Sprite2D).show_behind_parent == true, "MapSprite.show_behind_parent == true")

	# 3. OwnerOverlaySprite has show_behind_parent == true.
	t.check((ml.get_node("OwnerOverlaySprite") as Sprite2D).show_behind_parent == true, "OwnerOverlaySprite.show_behind_parent == true")

	# 4. MapSprite is before OwnerOverlaySprite in child order.
	t.check(ml.get_node("MapSprite").get_index() < ml.get_node("OwnerOverlaySprite").get_index(), "MapSprite index < OwnerOverlaySprite index")

	# 5. Second build keeps exactly 2 children with both flags still true.
	ml.build(w)
	t.check(ml.get_child_count() == 2, "exactly 2 children after second build")
	t.check((ml.get_node("MapSprite") as Sprite2D).show_behind_parent == true, "MapSprite.show_behind_parent still true after second build")
	t.check((ml.get_node("OwnerOverlaySprite") as Sprite2D).show_behind_parent == true, "OwnerOverlaySprite.show_behind_parent still true after second build")

	# 6. Town glyph sizes are correct.
	t.check(MapLayer.TOWN_SQUARE_SIZE == 18.0, "MapLayer.TOWN_SQUARE_SIZE == 18.0")
	t.check(MapLayer.TOWN_ROOF_HEIGHT == 10.0, "MapLayer.TOWN_ROOF_HEIGHT == 10.0")
	t.check(MapLayer.TOWN_OUTLINE_WIDTH == 2.0, "MapLayer.TOWN_OUTLINE_WIDTH == 2.0")

	ml.free()

	t.finish()
	quit()
