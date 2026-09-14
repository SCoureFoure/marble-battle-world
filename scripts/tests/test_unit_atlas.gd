extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. slot_origin(0) == Vector2i(0, 0)
	t.check(UnitAtlas.slot_origin(0) == Vector2i(0, 0), "case1 slot_origin(0)")

	# 2. slot_origin(5) == Vector2i(48, 64)
	t.check(UnitAtlas.slot_origin(5) == Vector2i(48, 64), "case2 slot_origin(5)")

	# 3. slot_origin(15) == Vector2i(144, 192)
	t.check(UnitAtlas.slot_origin(15) == Vector2i(144, 192), "case3 slot_origin(15)")

	# 4. build_image size is 192x256
	var img := UnitAtlas.build_image([Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.9)])
	t.check(img.get_size() == Vector2i(192, 256), "case4 build_image size")

	# 5. slot 0 region has at least one pixel with alpha > 0
	var slot0_region: Image = img.get_region(Rect2i(0, 0, 48, 64))
	var slot0_has_alpha: bool = false
	for y in range(slot0_region.get_height()):
		for x in range(slot0_region.get_width()):
			var pixel: Color = slot0_region.get_pixel(x, y)
			if pixel.a > 0:
				slot0_has_alpha = true
				break
		if slot0_has_alpha:
			break
	t.check(slot0_has_alpha, "case5 slot0 has alpha")

	# 6. slot 0 and slot 1 regions differ
	var slot1_region: Image = img.get_region(Rect2i(48, 0, 48, 64))
	t.check(slot0_region.get_data() != slot1_region.get_data(), "case6 slot0 slot1 differ")

	# 7. slot 2 region is fully transparent
	var slot2_region: Image = img.get_region(Rect2i(96, 0, 48, 64))
	var slot2_all_transparent: bool = true
	for y in range(slot2_region.get_height()):
		for x in range(slot2_region.get_width()):
			var pixel: Color = slot2_region.get_pixel(x, y)
			if pixel.a > 0:
				slot2_all_transparent = false
				break
		if not slot2_all_transparent:
			break
	t.check(slot2_all_transparent, "case7 slot2 fully transparent")

	# 8. rows_for
	t.check(UnitAtlas.rows_for(0) == 4 and UnitAtlas.rows_for(1) == 5 and UnitAtlas.rows_for(4) == 5 and UnitAtlas.rows_for(5) == 6, "case8 rows_for")

	# 9. build_image with a hero: size and hero slot has alpha
	var hero_img := UnitAtlas.build_image([Color(0.85, 0.2, 0.2)], [CharLooks.generic_warrior()])
	t.check(hero_img.get_size() == Vector2i(192, 320), "case9 build_image with hero size")
	var hero_region: Image = hero_img.get_region(Rect2i(0, 256, 48, 64))
	var hero_has_alpha: bool = false
	for y in range(hero_region.get_height()):
		for x in range(hero_region.get_width()):
			var pixel: Color = hero_region.get_pixel(x, y)
			if pixel.a > 0:
				hero_has_alpha = true
				break
		if hero_has_alpha:
			break
	t.check(hero_has_alpha, "case9 hero slot has alpha")

	t.finish()
	quit()
