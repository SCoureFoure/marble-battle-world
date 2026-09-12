class_name World extends RefCounted
## Overworld data object (docs/ARCHITECTURE.md §11.6). WorldMap, WorldGen,
## Units, Stacks, NameGen, Pathing are sibling M3 classes written elsewhere.

var rng: RandomNumberGenerator
var map: WorldMap
var towns: PackedVector2Array       # tile coords (x, y); index = town id
var town_owner: PackedInt32Array    # faction or -1
var town_state: PackedInt32Array    # 0 INTACT, 1 RAIDED, 2 RAZED
var town_pop: PackedFloat32Array
var town_recruit: PackedFloat32Array
var town_timer: PackedFloat32Array
var units: Units
var stacks: Stacks
var pathing: Pathing
var battles: Array                  # live BattleInstance
var next_battle_id: int
var scars: Array
var time: float
var faction_count: int
var reinforce: Dictionary           # WorldSim.reinforce: stack id -> battle id, path recomputed once
var plinko_rows: PackedInt32Array   # per faction, init 7
var plinko_bias: PackedFloat32Array # per faction, init 0.0
var plinko_order: Array             # per faction PackedInt32Array
var plinko_log: Array               # [stack, PackedInt32Array slots, Array[String] lines]
var events_log: Array = []          # String, one line per finished battle (M4)
var borders_version: int = 0
var ktraits: PackedFloat32Array     # size MAX_FACTIONS_WORLD*5; index f*5+k (M5)
var relations: PackedFloat32Array   # size MAX_FACTIONS_WORLD^2; index a*MAX_FACTIONS_WORLD+b (M5)
var faction_alive: PackedByteArray  # 1 while the faction has towns or stacks (M5)
var faction_color: PackedInt32Array # index into Tuning.FACTION_COLORS, f % 8 at creation (M5)
var faction_names: Array            # String per faction, NameGen.kingdom_name (M5)
var border_adj: PackedByteArray     # size MAX_FACTIONS_WORLD^2 adjacency cache (M5)
var border_adj_version: int = -1    # borders_version this cache was built from (M5)
var split_cooldown: PackedFloat32Array # per faction, seconds until check_split may split again (M5)
var meta_timer: float = 0.0         # accumulator: Kingdoms.check_split/check_death once per world second (M5)
var watched_battle: int = -1        # BattleInstance.id being watched full-sim, -1 none (M6)

# Clockwise from north: N, NE, E, SE, S, SW, W, NW.
const NEIGHBOR_DIRS := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func _init() -> void:
	rng = null
	map = null
	towns = PackedVector2Array()
	town_owner = PackedInt32Array()
	town_state = PackedInt32Array()
	town_pop = PackedFloat32Array()
	town_recruit = PackedFloat32Array()
	town_timer = PackedFloat32Array()
	units = null
	stacks = null
	pathing = null
	battles = []
	next_battle_id = 0
	scars = []
	time = 0.0
	faction_count = 0
	reinforce = {}
	plinko_rows = PackedInt32Array()
	plinko_bias = PackedFloat32Array()
	plinko_order = []
	plinko_log = []
	borders_version = 0
	ktraits = PackedFloat32Array()
	relations = PackedFloat32Array()
	faction_alive = PackedByteArray()
	faction_color = PackedInt32Array()
	faction_names = []
	border_adj = PackedByteArray()
	border_adj_version = -1
	split_cooldown = PackedFloat32Array()


