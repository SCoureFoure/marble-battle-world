class_name MapLayer
extends Node2D
## Baked overworld tile map, ownership overlay, borders, and town markers.
## Source: docs/ARCHITECTURE.md §11.2, §12.6,
## .warboss-horde/slices/m3-world-scene.md, .warboss-horde/slices/m4-render.md.

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
const TOWN_SQUARE_SIZE := 10.0
const TOWN_ROOF_HEIGHT := 6.0
const TOWN_NEUTRAL_COLOR := Color(0.75, 0.7, 0.6)
const TOWN_RAIDED_COLOR := Color(0.5, 0.5, 0.5)
const TOWN_RAZED_COLOR := Color(0.0, 0.0, 0.0)
const TOWN_RAZED_FLAME_COLOR := Color(0.95, 0.5, 0.1)

var world: World
var _sprite: Sprite2D
var _overlay_sprite: Sprite2D
var _prev_town_owner: PackedInt32Array
var _prev_town_state: PackedInt32Array
var _last_borders_version: int = -1

# Border-line segments (world-space point pairs, consumed two at a time by
# draw_multiline), grouped by the owning faction so each group can be drawn
# in that faction's darkened colour.
var _border_segments_by_owner: Dictionary = {}


func build(w: World) -> void:
	world = w
	var m := world.map

	var img := Image.create_empty(m.cols, m.rows, false, Image.FORMAT_RGB8)
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
		add_child(_sprite)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.scale = Vector2(Tuning.TILE, Tuning.TILE)

	if _overlay_sprite == null:
		_overlay_sprite = Sprite2D.new()
		_overlay_sprite.name = "OwnerOverlaySprite"
		_overlay_sprite.centered = false
		_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_overlay_sprite)

	_overlay_sprite.texture = ImageTexture.create_from_image(_build_overlay_image())
	_overlay_sprite.scale = Vector2(Tuning.TILE, Tuning.TILE)
	_last_borders_version = world.borders_version

	_prev_town_owner = world.town_owner.duplicate()
	_prev_town_state = world.town_state.duplicate()
	_rebuild_border_segments()
	queue_redraw()


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
		_draw_town(center, world.town_owner[i], world.town_state[i])


## House glyph (10x10 square, centred at the tile centre, + a triangle roof
## above it). INTACT: owner colour (neutral -1: TOWN_NEUTRAL_COLOR). RAIDED:
## grey. RAZED: black, plus a small orange flame triangle above the roof.
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

	if state == 2:
		var flame_w := 4.0
		var flame := PackedVector2Array([
			apex + Vector2(-flame_w * 0.5, 0.0),
			apex + Vector2(flame_w * 0.5, 0.0),
			apex + Vector2(0.0, -flame_w),
		])
		draw_colored_polygon(flame, TOWN_RAZED_FLAME_COLOR)
