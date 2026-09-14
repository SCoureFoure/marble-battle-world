# Presentation, controls and save/load

## What it does

Draws the overworld and battle views, reads player input (camera, time
controls, spectate clicks, save/load), and persists a `World` to disk. All
sim state (`BattleState`, `World`) is read-only from these files except for
`SaveGame.load`, which rebuilds a `World`, and the input handlers that flip
`WorldSim`/`BattleSim` stepping cadence and open/close panels. Two scene
roots exist: `scenes/world.tscn` (the game) and `scenes/battle.tscn` (a
standalone demo battle, not reached from the main scene).

## Where it lives

| File | Role |
|---|---|
| `scripts/world_scene.gd` | Overworld scene root: owns `World`, camera, input, time controls, wires every panel. |
| `scripts/battle_scene.gd` | Standalone demo-battle scene root (`scenes/battle.tscn`). |
| `scripts/render/battle_renderer.gd` | `BattleRenderer`: three `MultiMeshInstance2D`s (bodies/weapons/hp bars), pure buffer builders. |
| `scripts/render/terrain_layer.gd` | `TerrainLayer`: draws non-PLAIN `TerrainGrid` cells. |
| `scripts/render/stack_layer.gd` | `StackLayer`: overworld stack circles, battle-tile markers, captain/stack labels. |
| `scripts/render/label_pool.gd` | `LabelPool`: pooled `Label`s for captain labels and rising popups. |
| `scripts/render/battle_background.gd` | `BattleBackground`: parchment fill under a battle view's terrain layer. |
| `scripts/render/map_layer.gd` | `MapLayer`: baked tile texture, ownership overlay, border lines, town markers. |
| `scripts/render/plinko_view.gd` | `PlinkoView`: plinko board + drop animation + outcome text. |
| `scripts/render/ledger_panel.gd` | `LedgerPanel`: per-faction power table. |
| `scripts/render/spectate_panel.gd` | `SpectatePanel`: stack/unit info panel. |
| `scripts/render/timeline_panel.gd` | `TimelinePanel`: scrolling `events_log` tail. |
| `scripts/render/battle_view.gd` | `BattleView`: popup `SubViewport` battle arena for one live `BattleInstance`. |
| `scripts/render/battle_aftermath.gd` | `BattleAftermath`: cosmetic post-battle chase/celebration on a finished battle's orphaned `BattleState`, plus result-banner text. |
| `scenes/world.tscn` | Main scene (`project.godot` `run/main_scene`); root node runs `world_scene.gd`. |
| `scenes/battle.tscn` | Standalone battle demo scene; root node runs `battle_scene.gd`. |
| `shaders/marble_body.gdshader` | Marble fill, rim highlight, rank ring, captain dot. |
| `shaders/marble_weapon.gdshader` | Weapon bar shapes (shaft/head/shield). |
| `shaders/hp_bar.gdshader` | HP bar fill (green→red by fraction). |
| `scripts/world/save_game.gd` | `SaveGame`: `World` serialization/deserialization. |

## How it works

### Scene structure

1. `scenes/world.tscn` is the project's main scene; its root `Node2D` runs
   `scripts/world_scene.gd::_ready`, which builds `World.create(seed)` then
   adds, in order: `MapLayer` (`::build`), `StackLayer`, a `Camera2D`
   centred on the capital, `LabelPool`, `BattleView`, `LedgerPanel`
   (`::build`), `PlinkoView` (`::build`), `SpectatePanel` (`::build`),
   `TimelinePanel` (`::build`), a HUD `Label` under its own `CanvasLayer`,
   and time-control buttons via `scripts/world_scene.gd::_build_time_controls`.
2. `scenes/battle.tscn` is a separate, standalone demo: its root `Node2D`
   runs `scripts/battle_scene.gd::_ready`, which hand-builds one
   `BattleState` (two captains at rank 1 plus two 500-marble blocks), a
   `TerrainGrid` via `TerrainGen.demo`, a `BattleSim`, and its own
   `TerrainLayer` + `BattleRenderer` + `LabelPool` + `Camera2D` + HUD.
