# Werewolf Woods — Design Doc

Multiplayer asymmetric chase game (1 werewolf vs. many settlers), inspired by
Warcraft 3's **Tree Tag**. Built in **Godot 4.5**, GDScript, 2D with a faked
Don't Starve-style 3/4 camera. All art is drawn in code (no image assets yet).

## Core loop
1. **Scatter** — settlers spawn in the central clearing and run outward.
2. **Build** — settlers pick a spot in the forest or mountains and build a camp.
3. **Hunt** — the werewolf spawns and searches for them.
4. **End** — the match ends when the werewolf has caught every settler.

## Decided
- Art: pixel art generated in ChatGPT, snapped to real pixels with Pixel Snapper. Reference scale: settler 43 px tall; trees placed at 2.0–2.6x so pixels match: pine_tall 90x166, pine_dark 54x104, dead_pine 65x228, dead_tree 68x175; mushroom_brown 18x16; bush_small 49x35, bush_big 75x64, stump_log 79x45, fallen_tree 123x41 (resampled from larger art to the settler's pixel density); stump 38x29, log 58x25, boulder 38x30, mossy rock 24x20, ferns 42x29/33x25, grass tuft 18x17, mushroom 15x17, pebble 17x12, stick 19x13 (all at 1x); grass tile 131x129. Camera zoom 3x.
- Animation: H3 (ComfyUI, fl2va) for run cycles. Settler run cycles imported in 8 directions (right 29 frames, up 16, down 12, up_right 16, down_right 30; left side = mirrored right side). Diagonal idles = standing first frame of their video. Diagonals were sampled at ~7.4x so their size matches the older sprites (native grid in those videos was ~6.9x, which made him ~10% bigger). Pipeline: key out green, sample each video frame back onto the native pixel grid (~7.2–7.7x upscale), snap colours to the settler palette, pick the cleanest loop, align feet with the idle sprite.
- Map is hand-painted in the editor for now (same map every round); generator kept as an option.
- Werewolf is a **player** in the final game; we start with an **AI werewolf**.
- The werewolf **escalates over time**: more power, clues and power-ups, so
  every match eventually ends.
- Map is **procedural from a seed** (multiplayer only needs to sync the seed).
- Fog of war: cell-based light around the settler that fades to black; props cast soft
  shadows and dense forest dims it.
- Camera: fixed 3/4 view, objects upright and y-sorted; trees fade when the
  local player is behind them. No camera rotation (would require real 3D).

## Open questions
- Build phase length before the wolf spawns?
- What can settlers build (walls, campfire, traps…)? Costs / resources (wood?)
- Escalation: time-based, per catch, or both? Which power-ups first?
  Ideas: smell fresh footprints, hear chopping/building, break walls faster,
  howl that reveals nearest settler, faster movement, map-wide pings late game.
- Caught settlers: out, spectate, rescuable, or become wolves?
- Settler goal/score: survival time ranking, reaching dawn, or other?
- Campfire: there is now one in the central clearing (light + particles). Its light is visible from afar in the dark: light/warmth vs. revealing your position.

## Current state (prototype)
- World in main.tscn (built by WorldBuilder): grass Ground layer (80x80 tiles), Props layer with a seeded forest of two pine types (Tree Mix weights in WorldBuilder; the original pine.png was removed) + dead trees (~8%) + stumps, logs, boulders, mossy rocks, ferns, grass tufts, mushroom groups, pebbles and sticks around a central clearing, a Campfire at the centre (0,0), Spawn marker just south of it.
- Props are scenes (built from the PROPS table in tools/build_world.gd) with optional collision, vision blocker (pine trunks, boulders) and fade when the player is behind them. Big props (pine, stump, log, rocks) stay visible as silhouettes; small ground cover (ferns, grass, mushroom, pebble, stick) hides in line-of-sight shadow. All use scripts/varied_prop.gd for per-instance size/colour/flip. Paintable via the Props TileMapLayer (scene tiles, 8 px grid).
- Settler: AnimatedSprite2D built in code — idle stills + H3 run cycles in 8 directions (up/up_right/right/down_right/down, left side mirrored), WASD, Shift sprint (unlimited, no stamina). Every run cycle is given its own `cycle` time in player.gd `RUN` (0.5 s by default) at walk speed and plays faster when sprinting.
- Fog of war via the player's vision light, fading to completely black. Tunables in the Inspector on the Main node (Fog group): fog_color, fog_darkness, vision_radius, fog_start, fog_density, vision_brightness, vision_tint, vision_squash, shadow_softness (also live-editable while running). Invisible walls + camera limits follow the painted ground.
- Trees: one shared 2.0–2.6x scale (TREE_VARY in tools/build_world.gd) so all tree pixels are the same size; living pines ≈200–430 px, dead trees ≈350–590 px, each with its own size, hue/saturation/brightness and mirroring picked from its map position (scripts/varied_prop.gd, tunables on the root of each prop scene, e.g. pine.tscn). Colour shift is done in prop_fade.gdshader via varied_material.tres.
- Idle: the settler breathes (sprite stretched up from the feet on a sine wave) and drifts slightly while standing still (assets/characters/idle_breathe.gdshader); fades in after stopping, off instantly when moving. Settings in Main > Idle.
- Tree trunks never touch: WorldBuilder rejects a tree if it is closer sideways than both root widths + Trunk Gap while its base lies within the front tree's visible trunk height (TREE_SHAPE in world_builder.gd, art px, at each tree's max scale). Dead trees are placed first since their whole trunk is visible.
- Bushes (small/big): walk-in hiding spots - not solid; they bend when pushed and cover a player standing in them. (Their one-sided vision blockers only matter if Crisp Shadows is turned on.) Fallen trees and stump+log are solid, low (no sight block). Collision/vision blockers mirror with the sprite.
- Display: starts fullscreen (project.godot window/size/mode=3), F11 toggles windowed. Camera: Main > Camera > Camera Zoom (default 1.0 = far), Scroll Zoom off by default. Vision radius 380 px to suit the far camera.
- Darkness (scripts/darkness.gd): light cells that react to the props. Each prop makes its ground cells soak up light (ABSORB table: trunks most, canopies/bushes some, rocks/logs a little; scaled by Trunk/Canopy/Prop Shade). Light travels outward from the settler (and campfires) in straight lines cell by cell (each cell takes the light from one step back towards the source, bilinear), so props cast soft shadow wedges and dense forest dims it. A cell shows the light reaching it (no dark boxes). Recalculated only when the player enters another cell (~2.3 ms); campfire once. Blended cells (Cell Softness 2-4) or crisp squares (1). The darkness overlay is drawn in the world between ground (z -10) and props (z 0), so it only darkens the ground; props are lit by PROXIMITY in prop_fade.gdshader: distance from the player to the closest point on the prop's trunk line, same fade curve as the ground (radius/start/density/squash); campfire light read at the base. Shadows are only on the ground, so nearby props are never dark. Nothing moves by itself. Settings in Main > Fog.
- Wind: each prop sprite is sheared like a hinge at its base on a plain sine wave (vertex shader in prop_fade.gdshader); timing shifts slowly across the map so the forest moves as a wave. Settings in Main > Wind (strength, speed, lean, wave length, direction); per-prop "Sway" on each prop scene root (trees 1.0, dead trees 0.35, ferns 0.6, grass 0.8, rocks/logs/stumps 0).
- Plants: ferns, grass and mushrooms bend away when the settler walks through and spring back with a wobble (scripts/plant_push.gd, Sprite skew, only plants near the player). Settings in Main > Plants; per-plant "Bend" on each prop scene root. Only the local player pushes plants so far.
- Campfire: CPUParticles2D Fire/Core/Embers/Smoke + flickering PointLight2D that casts trunk shadows (scripts/campfire.gd: light_radius, light_energy, flicker_*).
- Debug: F toggle fog, mouse wheel zoom. Old procedural map still available (Main > Use Generated Map), but it uses the old code-drawn art.

