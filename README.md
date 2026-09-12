# Marble Battle World

Zero-player marble war simulation in Godot 4.7 (GDScript, GL Compatibility).
Factions of spinning-top marbles collide on a procedural overworld; battles,
plinko rewards, ranks, captains and kingdoms all emerge from the simulation.

- Design: `docs/GDD.md`
- Architecture seam (data layout, module APIs, tick order): `docs/ARCHITECTURE.md`

## Run

```sh
# Godot 4.7 stable binary
GODOT=C:/Users/SCora/Desktop/Godot_v4.7-stable_win64.exe

# Open the project
$GODOT --path .

# Run one headless test (also re-imports so new class_name scripts resolve)
bash tools/verify.sh test_spatial_hash

# Headless perf bench
$GODOT --headless --path . --script res://scripts/bench_battle.gd
```

Tests live in `scripts/tests/test_*.gd` and print `ALL_PASS (...)` or
`FAILURES=n of m` as their last line.
