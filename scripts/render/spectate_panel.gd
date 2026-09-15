class_name SpectatePanel
extends CanvasLayer
## Manager of InfoWindow popovers shown on left-click of a world-view stack or a
## battle-view marble. Source: docs/ARCHITECTURE.md §14.4,
## .warboss-horde/slices/m6-ui.md, .warboss-horde/slices/spectate-windows.md.

signal follow_requested(stack_id: int)
signal center_requested(stack_id: int)

const TRAIT_NAMES := ["Charger", "Cautious", "Tyrant", "Builder"]
const MAX_WINDOWS := 6
const REFRESH := 0.5
const SPAWN_OFFSET := Vector2(16, 16)
const PORTRAIT_CACHE_MAX := 128
const MAX_HERO_LINES := 6

var world: World
var shown_stack: int = -1

var _root: Control
var _windows: Dictionary = {}     # key ("s<stack>" / "u<unit>") -> InfoWindow
var _order: Array = []            # keys, oldest first
var _timer: float = 0.0
var _portraits: Dictionary = {}   # "h<unit>" / "g<colour index>" -> AtlasTexture
var _gens: Dictionary = {}        # window key -> gen of its slot when opened


func build(w: World) -> void:
	world = w

	_root = Control.new()
	_root.name = "SpectateWindows"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func _gen_of(key: String) -> int:
	var id: int = int(key.substr(1))
	return world.stacks.gen[id] if key.begins_with("s") else world.units.gen[id]


## Left-click on a stack in the world view.
func show_stack(stack_id: int, screen_pos: Vector2 = Vector2(-1, -1)) -> void:
	if world == null or stack_id < 0 or stack_id >= world.stacks.n:
		return
	var win := _open("s%d" % stack_id, screen_pos)
	shown_stack = stack_id
	_fill_stack(win, stack_id)


## Left-click on a marble in the battle view (nearest within 12 px).
func show_unit(w: World, unit_id: int, screen_pos: Vector2 = Vector2(-1, -1)) -> void:
	world = w
	if world == null or unit_id < 0 or unit_id >= world.units.n:
		return
	var win := _open("u%d" % unit_id, screen_pos)
	shown_stack = -1
	_fill_unit(win, unit_id)


func _open(key: String, screen_pos: Vector2) -> InfoWindow:
	if _windows.has(key) and _gens.get(key, -1) != _gen_of(key):
		close_window(key)

	if _windows.has(key):
		var existing: InfoWindow = _windows[key]
		existing.move_to_front()
		_order.erase(key)
		_order.append(key)
		return existing

	while _windows.size() >= MAX_WINDOWS:
		close_window(_order[0])

	var win := InfoWindow.new()
	win.key = key
	_root.add_child(win)
	_windows[key] = win
	_order.append(key)
	_gens[key] = _gen_of(key)

	win.close_pressed.connect(close_window.bind(key))
	if key.begins_with("s"):
		var sid: int = int(key.substr(1))
		win.follow_pressed.connect(func(): follow_requested.emit(sid))
		win.center_pressed.connect(func(): center_requested.emit(sid))

	var p: Vector2 = screen_pos
	if p.x < 0.0:
		p = get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO
	win.position = p + SPAWN_OFFSET
	if is_inside_tree():
		win.position = InfoWindow.clamp_pos(win.position, win.get_combined_minimum_size(), get_viewport().get_visible_rect().size)

	return win


func close_window(key: String) -> void:
	if not _windows.has(key):
		return
	var win: InfoWindow = _windows[key]
	_windows.erase(key)
	_order.erase(key)
	_gens.erase(key)
	# Never free() here: this runs inside the window's own close_pressed emission.
	if win.get_parent() != null:
		win.get_parent().remove_child(win)
	win.queue_free()

	shown_stack = -1
	for i in range(_order.size() - 1, -1, -1):
		var k: String = _order[i]
		if k.begins_with("s"):
			shown_stack = int(k.substr(1))
			break


func close() -> void:
	for key in _order.duplicate():
		close_window(key)
	shown_stack = -1


func window_count() -> int:
	return _windows.size()


func has_window(key: String) -> bool:
	return _windows.has(key)


## Not `get_window`: that name is Node's built-in.
func window_for(key: String) -> InfoWindow:
	return _windows[key] if _windows.has(key) else null


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		refresh_now()


func refresh_now() -> void:
	if world == null:
		return
	for key in _order:
		var k: String = key
		var win: InfoWindow = _windows[k]
		var id: int = int(k.substr(1))
		if k.begins_with("s"):
			_fill_stack(win, id)
		else:
			_fill_unit(win, id)