func setup_blank(cols: int, rows: int, seed: int) -> void:
	map = WorldMap.new(cols, rows, seed)
	map.kind.fill(WorldMap.Kind.PLAINS)
	towns = PackedVector2Array()
	town_owner = PackedInt32Array()
	town_state = PackedInt32Array()
	town_pop = PackedFloat32Array()
	town_recruit = PackedFloat32Array()
	town_timer = PackedFloat32Array()
	units = Units.new(2048)
	stacks = Stacks.new(64)
	pathing = Pathing.new(map)
	rng = RandomNumberGenerator.new()
	rng.seed = seed
	battles = []
	next_battle_id = 0
	scars = []
	time = 0.0
	faction_count = 0
	reinforce = {}

	# fiat: setup_blank seeds each faction's plinko order as the identity
	# permutation (no rng draw), unlike create() which shuffles.
	plinko_rows = PackedInt32Array()
	plinko_bias = PackedFloat32Array()
	plinko_order = []
	for _f in range(Tuning.N_FACTIONS):
		plinko_rows.append(7)
		plinko_bias.append(0.0)
		var order := PackedInt32Array()
		for k in range(Tuning.PLINKO_SLOTS):
			order.append(k)
		plinko_order.append(order)
	plinko_log = []
	borders_version = 0

	ktraits = PackedFloat32Array()
	ktraits.resize(Tuning.MAX_FACTIONS_WORLD * 5)
	ktraits.fill(Tuning.KTRAIT_INIT)
	relations = PackedFloat32Array()
	relations.resize(Tuning.MAX_FACTIONS_WORLD * Tuning.MAX_FACTIONS_WORLD)
	relations.fill(0.0)
	faction_alive = PackedByteArray()
	faction_alive.resize(Tuning.MAX_FACTIONS_WORLD)
	faction_alive.fill(0)
	faction_color = PackedInt32Array()
	faction_color.resize(Tuning.MAX_FACTIONS_WORLD)
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		faction_color[f] = f % 8
	faction_names = []

	border_adj = PackedByteArray()
	border_adj.resize(Tuning.MAX_FACTIONS_WORLD * Tuning.MAX_FACTIONS_WORLD)
	border_adj_version = -1
	split_cooldown = PackedFloat32Array()
	split_cooldown.resize(Tuning.MAX_FACTIONS_WORLD)
	split_cooldown.fill(0.0)
	meta_timer = 0.0


# Passable 8-neighbours of `tile`, clockwise from north.
static func _passable_neighbours(m: WorldMap, tile: Vector2i) -> Array:
	var out: Array = []
	for dir in NEIGHBOR_DIRS:
		var t: Vector2i = tile + dir
		if m.in_bounds(t.x, t.y) and m.passable(t.x, t.y):
			out.append(t)
	return out


