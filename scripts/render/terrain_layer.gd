class_name TerrainLayer
extends Node2D
## Draws non-PLAIN terrain cells. Source: docs/ARCHITECTURE.md §10.7,
## .warboss-horde/slices/m2-renderer.md §3.

var grid: TerrainGrid


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
				var oc: Color = Tuning.FACTION_COLORS[owner % 8] if owner >= 0 else Color(0.6, 0.6, 0.6)
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


func mark_dirty() -> void:
	queue_redraw()
