class_name MapLayer
extends Node2D
## Baked overworld tile map, ownership overlay, borders, and town markers.
## Source: docs/ARCHITECTURE.md §11.2, §12.6,
## .warboss-horde/slices/m3-world-scene.md, .warboss-horde/slices/m4-render.md,
## scripts/render/map_tile_art.gd.

const TILE_COLORS := [
	Color(0.87, 0.80, 0.62),   # PLAINS
	Color(0.45, 0.58, 0.36),   # FOREST
	Color(0.72, 0.64, 0.48),   # HILLS
	Color(0.50, 0.47, 0.44),   # MOUNTAIN
	Color(0.45, 0.60, 0.80),   # RIVER
	Color(0.55, 0.50, 0.45),   # RUIN
	Color(0.60, 0.58, 0.62),   # GRAVEYARD
	Color(0.80, 0.45, 0.30),   # TOWN
]
const OVERLAY_ALPHA := 0.28
const BORDER_DARKEN := Color(0.5, 0.5, 0.5, 1.0)
const BORDER_WIDTH := 2.0
const TOWN_SQUARE_SIZE := 18.0
const TOWN_ROOF_HEIGHT := 10.0
const TOWN_NEUTRAL_COLOR := Color(0.75, 0.7, 0.6)
const TOWN_RAIDED_COLOR := Color(0.5, 0.5, 0.5)
const TOWN_RAZED_COLOR := Color(0.0, 0.0, 0.0)
const TOWN_RAZED_FLAME_COLOR := Color(0.95, 0.5, 0.1)
const TOWN_OUTLINE_COLOR := Color(0.1, 0.08, 0.06)
const TOWN_OUTLINE_WIDTH := 2.0
const ART_CELL := 16
const HOUSE_SIZE := 48.0
const HOUSE_RAIDED_MODULATE := Color(0.6, 0.6, 0.6, 1.0)
const HOUSE_RAZED_MODULATE := Color(0.3, 0.25, 0.25, 1.0)
const FLAME_INNER_COLOR := Color(1.0, 0.85, 0.2)

var world: World
var _sprite: Sprite2D
var _overlay_sprite: Sprite2D
var _prev_town_owner: PackedInt32Array
var _prev_town_state: PackedInt32Array
var _last_borders_version: int = -1
var _art_ok: bool = false
var _house_tex: Dictionary = {}

# Border-line segments (world-space point pairs, consumed two at a time by
# draw_multiline), grouped by the owning faction so each group can be drawn
# in that faction's darkened colour.
var _border_segments_by_owner: Dictionary = {}


func build(w: World) -> void:
	world = w
	var m := world.map
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_art_ok = true
	for path in MapTileArt.required_textures():
		if not ResourceLoader.exists(path):
			_art_ok = false

	var img: Image
	if _art_ok:
		img = _bake_art_image()
		_house_tex = {}
		for i in range(world.towns.size()):
			var t: Vector2 = world.towns[i]
			var tex_path: String = MapTileArt.house_texture(int(t.x), int(t.y))
			_house_tex[tex_path] = load(tex_path) as Texture2D
	else:
		img = Image.create_empty(m.cols, m.rows, false, Image.FORMAT_RGB8)
		for ty in range(m.rows):
			for tx in range(m.cols):
				var k: int = m.kind[m.idx(tx, ty)]
				var base: Color = TILE_COLORS[k]
				var h: int = (tx * 73856093) ^ (ty * 19349663)
				var noise: float = float(h % 7) / 100.0 - 0.03
				img.set_pixel(tx, ty, base + Color(noise, noise, noise))

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "MapSprite"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.show_behind_parent = true
		add_child(_sprite)

	_sprite.texture = ImageTexture.create_from_image(img)
	if _art_ok:
		_sprite.scale = Vector2(Tuning.TILE / ART_CELL, Tuning.TILE / ART_CELL)
	else:
		_sprite.scale = Vector2(Tuning.TILE, Tuning.TILE)

	if _overlay_sprite == null:
		_overlay_sprite = Sprite2D.new()
		_overlay_sprite.name = "OwnerOverlaySprite"
		_overlay_sprite.centered = false
		_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay_sprite.show_behind_parent = true
		add_child(_overlay_sprite)

	_overlay_sprite.texture = ImageTexture.create_from_image(_build_overlay_image())
	_overlay_sprite.scale = Vector2(Tuning.TILE, Tuning.TILE)
	_last_borders_version = world.borders_version

	_prev_town_owner = world.town_owner.duplicate()
	_prev_town_state = world.town_state.duplicate()
	_rebuild_border_segments()
	queue_redraw()


