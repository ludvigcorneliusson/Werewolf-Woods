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
- Art: pixel art generated in ChatGPT, snapped to real pixels with Pixel Snapper. Reference scale: settler 43 px tall; big trees 84–101 px; bush 49; stump 29; rock 21; grass tile 131x129. Camera zoom 3x.
- Animation: H3 (ComfyUI, fl2va) for run cycles. Settler run cycles imported (right 29 frames, up 16, down 12; left = mirrored right). Pipeline: key out green, sample each video frame back onto the native pixel grid (~7.2–7.7x upscale), snap colours to the settler palette, pick the cleanest loop, align feet with the idle sprite.
- Map is hand-painted in the editor for now (same map every round); generator kept as an option.
- Werewolf is a **player** in the final game; we start with an **AI werewolf**.
- The werewolf **escalates over time**: more power, clues and power-ups, so
  every match eventually ends.
- Map is **procedural from a seed** (multiplayer only needs to sync the seed).
- **Fog of war = line of sight**: trunks and rocks block vision; anything in
  shadow (ground, characters) is hidden. Trees/rocks themselves stay visible.
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
- Campfire idea: light/warmth vs. revealing your position.

## Current state (prototype)
- Hand-painted World in main.tscn: grass Ground layer (30x30 tiles), Props layer with a seeded starter forest around a central clearing, Spawn marker.
- Props (trees, pine, bush, stump, rock) are scenes with trunk collision, a vision blocker (trees/bush), and fade when the player is behind them. Paintable via the Props TileMapLayer (scene tiles, 16 px grid).
- Settler: AnimatedSprite2D built in code — idle stills + H3 run cycles (up/down/right, left mirrored), WASD, Shift sprint with stamina. Every run cycle is normalised to `RUN_CYCLE_TIME` (0.5 s) at walk speed and plays faster when sprinting.
- Fog of war via the player's vision light; invisible walls + camera limits follow the painted ground.
- Debug: F toggle fog, mouse wheel zoom. Old procedural map still available (Main > Use Generated Map), but it uses the old code-drawn art.

## Files
- `main.tscn` — Main > World (y-sorted): Ground (TileMapLayer, grass), Props (TileMapLayer, scene tiles), Spawn (Marker2D).
- `assets/characters/` — settler_up/down/right.png (idle), settler_run_up/down/right.png (horizontal run strips; frame sizes/offsets in player.gd `RUN`).
- `assets/props/` — prop PNGs + one .tscn per prop, props_tileset.tres, prop_material.tres + prop_fade.gdshader (shared fade).
- `assets/tiles/` — grass.png + ground_tileset.tres.
- `tools/build_world.gd` — rebuilds prop scenes, tilesets and the World (OVERWRITES painted World). Prop collision/vision sizes are in its PROPS table.
- `scripts/main.gd` — entry point: darkness, player, world setup, borders, HUD, input.
- `scripts/player.gd` — settler movement, sprite direction, vision light, camera. Tunables: `WALK_SPEED`, `SPRINT_SPEED`, `STAMINA_*`, `RUN_CYCLE_TIME`.
- `scripts/map_generator.gd`, `scripts/prop.gd`, `scripts/map_preview.gd` — old procedural map (optional).

## Roadmap
1. AI werewolf: spawn timer, search → investigate (noise/footprints) → chase → catch.
2. Round flow: build phase, hunt phase, end screen.
3. Camp building: walls + campfire first.
4. Wolf escalation and power-ups.
5. Settler bots for testing.
6. Multiplayer: local (two windows) → online.
