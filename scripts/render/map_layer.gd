class_name MapLayer
extends Node2D
## Baked overworld tile map. Source: docs/ARCHITECTURE.md §11.2,
## .warboss-horde/slices/m3-world-scene.md.

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
const TOWN_TINT_SIZE := 6.0

var world: World
var _sprite: Sprite2D
var _prev_town_owner: PackedInt32Array


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
	_prev_town_owner = world.town_owner.duplicate()
	queue_redraw()


## Only town ownership changes the per-frame draw output (the baked tile
## image never changes), so redraw on demand instead of every frame.
func refresh_if_owner_changed() -> void:
	if world == null:
		return
	if world.town_owner != _prev_town_owner:
		_prev_town_owner = world.town_owner.duplicate()
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for i in range(world.towns.size()):
		var owner: int = world.town_owner[i]
		if owner < 0:
			continue
		var t: Vector2 = world.towns[i]
		var center := world.map.center_of(int(t.x), int(t.y))
		var rect := Rect2(center - Vector2(TOWN_TINT_SIZE, TOWN_TINT_SIZE) * 0.5, Vector2(TOWN_TINT_SIZE, TOWN_TINT_SIZE))
		draw_rect(rect, Tuning.FACTION_COLORS[owner % Tuning.FACTION_COLORS.size()])
