extends SceneTree
## Draggable detail popovers: InfoWindow + SpectatePanel window manager.
## Source: .warboss-horde/slices/info-window.md, spectate-windows.md,
## spectate-world-scene.md. Placement/look judged by capture.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func _init() -> void:
	var t := TestKit.new()

	# 1. InfoWindow.clamp_pos
	t.check(InfoWindow.clamp_pos(Vector2(-5, 900), Vector2(300, 200), Vector2(1600, 900)) == Vector2(0, 700), "1a: clamp low x, high y")
	t.check(InfoWindow.clamp_pos(Vector2(1500, 10), Vector2(300, 200), Vector2(1600, 900)) == Vector2(1300, 10), "1b: clamp high x")
	t.check(InfoWindow.clamp_pos(Vector2(50, 50), Vector2(300, 200), Vector2(200, 100)) == Vector2(0, 0), "1c: window bigger than view pins to 0,0")

	# 2. InfoWindow structure + content
	var win := InfoWindow.new()
	t.check(win is PanelContainer, "2a: InfoWindow is a PanelContainer")
	t.check(win.has_theme_stylebox_override("panel") and (win.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == InfoWindow.BG_COLOR, "2b: opaque stylebox")
	t.check(win._close.text == "x" and win._follow.text == "Follow" and win._center.text == "Centre", "2c: button labels")
	t.check(win._portrait.custom_minimum_size == Vector2(InfoWindow.PORTRAIT_SIZE, InfoWindow.PORTRAIT_SIZE)
		and win._portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "2d: portrait box")
	var img := Image.create_empty(48, 64, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	win.set_content("Title A", PackedStringArray(["one", "two"]), tex, true)
	t.check(win._title.text == "Title A" and win._body.text == "one\ntwo" and win._portrait.texture == tex
		and win._portrait.visible and win._buttons.visible, "2e: set_content with portrait + buttons")
	win.set_content("B", PackedStringArray(["x"]), null, false)
	t.check(not win._portrait.visible and not win._buttons.visible, "2f: no portrait, no buttons")
	win.set_buttons_enabled(false)
	t.check(win._follow.disabled and win._center.disabled, "2g: buttons disabled")
	win.set_buttons_enabled(true)
	t.check(not win._follow.disabled and not win._center.disabled, "2h: buttons enabled")

	# 3. InfoWindow signals + drag
	var fired := {"close": 0, "follow": 0, "center": 0}
	win.close_pressed.connect(func(): fired["close"] += 1)
	win.follow_pressed.connect(func(): fired["follow"] += 1)
	win.center_pressed.connect(func(): fired["center"] += 1)
	win._close.pressed.emit()
	win._follow.pressed.emit()
	win._center.pressed.emit()
	t.check(fired["close"] == 1 and fired["follow"] == 1 and fired["center"] == 1, "3a: buttons re-emit window signals")
	win.position = Vector2(100, 100)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	win._on_title_input(press)
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(10, 5)
	win._on_title_input(mm)
	t.check(win.position == Vector2(110, 105), "3b: drag moves by relative")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	win._on_title_input(release)
	win._on_title_input(mm)
	t.check(win.position == Vector2(110, 105), "3c: no move after release")
	win.free()

	# 4. SpectatePanel window manager
	var w := World.create(1)
	var sp := SpectatePanel.new()
	sp.build(w)
	var alive_stacks: Array = []
	for i in range(w.stacks.n):
		if w.stacks.alive[i] == 1:
			alive_stacks.append(i)
	t.check(alive_stacks.size() >= 7, "4pre: at least 7 alive stacks")
	var s0: int = alive_stacks[0]
	sp.show_stack(s0, Vector2(10, 10))
	t.check(sp.window_count() == 1 and sp.shown_stack == s0 and sp.has_window("s%d" % s0), "4a: one stack window")
	var w0: InfoWindow = sp.window_for("s%d" % s0)
	t.check(w0._title.text == w.stacks.label(s0) and w0._buttons.visible and not w0._follow.disabled, "4b: stack window title + buttons")
	t.check(w0._portrait.texture is AtlasTexture and (w0._portrait.texture as AtlasTexture).region == Rect2(CharLooks.frame_rect(0, 1)), "4c: portrait is front idle frame")
	sp.show_stack(s0, Vector2(500, 500))
	t.check(sp.window_count() == 1 and is_same(sp.window_for("s%d" % s0), w0), "4d: reopening same stack reuses window")
	for k in range(1, 7):
		sp.show_stack(alive_stacks[k], Vector2(10, 10))
	t.check(sp.window_count() == SpectatePanel.MAX_WINDOWS and not sp.has_window("s%d" % s0)
		and sp.has_window("s%d" % alive_stacks[6]) and sp.shown_stack == alive_stacks[6], "4e: cap evicts oldest")

	# 5. follow / centre signals carry the stack id
	var got := {"follow": -1, "center": -1}
	sp.follow_requested.connect(func(id: int): got["follow"] = id)
	sp.center_requested.connect(func(id: int): got["center"] = id)
	var s6: int = alive_stacks[6]
	var w6: InfoWindow = sp.window_for("s%d" % s6)
	w6.follow_pressed.emit()
	w6.center_pressed.emit()
	t.check(got["follow"] == s6 and got["center"] == s6, "5a: window buttons -> panel signals with stack id")

	# 6. live refresh + fallen
	w.stacks.alive[s6] = 0
	sp.refresh_now()
	t.check("Fallen" in w6._body.text and w6._follow.disabled and w6._center.disabled, "6a: dead stack shows Fallen, buttons disabled")

	# 7. unit window
	var cap: int = w.stacks.captain_unit[alive_stacks[1]]
	t.check(cap >= 0, "7pre: captain exists")
	sp.show_unit(w, cap, Vector2(20, 20))
	var wu: InfoWindow = sp.window_for("u%d" % cap)
	t.check(wu != null and wu._title.text == w.units.names.get(cap, "Unit %d" % cap) and not wu._buttons.visible, "7a: unit window, no buttons")
	t.check(sp.shown_stack == -1, "7b: unit window clears shown_stack")

	# 8. close one / close all
	var before := sp.window_count()
	sp.close_window("u%d" % cap)
	t.check(sp.window_count() == before - 1 and not sp.has_window("u%d" % cap), "8a: close_window")
	wu = null
	sp.window_for("s%d" % alive_stacks[5]).close_pressed.emit()
	t.check(not sp.has_window("s%d" % alive_stacks[5]), "8b: close button closes its window")
	sp.close()
	t.check(sp.window_count() == 0 and sp.shown_stack == -1, "8c: close() closes all")
	sp.free()

	# 9. world scene still loads
	var S: GDScript = load("res://scripts/world_scene.gd")
	t.check(S != null and S.can_instantiate(), "9a: world_scene loads")

	t.finish()
	quit()
