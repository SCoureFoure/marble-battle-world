# Marble War Simulation — Design Doc (Godot 4, 2D)

Zero-player simulation. Player watches. World runs itself. Nothing preset — factions, names, borders, traits all procedural at gen, then evolve from sim history.

**Build order:** (1) marble battles → (2) overworld movement + collisions → (3) plinko post-battle → (4) persistent kingdoms / meta → (5) optional roguelike mode.

**Priority #1: performance.** Target 500–2000 active marbles in battle at 60 fps, 10k+ units world-wide tracked as data. See §6 before writing any node code.

---

## 1. Battle (build first)

Arena = terrain tile where two stacks collided. Marbles behave like spinning tops / beyblades.

### 1.1 Marble data
| Field | Type | Notes |
|---|---|---|
| pos, vel | Vector2 | world units |
| radius, mass | float | mass ∝ radius² × rank_mult |
| hp, hp_max | float | hp bar drawn above |
| spin | float | RPM. Decays each tick. Damage mult + knockback resist |
| spin_cap | float | grows with rank/Drill |
| weapon_id | int | sword / spear / axe / dagger / shield. Sprite fixed at rim, rotates with spin |
| weapon_angle | float | current rotation, advanced by spin |
| faction_id | int | color fill |
| rank | int | 0 Recruit, 1 Veteran, 2 Elite, 3 Legend. Visual: stripe / helmet / crest / glow |
| morale | float | 0–1 |
| aggression | float | attraction strength |
| state | enum | ENGAGE / RETREAT / DEAD |
| captain_id | int | -1 if none |
| kills, xp | int | persist |

### 1.2 Forces (summed each physics tick)
- **Attraction** — weak pull toward nearest enemy within `engage_radius`. `F = k_attr * aggression * morale * dir`. Clusters drift together and grind.
- **Cohesion** — weak pull toward own captain (or own centroid if none). Keeps blobs.
- **Separation** — short-range push from allies to avoid overlap stacking.
- **Retreat** — when `state == RETREAT`: attraction sign flips (repel all enemies) + pull toward arena edge nearest home. Triggered: morale < 0.25, captain dead, hp < 20%.
- **Collision** — elastic bounce, mass-weighted. Spin transfer on contact: faster top steals fraction of slower top's spin.
- **Terrain** — sampled from arena grid per tick:
  - mud: friction ↑, speed ↓
  - cobble / ice: friction ↓, slides
  - slope: constant push vector
  - water: impassable / heavy slow
  - rock / tree: static circle obstacle, bounce
  - tower / building: capture zone, aura (spin regen, heal) to owner
  - hazard: fire patch (razed town), spike pit, boulder — emergent from world history
- **Spin decay** — `spin -= decay_rate * dt`. Contact with enemy costs extra spin. Standing in capture aura regens.

### 1.3 Weapon hit
Weapon = arc sweep from body rim. Each tick, arc segment tested against enemy circles (broadphase grid first).

```
damage = base[weapon] * (spin / spin_ref) * rank_mult[rank] * crit
knockback = kb[weapon] * (spin / spin_ref) / target.spin_resist
```

| Weapon | Reach | Base dmg | Speed | Knockback | Notes |
|---|---|---|---|---|---|
| dagger | 0.8r | low | fast | low | many hits |
| sword | 1.2r | mid | mid | mid | baseline |
| spear | 2.0r | mid | slow | low | outranges |
| axe | 1.3r | high | slow | high | knocks out of cluster |
| shield | 0.9r | very low | mid | mid | reduces incoming dmg 50% on facing side |

Crit 5%, fumble 3% (lose spin chunk). Floating text: `+1 kill`, `+2 LVL`, small handwritten font.

### 1.4 Captains
Larger marble, helmet sprite, name label. Aura radius: +cohesion, +morale for own faction. Death → faction-wide morale hit → likely mass retreat. Every kill increments permanent counter.

### 1.5 Battle end
- One side fully dead or retreated → winner.
- Timeout (`T_max`) → stalemate, both pull back, no plinko.
- 3+ factions same tile → free-for-all. Attraction to any non-allied enemy. Allied factions (diplomacy state) do not attract each other.
- Survivors return to overworld with xp, wounds (hp_max reduced until Settle heal).
- Dead marbles → gray husk + dropped weapon sprite left on overworld tile (scar, fades over years).

---

## 2. Overworld

Large parchment map. Procedural: rivers, forests, mountains, plains, ruins, graveyards.

### 2.1 Stacks
Army = stack. Continuous slow real-time movement (not turn-based). Label: `(tier)Name count/cap`. Path by terrain cost (A* on coarse grid, cached).

Faction AI picks goal per stack from weighted list, weights = faction traits:
`expand`, `defend`, `raid_rich_neighbor`, `hunt_weak`, `avenge_grudge`, `pilgrimage_to_ruin`, `idle_heal`.

### 2.2 Collision → battle
Two stack circles overlap → battle spawned on that tile. Tile terrain = arena. Stacks within `N` tiles of same factions can be pulled in as reinforcements, arriving mid-battle from arena edge.

