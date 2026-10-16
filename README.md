# LastGears

Twin-stick tactical mech squad shooter in Godot 4. Far future: the machines won.
What's left of humanity huddles in walled settlements, and mech squads trudge the
ruins between them. You lead a squad of four; your three squadmates think for
themselves.

Inspired by *Mech Engineer*'s top-down "grainy satellite feed" look and its
weight / power / heat build trade-offs, and by *Left 4 Dead*'s AI director.

## Running

Godot **4.7+** (Compatibility renderer).

```sh
~/bin/godot --path ~/Projects/LastGears
```

or open `project.godot` in the editor and press F5.

## Before pushing

```sh
GODOT=~/bin/godot tools/smoke_test.sh
```

Clones the committed state fresh (no editor cache), launches it, runs a simulated
playthrough and a full station visit, and fails on any script or engine error.

## Controls

Starts fullscreen (F11 toggles). Keyboard + mouse is the default; a gamepad also works.

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move (deliberately not fast) | WASD | Left stick |
| Aim | Mouse (crosshair; distance = mortar range) | Right stick |
| Weapon 1 (primary hardpoint) | Left click | R1 |
| Weapon 2 (secondary hardpoint) | Right click | L1 |
| Dodge roll (brief invulnerability, 2 s cooldown, +heat) | Space / Shift | Circle |
| Squad formation: follow → group up → spread out → hold | E (cycles) | D-pad → / ↑ / ↓ / ← |
| Radar range (175 / 350 / 700 m) | Q | R2 |
| Region map (havens, zones, threat) | M | Touchpad |
| Pause | Enter | Select/Share |
| Field refit menu (real time!) | Esc | Start |
| Refit: select / confirm / back | W,S / E, Space, left click / Backspace, right click | D-pad / A / B |
| FPS meter: per-system profiler breakdown | F1 | |
| Render resolution: fast (1600×900 scaled up) / sharp (native, e.g. Retina) | F9 | |
| Mech look: ORB TACTICAL (default: still orb + a tiny garbled terminal feed per unit) / HULL / GLYPH / MONOLITH / ORB (remembered) | F6 | |
| Toggle director readout | F3 | |
| Toggle satellite grain/tint (darkness stays) | F2 | |
| Restart | F5 | |

## The campaign

Travel station to station across the region. Each leg is a fresh zone between
two nodes on the region map; reaching the far gate takes you inside the walls:

- **HANGAR** – swap gear on any squad mech from your spare-parts inventory
  (instant and free; removed parts go back to spares).
- **MARKET** – sell/buy scrap, circuits and cells (prices vary by station),
  buy parts, sell spares. Ruins have no traders.
- **REPAIRS** – hull damage carries between legs; havens repair cheaper and can
  hire a replacement pilot for a fallen squadmate (fresh random weapons).
- **DEPART** – choose the next route: destination, zone, threat, payout.

Credits come from a delivery fee on arrival (scales with zone threat) plus
bounties for machines destroyed. Zones get harder with threat and with legs
travelled. Lose your Vanguard and you can retry the leg from the last station
(Enter / F5) or start a new campaign (N).

## The first leg

Every campaign generates its own region (`atlas.gd`, seeded per campaign). Each
leg's zone is a fresh dead city laid out along the real direction of travel on
the region map (heading north-west on the map = heading north-west in the zone).
Every run rolls fresh weapons for every mech (within each frame's weight limit);
frames and role modules stay fixed.

- **Biomes.** Each route on the region map has a terrain, and the zone is built
  to match: *dead city* (blocks, plazas, flickering streetlights), *industrial
  yards* (warehouses, storage tanks, pipe runs, sodium floodlights), *flooded
  district* (shallow water slows mechs ~40%, cold moonlit tint), *scrap fields*
  (wreck piles, hulks, burning wrecks, craters) and *dead forest* (dense bare
  trees throwing long shadows; the darkest). All props block movement and light.
- **Darkness.** The zones are pitch black. Each mech throws a cone of light where
  it aims (shadowed by buildings) plus a small hull halo; explosions and muzzle
  flashes light things up briefly; settlements burn beacons. Machines are only
  *known* to the squad while inside someone's cone (shared across the squad) or
  within ~110 px of a hull, so squadmates can be surprised from behind.
- **Radar (lower left).** Proximity sensor: friendlies and aim lines are live,
  hostile blips refresh only as the sweep passes (one revolution every 21.6 s) and fade between sweeps. Rim
  marker points to the destination. Q cycles range.
- **Formations (E / D-pad).** Follow (default slots), Group up (tight, shorter
  leash, no scavenging), Spread out (wide arc, longer leash), Hold (stay where
  the order was given). When idle, squadmates scan the arcs you aren't looking
  at: Rook your right, Wren your left, Mags your rear.
- **Region map (M).** Havens, outposts, machine hives and ruins linked by named
  zones with threat ratings. Current leg and live squad position highlighted;
  hover a node for details.

- **Squad of four.** You pilot VANGUARD. ROOK (brawler, Bulwark heavy frame), WREN
  (marksman, Kestrel light frame) and MAGS (medic, Sparrow support frame) run on a
  utility AI that re-scores follow / engage / cover / retreat / scavenge / repair
  several times a second through each pilot's personality (aggression, caution,
  loyalty, greed, heat discipline, preferred range). They lead targets, won't fire
  through each other, never drop splash on a squadmate, prioritise Ticks closing
  in, cover whoever is under the most pressure, and talk on the radio.
