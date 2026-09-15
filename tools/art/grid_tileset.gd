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

	var in_path: String = ""
	var out_path: String = ""
	var cell: int = 16
	var scale: int = 4

	for arg in args:
		if arg.begins_with("--in="):
			in_path = arg.substr(5)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--cell="):
			cell = int(arg.substr(7))
		elif arg.begins_with("--scale="):
			scale = int(arg.substr(8))

	var src: Image = Image.load_from_file(in_path)
	if src == null:
		printerr("Failed to load image: ", in_path)
		quit(1)
		return

	src.convert(Image.FORMAT_RGBA8)

	var cols: int = src.get_width() / cell
	var rows: int = src.get_height() / cell

	var cs: int = cell * scale
	var M: int = 24

	var out_width: int = M + cols * cs
	var out_height: int = M + rows * cs

	var img: Image = Image.create(out_width, out_height, false, Image.FORMAT_RGBA8)
	var bg_color: Color = Color(0.15, 0.15, 0.15, 1)

	for py: int in range(out_height):
		for px: int in range(out_width):
			img.set_pixel(px, py, bg_color)

	# Paint scaled source image
	for sy: int in range(src.get_height()):
		for sx: int in range(src.get_width()):
			var src_color: Color = src.get_pixel(sx, sy)
			if src_color.a > 0:
				for i: int in range(scale):
					for j: int in range(scale):
						var out_x: int = M + sx * scale + i
						var out_y: int = M + sy * scale + j
						if out_x >= 0 and out_x < out_width and out_y >= 0 and out_y < out_height:
							var existing: Color = img.get_pixel(out_x, out_y)
							var blended: Color = existing.blend(src_color)
							img.set_pixel(out_x, out_y, blended)

	# Draw grid lines
	var magenta: Color = Color(1, 0, 1, 1)
	var cyan: Color = Color(0, 1, 1, 1)

	# Vertical lines
	for c: int in range(cols + 1):
		var x: int = M + c * cs
		var line_width: int = 1 if c % 5 != 0 else 2
		var line_color: Color = magenta if c % 5 != 0 else cyan
		for lw: int in range(line_width):
			for r: int in range(rows * cs):
				var py: int = M + r
				if py >= 0 and py < out_height and x + lw >= 0 and x + lw < out_width:
					img.set_pixel(x + lw, py, line_color)

	# Horizontal lines
	for r: int in range(rows + 1):
		var y: int = M + r * cs
		var line_width: int = 1 if r % 5 != 0 else 2
		var line_color: Color = magenta if r % 5 != 0 else cyan
		for lw: int in range(line_width):
			for c: int in range(cols * cs):
				var px: int = M + c
				if px >= 0 and px < out_width and y + lw >= 0 and y + lw < out_height:
					img.set_pixel(px, y + lw, line_color)

	# Draw labels
	var yellow: Color = Color(1, 1, 0, 1)
	for c: int in range(cols):
		_draw_number(img, c, M + c * cs + 4, 6, 2, yellow)

	for r: int in range(rows):
		_draw_number(img, r, 2, M + r * cs + 4, 2, yellow)

	# Save PNG
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	img.save_png(out_path)

	print("GRID %s cols=%d rows=%d size=%dx%d" % [out_path, cols, rows, out_width, out_height])

	quit(0)
