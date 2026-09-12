class_name LedgerPanel
extends CanvasLayer
## Faction power ledger overlay. Source: docs/ARCHITECTURE.md §12.6,
## .warboss-horde/slices/m4-render.md.

const PANEL_WIDTH := 260.0
const SWATCH_SIZE := 14.0

var world: World

var _panel: PanelContainer
var _vbox: VBoxContainer
var _rows: Array = []   # per display row (rank, not faction): {swatch: ColorRect, label: Label}
var _timer: float = 0.0


func build(w: World) -> void:
	world = w

	_panel = PanelContainer.new()
	_panel.name = "LedgerPanelContainer"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.name = "LedgerRows"
	_panel.add_child(_vbox)

	_build_rows()
	_position_panel()
	_refresh()


func _position_panel() -> void:
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	_panel.position = Vector2(size.x - PANEL_WIDTH, 0.0)


func _build_rows() -> void:
	for _f in range(world.faction_count):
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		row.add_child(swatch)
		var label := Label.new()
		row.add_child(label)
		_vbox.add_child(row)
		_rows.append({"swatch": swatch, "label": label})


func _process(delta: float) -> void:
	if world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = Tuning.LEDGER_REFRESH
	_refresh()


func _refresh() -> void:
	var entries: Array = []
	for f in range(world.faction_count):
		var units := 0
		for u in range(world.units.n):
			if world.units.alive[u] == 1 and world.units.faction[u] == f:
				units += 1
		var towns := 0
		for t in range(world.towns.size()):
			if world.town_owner[t] == f:
				towns += 1
		var stack_count := 0
		for s in range(world.stacks.n):
			if world.stacks.alive[s] == 1 and world.stacks.faction[s] == f:
				stack_count += 1
		var power := units + 50 * towns
		entries.append({"faction": f, "units": units, "towns": towns, "stacks": stack_count, "power": power})

	entries.sort_custom(func(a, b): return a["power"] > b["power"])

	for r in range(entries.size()):
		if r >= _rows.size():
			break
		var e: Dictionary = entries[r]
		var f: int = e["faction"]
		var row: Dictionary = _rows[r]
		var swatch: ColorRect = row["swatch"]
		var label: Label = row["label"]
		swatch.color = Tuning.FACTION_COLORS[f % Tuning.FACTION_COLORS.size()]
		# UNDECIDED: the row text format "%s ... units %d towns %d stacks %d"
		# (m4-render.md §fiat) has no faction-name source anywhere in the
		# codebase (no `World` faction-name array/method); using "Faction %d"
		# as the %s placeholder.
		var faction_label := "Faction %d" % f
		if r == 0:
			label.text = "%s  ♛ units %d  towns %d  stacks %d" % [faction_label, e["units"], e["towns"], e["stacks"]]
		else:
			label.text = "%s  units %d  towns %d  stacks %d" % [faction_label, e["units"], e["towns"], e["stacks"]]
