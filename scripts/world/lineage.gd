class_name Lineage extends RefCounted
## Captain lineage: Roman numerals, captain creation, legend naming.
## docs/ARCHITECTURE.md §13.3.
## This slice (m5-fields) implements only numeral, make_captain, check_legend.
## Deferred to slice m5-lineage: on_battle_finished, note_settle, note_raze,
## update_trait.

enum Trait { CHARGER = 0, CAUTIOUS = 1, TYRANT = 2, BUILDER = 3 }


static func numeral(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var num := n
	var result := ""
	for i in range(vals.size()):
		var v: int = vals[i]
		var s: String = syms[i]
		while num >= v:
			result += s
			num -= v
	return result


## Captain creation everywhere goes through this: sets dynasty [name_base, 1]
## and names[u] = name_base + " I".
static func make_captain(w: World, u: int, name_base: String) -> void:
	w.units.is_captain[u] = 1
	w.units.dynasty[u] = [name_base, 1]
	w.units.names[u] = name_base + " I"


## Called by the bridge copy-back when rank becomes LEGEND_RANK.
static func check_legend(w: World, u: int) -> void:
	if w.units.rank[u] != Tuning.LEGEND_RANK:
		return
	w.units.names[u] = NameGen.legend_name(w.rng, w.units.kills[u])
