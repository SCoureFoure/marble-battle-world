class_name NameGen extends RefCounted
## Syllable-table name generator for stacks and their captains.

const ONSETS := ["ka", "to", "mu", "ren", "vel", "dor", "ash", "bri", "gal", "ith", "or", "ul"]
const CODAS := ["n", "r", "th", "s", "l", "k", "", "m"]


static func stack_name(rng: RandomNumberGenerator) -> String:
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var b: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
	return a.capitalize() + b + c


static func captain_name(rng: RandomNumberGenerator) -> String:
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
	return a.capitalize() + c + " I"