3. `scripts/render/battle_view.gd` mirrors `battle_scene.gd`'s node stack
   inside the world scene: a `CanvasLayer` → `SubViewportContainer` →
   `SubViewport` (1600×900) holding its own `Camera2D`, `BattleBackground`,
   `TerrainLayer`, `BattleRenderer`, `LabelPool`. `scripts/render/battle_view.gd::open`
   points it at one `BattleInstance` and sets `world.watched_battle`;
   `scripts/render/battle_view.gd::close` hides it and resets
   `watched_battle` to `-1`.

### Controls

This is the load-bearing part of this file — every input the scene handles.

| Input | Scope | Effect |
|---|---|---|
| `Space` | global | `scripts/world_scene.gd::_toggle_pause` — pause/unpause `WorldSim`. |
| `1` | global | `scripts/world_scene.gd::_set_speed` with `1` — 1 step/frame. |
| `2` | global | `scripts/world_scene.gd::_set_speed` with `5` — 5 steps/frame. |
| `3` | global | `scripts/world_scene.gd::_set_speed` with `50` — 50 steps/frame. |
| `4` | global | `scripts/world_scene.gd::_set_max` — MAX mode: loop `WorldSim.step` until `Tuning.MAX_FRAME_MS` has elapsed this frame (at least one step always runs). |
| `F5` | global | `scripts/world_scene.gd::_unhandled_input` calls `SaveGame.save(world, "user://save1.bin")`. |
| `F9` | global | `scripts/world_scene.gd::_try_load` → `SaveGame.load` then `scripts/world_scene.gd::_rebuild_layers`; shows a 3 s "load failed" HUD message on failure. |
| Left click | world view (battle view closed) | `scripts/world_scene.gd::_try_open_battle`: opens `BattleView` if the click hits a battle tile or a stack in `BATTLE`; otherwise `scripts/world_scene.gd::_try_spectate_stack` opens `SpectatePanel.show_stack` for the nearest alive stack within `Tuning.STACK_RADIUS * 2 / zoom`. |
| Right or middle mouse (hold + drag) | world view | Pans the camera: `camera.position -= mouse_relative / camera.zoom.x` while held. |
| Mouse wheel up/down | world view | Zoom by `ZOOM_STEP` (1.15), clamped to `[ZOOM_MIN, ZOOM_MAX]` = `[0.25, 3.0]` (`scripts/world_scene.gd::_zoom`). |
| `Esc` | `SpectatePanel` visible | `scripts/render/spectate_panel.gd::_input` closes the panel. |
| `Esc` or right click | `BattleView` visible | `scripts/render/battle_view.gd::_input` closes the battle view. |
| Left click | `BattleView` visible | `scripts/render/battle_view.gd::_try_spectate_marble`: nearest marble within 12 px opens `SpectatePanel.show_unit`. |

Time-control and save/load keys are read in `scripts/world_scene.gd::_unhandled_input`
before the battle-view-visible check, so they work whether or not a battle
is open; mouse handling in that function is skipped entirely while
`battle_view.visible`.

### World map rendering layers

1. `scripts/render/map_layer.gd::build` bakes an RGB8 `Image` (one pixel per
   tile, colour by `WorldMap.Kind` from `TILE_COLORS` plus a small
   deterministic per-tile dither), wrapped in a `Sprite2D` scaled by
   `Tuning.TILE`.
2. A second `Sprite2D` holds the ownership overlay from
   `::_build_overlay_image` (RGBA8, faction colour at alpha `OVERLAY_ALPHA`
   = 0.28, transparent where `owner < 0`); `::refresh_if_owner_changed`
   rebuilds it only when `world.borders_version` changes.
3. `::_rebuild_border_segments` walks every tile's east/south neighbour and
   records a segment where the owners differ, grouped by faction into
   `_border_segments_by_owner`; `::_draw` renders each group with
   `draw_multiline` in that faction's `Tuning.FACTION_COLORS` entry
   darkened by `BORDER_DARKEN`.
4. `::_draw_town` draws a house glyph per town (10×10 square + roof
   triangle) in the owner's colour (`TOWN_NEUTRAL_COLOR` if neutral), grey
   if RAIDED, black plus a small orange flame triangle if RAZED. Town
   markers also redraw when `town_owner`/`town_state` change without a
   `borders_version` bump (e.g. RAIDED → INTACT recovery).
