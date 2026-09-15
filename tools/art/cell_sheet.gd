extends SceneTree

const DIGITS: Array = [
	["111","101","101","101","111"], # 0
	["010","110","010","010","111"], # 1
	["111","001","111","100","111"], # 2
	["111","001","111","001","111"], # 3
	["101","101","111","001","001"], # 4
	["111","100","111","001","111"], # 5
	["111","100","111","101","111"], # 6
	["111","001","001","001","001"], # 7
	["111","101","111","101","111"], # 8
	["111","101","111","001","111"], # 9
]

func _draw_number(img: Image, n: int, x: int, y: int, px: int, color: Color) -> void:
	var digits: String = str(n)
	var col_offset: int = 0
	for digit_char in digits:
		var digit: int = int(digit_char)
		if digit >= 0 and digit <= 9:
			var glyph: Array = DIGITS[digit]
			for row: int in range(5):
				for col: int in range(3):
					if glyph[row][col] == "1":
						for i: int in range(px):
							for j: int in range(px):
								var pixel_x: int = x + col_offset + col * px + i
								var pixel_y: int = y + row * px + j
								if pixel_x >= 0 and pixel_y >= 0 and pixel_x < img.get_width() and pixel_y < img.get_height():
									img.set_pixel(pixel_x, pixel_y, color)
		col_offset += 4 * px

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	var spec_path: String = ""
	var out_path: String = ""
	var scale: int = 4

	for arg in args:
		if arg.begins_with("--spec="):
			spec_path = arg.substr(7)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--scale="):
			scale = int(arg.substr(8))

	var spec_text: String = ""
	var spec_file: FileAccess = FileAccess.open(spec_path, FileAccess.READ)
	if spec_file == null:
		printerr("Failed to load spec file: ", spec_path)
		quit(1)
		return

	spec_text = spec_file.get_as_text()
	var spec_data: Variant = JSON.parse_string(spec_text)

	if not spec_data is Array:
		printerr("Spec is not an array")
		quit(1)
		return

	var entries: Array = spec_data as Array

	var S: int = 3 * 16 * scale
	var G: int = 20
	var PER_ROW: int = 8

	var n: int = entries.size()
	var slot_rows: int = (n + PER_ROW - 1) / PER_ROW
	if slot_rows < 1:
		slot_rows = 1

	var img_width: int = G + PER_ROW * (S + G)
	var img_height: int = G + slot_rows * (S + G)

	var img: Image = Image.create(img_width, img_height, false, Image.FORMAT_RGBA8)
	var bg_color: Color = Color(0.15, 0.15, 0.15, 1)

	for py: int in range(img_height):
		for px: int in range(img_width):
			img.set_pixel(px, py, bg_color)

	var image_cache: Dictionary = {}
	var has_error: bool = false

	for entry_idx: int in range(n):
		var entry: Variant = entries[entry_idx]
		if not entry is Dictionary:
			continue

		var entry_dict: Dictionary = entry as Dictionary

		var file_str: String = ""
		var x_coord: int = 0
		var y_coord: int = 0
		var w_size: int = 1
		var h_size: int = 1

		if entry_dict.has("file"):
			file_str = entry_dict["file"]
		if entry_dict.has("x"):
			x_coord = entry_dict["x"]
		if entry_dict.has("y"):
			y_coord = entry_dict["y"]
		if entry_dict.has("w"):
			w_size = entry_dict["w"]
		if entry_dict.has("h"):
			h_size = entry_dict["h"]

		var slot_col: int = entry_idx % PER_ROW
		var slot_row: int = entry_idx / PER_ROW
		var slot_x: int = G + slot_col * (S + G)
		var slot_y: int = G + slot_row * (S + G)

		_draw_number(img, entry_idx, slot_x, slot_y - 14, 2, Color(1, 1, 0, 1))

		var src_img: Image = null

		if image_cache.has(file_str):
			src_img = image_cache[file_str]
		else:
			src_img = Image.load_from_file(file_str)
			if src_img != null:
				src_img.convert(Image.FORMAT_RGBA8)
			image_cache[file_str] = src_img

		if src_img == null:
			printerr("Failed to load image for entry %d: %s" % [entry_idx, file_str])
			for py: int in range(S):
				for px: int in range(S):
					var out_x: int = slot_x + px
					var out_y: int = slot_y + py
					if out_x >= 0 and out_x < img_width and out_y >= 0 and out_y < img_height:
						img.set_pixel(out_x, out_y, Color(1, 0, 0, 1))
			has_error = true
			continue

		var src_x: int = x_coord * 16
		var src_y: int = y_coord * 16
		var src_w: int = w_size * 16
		var src_h: int = h_size * 16

		if src_x < 0 or src_y < 0 or src_x + src_w > src_img.get_width() or src_y + src_h > src_img.get_height():
			printerr("Region out of bounds for entry %d" % [entry_idx])
			for py: int in range(S):
				for px: int in range(S):
					var out_x: int = slot_x + px
					var out_y: int = slot_y + py
					if out_x >= 0 and out_x < img_width and out_y >= 0 and out_y < img_height:
						img.set_pixel(out_x, out_y, Color(1, 0, 0, 1))
			has_error = true
			continue

		if w_size == 1 and h_size == 1:
			# Tile 3x3
			for tile_row: int in range(3):
				for tile_col: int in range(3):
					for src_py: int in range(16):
						for src_px: int in range(16):
							var src_color: Color = src_img.get_pixel(src_x + src_px, src_y + src_py)
							if src_color.a > 0:
								for i: int in range(scale):
									for j: int in range(scale):
										var out_x: int = slot_x + tile_col * 16 * scale + src_px * scale + i
										var out_y: int = slot_y + tile_row * 16 * scale + src_py * scale + j
										if out_x >= 0 and out_x < img_width and out_y >= 0 and out_y < img_height and out_x < slot_x + S and out_y < slot_y + S:
											var existing: Color = img.get_pixel(out_x, out_y)
											var blended: Color = existing.blend(src_color)
											img.set_pixel(out_x, out_y, blended)
		else:
			# Draw region once, scaled and clipped
			for src_py: int in range(src_h):
				for src_px: int in range(src_w):
					var src_color: Color = src_img.get_pixel(src_x + src_px, src_y + src_py)
					if src_color.a > 0:
						for i: int in range(scale):
							for j: int in range(scale):
								var out_x: int = slot_x + src_px * scale + i
								var out_y: int = slot_y + src_py * scale + j
								if out_x >= 0 and out_x < img_width and out_y >= 0 and out_y < img_height and out_x < slot_x + S and out_y < slot_y + S:
									var existing: Color = img.get_pixel(out_x, out_y)
									var blended: Color = existing.blend(src_color)
									img.set_pixel(out_x, out_y, blended)

	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	img.save_png(out_path)

	print("SHEET %s entries=%d" % [out_path, n])

	if has_error:
		quit(1)
	else:
		quit(0)