func _fill_stack(win: InfoWindow, stack_id: int) -> void:
	if _gens.get("s%d" % stack_id, -1) != world.stacks.gen[stack_id]:
		win.set_content(win._title.text, PackedStringArray(["Fallen"]), win._portrait.texture, true)
		win.set_buttons_enabled(false)
		return

	var stacks := world.stacks
	var f: int = stacks.faction[stack_id]

	if stacks.alive[stack_id] == 0:
		win.set_content(stacks.label(stack_id), PackedStringArray(["Fallen"]), _portrait(-1, f), true)
		win.set_buttons_enabled(false)
		return

	var faction_label: String = world.faction_names[f] if f < world.faction_names.size() else "Faction %d" % f

	var captain_u: int = stacks.captain_unit[stack_id]
	var captain_line := "Captain: none"
	var captain_alive := captain_u >= 0 and world.units.alive[captain_u] == 1
	if captain_alive:
		captain_line = "Captain: %s (%s)" % [_unit_name(captain_u), _trait_name(world.units.ctrait[captain_u])]

	var heroes: Array = []
	var weapon_counts: Array = []
	weapon_counts.resize(Tuning.WEAPON_NAMES.size())
	weapon_counts.fill(0)
	var troop_count := 0
	for u in range(world.units.n):
		if world.units.alive[u] == 1 and world.units.stack[u] == stack_id:
			if world.units.hero[u] == 1:
				heroes.append(u)
			else:
				troop_count += 1
				var wid: int = world.units.weapon[u]
				if wid >= 0 and wid < weapon_counts.size():
					weapon_counts[wid] += 1
	heroes.sort_custom(func(a, b): return world.units.kills[a] > world.units.kills[b])

	var lines: Array = [faction_label, captain_line]
	lines.append("Gold: %d" % int(stacks.gold[stack_id]))
	if captain_alive:
		lines.append("Age: %ds / %ds" % [int(world.time - world.units.career_start[captain_u]), int(Tuning.HERO_LIFESPAN)])
	var has_town := false
	for i in range(world.towns.size()):
		if world.town_owner[i] == f:
			has_town = true
			break
	if not has_town:
		lines.append("Free company")
	lines.append("Heroes: %d" % heroes.size())
	for k in range(mini(MAX_HERO_LINES, heroes.size())):
		var u: int = heroes[k]
		lines.append("  %s — %d kills" % [_unit_name(u), world.units.kills[u]])
	if heroes.size() > MAX_HERO_LINES:
		lines.append("  +%d more" % (heroes.size() - MAX_HERO_LINES))
	lines.append("Troops: %d" % troop_count)
	for wid in range(weapon_counts.size()):
		if weapon_counts[wid] > 0:
			var weapon_name: String = Tuning.WEAPON_NAMES[wid]
			lines.append("  %ss — %d" % [weapon_name.capitalize(), weapon_counts[wid]])
	# UNDECIDED: "goal name" has no fiat wording; using the Stacks.Goal enum's
	# own key (e.g. "HUNT_WEAK") rather than inventing display prose.
	lines.append("Goal: %s" % Stacks.Goal.keys()[stacks.goal[stack_id]])

	var portrait_unit: int = captain_u if captain_alive else -1
	win.set_content(stacks.label(stack_id), PackedStringArray(lines), _portrait(portrait_unit, f), true)
	win.set_buttons_enabled(true)


func _fill_unit(win: InfoWindow, unit_id: int) -> void:
	if _gens.get("u%d" % unit_id, -1) != world.units.gen[unit_id]:
		win.set_content(win._title.text, PackedStringArray(["Fallen"]), win._portrait.texture, false)
		return

	var f: int = world.units.faction[unit_id]
	var faction_label: String = world.faction_names[f] if f < world.faction_names.size() else "Faction %d" % f
	var lines := [
		faction_label,
		"Rank %d  Kills %d  XP %d" % [world.units.rank[unit_id], world.units.kills[unit_id], world.units.xp[unit_id]],
		"Trait: %s" % _trait_name(world.units.ctrait[unit_id]),
	]
	if world.units.hero[unit_id] == 1:
		lines.append("Hero")
	lines.append("Fate: %s" % Units.Fate.keys()[world.units.fate[unit_id]])
	win.set_content(_unit_name(unit_id), PackedStringArray(lines), _portrait(unit_id, f), false)


func _portrait(u: int, f: int) -> Texture2D:
	if not FileAccess.file_exists(CharLooks.BASE + "catalog.json"):
		return null

	var key: String
	var img: Image
	if u >= 0 and world.units.looks.has(u):
		key = "h%d:%d" % [u, world.units.gen[u]]
		if _portraits.has(key):
			return _portraits[key]
		img = CharLooks.compose(world.units.looks[u], Color(1, 1, 1))
	else:
		var ci: int = posmod(f, Tuning.FACTION_COLORS.size())
		key = "g%d" % ci
		if _portraits.has(key):
			return _portraits[key]
		var c: Color = Tuning.FACTION_COLORS[ci]
		img = CharLooks.compose(CharLooks.generic_warrior(), c)

	if _portraits.size() >= PORTRAIT_CACHE_MAX:
		_portraits.clear()
	var at := AtlasTexture.new()
	at.atlas = ImageTexture.create_from_image(img)
	at.region = Rect2(CharLooks.frame_rect(0, 1))
	_portraits[key] = at
	return at


func _unit_name(u: int) -> String:
	return world.units.names.get(u, "Unit %d" % u)


func _trait_name(t: int) -> String:
	return TRAIT_NAMES[t] if t >= 0 else "—"


func _input(event: InputEvent) -> void:
	if _order.size() == 0:
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and kev.keycode == KEY_ESCAPE:
			close_window(_order.back())
			get_viewport().set_input_as_handled()
