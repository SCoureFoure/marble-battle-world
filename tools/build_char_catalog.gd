extends SceneTree
## Build character catalog from pieces folder.

func _init() -> void:
	var pieces_path: String = "res://assets/art/chars/pieces/"

	# Build lists
	var builds: Array = ["average", "dainty", "heavy"]
	var skins: Array[String] = []
	var clothing: Dictionary = {}
	var hair: Dictionary = {}
	var headgear: Array[String] = []
	var other: Array[String] = []

	# Extract skins from Bodies folder (chara_body_average_<skin>.png pattern)
	var bodies_path: String = pieces_path + "Bodies/"
	var bodies_dir: DirAccess = DirAccess.open(bodies_path)
	if bodies_dir == null:
		print("CATALOG_FAIL ", bodies_path)
		quit(1)
		return

	bodies_dir.list_dir_begin()
	var file: String = bodies_dir.get_next()
	while file != "":
		if file.ends_with(".png"):
			# Pattern: chara_body_average_<skin>.png
			if file.begins_with("chara_body_average_"):
				var basename: String = file.trim_suffix(".png")
				var prefix: String = "chara_body_average_"
				if basename.length() > prefix.length():
					var skin: String = basename.substr(prefix.length())
					if skin not in skins:
						skins.append(skin)
		file = bodies_dir.get_next()

	skins.sort()

	# Extract clothing for each build
	for build in builds:
		var clothing_path: String = pieces_path + "Clothing/" + build + "_body/"
		var clothing_dir: DirAccess = DirAccess.open(clothing_path)
		if clothing_dir == null:
			print("CATALOG_FAIL ", clothing_path)
			quit(1)
			return

		var items: Array[String] = []
		clothing_dir.list_dir_begin()
		var item: String = clothing_dir.get_next()
		while item != "":
			if item.ends_with(".png"):
				var name: String = item.trim_suffix(".png")
				items.append(name)
			item = clothing_dir.get_next()

		items.sort()
		clothing[build] = items

	# Extract hair for each build
	for build in builds:
		var hair_path: String = pieces_path + "Hair/" + build + "_body/"
		var hair_dir: DirAccess = DirAccess.open(hair_path)
		if hair_dir == null:
			print("CATALOG_FAIL ", hair_path)
			quit(1)
			return

		var items: Array[String] = []
		hair_dir.list_dir_begin()
		var item: String = hair_dir.get_next()
		while item != "":
			if item.ends_with(".png"):
				var name: String = item.trim_suffix(".png")
				items.append(name)
			item = hair_dir.get_next()

		items.sort()
		hair[build] = items

	# Extract headgear
	var headgear_path: String = pieces_path + "Headgear/"
	var headgear_dir: DirAccess = DirAccess.open(headgear_path)
	if headgear_dir == null:
		print("CATALOG_FAIL ", headgear_path)
		quit(1)
		return

	headgear_dir.list_dir_begin()
	var item: String = headgear_dir.get_next()
	while item != "":
		if item.ends_with(".png"):
			var name: String = item.trim_suffix(".png")
			headgear.append(name)
		item = headgear_dir.get_next()

	headgear.sort()

	# Extract other
	var other_path: String = pieces_path + "Other/"
	var other_dir: DirAccess = DirAccess.open(other_path)
	if other_dir == null:
		print("CATALOG_FAIL ", other_path)
		quit(1)
		return

	other_dir.list_dir_begin()
	var file2: String = other_dir.get_next()
	while file2 != "":
		if file2.ends_with(".png"):
			var name: String = file2.trim_suffix(".png")
			other.append(name)
		file2 = other_dir.get_next()

	other.sort()

	# Build and write catalog
	var catalog: Dictionary = {
		"builds": builds,
		"skins": skins,
		"clothing": clothing,
		"hair": hair,
		"headgear": headgear,
		"other": other
	}

	var output_path: String = "res://assets/art/chars/catalog.json"
	var f: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if f == null:
		print("CATALOG_FAIL ", output_path)
		quit(1)
		return

	f.store_string(JSON.stringify(catalog, "\t"))

	# Print success message
	var a: int = clothing["average"].size()
	var d: int = clothing["dainty"].size()
	var h: int = clothing["heavy"].size()
	var ha: int = hair["average"].size()
	var hd: int = hair["dainty"].size()
	var hh: int = hair["heavy"].size()

	print("CATALOG_OK skins=%d clothing=%d/%d/%d hair=%d/%d/%d headgear=%d other=%d" % [
		skins.size(), a, d, h, ha, hd, hh, headgear.size(), other.size()
	])

	quit()
