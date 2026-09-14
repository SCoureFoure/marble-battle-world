class_name Looks extends RefCounted
## Captain/hero appearance (docs/ARCHITECTURE.md §20). A look is rolled once,
## with a private RNG so the world simulation is unaffected, and kept for life.

static func seed_for(w: World, u: int) -> int:
	return hash("%d:%d:%.3f" % [w.rng.seed, u, w.time])


## Gives unit `u` a look if it has none. No-op when it already has one or when
## the character catalog is unavailable.
static func ensure(w: World, u: int) -> void:
	if w.units.looks.has(u):
		return
	if CharLooks.catalog().is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(w, u)
	var sex: String = "f" if rng.randf() < 0.5 else "m"
	w.units.looks[u] = CharLooks.random_hero(rng, sex)
