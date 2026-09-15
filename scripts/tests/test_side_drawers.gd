extends SceneTree
## Collapsible side drawers: factions ledger (right edge) and event ticker
## (left edge). Source: .warboss-horde/slices/drawer-ledger.md,
## drawer-timeline.md, drawer-world-scene.md. Placement is judged by capture.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()
	var w := World.create(1)

	# 1. drawer_pos: right drawer hugs the right edge, left drawer the left edge, both vertically centred
	t.check(LedgerPanel.drawer_pos(Vector2(1600, 900), Vector2(300, 280)) == Vector2(1300, 310), "1a: ledger drawer_pos")
	t.check(LedgerPanel.drawer_pos(Vector2(400, 300), Vector2(24, 40)) == Vector2(376, 130), "1b: ledger collapsed tab")
	t.check(TimelinePanel.drawer_pos(Vector2(1600, 900), Vector2(340, 301)) == Vector2(0, 299.5), "1c: timeline drawer_pos")

	# 2. ledger drawer structure + collapse
	var lp := LedgerPanel.new()
	lp.build(w)
	t.check(lp._drawer is HBoxContainer and lp._drawer.get_parent() == lp, "2a: ledger drawer is a direct HBoxContainer child")
	t.check(lp._drawer.get_child_count() == 2 and lp._drawer.get_child(0) == lp._tab and lp._drawer.get_child(1) == lp._panel, "2b: ledger order [tab, panel]")
	t.check(lp.collapsed == false and lp._panel.visible and lp._tab.text == ">", "2c: ledger starts open, tab '>'")
	var row0: Label = lp._rows[0]["label"]
	t.check("units" in row0.text and lp._panel.custom_minimum_size.x == LedgerPanel.PANEL_WIDTH, "2c2: open rows show stats at full width")
	t.check(lp._panel.has_theme_stylebox_override("panel") and lp._panel.get_theme_stylebox("panel") is StyleBoxFlat
		and (lp._panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == LedgerPanel.BG_COLOR and LedgerPanel.BG_COLOR.a >= 0.85, "2c3: opaque background")
	lp.toggle_collapsed()
	t.check(lp.collapsed == true and lp._panel.visible and lp._tab.text == "<", "2d: ledger collapsed keeps panel visible, tab '<'")
	var name0: String = w.faction_names[0] if w.faction_names.size() > 0 else "Faction 0"
	t.check(not ("units" in row0.text) and row0.text.length() > 0 and lp._panel.custom_minimum_size.x == 0.0, "2d2: collapsed rows show names only, panel shrinks")
	var any_name := false
	for r in lp._rows:
		var lbl: Label = r["label"]
		if lbl.text.begins_with(name0):
			any_name = true
	t.check(any_name, "2d3: collapsed rows still carry faction names")
	lp.set_collapsed(true)
	t.check(lp.collapsed == true and lp._tab.text == "<", "2e: set_collapsed idempotent")
	lp.set_collapsed(false)
	t.check(lp.collapsed == false and lp._panel.visible and lp._tab.text == ">" and "units" in row0.text, "2f: ledger reopened with stats")
	lp._tab.pressed.emit()
	t.check(lp.collapsed == true, "2g: tab press toggles")
	lp.free()

	# 3. timeline drawer structure + collapse
	var tp := TimelinePanel.new()
	tp.build(w)
	t.check(tp._drawer is HBoxContainer and tp._drawer.get_parent() == tp, "3a: timeline drawer is a direct HBoxContainer child")
	t.check(tp._drawer.get_child_count() == 2 and tp._drawer.get_child(0) == tp._panel and tp._drawer.get_child(1) == tp._tab, "3b: timeline order [panel, tab]")
	t.check(tp._label.get_parent() == tp._panel, "3c: label inside panel")
	t.check(tp.collapsed == false and tp._panel.visible and tp._tab.text == "<", "3d: timeline starts open, tab '<'")
	tp.toggle_collapsed()
	t.check(tp.collapsed == true and not tp._panel.visible and tp._tab.text == ">", "3e: timeline collapsed, tab '>'")
	tp._tab.pressed.emit()
	t.check(tp.collapsed == false and tp._panel.visible, "3f: tab press reopens")
	t.check(tp._label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and tp._label.custom_minimum_size.x == TimelinePanel.LOG_WIDTH, "3g: wrapped fixed-width log")
	w.log_event("hello drawer")
	tp._refresh()
	t.check(tp._label.text.ends_with("hello drawer"), "3h: refresh still fills the label")
	tp.free()

	# 4. world scene wiring
	var S: GDScript = load("res://scripts/world_scene.gd")
	t.check(S != null and S.can_instantiate(), "4a: world_scene loads")

	t.finish()
	quit()
