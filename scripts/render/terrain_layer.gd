class_name TerrainLayer
extends Node2D
## Draws non-PLAIN terrain cells. Source: docs/ARCHITECTURE.md §10.7,
## .warboss-horde/slices/m2-renderer.md §3.

var grid: TerrainGrid
var palette: PackedInt32Array = PackedInt32Array()  # see BattleRenderer.faction_color


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
		match k:
			TerrainGrid.Kind.MUD:
				draw_rect(rect, Color(0.55, 0.42, 0.28))
			TerrainGrid.Kind.COBBLE:
				draw_rect(rect, Color(0.75, 0.72, 0.66))
			TerrainGrid.Kind.ICE:
				draw_rect(rect, Color(0.80, 0.90, 0.95))
			TerrainGrid.Kind.WATER:
				draw_rect(rect, Color(0.45, 0.60, 0.80))
			TerrainGrid.Kind.ROCK:
				draw_circle(center, grid.cell * Tuning.OBSTACLE_RADIUS_FRAC, Color(0.45, 0.45, 0.45))
			TerrainGrid.Kind.TREE:
				draw_circle(center, grid.cell * Tuning.OBSTACLE_RADIUS_FRAC, Color(0.30, 0.50, 0.30))
			TerrainGrid.Kind.TOWER:
				draw_rect(rect, Color(0.35, 0.30, 0.40))
				var owner: int = grid.owner[c]
				var oc: Color = BattleRenderer.faction_color(owner, palette) if owner >= 0 else Color(0.6, 0.6, 0.6)
				var inner := Rect2(center - Vector2(grid.cell, grid.cell) * 0.25, Vector2(grid.cell, grid.cell) * 0.5)
				draw_rect(inner, oc)
			TerrainGrid.Kind.FIRE:
				draw_rect(rect, Color(0.95, 0.45, 0.10))
			TerrainGrid.Kind.SPIKE:
				draw_rect(rect, Color(0.30, 0.30, 0.30))
				# UNDECIDED: contract gives no colour for the SPIKE "X" lines,
				# only "SPIKE 0.30,0.30,0.30 with X" and "two diagonal lines
				# width 2" -- using black for visibility against the base fill.
				draw_line(rect.position, rect.position + rect.size, Color(0, 0, 0), 2.0)
				draw_line(rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(0, rect.size.y), Color(0, 0, 0), 2.0)
			TerrainGrid.Kind.FLOWERS:
				draw_rect(rect, Color(0.62, 0.78, 0.42))
				var p1 := top_left + Vector2(0.25, 0.3) * grid.cell
				var p2 := top_left + Vector2(0.7, 0.45) * grid.cell
				var p3 := top_left + Vector2(0.4, 0.75) * grid.cell
				draw_circle(p1, 3.0, Color(0.95, 0.60, 0.80))
				draw_circle(p2, 3.0, Color(0.95, 0.60, 0.80))
				draw_circle(p3, 3.0, Color(0.95, 0.60, 0.80))


func mark_dirty() -> void:
	queue_redraw()
