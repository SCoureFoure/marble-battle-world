extends SceneTree
## A world faction's battle marbles and towers use its overworld colour, not
## the colour of the local battle index it happens to occupy.

const TestKit = preload("res://scripts/tests/test_kit.gd")


func mk_stack(w: World, f: int, tx: int, ty: int, n_units: int, prev_dx: int) -> int:
	var c := w.map.center_of(tx, ty)
	var id := w.stacks.add(f, c.x, c.y, "S")
	w.stacks.prev_x[id] = c.x + prev_dx * 64
	for i in range(n_units):
		w.units.add(f, 0, 1, false, id)
	var cap_id := w.units.add(f, 1, 1, true, id)
	w.stacks.captain_unit[id] = cap_id
	w.stacks.recount(w.units)
	return id


func _init() -> void:
	var t := TestKit.new()

	# 1. faction_color: palette override, -1 and empty fall back to identity.
	var pal := PackedInt32Array([9, -1])
	t.check(BattleRenderer.faction_color(0, pal) == Tuning.FACTION_COLORS[9], "palette[0]=9 -> colour 9")
	t.check(BattleRenderer.faction_color(1, pal) == Tuning.FACTION_COLORS[1], "palette -1 -> identity")
	t.check(BattleRenderer.faction_color(2, pal) == Tuning.FACTION_COLORS[2], "past palette end -> identity")
	t.check(BattleRenderer.faction_color(3, PackedInt32Array()) == Tuning.FACTION_COLORS[3], "empty palette -> identity")

	# 2. world factions 3 and 5 fight; local indices differ from world ids.
	var w := World.new()
	w.setup_blank(12, 8, 7)
	var sa := mk_stack(w, 3, 5, 4, 6, -1)
	var sb := mk_stack(w, 5, 5, 4, 6, 1)
	var inst := BattleBridge.start(w, sa, sb)
	var remapped := false
	for lf in range(inst.faction_map.size()):
		if inst.faction_map[lf] >= 0 and inst.faction_map[lf] != lf:
			remapped = true
	t.check(remapped, "case2 some local index differs from its world faction")

	var palette := BattleView.build_palette(inst, w)
	var buf := BattleRenderer.build_buffer(inst.state, palette)
	var match_ok := true
	for i in range(inst.state.n):
		var wf: int = inst.faction_map[inst.state.faction_id[i]]
		var want: Color = Tuning.FACTION_COLORS[wf % Tuning.FACTION_COLORS.size()]
		var b := i * 16
		if not (t.approx(buf[b + 12], want.r) and t.approx(buf[b + 13], want.g) and t.approx(buf[b + 14], want.b)):
			match_ok = false
	t.check(inst.state.n > 0, "case2 marbles spawned")
	t.check(match_ok, "case2 every marble uses its world faction's overworld colour")

	# 3. unused local slots stay -1; faction_color entry is honoured.
	for lf in range(inst.faction_map.size()):
		if inst.faction_map[lf] < 0:
			t.check(palette[lf] == -1, "case3 unused slot %d -> -1" % lf)
	w.faction_color[5] = 12
	var palette3 := BattleView.build_palette(inst, w)
	var lf5 := -1
	for lf in range(inst.faction_map.size()):
		if inst.faction_map[lf] == 5:
			lf5 = lf
	t.check(lf5 >= 0 and palette3[lf5] == 12, "case3 palette follows world.faction_color")

	t.finish()
	quit()
