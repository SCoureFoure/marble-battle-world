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
