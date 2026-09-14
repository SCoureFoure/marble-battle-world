class_name TerrainLayer
extends Node2D
## Draws non-PLAIN terrain cells. Source: docs/ARCHITECTURE.md §10.7,
## .warboss-horde/slices/m2-renderer.md §3.

const ART := "res://assets/art/rpg/"
const PX := 2.5   # source pixel -> world units (TERRAIN_CELL 40 / 16 px tiles)
const SPRITES := {
	TerrainGrid.Kind.ROCK: ["rock_1.png", "rock_2.png", "rock_3.png", "rock_4.png", "rock_5.png", "rock_6.png"],
	TerrainGrid.Kind.TREE: ["tree_deciduous_small_1.png", "tree_deciduous_small_2.png", "tree_deciduous_small_3.png", "tree_deciduous_small_4.png", "tree_deciduous_small_5.png"],
	TerrainGrid.Kind.TOWER: ["column_tall.png"],
	TerrainGrid.Kind.FIRE: ["campfire_logs.png"],
	TerrainGrid.Kind.SPIKE: ["hole_spiky.png"],
	TerrainGrid.Kind.ICE: ["ice_1.png", "ice_2.png", "ice_3.png"],
	TerrainGrid.Kind.FLOWERS: ["grass_tuft_1.png"],   # tufts 2-4 are snowy/dry variants
	TerrainGrid.Kind.COBBLE: ["gravel_1.png", "gravel_2.png"],
	TerrainGrid.Kind.WATER: ["pond_weed.png"],
	TerrainGrid.Kind.MUD: ["mushrooms_1.png", "mushrooms_2.png", "mushrooms_3.png"],
}
const GROUND := [TerrainGrid.Kind.MUD, TerrainGrid.Kind.COBBLE, TerrainGrid.Kind.ICE, TerrainGrid.Kind.WATER, TerrainGrid.Kind.FLOWERS]

var grid: TerrainGrid
var palette: PackedInt32Array = PackedInt32Array()  # see BattleRenderer.faction_color
var _tex_cache: Dictionary = {}


## "" when the kind has no sprite list; else ART + list[c % list.size()].
static func sprite_path(kind: int, c: int) -> String:
	if kind not in SPRITES:
		return ""
	var list = SPRITES[kind]
	return ART + list[c % list.size()]


## Whether cell `c` of `kind` gets a sprite drawn at all.
## Kinds not in SPRITES -> false. Kinds in GROUND -> ((c * 7919) % 3) == 0.
## Every other kind in SPRITES (ROCK, TREE, TOWER, FIRE, SPIKE) -> true.
static func decorates(kind: int, c: int) -> bool:
	if kind not in SPRITES:
		return false
	if kind in GROUND:
		return ((c * 7919) % 3) == 0
	return true


func _texture(path: String) -> Texture2D:
	if path in _tex_cache:
		return _tex_cache[path]
	var tex = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if grid == null:
		return
	for c in range(grid.cols * grid.rows):
		var k: int = grid.kind[c]
		if k == TerrainGrid.Kind.PLAIN:
			continue
		var center := grid.cell_center(c)
		var top_left := center - Vector2(grid.cell, grid.cell) * 0.5
		var rect := Rect2(top_left, Vector2(grid.cell, grid.cell))

		# Step 1: Base fill
		match k:
			TerrainGrid.Kind.MUD:
				draw_rect(rect, Color(0.55, 0.42, 0.28))
			TerrainGrid.Kind.COBBLE:
				draw_rect(rect, Color(0.75, 0.72, 0.66))
			TerrainGrid.Kind.ICE:
				draw_rect(rect, Color(0.80, 0.90, 0.95))
			TerrainGrid.Kind.WATER:
				draw_rect(rect, Color(0.45, 0.60, 0.80))
			TerrainGrid.Kind.TOWER:
				draw_rect(rect, Color(0.35, 0.30, 0.40))
			TerrainGrid.Kind.FIRE:
				draw_rect(rect, Color(0.95, 0.45, 0.10))
			TerrainGrid.Kind.SPIKE:
				draw_rect(rect, Color(0.30, 0.30, 0.30))
			TerrainGrid.Kind.FLOWERS:
				draw_rect(rect, Color(0.62, 0.78, 0.42))
			# ROCK and TREE have no base fill

		# Step 2: Sprite (and Step 3: Fallback)
		if decorates(k, c):
			var sprite_p = sprite_path(k, c)
			var tex = _texture(sprite_p)
			if tex != null:
				var size := tex.get_size() * PX
				draw_texture_rect(tex, Rect2(Vector2(center.x - size.x * 0.5, top_left.y + grid.cell - size.y), size), false)
			else:
				# Step 3: Fallback
				match k:
					TerrainGrid.Kind.ROCK:
						draw_circle(center, grid.cell * Tuning.OBSTACLE_RADIUS_FRAC, Color(0.45, 0.45, 0.45))
					TerrainGrid.Kind.TREE:
						draw_circle(center, grid.cell * Tuning.OBSTACLE_RADIUS_FRAC, Color(0.30, 0.50, 0.30))
					TerrainGrid.Kind.TOWER:
						var owner: int = grid.owner[c]
						var oc: Color = BattleRenderer.faction_color(owner, palette) if owner >= 0 else Color(0.6, 0.6, 0.6)
						var inner := Rect2(center - Vector2(grid.cell, grid.cell) * 0.25, Vector2(grid.cell, grid.cell) * 0.5)
						draw_rect(inner, oc)
					TerrainGrid.Kind.SPIKE:
						draw_line(rect.position, rect.position + rect.size, Color(0, 0, 0), 2.0)
						draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), Color(0, 0, 0), 2.0)
					TerrainGrid.Kind.FLOWERS:
						var p1 := top_left + Vector2(0.25, 0.3) * grid.cell
						var p2 := top_left + Vector2(0.7, 0.45) * grid.cell
						var p3 := top_left + Vector2(0.4, 0.75) * grid.cell
						draw_circle(p1, 3.0, Color(0.95, 0.60, 0.80))
						draw_circle(p2, 3.0, Color(0.95, 0.60, 0.80))
						draw_circle(p3, 3.0, Color(0.95, 0.60, 0.80))

		# Step 4: Tower owner
		if k == TerrainGrid.Kind.TOWER:
			var owner: int = grid.owner[c]
			var oc: Color = BattleRenderer.faction_color(owner, palette) if owner >= 0 else Color(0.6, 0.6, 0.6)
			draw_rect(rect.grow(-2.0), oc, false, 4.0)


func mark_dirty() -> void:
	queue_redraw()
