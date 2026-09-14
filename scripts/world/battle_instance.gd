class_name BattleInstance extends RefCounted
## Per-battle overworld bridge object (docs/ARCHITECTURE.md §11.5).
## BattleBridge (sibling, written concurrently) fills state/sim/terrain.

var id: int
var tile: Vector2i
var state: BattleState
var sim: BattleSim
var terrain: TerrainGrid
var faction_map: PackedInt32Array   # local faction index -> world faction id
var unit_of: PackedInt32Array       # marble index -> unit id
var stack_ids: PackedInt32Array     # every stack that joined
var edge_of_faction: PackedInt32Array   # local faction -> home edge 0..3
var started: float                  # world time
var captain_before: PackedInt32Array    # parallel to stack_ids: each stack's
                                         # captain unit id before the finish()
                                         # copy-back (M5, Lineage.on_battle_finished)
var captain_killers: Array          # [victim_world_f, killer_world_f] pairs,
                                     # appended by WorldSim.step_battles from
                                     # CAPTAIN_DEAD events (M5, §13.4)
var side_factions: Array            # per local faction index (0..3): a
                                     # PackedInt32Array of every world faction
                                     # joined at that index (allies, §13.5)
var lod_xp_acc: PackedFloat32Array  # BattleLod xp-credit accumulator, one
                                     # float per marble; grown to state.n by
                                     # BattleLod.step (M6, §14.2)
var slayers: PackedInt32Array       # unit ids that killed a captain or hero this battle (M9)


func _init(id_: int, tile_: Vector2i) -> void:
	id = id_
	tile = tile_
	state = null
	sim = null
	terrain = null
	stack_ids = PackedInt32Array()
	faction_map = PackedInt32Array()
	edge_of_faction = PackedInt32Array()
	unit_of = PackedInt32Array()
	started = 0.0
	captain_before = PackedInt32Array()
	captain_killers = []
	side_factions = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	lod_xp_acc = PackedFloat32Array()
	slayers = PackedInt32Array()
