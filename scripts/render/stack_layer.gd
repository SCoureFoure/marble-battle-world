class_name StackLayer
extends Node2D
## Draws overworld unit stacks and battle markers, and drives the captain
## labels for the stacks nearest the camera. Source: docs/ARCHITECTURE.md
## §11.3, .warboss-horde/slices/m3-world-scene.md.

const OUTLINE_COLOR := Color(0.1, 0.1, 0.1)
const BATTLE_LABEL_COLOR := Color(0.9, 0.1, 0.1)
const LABEL_SLOTS := 60

const HERO_SIDE_K := 2.4
const WALK_RATE := 0.08
const WALK_SEQ := [0, 1, 2, 1]
const IDLE_MOVE := 0.05
const MAX_ALLY_FLAGS := 3
const TEX_CACHE_MAX := 256
const POLE_COLOR := Color(0.3, 0.2, 0.1)

var world: World
var camera: Camera2D
var label_pool: LabelPool

var _tex_cache: Dictionary = {}              # "unit:gen" -> ImageTexture
var _generic_cache: Dictionary = {}   # colour index -> ImageTexture
var _last_pos: PackedVector2Array = PackedVector2Array()
var _facing: PackedByteArray = PackedByteArray()
var _anim: PackedFloat32Array = PackedFloat32Array()
var _last_gen: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func hero_rect(pos: Vector2, tier: int) -> Rect2:
	var r: float = Tuning.STACK_RADIUS * (0.7 + 0.2 * tier)
	var side: float = r * HERO_SIDE_K
	return Rect2(pos.x - side * 0.5, pos.y + r * 0.5 - side, side, side)


static func step_walk(delta: Vector2, facing: int, anim: float) -> Array:
	var d: float = delta.length()
	if d < IDLE_MOVE:
		return [facing, anim, 1]

	var new_facing: int = facing
	if absf(delta.x) >= absf(delta.y):
		new_facing = 1 if delta.x < 0 else 2
	else:
		new_facing = 3 if delta.y < 0 else 0

	var new_anim: float = anim + d * WALK_RATE
	var frame: int = WALK_SEQ[posmod(int(floor(new_anim)), 4)]

	return [new_facing, new_anim, frame]


static func pole_segment(rect: Rect2) -> PackedVector2Array:
	var side: float = rect.size.x
	var px: float = rect.end.x - side * 0.1
	var bottom := Vector2(px, rect.end.y - side * 0.2)
	var top := Vector2(px, rect.position.y - side * 0.45)
	return PackedVector2Array([bottom, top])


static func flag_points(rect: Rect2, k: int) -> PackedVector2Array:
	var side: float = rect.size.x
	var px: float = rect.end.x - side * 0.1
	var top_y: float = rect.position.y - side * 0.45

	var ty: float = top_y + k * side * 0.27
	var h: float = side * 0.24
	var w: float = side * (0.6 if k == 0 else 0.42)

	return PackedVector2Array([
		Vector2(px, ty),
		Vector2(px + w, ty + h * 0.5),
		Vector2(px, ty + h)
	])