- **Field refit (Start).** Real time: the world keeps going, your mech stands still
  and can't fire, and your squad moves to cover you. Fabricate parts from salvaged
  scrap / circuits / cells; each install takes seconds, during which that slot is
  offline. Stripping a part salvages half its scrap. Field repair is here too.
- **Customisation.** 4 frames, 11 weapons (autocannon, gatling, flak, rockets, pulse
  laser, mortar, incinerator, plus the rail driver — a piercing beam through every
  machine in a line — the arc caster — lightning chaining through 6 machines — the
  cluster mortar — a shell that bursts into bomblets — and the swarm pod — homing
  micro-missiles), 9 modules (plating, heat sinks, reactor booster,
  servos, shield, targeting computer, ammo rack, repair drone, fire cycler). Every
  part has weight vs. frame max, power draw vs. reactor output, and heat vs.
  cooling. Overweight = slower and hotter; power deficit = weapons cycle slower;
  heat 100 = shutdown and venting. The refit panel previews every stat delta.
- **Director.** RELAX (nothing spawns: breathe, scavenge, refit) → BUILD-UP (small
  packs trickle in from out of sight) → PEAK (a horde from one or two directions,
  with Wardens) → back to RELAX once the area is actually clear. Intensity rises
  with damage taken and nearby enemies; difficulty scales with how far east you
  are. The top-right readout (F3) shows what it's doing, for tuning.
- **Enemies are dots, and there are a lot of them.** Around two thousand per zone: dormant
  crawler fields scattered through the city (asleep they cost nothing: they sit in a
  static grid outside the simulation) (they wake when you get close or
  shoot them), plus much bigger director packs and hordes. All weapons hit ~2.2×
  harder with bigger magazines to cope. Five types:
  - **Crawler** (dull red dot): the bulk of the swarm. Slow, fragile, endless.
  - **Skitter** (red dot): medium-pace biter.
  - **Spitter** (orange ring): keeps range, strafes, fires slow bolts.
  - **Tick** (blinking yellow): rare, fast suicide runner, explodes on contact *or death*,
    chains, and hurts everyone, including other machines.
  - **Warden** (magenta diamond): armoured brute (−5 per hit, so gatling/flamer
    struggle; autocannon/rockets/mortar crack it). Drops good salvage.

## Code map

```
scripts/
  g.gd                  autoload: shared state, materials, radio, input map
  main.gd               builds the scene, win/lose, bot test hooks
  world.gd              map gen, drawing, collision, LOS, A* (squad), flow field (swarm)
  parts_db.gd           ALL tunable data: frames, weapons, modules, costs
  loadout.gd            parts -> derived stats (weight/power/heat budgets)
  mech.gd               mech movement, heat, weapons, installs, damage, drawing
  squad_brain.gd        personalities, utility AI, barks
  enemy_manager.gd      enemy types + swarm sim (spatial buckets) + drawing
  projectile_manager.gd bullets, rockets, mortar shells, explosions, fx
  director.gd           L4D-style pacing
  atlas.gd              region network (havens, hives, zones) for the region map
  campaign.gd           persistent run state: location, credits, materials, spares, squad
  station_menu.gd       station screen: hangar, market, repairs, depart
  field_menu.gd         real-time refit UI
  hud.gd                HUD, tactical corridor map, end screen
  lighting.gd           darkness: ray-cast light cones painted into a half-res light map
                        (applied by the post shader), flashes, vision-cone maths
  game_camera.gd        follow, aim look-ahead, tactical zoom, shake
shaders/satellite.gdshader   grain / scanline / tint "satellite feed" filter
```

Balancing lives almost entirely in `parts_db.gd`, `enemy_manager.gd` (`TYPES`) and
`director.gd`.

## Performance notes

Built for 120 Hz. Everything that moves updates every rendered frame (no 60 Hz
physics stepping). The swarm re-decides ~20×/s, time-sliced, but all of it
moves every frame; sleeping machines cost nothing until they wake. The flow
field that steers the swarm is rebuilt a slice per frame so it never hitches.
The city is drawn in 600 px chunks so off-screen chunks are culled, and
enemies, shots and pickups only draw on screen. Darkness doesn't use Light2D:
cones are ray-cast against the grid and painted once into a half-resolution
light map that the post shader multiplies in. F1 shows the per-system cost.
Draw calls are kept low: city chunks near the camera are baked once into
textures (one quad each), every machine and radar blip is the same batched
dot sprite, tracers and shards go out in one multi-line call, and the static
HUD renders offscreen ~20x/s and is a single quad in between.

On a Mac you can also try Godot's native Metal renderer (it falls back to
OpenGL automatically if unavailable):

```sh
~/bin/godot --path ~/Projects/LastGears --rendering-method mobile
```

While you play, a `[perf]` line goes to the terminal (and is appended to
`perf.log` in the project folder, git-ignored) every 5 s, and every second
whenever FPS drops below 100 with machines awake: FPS, average and worst frame
time, enemy counts, director phase, render mode, the five most expensive
systems and draw calls. Each session starts with a header naming the GPU,
screen size and refresh rate.

## Automated playtest

An AI can drive the player for smoke tests and pacing checks:

```sh
godot --headless --path . --fixed-fps 60 --quit-after 25200 -- --bot --seed=7
```

It prints director phase changes and a status line every 10 s (enemy count,
intensity, materials, each mech's state and hull), and exercises the refit menu.
Add `--shots=/some/dir` (with a real or virtual display, not `--headless`) to save
screenshots. `-- --gallery --shots=/some/dir` renders every mech style side by
side to `gallery.png` (`--gallery-styles=3,4,5` picks rows); `--mech-style=N`
(0-4) forces a style.