5. `scripts/render/stack_layer.gd::_draw` draws a filled circle per alive
   stack, radius `Tuning.STACK_RADIUS * (0.7 + 0.2 * tier)`, coloured by
   `Tuning.FACTION_COLORS[faction % 8]` with a dark outline, plus a red "X"
   (`draw_string`) at the tile centre of every live `BattleInstance`.
6. `::update_labels` sorts alive stacks by camera distance, gives the
   nearest 60 a `LabelPool.set_captain` label (`Stacks.label`, with a
   `" RETREAT"` suffix when `state == RETREATING`), and hides the rest.

### Battle view rendering

1. `BattleRenderer` (shared by `battle_scene.gd` and `BattleView`) owns
   three `MultiMeshInstance2D`s — `Bodies`, `Weapons`, `HpBars` — each
   `TRANSFORM_2D`, `use_custom_data = true`, a 2×2 `QuadMesh`, and one
   `ShaderMaterial` (`shaders/marble_body.gdshader`,
   `shaders/marble_weapon.gdshader`, `shaders/hp_bar.gdshader`).
2. `scripts/render/battle_renderer.gd::build_buffer` (12 floats/marble):
   scale = radius (0 if DEAD), position, `custom.rgb` = faction colour,
   `custom.a = rank / 3.0 + (2.0 if is_captain)`. The shader fills a circle,
   darkens a rim (`d > 0.8`), lightens an upper-left highlight, draws a dark
   rank ring at `0.55 < d < 0.65`, and a dark centre dot (`d < 0.25`) for
   captains.
3. `::build_weapon_buffer`: a bar from the marble rim to
   `Tuning.WEAPON_REACH[w] * radius` along `weapon_angle`, `custom.r =
   weapon_id / 4.0`. The shader draws a thin shaft (dagger's is shorter,
   axe adds a wide head), or, for shield (id 4), a short thick bar near the
   rim only.
4. `::build_hp_buffer`: a bar above the marble (width = radius, height
   1.5), `custom.r = hp / hp_max`; hidden (scale 0) at full HP or DEAD. The
   shader fills the left `custom.r` fraction green→red, the rest dark.
5. `::refresh` (driven every `_process`) rebuilds and re-uploads all three
   buffers via `RenderingServer.multimesh_set_buffer`; `::attach` sets the
   three instance counts once.
6. `scripts/render/terrain_layer.gd::_draw` draws one rect per non-PLAIN
   cell (colour by `TerrainGrid.Kind`), circles for ROCK/TREE, a TOWER
   square with an owner-coloured inner square, and a SPIKE square with two
   diagonal lines; redrawn only via `::mark_dirty` (called when
   `terrain.owner` changes).
7. `scripts/render/label_pool.gd`: 100 pooled `Label`s — slots `0..63` for
   captain/stack labels (`::set_captain`/`::hide_captain`), slots `64..99`
   round-robin for popups (`::popup`) that rise `POPUP_RISE` = 30 px over
   `POPUP_LIFETIME` = 1.0 s while fading out.
8. Each `_process` in `battle_scene.gd` and `battle_view.gd` walks
   `state.events` and calls `LabelPool.popup`: `KILL` → `"+1 kill"` at the
   actor, `LEVEL` → `"LVL %d"` at the actor, `CAPTAIN_DEAD` → `"CAPTAIN
   DOWN"` at the target; both also refresh a `"Captain %d"` label per live
   `faction_captain` every frame.
