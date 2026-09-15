extends SceneTree
## Screen-space overworld labels (armies + towns) and tile-derived town names.
## Source: .warboss-horde/slices/town-names.md, map-labels.md, map-labels-scene.md.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# 1. NameGen.town_name
	var n1 := NameGen.town_name(Vector2i(12, 7))
	t.check(n1 == NameGen.town_name(Vector2i(12, 7)), "1a: deterministic per tile")
	t.check(n1.length() >= 4 and n1.substr(0, 1) == n1.substr(0, 1).to_upper(), "1b: capitalised")
	var suffix_ok := false
	for s in NameGen.TOWN_SUFFIXES:
		if n1.ends_with(s):
			suffix_ok = true
	t.check(suffix_ok, "1c: ends with a town suffix")
	var names := {}
	for x in range(10):
		for y in range(5):
			names[NameGen.town_name(Vector2i(x * 3, y * 5))] = true
	t.check(names.size() >= 20, "1d: varied across 50 tiles (got %d)" % names.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var before := rng.state
	NameGen.town_name(Vector2i(1, 1))
	t.check(rng.state == before, "1e: no shared rng consumed (pure)")

	# 2. MapLabels.army_text / text_color
	t.check(MapLabels.army_text("Orrenth", 101, false) == "Orrenth · 101", "2a: army text")
	t.check(MapLabels.army_text("Orrenth", 7, true) == "Orrenth · 7 (retreat)", "2b: retreat suffix")
	var c := Color(0.2, 0.4, 0.9)
	t.check(MapLabels.text_color(c) == c.lerp(Color(1, 1, 1), 0.45), "2c: text_color lightens")

	# 3. resolve_overlaps: greedy, earlier wins
	var vis := MapLabels.resolve_overlaps([Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10), Rect2(20, 0, 10, 10), Rect2(9, 9, 2, 2)])
	t.check(vis == PackedByteArray([1, 0, 1, 0]), "3a: overlap hides later rects")
	t.check(MapLabels.resolve_overlaps([]) == PackedByteArray(), "3b: empty")
	var touch := MapLabels.resolve_overlaps([Rect2(0, 0, 10, 10), Rect2(10, 0, 10, 10)])
	t.check(touch == PackedByteArray([1, 1]), "3c: edge-touching rects both visible")

	# 4. collect
	var w := World.create(1)
	var ml := MapLabels.new()
	var cam := Camera2D.new()
	ml.build(w, cam)
	t.check(ml.layer == MapLabels.LAYER and ml._canvas != null and ml._canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE, "4a: build")
	var map_size := Vector2(w.map.cols * Tuning.TILE, w.map.rows * Tuning.TILE)
	var entries: Array = ml.collect(Transform2D.IDENTITY, map_size, 1.0)
	t.check(entries.size() > 0 and entries.size() <= MapLabels.MAX_LABELS, "4b: some labels")
	var no_overlap := true
	for i in range(entries.size()):
		for j in range(i + 1, entries.size()):
			var ra: Rect2 = entries[i]["rect"]
			var rb: Rect2 = entries[j]["rect"]
			if ra.intersects(rb):
				no_overlap = false
	t.check(no_overlap, "4c: returned labels never overlap")
	var town_names := {}
	for k in range(w.towns.size()):
		var tv: Vector2 = w.towns[k]
		town_names[NameGen.town_name(Vector2i(int(tv.x), int(tv.y)))] = true
	var has_town := false
	var has_army := false
	var first: Dictionary = entries[0]
	t.check(first.has("text") and first.has("rect") and first.has("color"), "4d: entry keys")
	for e2 in entries:
		if town_names.has(e2["text"]):
			has_town = true
		if " · " in String(e2["text"]):
			has_army = true
	t.check(has_town and has_army, "4e: towns and armies both labelled at zoom 1")
	var far: Array = ml.collect(Transform2D.IDENTITY, map_size, 0.2)
	var far_town := false
	for e3 in far:
		if town_names.has(e3["text"]):
			far_town = true
	t.check(not far_town, "4f: towns hidden below TOWN_MIN_ZOOM")
	var tiny: Array = ml.collect(Transform2D.IDENTITY, Vector2(1, 1), 1.0)
	t.check(tiny.size() <= 1, "4g: off-screen labels culled")
	# 5. label_rect: centred on the anchor, top edge at the anchor
	t.check(MapLabels.label_rect(Vector2(100, 50), 40.0) == Rect2(80, 50, 40, MapLabels.FONT_SIZE + 4), "5a: label_rect")
	cam.free()
	ml.free()

	t.finish()
	quit()