static func flag_factions(w: World, f: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.append(f)

	var ally_count: int = 0
	for g in range(0, w.faction_count):
		if g != f and w.faction_alive[g] == 1 and w.allied(f, g):
			result.append(g)
			ally_count += 1
			if ally_count >= MAX_ALLY_FLAGS:
				break

	return result


func hero_texture(u: int) -> Texture2D:
	if world == null or u < 0 or not world.units.looks.has(u):
		return null

	var key := "%d:%d" % [u, world.units.gen[u]]
	if _tex_cache.has(key):
		return _tex_cache[key]

	if _tex_cache.size() >= TEX_CACHE_MAX:
		_tex_cache.clear()

	var look: Dictionary = world.units.looks[u]
	var img: Image = CharLooks.compose(look, Color(1, 1, 1))
	var tex: Texture2D = ImageTexture.create_from_image(img)

	_tex_cache[key] = tex
	return tex


func generic_texture(f: int) -> Texture2D:
	if not FileAccess.file_exists(CharLooks.BASE + "catalog.json"):
		return null

	var ci: int = posmod(f, Tuning.FACTION_COLORS.size())
	if _generic_cache.has(ci):
		return _generic_cache[ci]

	var c: Color = Tuning.FACTION_COLORS[ci]
	var img: Image = CharLooks.compose(CharLooks.generic_warrior(), c)
	var tex: Texture2D = ImageTexture.create_from_image(img)

	_generic_cache[ci] = tex
	return tex


func stack_texture(cap: int, f: int) -> Texture2D:
	var tex := hero_texture(cap)
	if tex != null:
		return tex
	return generic_texture(f)


func _draw() -> void:
	if world == null:
		return

	var stacks := world.stacks

	# Resize tracking arrays if needed
	if _last_pos.size() != stacks.n:
		_last_pos.resize(stacks.n)
		_facing.resize(stacks.n)
		_anim.resize(stacks.n)
		_last_gen.resize(stacks.n)
		for i in range(stacks.n):
			_last_pos[i] = Vector2(stacks.x[i], stacks.y[i])
			_facing[i] = 0
			_anim[i] = 0.0
			_last_gen[i] = stacks.gen[i]

	var flags_by_faction: Dictionary = {}

	for i in range(stacks.n):
		if stacks.alive[i] == 0:
			continue

		var pos := Vector2(stacks.x[i], stacks.y[i])
		if _last_gen[i] != stacks.gen[i]:
			_last_gen[i] = stacks.gen[i]
			_last_pos[i] = pos
			_facing[i] = 0
			_anim[i] = 0.0
		var tier := stacks.tier(i)
		var cap: int = stacks.captain_unit[i]
		var tex: Texture2D = stack_texture(cap, stacks.faction[i])

		if tex == null:
			# Fallback to circle marker
			var radius: float = Tuning.STACK_RADIUS * (0.7 + 0.2 * tier)
			var color: Color = Tuning.FACTION_COLORS[stacks.faction[i] % Tuning.FACTION_COLORS.size()]
			draw_circle(pos, radius, color)
			draw_arc(pos, radius, 0.0, TAU, 24, OUTLINE_COLOR, 2.0)
			_last_pos[i] = pos
			continue

		# Draw hero sprite with walk cycle
		var walk: Array = step_walk(pos - _last_pos[i], int(_facing[i]), _anim[i])
		_facing[i] = int(walk[0])
		_anim[i] = walk[1]
		_last_pos[i] = pos

		var rect: Rect2 = hero_rect(pos, tier)
		var frame_rect: Rect2i = CharLooks.frame_rect(int(walk[0]), int(walk[2]))
		draw_texture_rect_region(tex, rect, Rect2(frame_rect))

		# Draw flag pole
		var pole: PackedVector2Array = pole_segment(rect)
		draw_line(pole[0], pole[1], POLE_COLOR, 1.5)

		# Draw faction flags
		var faction_id: int = stacks.faction[i]
		if not flags_by_faction.has(faction_id):
			flags_by_faction[faction_id] = flag_factions(world, faction_id)

		var fl: PackedInt32Array = flags_by_faction[faction_id]
		for k in range(fl.size()):
			var pts: PackedVector2Array = flag_points(rect, k)
			var flag_color: Color = Tuning.FACTION_COLORS[fl[k] % Tuning.FACTION_COLORS.size()]
			draw_colored_polygon(pts, flag_color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), OUTLINE_COLOR, 1.0)

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
			# LabelPool offsets by (-20, -18); +26 puts the name just below the hero's feet.
			label_pool.set_captain(slot, text, Vector2(stacks.x[i], stacks.y[i] + 26.0))
		else:
			label_pool.hide_captain(slot)