9. Aftermath: when the watched battle ends, `BattleBridge.finish` drops it
   from `world.battles` and nothing in the world touches its `BattleState`
   again. `scripts/render/battle_view.gd::_process` notices the instance is
   gone and calls `::_start_aftermath`: a top banner (`"<FACTION> VICTORY"`
   in the winner's colour with the winning stacks underneath, or
   `"STALEMATE"`) fades in, and a `BattleAftermath` steps the orphaned state
   at `Tuning.DT` on real frame time (at most 4 steps per frame, frozen while
   the world is paused, unaffected by world speed).
   `scripts/render/battle_aftermath.gd::step`: winners that were assigned a
   nearby fleeing marble (`::_assign_chasers`, up to 2 chasers per fleer
   within 240 px, never the captain) chase it for 2.5 s; every other winner
   circles its captain (or the winners' starting centroid) with twirling
   weapons and a pulsing spin glow; losers run for their home edge and
   disappear there. Movement reuses `BattleSim.integrate` without hazards
   plus `Collision.resolve` with `bump_cd` pinned, and `Weapons.tick` never
   runs, so nothing takes damage. The view stays open until `Esc` / right
   click, as before; the aftermath changes no world result.

### Panels

1. `scripts/render/ledger_panel.gd`: a right-anchored `PanelContainer`
   (`anchor_right = 1`, `offset_left = -270`), one row per faction sorted by
   `power = units_alive + 50 * towns_owned`, refreshed every
   `Tuning.LEDGER_REFRESH` s by `::_refresh`; the top row gets a `♛` prefix;
   labels use `world.faction_names` (falling back to `"Faction %d"` for
   hand-built test worlds with no names).
2. `scripts/render/spectate_panel.gd`: a bottom-right `PanelContainer`,
   hidden until `::show_stack` (stack label, faction name, captain name +
   trait, top 5 units by kills, current goal's enum key) or `::show_unit`
   (unit name, faction, rank/kills/xp, trait) is called; `Esc` calls
   `::close`.
3. `scripts/render/timeline_panel.gd`: a `Label` positioned at `(8, 28)`
   (under the HUD label at `(8, 8)`), showing the last `Tuning.TIMELINE_LINES`
   lines of `world.events_log`, refreshed only when the log's length
   changes.
4. `scripts/render/plinko_view.gd`: a bottom-left `CanvasLayer` with a
   nested `_Board` `Control`. On a new `world.plinko_log` entry it enters
   the `DROP` phase, animating a ball along the recorded path over
   `BALL_DROP_TIME` = 2.0 s while drawing pegs and labelled slot boxes, then
   the `OUTCOME` phase shows the outcome text lines for `OUTCOME_TIME` =
   3.0 s before going idle.

### Time controls

1. `scripts/world_scene.gd::_build_time_controls` creates a bottom-centre
   `HBoxContainer` with five buttons (`⏸`, `1x`, `5x`, `50x`, `MAX`) wired to
   the same handlers as the matching keyboard shortcuts.
2. `scripts/world_scene.gd::_process` drives stepping: paused → no
   `WorldSim.step` calls; `max_mode` → loop `WorldSim.step(world, Tuning.DT)`
   until `Tuning.MAX_FRAME_MS` has elapsed in that frame (at least one step
   always runs); otherwise call it `steps_per_frame` times (1, 5, or 50).
3. The HUD label shows `"PAUSED"`, `"MAX"`, or `"x%d"` plus world tick
   stats (time, alive stacks, live battles, total units, fps, world step
   time), or a transient message (`::_show_message`, e.g. `"load failed"`)
   for its duration.

### Save/load

1. `scripts/world/save_game.gd::save(w, path)` writes one file: a header
   `Dictionary` (`version = Tuning.SAVE_VERSION`, `rng.state`, `time`,
   `faction_count`, `next_battle_id`, map `cols`/`rows`, `borders_version`),
   then five more `store_var` Dictionaries in order — map (`kind`/`owner`),
   units (every field plus `dynasty`/`names`), stacks (every field, `path`
   as an `Array` of `PackedVector2Array`), towns, meta
   (`ktraits`/`relations`/`faction_*`/plinko profile/`split_cooldown`), and
   logs (`events_log`, the last 10 `plinko_log` entries, `scars`).
2. Live battles are never saved: `save` works on **copies** of
   `stacks.state`/`battle_id`/`immunity` (the live `World` is never
   mutated), forcing any stack caught mid-`BATTLE` to `IDLE` with
   `battle_id = -1` and `immunity = Tuning.RETREAT_IMMUNITY` before writing.
3. `::load(path)` returns `null` (no crash) when the file is missing or
   `header.version != Tuning.SAVE_VERSION` (a `push_error` names both
   versions); otherwise it rebuilds `World`, `WorldMap`, `Units`, `Stacks`
   field-by-field, sets `battles = []` and `reinforce = {}`, resets the
   border-adjacency cache (`border_adj_version = -1`), builds a fresh
   `Pathing`, then calls `w.sync_town_arrays()` and `w.recompute_borders()`.
4. File location and version: `user://save1.bin` (`SAVE_PATH` constant in
   `scripts/world_scene.gd`), bound to `F5` (save) / `F9` (load);
   `Tuning.SAVE_VERSION` is currently `1` and any format change must bump it
   (old saves then fail `::load` cleanly instead of loading corrupt data).

## Knobs

| Constant | Value | Raise it and... |
|---|---|---|
| `DT` | `1.0 / 60.0` | Each `WorldSim.step`/`BattleSim.step` call (driven by `world_scene.gd`/`battle_scene.gd`) advances simulated time further per call; at a fixed real-time frame rate the world/battle run faster. |
| `TILE` | `32.0` | World-map pixels per tile grow: `MapLayer`'s baked texture and sprite scale, and every world-space position derived from a tile, get bigger/coarser. |
| `STACK_RADIUS` | `12.0` | Stack circles in `StackLayer` and the click-hit radius (`_try_spectate_stack`, world-scene mouse pick) grow. |
| `TERRAIN_CELL` | `40.0` | Battle-view terrain cells (`TerrainLayer` rects/circles) get bigger; fewer, chunkier terrain features per arena. |
| `OBSTACLE_RADIUS_FRAC` | `0.4` | ROCK/TREE obstacle circles in `TerrainLayer` grow relative to `TERRAIN_CELL`. |
| `ARENA_W` | `1600.0` | `BattleBackground`'s parchment rect (and the whole battle arena) widens. |
| `ARENA_H` | `900.0` | `BattleBackground`'s parchment rect (and the whole battle arena) grows taller. |
| `FACTION_COLORS` | `[Color(0.85,0.2,0.2), Color(0.2,0.4,0.9), Color(0.2,0.7,0.3), Color(0.9,0.7,0.1), Color(0.6,0.3,0.8), Color(0.9,0.5,0.2), Color(0.2,0.8,0.8), Color(0.5,0.5,0.5)]` | Every faction-coloured element repaints: marble bodies, stack circles, map ownership overlay/borders/town markers, ledger swatches. Index = `faction_id % 8`. |
| `WEAPON_REACH` | `[0.8, 1.2, 2.0, 1.3, 0.9]` | The weapon bar drawn by `build_weapon_buffer` gets longer for that weapon id (index = weapon id: dagger, sword, spear, axe, shield). |
| `PLINKO_W` | `360.0` | `PlinkoView`'s board and slot boxes get wider (board-space, drawn at `BOARD_SCALE` = 0.5). |
| `PLINKO_H` | `480.0` | `PlinkoView`'s board and slot band position get taller. |
| `PLINKO_SLOTS` | `9` | `PlinkoView` draws that many slot boxes across the bottom band (`slot_order` must still hold this many entries). |
| `PLINKO_BALL_R` | `8.0` | The animated plinko ball in `PlinkoView` grows. |
| `PLINKO_SLOT_BAND` | `40.0` | The slot-box band at the bottom of the plinko board (`PlinkoView`) grows taller. |
| `LEDGER_REFRESH` | `0.5` | `LedgerPanel` recomputes its rows less often (seconds between refreshes). |
| `TIMELINE_LINES` | `12` | `TimelinePanel` shows more lines of `events_log` history at once. |
| `MAX_FRAME_MS` | `12.0` | MAX time-control mode runs more `WorldSim.step` calls per frame before yielding (higher = more sim work, lower fps headroom). |
| `RETREAT_IMMUNITY` | `10.0` | A stack forced out of `BATTLE` by `SaveGame.save` (see Save/load) gets this much longer immunity to a new battle on load. |
| `MAX_FACTIONS_WORLD` | `16` | Only affects save/load indirectly (`SaveGame` doesn't size anything from it directly; it's read for the border-adjacency cache size after load). |
| `SAVE_VERSION` | `1` | Bumping it makes every existing save file fail `SaveGame.load` (clean `null`, not a crash) until re-saved. |

## Tweak recipes

- **Want the world map to read at a glance from further zoomed out?**
  Change `TILE` (current `32.0`) up. Watch `MapLayer`'s baked sprite and
  every stack/label position scale with it. Re-run:
  `bash tools/verify.sh test_world_scene_smoke`.
- **Want faction colours to read better against the parchment/plains
  palette?** Change `FACTION_COLORS` (current 8-entry array). Watch marble
  bodies, stack circles, map overlay/borders, town markers, ledger
  swatches all shift together. Pinned by `test_tuning` (`FACTION_COLORS.size()
  == 8`) and `test_renderer_buffer` (hardcodes `buf[8..10]` for faction 0 and
  1's colours) — update both tests too. Re-run:
  `bash tools/verify.sh test_renderer_buffer`.
- **Want weapon reach to read more visibly on screen?** Change
  `WEAPON_REACH` (current `[0.8, 1.2, 2.0, 1.3, 0.9]`). Watch
  `build_weapon_buffer`'s bar length. Pinned by `test_tuning`
  (`WEAPON_REACH[2] == 2.0`) and `test_renderer_buffer` (hardcodes the
  sword-bar length as `4.8`/`9.6`) — update both. Re-run:
  `bash tools/verify.sh test_renderer_buffer`.
- **Want the ledger to feel snappier or cheaper?** Change `LEDGER_REFRESH`
  (current `0.5`) down or up. Watch `LedgerPanel::_process`'s refresh
  cadence and CPU cost of the per-faction unit/town/stack scan. No test
  pins the value. Re-run: `bash tools/verify.sh test_world_scene_smoke`.
- **Want MAX time-control mode to push more simulation per frame?** Change
  `MAX_FRAME_MS` (current `12.0`) up. Watch actual fps drop and
  `world_ms` in the HUD rise. No test pins the value (not exercised
  headless). Re-run: `bash tools/verify.sh test_world_scene_smoke`.
- **Want a save-format change to be safely rejected by old saves?** Bump
  `SAVE_VERSION` (current `1`) whenever the `store_var` shape in
  `SaveGame.save`/`load` changes. Pinned by `test_tuning`
  (`SAVE_VERSION == 1`) and `test_save_game` (writes a header with
  `version = 99` and expects `load` to return `null`) — update both. Re-run:
  `bash tools/verify.sh test_save_game`.

## Gotchas

- `SPEED_STEPS = [1, 5, 50]` exists in `scripts/sim/tuning.gd` but is not
  read anywhere in this slice: the 1x/5x/50x buttons and `1`/`2`/`3` keys in
  `scripts/world_scene.gd` hardcode the literals `1`, `5`, `50` instead of
  indexing `Tuning.SPEED_STEPS`. Doc drift risk: changing `SPEED_STEPS`
  changes nothing on screen.
- `scripts/render/stack_layer.gd::_draw`'s battle-tile "X" label is drawn
  directly with `draw_string` rather than through `LabelPool`, so it is not
  part of the pooled-label system the rest of the UI uses (see the
  `// UNDECIDED` comment in that file).
- `scripts/render/label_pool.gd::set_captain` uses a fixed
  `Vector2(-20, -18)` offset; there is no per-call radius to size the
  offset by (see the `// UNDECIDED` comment in that file).
- `BattleRenderer.refresh()` is called both by its own `_process` (as a
  child of the main viewport or of a `BattleView`'s `SubViewport`) and
  would double-build its buffers if a caller invoked it again manually;
  `battle_view.gd::_process` explicitly does not call it for this reason.
- Determinism: nothing in this slice draws randomness directly, but
  `SaveGame` round-trips `w.rng.state` — a battle in flight at save time is
  discarded (see Save/load item 2), so `w` and a freshly loaded copy only
  match bit-for-bit going forward if no battle was live at save time
  (`test_save_game`'s determinism case explicitly waits for
  `w.battles.size() == 0` first).
- `MapLayer`'s border-colour tie-break (which faction "owns" a border line
  when tiles differ) and `StackLayer`'s battle-"X" routing are both
  `// UNDECIDED` fiat choices made in-code; see those files.
- `LedgerPanel`/`SpectatePanel` fall back to `"Faction %d"` when
  `world.faction_names` is shorter than the faction index — this only
  happens for hand-built test worlds (`World.new()` + `setup_blank`, no
  `faction_names` populated), not for `World.create`.

### Cross-links

[Battle](01-battle.md) for `BattleState`/`BattleSim` fields this slice only
reads. [Overworld](02-overworld.md) for `World`/`WorldSim`/`BattleInstance`.
[Plinko, towns, borders](03-plinko-towns.md) for `plinko_log` shape and
border computation. [Meta progression](04-meta-progression.md) for
`faction_names`, `ktraits`, traits shown in `SpectatePanel`.