func _bake_art_image() -> Image:
	var m := world.map
	var images: Dictionary = {}
	for path in MapTileArt.required_textures():
		var tex: Texture2D = load(path)
		var src_img: Image = tex.get_image()
		if src_img.is_compressed():
			src_img.decompress()
		src_img.convert(Image.FORMAT_RGBA8)
		images[path] = src_img

	var out: Image = Image.create_empty(m.cols * ART_CELL, m.rows * ART_CELL, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 1))

	var all_ops: Dictionary = {}
	for cy in range(m.rows):
		for cx in range(m.cols):
			all_ops[Vector2i(cx, cy)] = MapTileArt.tile_ops(m, cx, cy)

	for layer in range(2):
		for ty in range(m.rows):
			for tx in range(m.cols):
				var ops: Array = all_ops[Vector2i(tx, ty)]
				var o := Vector2i(tx * ART_CELL, ty * ART_CELL)
				for j in range(ops.size()):
					var op: Dictionary = ops[j]
					if int(op["layer"]) != layer:
						continue
					if op.has("tex"):
						var tex_path: String = op["tex"]
						var dst: Vector2i = op["dst"]
						var r: Rect2i = op["src"]
						var d := o + dst
						if d.y < 0:
							r.position.y -= d.y
							r.size.y += d.y
							d.y = 0
						if d.x < 0:
							r.position.x -= d.x
							r.size.x += d.x
							d.x = 0
						if r.size.x <= 0 or r.size.y <= 0:
							continue
						out.blend_rect(images[tex_path], r, d)
					else:
						var rect: Rect2i = op["rect"]
						var color: Color = op["color"]
						out.fill_rect(Rect2i(o + rect.position, rect.size), color)

	return out


func _build_overlay_image() -> Image:
	var m := world.map
	var img := Image.create_empty(m.cols, m.rows, false, Image.FORMAT_RGBA8)
	for ty in range(m.rows):
		for tx in range(m.cols):
			var owner: int = m.owner[m.idx(tx, ty)]
			if owner < 0:
				img.set_pixel(tx, ty, Color(0.0, 0.0, 0.0, 0.0))
			else:
				var c: Color = Tuning.FACTION_COLORS[owner % Tuning.FACTION_COLORS.size()]
				img.set_pixel(tx, ty, Color(c.r, c.g, c.b, OVERLAY_ALPHA))
	return img


## Owner overlay + border lines rebuild only when `world.borders_version`
## changes; town markers also redraw when town_state/town_owner changed
## without a borders_version bump (e.g. RAIDED -> INTACT recovery, which
## does not call World.recompute_borders()).
func refresh_if_owner_changed() -> void:
	if world == null:
		return

	var version_changed := world.borders_version != _last_borders_version
	if version_changed:
		_last_borders_version = world.borders_version
		(_overlay_sprite.texture as ImageTexture).update(_build_overlay_image())
		_rebuild_border_segments()

	var towns_changed := world.town_owner != _prev_town_owner or world.town_state != _prev_town_state
	if towns_changed:
		_prev_town_owner = world.town_owner.duplicate()
		_prev_town_state = world.town_state.duplicate()

	if version_changed or towns_changed:
		queue_redraw()


func _rebuild_border_segments() -> void:
	_border_segments_by_owner = {}
	var m := world.map
	var tile := Tuning.TILE
	for ty in range(m.rows):
		for tx in range(m.cols):
			var owner: int = m.owner[m.idx(tx, ty)]
			if tx + 1 < m.cols:
				var eowner: int = m.owner[m.idx(tx + 1, ty)]
				if eowner != owner:
					_add_border_segment(owner, eowner,
						Vector2((tx + 1) * tile, ty * tile), Vector2((tx + 1) * tile, (ty + 1) * tile))
			if ty + 1 < m.rows:
				var sowner: int = m.owner[m.idx(tx, ty + 1)]
				if sowner != owner:
					_add_border_segment(owner, sowner,
						Vector2(tx * tile, (ty + 1) * tile), Vector2((tx + 1) * tile, (ty + 1) * tile))


## UNDECIDED: §12.6 says a border segment is drawn "in the darker owner
## colour" without saying which side wins when the two neighbouring tiles
## are both owned (by different factions) or when only one side is owned
## (-1 neutral has no colour). Fiat: prefer the non-neutral side; if both
## sides are owned, use the "current" tile of the tx/ty scan (owner_a).
## Also: the contract phrase "cache the segments in a PackedVector2Array
## pairs list" (singular) is read here as "one such list per colour group"
## so draw_multiline can still take one colour per call.
func _add_border_segment(owner_a: int, owner_b: int, p0: Vector2, p1: Vector2) -> void:
	var owner := owner_a if owner_a >= 0 else owner_b
	if owner < 0:
		return
	if not _border_segments_by_owner.has(owner):
		_border_segments_by_owner[owner] = PackedVector2Array()
	var arr: PackedVector2Array = _border_segments_by_owner[owner]
	arr.append(p0)
	arr.append(p1)
	_border_segments_by_owner[owner] = arr


func _draw() -> void:
	if world == null:
		return

	for owner in _border_segments_by_owner:
		var color: Color = Tuning.FACTION_COLORS[owner % Tuning.FACTION_COLORS.size()] * BORDER_DARKEN
		draw_multiline(_border_segments_by_owner[owner], color, BORDER_WIDTH)

	for i in range(world.towns.size()):
		var t: Vector2 = world.towns[i]
		var center := world.map.center_of(int(t.x), int(t.y))
		if _art_ok:
			_draw_town_art(center, world.town_owner[i], world.town_state[i], int(t.x), int(t.y))
		else:
			_draw_town(center, world.town_owner[i], world.town_state[i])