## Files
- `main.tscn` — Main > World (y-sorted): Ground (TileMapLayer, grass), Props (TileMapLayer, scene tiles), Spawn (Marker2D).
- `assets/characters/` — settler_up/down/right/up_right/down_right.png (idle), settler_run_<same>.png (horizontal run strips; frame sizes/offsets in player.gd `RUN`).
- `assets/props/` — prop PNGs + one .tscn per prop, props_tileset.tres, varied_material.tres + prop_fade.gdshader (shared fade + colour variance), campfire.png/.tscn.
- `assets/tiles/` — grass.png + ground_tileset.tres.
- `tools/world_builder.gd` — WorldBuilder node in main.tscn: set map size (ground_tiles), seed, clearing, forest density and per-prop amounts (Props group) in the Inspector, click **Rebuild World**, save. Replaces the World node.
- `tools/build_world.gd` — rebuilds prop scenes, tilesets and the World (OVERWRITES painted World). Prop collision/vision sizes are in its PROPS table; World settings come from the WorldBuilder node.
- `tools/build_campfire.gd` — makes campfire.tscn once (OVERWRITES particle tweaks if re-run).
- `scripts/main.gd` — entry point: fog settings + darkness, player, world setup, borders, HUD, input.
- `scripts/player.gd` — settler movement, sprite direction, vision light, camera. Tunables: `WALK_SPEED`, `SPRINT_SPEED`, `RUN[...].cycle` (per-direction run speed).
- `scripts/map_generator.gd`, `scripts/prop.gd`, `scripts/map_preview.gd` — old procedural map (optional).

## Roadmap
1. AI werewolf: spawn timer, search → investigate (noise/footprints) → chase → catch.
2. Round flow: build phase, hunt phase, end screen.
3. Camp building: walls + campfire first.
4. Wolf escalation and power-ups.
5. Settler bots for testing.
6. Multiplayer: local (two windows) → online.
