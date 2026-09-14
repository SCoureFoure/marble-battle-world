class_name SpectatePanel
extends CanvasLayer
## Bottom-right info panel shown on left-click of a world-view stack or a
## battle-view marble. Source: docs/ARCHITECTURE.md §14.4,
## .warboss-horde/slices/m6-ui.md.

const PANEL_WIDTH := 280.0
const PANEL_HEIGHT := 220.0
const TRAIT_NAMES := ["Charger", "Cautious", "Tyrant", "Builder"]

var world: World
var shown_stack: int = -1

var _panel: PanelContainer
var _label: Label


func build(w: World) -> void:
	world = w

	_panel = PanelContainer.new()
	_panel.name = "SpectatePanelContainer"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_top = -PANEL_HEIGHT
	_panel.visible = false
	add_child(_panel)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_panel.add_child(_label)


## Left-click on a stack in the world view.
func show_stack(stack_id: int) -> void:
	if world == null or stack_id < 0 or stack_id >= world.stacks.n:
		return
	shown_stack = stack_id
	var stacks := world.stacks
	var f: int = stacks.faction[stack_id]
	var faction_label: String = world.faction_names[f] if f < world.faction_names.size() else "Faction %d" % f

	var captain_u: int = stacks.captain_unit[stack_id]
	var captain_line := "Captain: none"
	var captain_alive := captain_u >= 0 and world.units.alive[captain_u] == 1
	if captain_alive:
		captain_line = "Captain: %s (%s)" % [_unit_name(captain_u), _trait_name(world.units.ctrait[captain_u])]

	var members: Array = []
	var hero_count := 0
	for u in range(world.units.n):
		if world.units.alive[u] == 1 and world.units.stack[u] == stack_id:
			members.append(u)
			if world.units.hero[u] == 1:
				hero_count += 1
	members.sort_custom(func(a, b): return world.units.kills[a] > world.units.kills[b])

	var lines: Array = [stacks.label(stack_id), faction_label, captain_line]
	lines.append("Gold: %d" % int(stacks.gold[stack_id]))
	if captain_alive:
		lines.append("Age: %ds / %ds" % [int(world.time - world.units.career_start[captain_u]), int(Tuning.HERO_LIFESPAN)])
	lines.append("Heroes: %d" % hero_count)
	var has_town := false
	for i in range(world.towns.size()):
		if world.town_owner[i] == f:
			has_town = true
			break
	if not has_town:
		lines.append("Free company")
	for k in range(mini(5, members.size())):
		var u: int = members[k]
		lines.append("%s — %d kills" % [_unit_name(u), world.units.kills[u]])
	# UNDECIDED: "goal name" has no fiat wording; using the Stacks.Goal enum's
	# own key (e.g. "HUNT_WEAK") rather than inventing display prose.
	lines.append("Goal: %s" % Stacks.Goal.keys()[stacks.goal[stack_id]])

	_label.text = "\n".join(lines)
	_panel.visible = true


## Left-click on a marble in the battle view (nearest within 12 px).
func show_unit(w: World, unit_id: int) -> void:
	world = w
	shown_stack = -1
	if world == null or unit_id < 0 or unit_id >= world.units.n:
		return
	var lines := [
		_unit_name(unit_id),
		"Faction %d" % world.units.faction[unit_id],
		"Rank %d  Kills %d  XP %d" % [world.units.rank[unit_id], world.units.kills[unit_id], world.units.xp[unit_id]],
		"Trait: %s" % _trait_name(world.units.ctrait[unit_id]),
	]
	if world.units.hero[unit_id] == 1:
		lines.append("Hero")
	lines.append("Fate: %s" % Units.Fate.keys()[world.units.fate[unit_id]])
	_label.text = "\n".join(lines)
	_panel.visible = true


func close() -> void:
	shown_stack = -1
	_panel.visible = false


func _unit_name(u: int) -> String:
	return world.units.names.get(u, "Unit %d" % u)


func _trait_name(t: int) -> String:
	return TRAIT_NAMES[t] if t >= 0 else "—"


func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and kev.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