## House glyph (18x18 square, dark outline, centred at the tile centre, + a triangle roof
## above it). INTACT: owner colour (neutral -1: TOWN_NEUTRAL_COLOR). RAIDED:
## grey. RAZED: black, plus a small orange flame triangle above the roof.
## Fallback used when map art (MapTileArt) is missing.
func _draw_town(center: Vector2, owner: int, state: int) -> void:
	var color: Color
	match state:
		1:
			color = TOWN_RAIDED_COLOR
		2:
			color = TOWN_RAZED_COLOR
		_:
			color = Tuning.FACTION_COLORS[owner % Tuning.FACTION_COLORS.size()] if owner >= 0 else TOWN_NEUTRAL_COLOR

	var half := TOWN_SQUARE_SIZE * 0.5
	var sq_rect := Rect2(center - Vector2(half, half), Vector2(TOWN_SQUARE_SIZE, TOWN_SQUARE_SIZE))
	draw_rect(sq_rect, color)

	var apex := Vector2(center.x, sq_rect.position.y - TOWN_ROOF_HEIGHT)
	var roof := PackedVector2Array([sq_rect.position, Vector2(sq_rect.position.x + TOWN_SQUARE_SIZE, sq_rect.position.y), apex])
	draw_colored_polygon(roof, color)

	draw_rect(sq_rect, TOWN_OUTLINE_COLOR, false, TOWN_OUTLINE_WIDTH)
	draw_polyline(PackedVector2Array([sq_rect.position, apex, Vector2(sq_rect.position.x + TOWN_SQUARE_SIZE, sq_rect.position.y)]), TOWN_OUTLINE_COLOR, TOWN_OUTLINE_WIDTH)

	if state == 2:
		var flame_w := 8.0
		var flame := PackedVector2Array([
			apex + Vector2(-flame_w * 0.5, 0.0),
			apex + Vector2(flame_w * 0.5, 0.0),
			apex + Vector2(0.0, -flame_w),
		])
		draw_colored_polygon(flame, TOWN_RAZED_FLAME_COLOR)


## Art-backed town render: a 48x48 house sprite (bottom aligned to the tile's
## bottom edge) with a pennant in the owner colour, or flames when RAZED.
## Falls back to _draw_town() when the house texture for this tile is missing.
func _draw_town_art(center: Vector2, owner: int, state: int, tx: int, ty: int) -> void:
	var rect := Rect2(center - Vector2(HOUSE_SIZE * 0.5, HOUSE_SIZE - Tuning.TILE * 0.5), Vector2(HOUSE_SIZE, HOUSE_SIZE))

	var house_modulate: Color
	match state:
		1:
			house_modulate = HOUSE_RAIDED_MODULATE
		2:
			house_modulate = HOUSE_RAZED_MODULATE
		_:
			house_modulate = Color(1, 1, 1, 1)

	var tex: Texture2D = _house_tex.get(MapTileArt.house_texture(tx, ty))
	if tex == null:
		_draw_town(center, owner, state)
		return
	draw_texture_rect(tex, rect, false, house_modulate)

	if owner >= 0 and state != 2:
		var px: float = rect.end.x - 6.0
		var top: float = rect.position.y - 10.0
		draw_line(Vector2(px, top), Vector2(px, rect.position.y + 14.0), TOWN_OUTLINE_COLOR, 2.0)

		var flag_color: Color
		var points: PackedVector2Array
		if state == 1:
			flag_color = TOWN_RAIDED_COLOR
			points = PackedVector2Array([
				Vector2(px + 1, top), Vector2(px + 15, top + 3), Vector2(px + 9, top + 5),
				Vector2(px + 15, top + 7), Vector2(px + 1, top + 10),
			])
		else:
			flag_color = Tuning.FACTION_COLORS[owner % Tuning.FACTION_COLORS.size()]
			points = PackedVector2Array([
				Vector2(px + 1, top), Vector2(px + 15, top + 5), Vector2(px + 1, top + 10),
			])

		draw_colored_polygon(points, flag_color)
		var outline_points := points.duplicate()
		outline_points.append(points[0])
		draw_polyline(outline_points, TOWN_OUTLINE_COLOR, 1.0)

	if state == 2:
		var flame_ox: Array[float] = [-10.0, 0.0, 10.0]
		var flame_hgt: Array[float] = [14.0, 20.0, 14.0]
		var base_y: float = rect.position.y + 30.0
		for i in range(3):
			var cx: float = center.x + flame_ox[i]
			var hgt: float = flame_hgt[i]
			var outer := PackedVector2Array([
				Vector2(cx - 5, base_y), Vector2(cx + 5, base_y), Vector2(cx, base_y - hgt),
			])
			draw_colored_polygon(outer, TOWN_RAZED_FLAME_COLOR)
			var inner := PackedVector2Array([
				Vector2(cx - 2.5, base_y), Vector2(cx + 2.5, base_y), Vector2(cx, base_y - hgt * 0.6),
			])
			draw_colored_polygon(inner, FLAME_INNER_COLOR)
