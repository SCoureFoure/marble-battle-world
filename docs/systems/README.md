# Marble Battle World — systems guide

Marble Battle World is a zero-player marble war simulation: nobody plays a
turn, the code runs a whole world of spinning-top marble armies on its own
and the fun is in watching it. Milestones M1-M2 built the core marble-vs-marble
battle sim (SoA arrays, spatial hash, forces, collision, weapons, terrain).
M3 layered an overworld on top (map, stacks, pathing, collision -> battle
bridge). M4 added plinko post-battle rewards, towns and borders. M5 added
meta progression (soldier XP/rank persistence, captain lineage, kingdom
traits, relations). M6 added battle LOD (statistical auto-resolve), save/load,
time controls, spectate and a timeline panel.

## The big loop

```text
world tick -> stacks move -> contact -> battle (full sim or LOD)
  -> result -> plinko -> outcomes -> towns/borders/lineage/kingdoms -> next tick
```

Every frame, `scripts/world_scene.gd` calls `scripts/world/world_sim.gd::step`
some number of times depending on the chosen speed (1x/5x/50x/MAX). Inside one
step, idle stacks pick a goal and path toward it, moving stacks advance along
their path (`scripts/world/world_sim.gd::move_stacks`), and stacks of opposing
factions that get close enough start or join a battle
(`scripts/world/world_sim.gd::check_collisions`) via
`scripts/world/battle_bridge.gd::start`/`::join`. Each live battle then gets
one tick of either the full marble sim (if it is the watched battle) or the
statistical LOD (`scripts/world/world_sim.gd::step_battles`). When a battle's
winner is decided, `scripts/world/battle_bridge.gd::finish` writes survivors,
XP, rebirths and relation changes back to units/stacks, and one plinko drop
per winning stack with a living captain runs
(`scripts/world/world_sim.gd::_run_plinko`), applying outcomes to the world
(gold, recruits, curses, town effects, ...). Town production/recruitment and
border ownership are recomputed as part of the same or a following tick, and
kingdom-level bookkeeping (splits, deaths, trait drift) ticks once per world
second before the loop repeats.

## System map

| System | Guide | Main files | Start tweaking here |
|---|---|---|---|
| Battle simulation | [Battle](01-battle.md) | `scripts/sim/battle_sim.gd`, `scripts/sim/forces.gd`, `scripts/sim/weapons.gd` | `scripts/sim/tuning.gd` movement/weapon constants |
| Overworld and battle bridge | [Overworld](02-overworld.md) | `scripts/world/world_sim.gd`, `scripts/world/battle_bridge.gd`, `scripts/world/battle_lod.gd` | `scripts/world/kingdoms.gd::goal_weights` (hardcoded goal weights) |
| Plinko rewards, towns and borders | [Plinko, towns and borders](03-plinko-towns.md) | `scripts/world/plinko.gd`, `scripts/world/plinko_outcomes.gd`, `scripts/world/town_sim.gd` | `scripts/world/plinko_outcomes.gd` outcome table |
| Meta progression | [Meta progression](04-meta-progression.md) | `scripts/world/lineage.gd`, `scripts/world/kingdoms.gd`, `scripts/world/namegen.gd` | trait constants in `scripts/sim/tuning.gd` (`KT_*`) |
| Presentation, controls and save/load | [Presentation and save](05-presentation-save.md) | `scripts/world_scene.gd`, `scripts/battle_scene.gd`, `scripts/world/save_game.gd` | `scripts/world_scene.gd::_unhandled_input` |
| Tuning reference | [Tuning reference](06-tuning-reference.md) | `scripts/sim/tuning.gd` | pick a constant, grep who reads it |

## Running and watching

Launch the main scene (the overworld, `run/main_scene` in `project.godot` is
`res://scenes/world.tscn`):

```sh
GODOT=C:/Users/SCora/Desktop/Godot_v4.7-stable_win64.exe
$GODOT --path .
```

`scenes/battle.tscn` (`scripts/battle_scene.gd`) runs a single demo battle
directly instead of the overworld.