Overworld shows: crossed swords on battling tiles, `RETREAT` text + arrow on fleeing stacks.

### 2.3 Towns
Neutral or owned. Produce recruits over time into nearest owned stack. States: intact / raided (neutral) / razed (ruin + fire hazard, heals over long time). Borders = voronoi-ish from town ownership, redrawn on change.

### 2.4 Ledger (right panel)
Faction color, crown, total units, kingdom count. Sorted by power.

---

## 3. Post-battle plinko

Winner only. One marble dropped per surviving captain. Auto-runs (physics). Loser gets nothing.

Pegs: random layout, density/bias drifts per faction over time (emergent). Extra pegs / slots unlock as faction ages.

Slots (weights drift per faction):
| Slot | Effect |
|---|---|
| Settle | occupy nearest town, heal fully |
| Recruit | pull fighters from town / wilds |
| Raid | town → neutral, spawns loot pile |
| Raze | destroy town → ruin, loot, enemy morale hit |
| Forge | upgrade weapon of N units (sword → greatsword etc) |
| Drill | spin_cap ↑ for army |
| Hero Trial | captain gains trait |
| Heir | spawn new captain from top killer |
| Curse | desertion, plague, lost loot |

Marble may bounce into multiple slots → multiple outcomes.

---

## 4. Meta progression (all sim-driven)

### Soldiers
- XP per hit / kill / survive. Ranks Recruit → Veteran → Elite → Legend.
- Stat growth: hp, spin_cap, damage, morale.
- Wounds persist until Settle.
- Legends get generated name from history (`Mudslide Kalen, killer of 40`).
- Persist across battles, faction death (hireable as merc by others).

### Captains / heroes
- Name + dynasty numeral (`Toby XV`). Death → heir from best soldier, numeral +1, inherits partial stats + one trait.
- Traits emergent from behavior log: front-line → Charger; many retreats → Cautious; many razes → Tyrant; many Settles → Builder. Traits shift plinko weights.
- Permanent kill counter, battle log.

### Kingdoms
- No fixed identity. Trait vector accumulates: aggression, diplomacy, greed, piety, cohesion. Drives stack AI goals, plinko bias, weapon preference.
- Split when size high + cohesion low → civil war (two stacks fight).
- Die when zero towns and zero stacks. Rebirth: surviving Legend founds new kingdom in ruins.
- Alliances / vendettas from battle history (killed my captain → grudge weight).

---

## 5. Render / feel

- Parchment bg, marker outlines, watercolor blotches. Marbles = flat colored circle + rim highlight.
- SFX: marble clack (pooled, pitch-varied), spin whir (loop, volume ∝ nearby spin sum).
- Map scars: graves, husks, burnt towns, blood blotches. Fade over years.
- Time slider: 1× / 5× / 50× / max.
- Spectate: click stack or marble → history panel. Global timeline of events (`Kingdom X fell`, `Captain Y XLII died`).

---

## 6. Godot 4 performance plan

Rules, in order:

### 6.1 No nodes per marble
Node2D per marble = dead at ~500. Use:
- **Data**: `PackedFloat32Array` / `PackedVector2Array` per field (SoA). Or one `PackedFloat32Array` with stride. Never `Array[Dictionary]`.
- **Render**: `MultiMeshInstance2D` for bodies. One multimesh per faction color or use per-instance custom data (`INSTANCE_CUSTOM`) for color + rank + spin angle in shader. Second multimesh for weapons (rotated by `weapon_angle`). HP bars: third multimesh, quad with custom data = hp ratio, shader draws fill.
- **Text** (names, kill popups): only for captains + popups. Pool `Label` nodes, max ~50 live.

### 6.2 Physics
Skip Godot physics bodies. Write custom loop:
- Uniform spatial hash grid, cell = `2 * max_radius`. Rebuild each tick (cheap, arrays).
- Neighbor query = 3×3 cells. Handles attraction, separation, collision, weapon arc test.
- Fixed timestep in `_physics_process`. Substep 2× if velocities high.
- Circle-circle only. Weapon arc = circle at rim offset (approximation), not real arc geometry.

### 6.3 Where the loop runs
Three tiers, pick by profiling:
1. **GDScript + packed arrays** — fine to ~800 marbles. Start here.
2. **C# (.NET Godot)** — `Span<float>`, structs, no GC churn. ~3–5k.
3. **GDExtension (C++ / Rust)** — sim in native, push positions to multimesh via `RenderingServer.multimesh_set_buffer()` once per frame. 10k+. Rust via `gdext` recommended if team knows it.

Design step 1 so data layout matches step 3 → swap without rewriting render side.

### 6.4 Multithreading
- Battle sim on `WorkerThreadPool` — partition marbles by grid rows, compute forces in parallel, apply in serial. Only after single-thread is tuned.
- Multiple simultaneous battles: each battle = independent job. Off-screen battles run at reduced tick rate (1/4) or resolve statistically (see 6.6).

