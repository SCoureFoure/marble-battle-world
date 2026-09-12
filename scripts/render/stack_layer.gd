class_name StackLayer
extends Node2D
## Draws overworld unit stacks and battle markers, and drives the captain
## labels for the stacks nearest the camera. Source: docs/ARCHITECTURE.md
## §11.3, .warboss-horde/slices/m3-world-scene.md.

const OUTLINE_COLOR := Color(0.1, 0.1, 0.1)
const BATTLE_LABEL_COLOR := Color(0.9, 0.1, 0.1)
const LABEL_SLOTS := 60

var world: World
var camera: Camera2D
var label_pool: LabelPool


func _draw() -> void:
	if world == null:
		return

	var stacks := world.stacks
	for i in range(stacks.n):
		if stacks.alive[i] == 0:
			continue
		var pos := Vector2(stacks.x[i], stacks.y[i])
		var tier := stacks.tier(i)
		var radius: float = Tuning.STACK_RADIUS * (0.7 + 0.2 * tier)
		var color: Color = Tuning.FACTION_COLORS[stacks.faction[i] % Tuning.FACTION_COLORS.size()]
		draw_circle(pos, radius, color)
		draw_arc(pos, radius, 0.0, TAU, 24, OUTLINE_COLOR, 2.0)

	# UNDECIDED: the contract's "battling tiles: red 'X' label at the tile
	# centre" sentence sits in the same bullet as the LabelPool captain-label
	# sentence, but only the captain label is explicitly said to go "via
	# LabelPool.set_captain"; LabelPool.set_captain also has no colour
	# parameter to make the X red. Drawing it directly here with draw_string
	# instead of routing it through LabelPool.
	for b in world.battles:
		var inst: BattleInstance = b
		var center := world.map.center_of(inst.tile.x, inst.tile.y)
		draw_string(ThemeDB.fallback_font, center, "X", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, BATTLE_LABEL_COLOR)


func update_labels() -> void:
	if world == null or label_pool == null:
		return

	var stacks := world.stacks
	var cam_pos: Vector2 = camera.position if camera != null else Vector2.ZERO

	var order: Array[int] = []
	for i in range(stacks.n):
		if stacks.alive[i] == 1:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := cam_pos.distance_squared_to(Vector2(stacks.x[a], stacks.y[a]))
		var db := cam_pos.distance_squared_to(Vector2(stacks.x[b], stacks.y[b]))
		return da < db)

	var shown := mini(order.size(), LABEL_SLOTS)
	for slot in range(LABEL_SLOTS):
		if slot < shown:
			var i: int = order[slot]
			var text := stacks.label(i)
			if stacks.state[i] == Stacks.State.RETREATING:
				text += " RETREAT"
			label_pool.set_captain(slot, text, Vector2(stacks.x[i], stacks.y[i]))
		else:
			label_pool.hide_captain(slot)
