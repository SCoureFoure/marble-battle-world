extends SceneTree

const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# World helper
	var w := World.new()
	w.setup_blank(12, 8, 7)
	w.faction_count = 1
	w.faction_alive[0] = 1
	w.faction_names = ["Alpha"]

	# 1. u = w.units.add(0, 1, 1, true, -1); Lineage.make_captain(w, u, "Toby") → w.units.looks.has(u)
	var u: int = w.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w, u, "Toby")
	t.check(w.units.looks.has(u), "1: Lineage.make_captain sets a look")

	# 2. that look has keys build, sex, layers and (look["layers"] as Array).size() >= 3
	var look: Dictionary = w.units.looks[u]
	var layers: Array = look.get("layers", []) as Array
	t.check(look.has("build") and look.has("sex") and look.has("layers") and layers.size() >= 3, "2: look has keys and layers.size() >= 3")

	# 3. calling Looks.ensure(w, u) again leaves w.units.looks[u] equal to the saved copy
	var saved_look: Dictionary = look.duplicate(true)
	Looks.ensure(w, u)
	t.check(w.units.looks[u] == saved_look, "3: Looks.ensure is idempotent")

	# 4. RNG isolation: w.rng.state unchanged by make_captain calls
	var w2 := World.new()
	w2.setup_blank(12, 8, 7)
	w2.faction_count = 1
	w2.faction_alive[0] = 1
	w2.faction_names = ["Alpha"]
	var st_before: int = w2.rng.state
	var v: int = w2.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w2, v, "Toby")
	t.check(w2.rng.state == st_before, "4: RNG isolation - w.rng.state unchanged")

	# 5. Heroes.promote(w, v) for a fresh non-captain unit v → w.units.looks.has(v)
	var w3 := World.new()
	w3.setup_blank(12, 8, 7)
	w3.faction_count = 1
	w3.faction_alive[0] = 1
	w3.faction_names = ["Alpha"]
	var c: Vector2 = w3.map.center_of(2, 2)
	var sid: int = w3.stacks.add(0, c.x, c.y, "S")
	var fresh_unit: int = w3.units.add(0, 0, 0, false, sid)
	Heroes.promote(w3, fresh_unit)
	t.check(w3.units.looks.has(fresh_unit), "5: Heroes.promote sets a look")

	# 6. determinism: two fresh blank worlds built identically, same unit ids and w.time, Looks.seed_for equal and the resulting looks[u] equal
	var w4a := World.new()
	w4a.setup_blank(12, 8, 7)
	w4a.faction_count = 1
	w4a.faction_alive[0] = 1
	w4a.faction_names = ["Alpha"]
	var u4a: int = w4a.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w4a, u4a, "Toby")

	var w4b := World.new()
	w4b.setup_blank(12, 8, 7)
	w4b.faction_count = 1
	w4b.faction_alive[0] = 1
	w4b.faction_names = ["Alpha"]
	var u4b: int = w4b.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w4b, u4b, "Toby")

	var seed_4a: int = Looks.seed_for(w4a, u4a)
	var seed_4b: int = Looks.seed_for(w4b, u4b)
	t.check(seed_4a == seed_4b and w4a.units.looks[u4a] == w4b.units.looks[u4b], "6: determinism - seed and looks equal across identical worlds")

	# 7. World.create(1): every unit with is_captain == 1 and alive == 1 has an entry in looks
	var w7 := World.create(1)
	var all_captains_have_looks := true
	for uid in range(w7.units.n):
		if w7.units.is_captain[uid] == 1 and w7.units.alive[uid] == 1:
			if not w7.units.looks.has(uid):
				all_captains_have_looks = false
				break
	t.check(all_captains_have_looks, "7: World.create - all captains have looks")

	# 8. save/load round-trip
	const SAVE_PATH := "user://test_looks.bin"
	var w8 := World.new()
	w8.setup_blank(12, 8, 7)
	w8.faction_count = 1
	w8.faction_alive[0] = 1
	w8.faction_names = ["Alpha"]
	var u8: int = w8.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w8, u8, "Toby")

	var save_ok: bool = SaveGame.save(w8, SAVE_PATH) == OK
	var w8_loaded := SaveGame.load(SAVE_PATH)
	var loaded_ok: bool = w8_loaded != null
	var sizes_match: bool = loaded_ok and w8_loaded.units.looks.size() == w8.units.looks.size()
	var builds_match: bool = false
	if sizes_match and w8.units.looks.size() > 0:
		var first_uid: int = w8.units.looks.keys()[0]
		builds_match = w8_loaded.units.looks[first_uid]["build"] == w8.units.looks[first_uid]["build"]
	t.check(save_ok and loaded_ok and sizes_match and builds_match, "8: save/load round-trip preserves looks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	t.finish()
	quit()
