class_name CharLooks extends RefCounted
## Character appearance composition: builds looks from catalog pieces.

const BASE := "res://assets/art/chars/"
const SHEET := Vector2i(48, 64)
const FRAME := 16
enum Tint { NONE = 0, FACTION = 1, GREY = 2 }
const GREY_TINT := Color(0.62, 0.64, 0.68)
const NATURAL_SKINS := ["light", "medium", "dark", "black"]
const FANTASY_SKINS := ["blue", "green", "purple", "red", "yellow", "white"]
const FEMALE_ONLY := ["_bikini_", "_dress_", "_pinafore_", "_summer_skirt_"]

static var _catalog: Dictionary = {}


## Path to body piece (format: "pieces/Bodies/chara_body_<build>_<skin>.png").
static func body_path(build: String, skin: String) -> String:
	return "pieces/Bodies/chara_body_%s_%s.png" % [build, skin]


## Path to clothing piece (format: "pieces/Clothing/<build>_body/<name>.png").
static func clothing_path(build: String, name: String) -> String:
	return "pieces/Clothing/%s_body/%s.png" % [build, name]


## Path to hair piece (format: "pieces/Hair/<build>_body/<name>.png").
static func hair_path(build: String, name: String) -> String:
	return "pieces/Hair/%s_body/%s.png" % [build, name]


## Path to headgear piece (format: "pieces/Headgear/<name>.png").
static func headgear_path(name: String) -> String:
	return "pieces/Headgear/%s.png" % name


## Path to other piece (format: "pieces/Other/<name>.png").
static func other_path(name: String) -> String:
	return "pieces/Other/%s.png" % name


## Load catalog from JSON file, caching the result.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var file_path := BASE + "catalog.json"
		if ResourceLoader.exists(file_path):
			var content: String = FileAccess.get_file_as_string(file_path)
			var parsed = JSON.parse_string(content)
			if parsed is Dictionary:
				_catalog = parsed
		else:
			_catalog = {}
	return _catalog


## Filter names by build. "dainty" → names containing "_dainty_" or ending with "_dainty".
## Other builds → names containing neither.
static func for_build(names: Array, build: String) -> Array:
	var result: Array = []
	if build == "dainty":
		for name in names:
			var s: String = name
			if "_dainty_" in s or s.ends_with("_dainty"):
				result.append(name)
	else:
		for name in names:
			var s: String = name
			if not ("_dainty_" in s or s.ends_with("_dainty")):
				result.append(name)
	return result


## Rect of one frame in the sheet (3 cols x 4 rows of 16x16).
static func frame_rect(facing: int, frame: int) -> Rect2i:
	return Rect2i(frame * 16, facing * 16, 16, 16)


## Generic warrior: average build, male, medium skin, red tunic, grey helmet.
static func generic_warrior() -> Dictionary:
	return {
		"build": "average",
		"sex": "m",
		"layers": [
			[body_path("average", "medium"), Tint.NONE],
			[clothing_path("average", "average_tunic_red"), Tint.FACTION],
			[headgear_path("helmet_normal"), Tint.GREY],
		]
	}


