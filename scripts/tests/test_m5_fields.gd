extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. Lineage.numeral
	t.check(Lineage.numeral(1) == "I", "Lineage.numeral(1) == I")
	t.check(Lineage.numeral(4) == "IV", "Lineage.numeral(4) == IV")
	t.check(Lineage.numeral(9) == "IX", "Lineage.numeral(9) == IX")
	t.check(Lineage.numeral(14) == "XIV", "Lineage.numeral(14) == XIV")
	t.check(Lineage.numeral(40) == "XL", "Lineage.numeral(40) == XL")
	t.check(Lineage.numeral(90) == "XC", "Lineage.numeral(90) == XC")
	t.check(Lineage.numeral(400) == "CD", "Lineage.numeral(400) == CD")
	t.check(Lineage.numeral(1994) == "MCMXCIV", "Lineage.numeral(1994) == MCMXCIV")
	t.check(Lineage.numeral(3999) == "MMMCMXCIX", "Lineage.numeral(3999) == MMMCMXCIX")

	# 2. Units.add defaults; Lineage.make_captain on a blank world
	var u := Units.new(4)
	var id0 := u.add(0, 0, 0, false, -1)
	t.check(u.ctrait[id0] == -1, "Units.add: ctrait[0] == -1")
	t.check(u.c_fights[id0] == 0, "Units.add: c_fights[0] == 0")
	t.check(u.dynasty.is_empty(), "Units.add: dynasty empty")

	var w := World.new()
	w.setup_blank(4, 4, 1)
	var cap_id := w.units.add(0, 1, 1, true, -1)
	Lineage.make_captain(w, cap_id, "Toby")
	t.check(w.units.is_captain[cap_id] == 1, "make_captain: is_captain[0] == 1")
	t.check(w.units.dynasty[cap_id] == ["Toby", 1], "make_captain: dynasty[0] == [Toby, 1]")
	t.check(w.units.names[cap_id] == "Toby I", "make_captain: names[0] == Toby I")

	# 3. Blank world: ktraits/relations helpers
	t.check(w.ktraits.size() == 80, "blank world: ktraits.size() == 80")
	t.check(t.approx(w.ktrait(0, 4), 0.5), "blank world: ktrait(0, 4) approx 0.5")
	w.add_ktrait(0, 4, 0.7)
	t.check(t.approx(w.ktrait(0, 4), 1.0), "add_ktrait(0, 4, 0.7) -> ktrait(0, 4) == 1.0 (clamped)")
	w.add_ktrait(0, 4, -3.0)
	t.check(t.approx(w.ktrait(0, 4), 0.0), "add_ktrait(0, 4, -3.0) -> ktrait(0, 4) == 0.0 (clamped)")

	t.check(w.relation(1, 2) == 0.0, "blank world: relation(1, 2) == 0.0")
	w.add_relation(1, 2, -0.7)
	t.check(t.approx(w.relation(2, 1), -0.7), "add_relation(1, 2, -0.7) -> relation(2, 1) approx -0.7 (symmetric)")
	w.add_relation(1, 2, -0.7)
	t.check(t.approx(w.relation(1, 2), -1.0), "add_relation(1, 2, -0.7) again -> -1.0 (clamped)")
	t.check(w.allied(1, 2) == false, "allied(1, 2) == false")
	w.add_relation(3, 4, 0.6)
	t.check(w.allied(4, 3) == true, "add_relation(3, 4, 0.6) -> allied(4, 3) == true")

	# 4. World.create(42): faction fields + captain naming + determinism
	var w1 := World.create(42)
	t.check(w1.faction_names.size() == 6, "World.create: faction_names.size() == 6")
	var suffixes := ["ia", "mark", "land", "gard"]
	var names_ok := true
	for name in w1.faction_names:
		if String(name).is_empty():
			names_ok = false
		var ends_ok := false
		for suf in suffixes:
			if String(name).ends_with(suf):
				ends_ok = true
		if not ends_ok:
			names_ok = false
	t.check(names_ok, "World.create: faction_names non-empty, ending with a kingdom suffix")
	t.check(w1.faction_alive[0] == 1, "World.create: faction_alive[0] == 1")
	t.check(w1.faction_alive[6] == 0, "World.create: faction_alive[6] == 0")
	t.check(w1.faction_color[5] == 5, "World.create: faction_color[5] == 5")

	var captains_ok := true
	for i in range(w1.stacks.n):
		var cu: int = w1.stacks.captain_unit[i]
		if cu == -1:
			continue
		if not String(w1.units.names[cu]).ends_with(" I"):
			captains_ok = false
		var dyn: Array = w1.units.dynasty[cu]
		if int(dyn[1]) != 1:
			captains_ok = false
	t.check(captains_ok, "World.create: every stack captain's names ends with ' I', dynasty numeral == 1")

	var w2 := World.create(42)
	t.check(w1.faction_names == w2.faction_names, "World.create(42) determinism: equal faction_names")

	# 5. NameGen.legend_name determinism + shape
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 2
	var legend1 := NameGen.legend_name(rng1, 40)
	t.check(legend1.ends_with(", killer of 40"), "legend_name ends with ', killer of 40'")
	t.check(legend1.substr(0, 1) == legend1.substr(0, 1).to_upper(), "legend_name starts with an uppercase letter")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 2
	var legend2 := NameGen.legend_name(rng2, 40)
	t.check(legend1 == legend2, "legend_name: two rngs seed 2 give equal names")

	# 6. Lineage.check_legend
	var wl := World.new()
	wl.setup_blank(4, 4, 3)
	var u_legend := wl.units.add(0, 3, 0, false, -1)
	wl.units.kills[u_legend] = 12
	Lineage.check_legend(wl, u_legend)
	t.check(String(wl.units.names[u_legend]).ends_with(", killer of 12"), "check_legend: rank 3 sets names ending ', killer of 12'")

	var u_low := wl.units.add(0, 2, 0, false, -1)
	wl.units.kills[u_low] = 12
	wl.units.names[u_low] = "Placeholder"
	Lineage.check_legend(wl, u_low)
	t.check(wl.units.names[u_low] == "Placeholder", "check_legend: rank 2 leaves names unchanged")

	# 7. World.log_event
	var we := World.new()
	we.setup_blank(4, 4, 4)
	for i in range(250):
		we.log_event("x")
	t.check(we.events_log.size() == 200, "log_event x250: events_log.size() == 200")
	t.check(we.events_log[we.events_log.size() - 1] == "x", "log_event x250: last == x")

	t.finish()
	quit()
