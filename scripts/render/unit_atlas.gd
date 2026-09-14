class_name UnitAtlas extends RefCounted
## Atlas builder for unit sprites: one generic warrior sheet per faction, tinted to faction color.

const SLOTS := 16
const COLS := 4
const ROWS := 4
const SHEET_W := 48
const SHEET_H := 64


static func slot_origin(slot: int) -> Vector2i:
	return Vector2i((slot % COLS) * SHEET_W, (slot / COLS) * SHEET_H)


## Sheet rows needed to fit the 16 faction slots plus `hero_count` hero slots.
static func rows_for(hero_count: int) -> int:
	return int(ceil(float(SLOTS + hero_count) / float(COLS)))


static func build_image(colors: Array, heroes: Array = []) -> Image:
	var img: Image = Image.create_empty(COLS * SHEET_W, rows_for(heroes.size()) * SHEET_H, false, Image.FORMAT_RGBA8)
	var look: Dictionary = CharLooks.generic_warrior()

	for i in range(mini(colors.size(), SLOTS)):
		var c: Color = colors[i]
		var sheet: Image = CharLooks.compose(look, c)
		img.blend_rect(sheet, Rect2i(0, 0, SHEET_W, SHEET_H), slot_origin(i))

	for k in range(heroes.size()):
		var hero_look: Dictionary = heroes[k]
		var hero_sheet: Image = CharLooks.compose(hero_look, Color(1, 1, 1))
		img.blend_rect(hero_sheet, Rect2i(0, 0, SHEET_W, SHEET_H), slot_origin(SLOTS + k))

	return img
