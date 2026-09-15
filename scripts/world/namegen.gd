class_name NameGen extends RefCounted
## Syllable-table name generator for stacks and their captains.

const ONSETS := ["ka", "to", "mu", "ren", "vel", "dor", "ash", "bri", "gal", "ith", "or", "ul"]
const CODAS := ["n", "r", "th", "s", "l", "k", "", "m"]
const KINGDOM_SUFFIXES := ["ia", "mark", "land", "gard"]
const LEGEND_ADJECTIVES := ["Mudslide", "Ironhand", "Redspin", "Grim", "Quiet", "Wolfish", "Brassbound", "Hollow"]
const TOWN_SUFFIXES := ["ford", "ton", "wick", "holm", "burg", "stead", "by", "mere"]


static func stack_name(rng: RandomNumberGenerator) -> String:
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var b: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
	return a.capitalize() + b + c


## Captain name without the dynasty numeral suffix (M5: Lineage.make_captain
## appends " I" via dynasty numeral 1).
static func captain_name_base(rng: RandomNumberGenerator) -> String:
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
	return a.capitalize() + c


static func captain_name(rng: RandomNumberGenerator) -> String:
	return captain_name_base(rng) + " I"


static func kingdom_name(rng: RandomNumberGenerator) -> String:
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var b: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var suf: String = KINGDOM_SUFFIXES[rng.randi_range(0, KINGDOM_SUFFIXES.size() - 1)]
	return a.capitalize() + b + suf


static func legend_name(rng: RandomNumberGenerator, kills: int) -> String:
	var adj: String = LEGEND_ADJECTIVES[rng.randi_range(0, LEGEND_ADJECTIVES.size() - 1)]
	var a: String = ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
	return "%s %s, killer of %d" % [adj, a.capitalize() + c, kills]


static func hero_epithet(rng: RandomNumberGenerator) -> String:
	return LEGEND_ADJECTIVES[rng.randi_range(0, LEGEND_ADJECTIVES.size() - 1)]


## Town name derived only from its tile, so it needs no saved state and draws nothing from the world rng.
static func town_name(tile: Vector2i) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = absi(tile.x * 73856093 ^ tile.y * 19349663) + 7919
	var a: String = ONSETS[r.randi_range(0, ONSETS.size() - 1)]
	var c: String = CODAS[r.randi_range(0, CODAS.size() - 1)]
	var suf: String = TOWN_SUFFIXES[r.randi_range(0, TOWN_SUFFIXES.size() - 1)]
	return a.capitalize() + c + suf