Headless tests live under scripts/tests, one `test_<name>.gd` per module; run
one with `bash tools/verify.sh <test_basename>` (the membrane — see
`tools/verify.sh`). Headless perf benches are plain `SceneTree` scripts:
`scripts/bench_battle.gd` (500 marbles, 600 ticks, fails if `SIM_MS_AVG` is
not under 12 ms) and `scripts/bench_world.gd` (200 stacks, 1800 ticks, fails
if `WORLD_MS_AVG` is not under 4 ms), run with
`$GODOT --headless --path . --script res://scripts/bench_battle.gd` (or
`bench_world.gd`).

There is no dedicated capture tool under `tools/`: screenshots are taken ad
hoc by passing `--capture=<path>` (plus optional `--capture-tick=` and, for
the world scene, `--capture-battle=1`) as a user arg to `world.tscn` or
`battle.tscn`; both `scripts/world_scene.gd::_capture` and
`scripts/battle_scene.gd::_capture` grab `get_viewport().get_texture()` and
save it as a PNG, then quit.

## Tweak loop

1. Pick a knob in [06-tuning-reference.md](06-tuning-reference.md) and note
   which system(s) read it.
2. Edit the value in `scripts/sim/tuning.gd` (it is a `const`, so the change
   needs an engine restart to take effect).
3. Run the owning test(s), e.g. `bash tools/verify.sh test_forces`.
4. Watch it in-game: launch `world.tscn` (or `battle.tscn` for an isolated
   battle) and observe.
5. Run `node tools/check_guide.mjs` to catch this guide drifting from the
   value you just changed.

## Ten knobs with the biggest feel impact

| Constant | Value | Why it matters |
|---|---|---|
| `K_ATTR` | `40.0` | How hard marbles get pulled toward the enemy once engaged; low values make battles a slow grind, high values make them collide almost instantly. |
| `K_SEPARATION` | `120.0` | How strongly marbles push apart from close neighbours; controls how tightly packed a marble mass looks. |
| `SPIN_DECAY` | `4.0` | Passive spin (HP) loss per second; sets the baseline pace at which a battle can end even without much fighting. |
| `WEAPON_DMG` | `[4.0, 8.0, 8.0, 14.0, 2.0]` | Per-weapon-type damage per hit (index = weapon id); directly sets which weapon feels strong. |
| `RETREAT_THRESHOLD` | `0.25` | Morale fraction below which a faction starts routing; lower means battles fight to the bitter end, higher means armies break early. |
| `T_MAX_BATTLE` | `120.0` | Hard time cap (seconds) after which a battle is forced to a decision instead of grinding forever. |
| `STACK_SPEED` | `48.0` | Overworld movement speed of a stack; sets how fast the map feels like it is churning. |
| `AI_TICK` | `2.0` | Seconds between an idle stack's goal re-evaluations; lower makes armies feel reactive, higher makes them feel sluggish. |
| `MORALE_HIT_CAPTAIN_DEAD` | `-0.4` | Morale lost by a faction when its captain dies; the bigger the drop, the more a single captain kill decides a battle. |
| `PLINKO_BIAS_GREED` | `200.0` | How much a faction's greed trait skews its plinko board toward gold-favouring slots; sets how much post-battle rewards vary by faction personality. |

**Dead knobs.** These constants exist in `scripts/sim/tuning.gd` but no game code reads them, so
editing them changes nothing: `PLINKO_ROWS_MIN`, `PLINKO_ROWS_MAX`, `GOAL_WEIGHTS`, `SPEED_STEPS`
(and `WEAPON_NAMES`, which is labels only). Stack AI goal weights are hardcoded in
`scripts/world/kingdoms.gd::goal_weights`; time-control speeds (1, 5, 50) are hardcoded in
`scripts/world_scene.gd` (speed buttons and `scripts/world_scene.gd::_unhandled_input`). To make those tweakable, move the literals into `Tuning`.

## Determinism and tests

Every battle draw goes through that battle's own `BattleState.rng`
(`RandomNumberGenerator`, seeded at battle creation); every overworld draw
goes through `World.rng` (seeded `seed + 1` in `World.create`, separate from
the map generator's own seeded rng). Nothing is allowed to call the global
`randf()`/`randi()`. Because of this, changing almost any constant in
`scripts/sim/tuning.gd` can change the exact sequence of outcomes a seeded
test asserts (kill order, winner, tick count, exact positions), even if the
constant "shouldn't" matter for that test — that is why `tools/verify.sh`
re-imports before running and why a green run requires the process to exit
0, print `ALL_PASS`, and contain no `FAILURES=`, parse error, script error or
failed-to-load-script line.