static func create(seed: int) -> World:
	var w := World.new()

	# Map generation first: WorldGen draws from map.rng (seeded `seed`).
	w.map = WorldMap.new(Tuning.WORLD_COLS, Tuning.WORLD_ROWS, seed)
	var town_tiles: Array = WorldGen.generate(w.map)

	# add_town so create() and hand-built worlds share one path (fiat, §12.1).
	for ti in range(town_tiles.size()):
		var t: Vector2i = town_tiles[ti]
		var owner := ti if ti < Tuning.N_FACTIONS else -1
		w.add_town(t, owner)

	w.faction_count = Tuning.N_FACTIONS
	w.units = Units.new(16384)
	w.stacks = Stacks.new(512)
	w.pathing = Pathing.new(w.map)
	w.battles = []
	w.next_battle_id = 0
	w.scars = []
	w.time = 0.0
	w.reinforce = {}

	# world.rng, seeded seed + 1, drives stack names, unit counts, weapons,
	# captain names — in faction order, stack order.
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = seed + 1

	for fi in range(Tuning.N_FACTIONS):
		var capital_tile: Vector2i = town_tiles[fi]
		var neighbours := _passable_neighbours(w.map, capital_tile)

		for k in range(Tuning.STACKS_PER_FACTION):
			var tile: Vector2i
			if k == 0:
				tile = capital_tile
			elif k - 1 < neighbours.size():
				tile = neighbours[k - 1]
			else:
				tile = capital_tile

			var pos := w.map.center_of(tile.x, tile.y)
			var stack_name := NameGen.stack_name(w.rng)
			var stack_id := w.stacks.add(fi, pos.x, pos.y, stack_name)

			var unit_count := w.rng.randi_range(Tuning.STACK_UNITS_MIN, Tuning.STACK_UNITS_MAX)
			for _u in range(unit_count):
				var weapon := w.rng.randi_range(0, 4)
				w.units.add(fi, 0, weapon, false, stack_id)

			var captain_id := w.units.add(fi, 1, 1, true, stack_id)
			Lineage.make_captain(w, captain_id, NameGen.captain_name_base(w.rng))
			w.stacks.captain_unit[stack_id] = captain_id
			w.stacks.count[stack_id] = unit_count + 1

	# fiat: per-faction plinko profile, shuffled from world.rng after stacks
	# so stack-building draws stay stable regardless of plinko changes.
	w.plinko_rows = PackedInt32Array()
	w.plinko_bias = PackedFloat32Array()
	w.plinko_order = []
	for _f in range(Tuning.N_FACTIONS):
		w.plinko_rows.append(7)
		w.plinko_bias.append(0.0)
		var order := PackedInt32Array()
		for k in range(Tuning.PLINKO_SLOTS):
			order.append(k)
		for k in range(order.size() - 1, 0, -1):
			var j := w.rng.randi_range(0, k)
			var tmp := order[k]
			order[k] = order[j]
			order[j] = tmp
		w.plinko_order.append(order)
	w.plinko_log = []

	# M5 kingdom fields: faction_names drawn after plinko orders so stack-
	# and plinko-building draws stay stable regardless of naming changes.
	w.ktraits = PackedFloat32Array()
	w.ktraits.resize(Tuning.MAX_FACTIONS_WORLD * 5)
	w.ktraits.fill(Tuning.KTRAIT_INIT)
	w.relations = PackedFloat32Array()
	w.relations.resize(Tuning.MAX_FACTIONS_WORLD * Tuning.MAX_FACTIONS_WORLD)
	w.relations.fill(0.0)
	w.faction_alive = PackedByteArray()
	w.faction_alive.resize(Tuning.MAX_FACTIONS_WORLD)
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		w.faction_alive[f] = 1 if f < w.faction_count else 0
	w.faction_color = PackedInt32Array()
	w.faction_color.resize(Tuning.MAX_FACTIONS_WORLD)
	for f in range(Tuning.MAX_FACTIONS_WORLD):
		w.faction_color[f] = f % 8
	w.faction_names = []
	for _f in range(w.faction_count):
		w.faction_names.append(NameGen.kingdom_name(w.rng))

	w.border_adj = PackedByteArray()
	w.border_adj.resize(Tuning.MAX_FACTIONS_WORLD * Tuning.MAX_FACTIONS_WORLD)
	w.border_adj_version = -1
	w.split_cooldown = PackedFloat32Array()
	w.split_cooldown.resize(Tuning.MAX_FACTIONS_WORLD)
	w.split_cooldown.fill(0.0)
	w.meta_timer = 0.0

	w.recompute_borders()

	return w


func town_at(tile: Vector2i) -> int:
	for i in range(towns.size()):
		if int(towns[i].x) == tile.x and int(towns[i].y) == tile.y:
			return i
	return -1


func nearest_town(x: float, y: float, owner_filter: int, mode: int) -> int:
	var best := -1
	var best_dist := INF
	for i in range(towns.size()):
		var owner := town_owner[i]
		var matches := false
		match mode:
			0:
				matches = owner == owner_filter
			1:
				matches = owner != owner_filter and owner != -1
			2:
				matches = owner == -1
		if not matches:
			continue
		var c := map.center_of(int(towns[i].x), int(towns[i].y))
		var d := Vector2(x, y).distance_to(c)
		if d < best_dist:
			best_dist = d
			best = i
	return best