### 6.5 Overworld
- Stacks as data arrays, not nodes. Draw with `MultiMeshInstance2D` + one `_draw()` pass for borders (cached `Polygon2D` / `Line2D` rebuilt only on ownership change).
- Terrain = `TileMapLayer` (Godot 4.3+), or single baked texture + separate cost grid `PackedByteArray`.
- Pathfinding: `AStarGrid2D` with coarse cells. Cache paths; recompute only on goal change.
- Collision check: spatial hash again, stacks are few (hundreds). Trivial.

### 6.6 LOD for battles
- **On screen**: full sim.
- **Near**: full sim, half tick rate.
- **Far / off screen**: statistical resolve — Lanchester-style: `dmg_rate = Σ(spin × rank_mult) per side`, apply per second, roll morale. Produces same xp/kill/death outputs. Player never sees difference.
- Switch mode when camera moves; snapshot marble positions so zoom-in looks continuous.

### 6.7 Rendering
- Single `SubViewport` for battle if needed for zoom; otherwise `Camera2D` on world.
- Shader per multimesh: body color from `INSTANCE_CUSTOM.rgb`, rank ring from `.a`. Spin angle passed to weapon shader for rotation → zero CPU transform updates for weapon sprites, just write angle float.
- Scars: draw into persistent `Image` → `ImageTexture.update()` per event, not sprites.
- Floating text: multimesh of glyph quads or pooled `Label`s. Cap.

### 6.8 Persistence
- World state = packed arrays + small dicts for names/history. Save via `FileAccess.store_buffer()` on packed arrays. Avoid `var_to_bytes` on huge dicts.
- History log: append-only, ring buffer for recent, compressed to summaries beyond N entries.

### 6.9 Profiling gates
Do not add features until gate passes:
| Milestone | Gate |
|---|---|
| M1 battle proto | 500 marbles, 60 fps, GDScript |
| M2 arena terrain + captains | 1000 marbles, 60 fps |
| M3 overworld | 200 stacks moving, 3 battles live, 60 fps |
| M4 plinko + meta | no regression |
| M5 native port | 5000 marbles, 60 fps |

Use Godot profiler + `Performance.get_monitor()`. Measure sim ms and render ms separately.

---

## 7. Tuning starting values

```
dt              = 1/60
engage_radius   = 12 * r
k_attr          = 40
k_cohesion      = 15
k_separation    = 120 (range 1.2 * r)
spin_start      = 100
spin_cap[rank]  = [120, 150, 190, 250]
spin_decay      = 4 / s
spin_hit_cost   = 6
spin_transfer   = 0.15
friction        = 0.92 (mud 0.80, cobble 0.98)
morale_start    = 0.8
morale_hit_ally_death   = -0.02
morale_hit_captain_dead = -0.4
retreat_threshold = 0.25
rank_mult       = [1.0, 1.25, 1.6, 2.2]
xp_per_hit      = 1
xp_per_kill     = 10
rank_xp         = [0, 30, 120, 500]
T_max battle    = 120 s
```

---

## 8. Optional later: roguelike mode

Player controls one captain lineage inside same sim. Same data, same loop. Player input = nudge plinko marble once per drop, pick stack goal. Everything else unchanged. Do not design for this until sim stable.

---

## 9. Milestone checklist

- [ ] M1: SoA marble arrays, spatial hash, attraction/separation/collision, multimesh render. 500 marbles.
- [ ] M2: weapons + arc hits, spin, hp, retreat, terrain grid, captains, kill/lvl popups.
- [ ] M3: overworld map, stacks, movement, collision → battle spawn, reinforcements, retreat return.
- [ ] M4: plinko board, slots, towns, borders, ledger.
- [ ] M5: xp/rank persistence, captain lineage, traits, kingdom trait vector, split/death/rebirth.
- [ ] M6: LOD statistical battles, save/load, time slider, spectate panel, timeline.
- [ ] M7: native port if needed.
- [ ] Later (bookmarked 2026-09-13): battle camera auto-zoom — battle view zooms ~1.5–2.5× onto where fighting is happening and pans smoothly, so weapon silhouettes (drawn at true hitbox size, ARCHITECTURE §16.5) are readable. Rendering-only; sim unchanged. Alternative considered: marble radius 8 → 12.
- [ ] Local economies (spec 2026-09-15: `docs/future-state-and-ideas/local-economies.md`), one step at a time:
  - [ ] E1: town food + prosperity — farm yield from surrounding tiles, growth needs surplus, hunger shrinks pop and raises `town_griev`, tax scales with prosperity.
  - [ ] E2: caravans — `Stacks.kind = CARAVAN`, food/wares deliveries between towns, trade raises prosperity and relations, PREY goal for poor armies, route cuts.
  - [ ] E3: kingdom treasury (`faction_gold`), tithe split by greed, wages to armies, lords get Wealth/Land drives from their fief.
  - [ ] E4: reinvestment — town buildings (FARMS, MARKET, WALLS, TEMPLE) chosen by lord or crown values; investing calms the town and pulls its values toward the investor.
  - [ ] E5 (optional): villages as raidable map sites attached to towns.
