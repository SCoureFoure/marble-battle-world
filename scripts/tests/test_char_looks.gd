extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. catalog builds size
	t.check(CharLooks.catalog()["builds"].size() == 3, "case1 builds size")

	# 2. skins has medium
	t.check((CharLooks.catalog()["skins"] as Array).has("medium"), "case2 skins has medium")

	# 3. average clothing has average_tunic_red
	t.check((CharLooks.catalog()["clothing"]["average"] as Array).has("average_tunic_red"), "case3 average tunic red")

	# 4. headgear has helmet_normal
	t.check((CharLooks.catalog()["headgear"] as Array).has("helmet_normal"), "case4 headgear has helmet_normal")

	# 5. for_build dainty filter
	var dainty_names := CharLooks.for_build(["helmet_normal", "helmet_dainty_normal", "crown_pointy_dainty"], "dainty")
	t.check(dainty_names == ["helmet_dainty_normal", "crown_pointy_dainty"], "case5 for_build dainty")

	# 6. for_build heavy filter (excludes dainty)
	var heavy_names := CharLooks.for_build(["helmet_normal", "helmet_dainty_normal", "crown_pointy_dainty"], "heavy")
	t.check(heavy_names == ["helmet_normal"], "case6 for_build heavy")

	# 7. frame_rect(2, 1)
	t.check(CharLooks.frame_rect(2, 1) == Rect2i(16, 32, 16, 16), "case7 frame_rect")

	# 8. generic_warrior layers and tints
	var generic := CharLooks.generic_warrior()
	var generic_layers: Array = generic["layers"]
	var generic_tints: Array = []
	for layer in generic_layers:
		generic_tints.append(layer[1])
	t.check(generic_layers.size() == 3, "case8 generic layers count")
	t.check(generic_tints == [0, 1, 2], "case8 generic tints")

	# 9. generic_warrior layer paths exist
	var generic_paths_exist := true
	for layer in generic_layers:
		var path: String = layer[0]
		if not ResourceLoader.exists(CharLooks.BASE + path):
			generic_paths_exist = false
			break
	t.check(generic_paths_exist, "case9 generic layer paths exist")

	# 10. compose size
	var composed_red := CharLooks.compose(generic, Color(0.85, 0.2, 0.2))
	t.check(composed_red.get_size() == Vector2i(48, 64), "case10 compose size")

	# 11. compose differs with different faction colors
	var composed_blue := CharLooks.compose(generic, Color(0.2, 0.4, 0.9))
	t.check(composed_red.get_data() != composed_blue.get_data(), "case11 compose differs by faction")

	# 12. determinism with seed 5
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 5
	var hero1 := CharLooks.random_hero(rng1, "m")

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var hero2 := CharLooks.random_hero(rng2, "m")

	t.check(hero1 == hero2, "case12 determinism seed 5")

	# 13. layer paths for seeds 0..49 (sex "f") all exist
	var female_paths_exist := true
	for seed in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hero := CharLooks.random_hero(rng, "f")
		var layers: Array = hero["layers"]
		for layer in layers:
			var path: String = layer[0]
			if not ResourceLoader.exists(CharLooks.BASE + path):
				female_paths_exist = false
				break
		if not female_paths_exist:
			break
	t.check(female_paths_exist, "case13 random_hero female paths exist seeds 0-49")

	# 14. seeds 0..199 with sex "m": no FEMALE_ONLY keyword
	var male_no_female := true
	for seed in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hero := CharLooks.random_hero(rng, "m")
		var layers: Array = hero["layers"]
		for layer in layers:
			var path: String = layer[0]
			for keyword in CharLooks.FEMALE_ONLY:
				if keyword in path:
					male_no_female = false
					break
			if not male_no_female:
				break
		if not male_no_female:
			break
	t.check(male_no_female, "case14 male heroes no female keywords seeds 0-199")

	# 15. seeds 0..399 with sex "f": at least one has FEMALE_ONLY keyword
	var female_has_keyword := false
	for seed in range(400):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hero := CharLooks.random_hero(rng, "f")
		var layers: Array = hero["layers"]
		for layer in layers:
			var path: String = layer[0]
			for keyword in CharLooks.FEMALE_ONLY:
				if keyword in path:
					female_has_keyword = true
					break
			if female_has_keyword:
				break
		if female_has_keyword:
			break
	t.check(female_has_keyword, "case15 female heroes have female keywords seeds 0-399")

	# 16. seeds 0..399, both sexes: no "crown"
	var no_crowns := true
	for seed in range(400):
		for sex in ["m", "f"]:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var hero := CharLooks.random_hero(rng, sex)
			var layers: Array = hero["layers"]
			for layer in layers:
				var path: String = layer[0]
				if "crown" in path:
					no_crowns = false
					break
			if not no_crowns:
				break
		if not no_crowns:
			break
	t.check(no_crowns, "case16 no crowns seeds 0-399 both sexes")

	# 17. seeds 0..49: first layer body matches build
	var bodies_match_build := true
	for seed in range(50):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var hero := CharLooks.random_hero(rng, "f")
		var build: String = hero["build"]
		var layers: Array = hero["layers"]
		var first_path: String = layers[0][0]
		var expected_start := "pieces/Bodies/chara_body_" + build
		if not first_path.begins_with(expected_start):
			bodies_match_build = false
			break
	t.check(bodies_match_build, "case17 first layer body matches build seeds 0-49")

	t.finish()
	quit()