func nearest_enemy_stack(i: int, weaker_only: bool) -> int:
	var best := -1
	var best_dist := INF
	var fi := stacks.faction[i]
	var xi := stacks.x[i]
	var yi := stacks.y[i]
	var ci := stacks.count[i]
	for j in range(stacks.n):
		if j == i:
			continue
		if stacks.alive[j] == 0:
			continue
		if stacks.faction[j] == fi:
			continue
		if weaker_only and stacks.count[j] > ci:
			continue
		var d := Vector2(xi, yi).distance_to(Vector2(stacks.x[j], stacks.y[j]))
		if d < best_dist:
			best_dist = d
			best = j
	return best


func stack_tile(i: int) -> Vector2i:
	return map.tile_of(stacks.x[i], stacks.y[i])


func add_town(tile: Vector2i, owner: int) -> int:
	var id := towns.size()
	towns.append(Vector2(tile.x, tile.y))
	town_owner.append(owner)
	town_state.append(0)
	town_pop.append(Tuning.TOWN_POP_START)
	town_recruit.append(0.0)
	town_timer.append(0.0)
	map.kind[map.idx(tile.x, tile.y)] = WorldMap.Kind.TOWN
	return id


## Resizes town_state/town_pop/town_recruit/town_timer up to towns.size(),
## filling new entries with 0 / TOWN_POP_START / 0.0 / 0.0. Never shrinks,
## never overwrites existing entries. Covers callers (e.g. tests) that
## append to towns/town_owner directly without going through add_town.
func sync_town_arrays() -> void:
	var n := towns.size()
	if town_state.size() < n:
		var old := town_state.size()
		town_state.resize(n)
		for i in range(old, n):
			town_state[i] = 0
	if town_pop.size() < n:
		var old := town_pop.size()
		town_pop.resize(n)
		for i in range(old, n):
			town_pop[i] = Tuning.TOWN_POP_START
	if town_recruit.size() < n:
		var old := town_recruit.size()
		town_recruit.resize(n)
		for i in range(old, n):
			town_recruit[i] = 0.0
	if town_timer.size() < n:
		var old := town_timer.size()
		town_timer.resize(n)
		for i in range(old, n):
			town_timer[i] = 0.0


func recompute_borders() -> void:
	sync_town_arrays()
	for ty in range(map.rows):
		for tx in range(map.cols):
			var i := map.idx(tx, ty)
			if not map.passable(tx, ty):
				map.owner[i] = -1
				continue
			var best_owner := -1
			var best_dist := 1 << 30
			for ti in range(towns.size()):
				var owner: int = town_owner[ti]
				if owner < 0:
					continue
				var tx_t := int(towns[ti].x)
				var ty_t := int(towns[ti].y)
				var d: int = maxi(absi(tx - tx_t), absi(ty - ty_t))
				if d <= Tuning.BORDER_RANGE and d < best_dist:
					best_dist = d
					best_owner = owner
			map.owner[i] = best_owner
	borders_version += 1


func ktrait(f: int, k: int) -> float:
	return ktraits[f * 5 + k]


func add_ktrait(f: int, k: int, d: float) -> void:
	ktraits[f * 5 + k] = clampf(ktraits[f * 5 + k] + d, 0.0, 1.0)


func relation(a: int, b: int) -> float:
	return relations[a * Tuning.MAX_FACTIONS_WORLD + b]


func add_relation(a: int, b: int, d: float) -> void:
	var v := clampf(relation(a, b) + d, -1.0, 1.0)
	relations[a * Tuning.MAX_FACTIONS_WORLD + b] = v
	relations[b * Tuning.MAX_FACTIONS_WORLD + a] = v


func allied(a: int, b: int) -> bool:
	return relation(a, b) >= Tuning.REL_ALLY_THRESHOLD


## Appends a log line, keeping only the last 200 entries.
func log_event(text: String) -> void:
	events_log.append(text)
	while events_log.size() > 200:
		events_log.pop_front()
