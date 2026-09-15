extends SceneTree
## Times WorldGen.generate on the default map size for a few seeds.
## Usage: godot --headless --path . --script res://tools/bench_worldgen.gd


func _init() -> void:
	var seeds: Array[int] = [1, 42, 7]
	for s in seeds:
		var m := WorldMap.new(Tuning.WORLD_COLS, Tuning.WORLD_ROWS, s)
		var t0 := Time.get_ticks_usec()
		var towns: Array = WorldGen.generate(m)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		print("GEN seed=%d ms=%.1f towns=%d" % [s, ms, towns.size()])
	quit()
