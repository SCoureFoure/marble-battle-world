extends SceneTree
const TestKit = preload("res://scripts/tests/test_kit.gd")

func _init() -> void:
	var t := TestKit.new()

	# 1. Units.new(8): hero.size() == 8, career_start.size() == 8, mentor[3] == -1, fate[3] == Units.Fate.ACTIVE
	var units := Units.new(8)
	t.check(units.hero.size() == 8, "Units.new(8): hero.size() == 8")
	t.check(units.career_start.size() == 8, "Units.new(8): career_start.size() == 8")
	t.check(units.mentor[3] == -1, "Units.new(8): mentor[3] == -1")
	t.check(units.fate[3] == Units.Fate.ACTIVE, "Units.new(8): fate[3] == Units.Fate.ACTIVE")

	# Set values and add unit, check defaults
	units.mentor[0] = 5
	units.hero[0] = 1
	units.ambition[0] = 0.7
	units.career_start[0] = 9.0
	units.fate[0] = Units.Fate.LORD
	units.n = 0
	var added_id := units.add(1, 0, 1, false, 0)
	t.check(added_id == 0, "Units.add returns 0")
	t.check(units.mentor[0] == -1, "after add: mentor[0] == -1")
	t.check(units.hero[0] == 0, "after add: hero[0] == 0")
	t.check(units.ambition[0] == 0.0, "after add: ambition[0] == 0.0")
	t.check(units.career_start[0] == 0.0, "after add: career_start[0] == 0.0")
	t.check(units.fate[0] == Units.Fate.ACTIVE, "after add: fate[0] == Units.Fate.ACTIVE")

	# 2. Units.Fate enum values
	t.check(Units.Fate.LORD == 1, "Units.Fate.LORD == 1")
	t.check(Units.Fate.RETIRED == 2, "Units.Fate.RETIRED == 2")
	t.check(Stacks.Goal.RESTOCK == 7, "Stacks.Goal.RESTOCK == 7")
	t.check(Stacks.Goal.FOUND == 8, "Stacks.Goal.FOUND == 8")
	t.check(Stacks.Goal.AVENGE == 6, "Stacks.Goal.AVENGE == 6")

	# 3. Stacks.new(4): gold.size() == 4, add() sets gold to 0.0
	var stacks := Stacks.new(4)
	t.check(stacks.gold.size() == 4, "Stacks.new(4): gold.size() == 4")
	stacks.gold[0] = 3.0
	stacks.n = 0
	stacks.add(0, 1.0, 1.0, "S")
	t.check(stacks.gold[0] == 0.0, "Stacks.add: gold[0] == 0.0")

	# 4. World.new(); setup_blank(12, 8, 1)
	var w := World.new()
	w.setup_blank(12, 8, 1)
	t.check(w.town_gold.size() == 0, "setup_blank: town_gold.size() == 0")
	t.check(w.history["restocks"] == 0, "setup_blank: history[restocks] == 0")
	t.check(w.history.size() == 6, "setup_blank: history.size() == 6")

	w.add_town(Vector2i(2, 2), 0)
	t.check(w.town_gold.size() == 1, "after add_town: town_gold.size() == 1")
	t.check(w.town_gold[0] == 0.0, "after add_town: town_gold[0] == 0.0")
	t.check(w.town_lord[0] == -1, "after add_town: town_lord[0] == -1")

	# Append a town by hand and sync
	w.towns.append(Vector2(5, 5))
	w.town_owner.append(-1)
	w.town_gold[0] = 4.0
	w.sync_town_arrays()
	t.check(w.town_gold.size() == 2, "after sync_town_arrays: town_gold.size() == 2")
	t.check(w.town_lord[1] == -1, "after sync_town_arrays: town_lord[1] == -1")
	t.check(w.town_gold[0] == 4.0, "after sync_town_arrays: town_gold[0] kept its value")

	# 5. World.bump()
	w.bump("foundings")
	w.bump("foundings")
	t.check(w.history["foundings"] == 2, "bump(foundings) twice -> history[foundings] == 2")
	w.bump("new_key")
	t.check(w.history["new_key"] == 1, "bump(new_key) -> history[new_key] == 1")

	# 6. BattleInstance.new(0, Vector2i.ZERO).slayers
	var bi := BattleInstance.new(0, Vector2i.ZERO)
	t.check(bi.slayers.size() == 0, "BattleInstance.new: slayers.size() == 0")
	t.check(typeof(bi.slayers) == TYPE_PACKED_INT32_ARRAY, "BattleInstance.new: slayers is PackedInt32Array")

	# 7. World.create(11): history.size() == 6, town_gold.size() == towns.size(), town_lord.size() == towns.size()
	var wc := World.create(11)
	t.check(wc.history.size() == 6, "World.create: history.size() == 6")
	t.check(wc.town_gold.size() == wc.towns.size(), "World.create: town_gold.size() == towns.size()")
	t.check(wc.town_lord.size() == wc.towns.size(), "World.create: town_lord.size() == towns.size()")

	t.finish()
	quit()
