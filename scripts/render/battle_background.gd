class_name BattleBackground
extends Node2D
## Parchment fill for the battle view SubViewport, drawn under the terrain
## layer. Source: .warboss-horde/slices/m3-scene-fixes.md item 2.


func _draw() -> void:
	var rect := Rect2(0, 0, Tuning.ARENA_W, Tuning.ARENA_H)
	draw_rect(rect, Color(0.93, 0.88, 0.75), true)
	draw_rect(rect, Color(0.25, 0.2, 0.15), false, 3.0)
