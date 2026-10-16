# LastGears

Twin-stick tactical mech squad shooter in Godot 4. Far future: the machines won.
What's left of humanity huddles in walled settlements, and mech squads trudge the
ruins between them. You lead a squad of four; your three squadmates think for
themselves.

Inspired by *Mech Engineer*'s top-down "grainy satellite feed" look and its
weight / power / heat build trade-offs, and by *Left 4 Dead*'s AI director.

## Running

Godot **4.4+** (Compatibility renderer).

```sh
godot --path /path/to/LastGears
```

or open `project.godot` in the editor and press F5.

## Controls

Starts fullscreen (F11 toggles). Keyboard + mouse is the default; a gamepad also works.

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move (deliberately not fast) | WASD | Left stick |
| Aim | Mouse (crosshair; distance = mortar range) | Right stick |
| Weapon 1 (primary hardpoint) | Left click | R1 |
| Weapon 2 (secondary hardpoint) | Right click | L1 |
| Tactical view + corridor map | Q (toggle) | Hold R2 |
| Pause | Enter | Select/Share |
| Field refit menu (real time!) | Esc | Start |
| Refit: select / confirm / back | W,S / E, Space, left click / Backspace, right click | D-pad / A / B |
| Toggle director readout | F3 | |
| Toggle satellite filter | F2 | |
| Restart | F5 | |

## The vertical slice

Get from **Outpost Gravel** (west) to **Haven-7** (east) along the old freight road.

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
- **Customisation.** 4 frames, 7 weapons (autocannon, gatling, flak, rockets, pulse
  laser, mortar, incinerator), 9 modules (plating, heat sinks, reactor booster,
  servos, shield, targeting computer, ammo rack, repair drone, fire cycler). Every
  part has weight vs. frame max, power draw vs. reactor output, and heat vs.
  cooling. Overweight = slower and hotter; power deficit = weapons cycle slower;
  heat 100 = shutdown and venting. The refit panel previews every stat delta.
- **Director.** RELAX (nothing spawns: breathe, scavenge, refit) → BUILD-UP (small
  packs trickle in from out of sight) → PEAK (a horde from one or two directions,
  with Wardens) → back to RELAX once the area is actually clear. Intensity rises
  with damage taken and nearby enemies; difficulty scales with how far east you
  are. The top-right readout (F3) shows what it's doing, for tuning.
- **Enemies are dots.** Rendered in bulk like *Mech Engineer*'s swarms, mechs a bit
  bigger and readable. Four types:
  - **Skitter** (red dot): fast, fragile melee swarm.
  - **Spitter** (orange ring): keeps range, strafes, fires slow bolts.
  - **Tick** (blinking yellow): suicide runner, explodes on contact *or death*,
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
  field_menu.gd         real-time refit UI
  hud.gd                HUD, tactical corridor map, end screen
  tactical_overlay.gd   world-space markers in tactical view
  game_camera.gd        follow, aim look-ahead, tactical zoom, shake
shaders/satellite.gdshader   grain / scanline / tint "satellite feed" filter
```

Balancing lives almost entirely in `parts_db.gd`, `enemy_manager.gd` (`TYPES`) and
`director.gd`.

## Automated playtest

An AI can drive the player for smoke tests and pacing checks:

```sh
godot --headless --path . --fixed-fps 60 --quit-after 25200 -- --bot --seed=7
```

It prints director phase changes and a status line every 10 s (enemy count,
intensity, materials, each mech's state and hull), and exercises the refit menu.
Add `--shots=/some/dir` (with a real or virtual display, not `--headless`) to save
screenshots.