## Random hero with deterministic RNG sequence.
## // UNDECIDED: if facial or extra pools are empty (e.g., from catalog filtering),
## randi_range is only called if pool.size() > 0. Contract says "every step always draws"
## but randi_range(0, -1) is invalid. Implementation assumes pools are non-empty or
## handles gracefully by skipping the draw if pool is empty.
static func random_hero(rng: RandomNumberGenerator, sex: String) -> Dictionary:
	var cat: Dictionary = catalog()

	# Step 1: build
	var build: String = cat["builds"][rng.randi_range(0, 2)]

	# Step 2: skin
	var natural: bool = rng.randf() < 0.85
	var skin_pool: Array = NATURAL_SKINS if natural else FANTASY_SKINS
	var skin: String = skin_pool[rng.randi_range(0, skin_pool.size() - 1)]

	# Step 3: clothing
	var clothing_pool: Array = cat["clothing"][build]
	if sex == "m":
		# Remove female-only items
		var filtered: Array = []
		for item in clothing_pool:
			var s: String = item
			var is_female_only: bool = false
			for keyword in FEMALE_ONLY:
				if keyword in s:
					is_female_only = true
					break
			if not is_female_only:
				filtered.append(item)
		clothing_pool = filtered
	var clothing: String = clothing_pool[rng.randi_range(0, clothing_pool.size() - 1)]

	# Step 4: hair
	var hair: String = cat["hair"][build][rng.randi_range(0, cat["hair"][build].size() - 1)]

	# Step 5: headgear
	var has_head: bool = rng.randf() < 0.5
	var hg_pool: Array = for_build(cat["headgear"], build)
	var hg: String = ""
	if has_head:
		hg = hg_pool[rng.randi_range(0, hg_pool.size() - 1)]

	# Step 6: facial hair (beard/moustache)
	var has_face: bool = rng.randf() < 0.35
	var face_pool: Array = []
	for item in cat["other"]:
		var s: String = item
		if s.begins_with("beard") or s.begins_with("moustache"):
			face_pool.append(item)
	face_pool = for_build(face_pool, build)
	var face: String = ""
	if face_pool.size() > 0:
		var face_pick: int = rng.randi_range(0, face_pool.size() - 1)
		if has_face:
			face = face_pool[face_pick]

	# Step 7: extra (non-crown, non-facial)
	var has_extra: bool = rng.randf() < 0.15
	var extra_pool: Array = []
	for item in cat["other"]:
		var s: String = item
		if not (s.begins_with("beard") or s.begins_with("moustache") or s.begins_with("crown")):
			extra_pool.append(item)
	extra_pool = for_build(extra_pool, build)
	var extra: String = ""
	if extra_pool.size() > 0:
		var extra_pick: int = rng.randi_range(0, extra_pool.size() - 1)
		if has_extra:
			extra = extra_pool[extra_pick]

	# Build layers: body, clothing, hair, facial (if has_face), headgear (if has_head), extra (if has_extra)
	var layers: Array = [
		[body_path(build, skin), Tint.NONE],
		[clothing_path(build, clothing), Tint.NONE],
		[hair_path(build, hair), Tint.NONE],
	]

	if has_face and face != "":
		layers.append([other_path(face), Tint.NONE])

	if has_head and hg != "":
		layers.append([headgear_path(hg), Tint.NONE])

	if has_extra and extra != "":
		layers.append([other_path(extra), Tint.NONE])

	return {
		"build": build,
		"sex": sex,
		"layers": layers
	}


## Tint an image by luminance scaling.
static func tinted(img: Image, c: Color) -> Image:
	var result: Image = img.duplicate()
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var pixel: Color = result.get_pixel(x, y)
			if pixel.a > 0:
				var l: float = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
				var k: float = clampf(l * 1.6, 0.0, 1.0)
				var new_color := Color(k * c.r, k * c.g, k * c.b, pixel.a)
				result.set_pixel(x, y, new_color)
	return result


## Load a piece image from a path.
static func load_piece(path: String) -> Image:
	var tex: Texture2D = load(BASE + path)
	if tex == null:
		return null

	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Compose a look into a single image with faction tinting applied.
static func compose(look: Dictionary, faction: Color) -> Image:
	var result: Image = Image.create_empty(48, 64, false, Image.FORMAT_RGBA8)

	var layers: Array = look["layers"]
	for layer in layers:
		var piece_path: String = layer[0]
		var tint_type: int = layer[1]

		var img: Image = load_piece(piece_path)
		if img == null:
			continue

		match tint_type:
			Tint.FACTION:
				img = tinted(img, faction)
			Tint.GREY:
				img = tinted(img, GREY_TINT)
			# Tint.NONE: use as is

		result.blend_rect(img, Rect2i(0, 0, 48, 64), Vector2i.ZERO)

	return result
