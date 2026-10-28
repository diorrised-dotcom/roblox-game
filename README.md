# LIGHTS OUT

Co-op first-person survival horror for Roblox. Light is the only protection; every safe light eventually fails.
This repo is the **MVP**: one facility (THE BLACKOUT FACILITY), one monster (the Stalker), 2-6 players.

## Run it

Requires [Rojo](https://rojo.space) 7.x.

```bash
rojo serve          # then connect from the Rojo plugin in an empty Studio baseplate
# or build a place file:
rojo build -o LightsOut.rbxl
```

Press Play (Studio needs only 1 player; live servers need `Config.Round.MinPlayers`).
The graybox map is generated at runtime by `MapBuilder` if `Workspace.LightZones` does not exist.

> **Not yet verified in Studio.** This was written without Studio access (the Roblox Studio MCP server failed
> to connect) and the Luau was not compiled or run. Expect to fix small API/typo issues on first play.

## Layout

| Path | Purpose |
|---|---|
| `src/shared/Config.luau` | All tuning values (movement, light cycle, Stalker, rounds, rewards, sound ids) |
| `src/server/LightService` | Light-zone state machine + **server-side** safe check and exposure timer |
| `src/server/MovementService` | Server-authoritative stamina / sprint speed, fall kill |
| `src/server/Stalker` | Stalker model, patrol, weighted target choice, pathfinding, kill validation |
| `src/server/RoundService` | Intermission -> countdown -> play -> end, spectating, objective, rewards |
| `src/server/MapBuilder` | Graybox facility generator (8 light zones, pits, switches, gate, exit) |
| `src/server/Collision` | `Players` / `Bridges` collision groups (see below) |
| `src/server/Progression` | XP + coins (DataStore, cosmetic currency only) |
| `src/client/*` | Movement feel, light flicker rendering, HUD, audio, spectator camera |

## How the core loop works

- Each zone is a model with a `Boundary` box and a `Bulb`. Zones are **armed when a player first enters**;
  an armed zone runs Stable 20s -> Flickering 7s -> Critical 3s -> Off, stays dark 12s, then relights *unarmed*.
  So the next light is always lit when you arrive, and the clock starts when you do.
- Protection is decided only on the server (`LightService.IsSafe`). A newly exposed player has
  `Config.GraceSeconds` (1.5s) before the Stalker may kill them.
- The Stalker picks among exposed players (weighted toward closer, not strictly nearest), accelerates while
  chasing, and gives up when its target gets back into a lit zone.
- Objective: hold 3 generator switches in Zone 07 -> BLACKOUT (stable/flicker times halve, Stalker x1.15 speed,
  a second Stalker spawns behind you, the exit gate opens) -> reach the exit.
- Death = immediate, then spectate (click to cycle). Round ends on escape (10s for the others), total
  elimination, or the 15 minute cap.

## Map contract (to use your own map instead of the graybox)

- `Workspace.LightZones`: Models with attributes `Label`, `Order` (1..n), optional `Permanent`; children `Boundary`
  (Part, the safe volume), `Bulb` (Part containing a `PointLight`, optional `Hum` Sound).
- `Workspace.Facility`: `Switches` folder (Parts with a `ProximityPrompt`), `ExitGate` Part, `ExitTrigger` Part,
  a `SpawnLocation`.
- `Workspace.StalkerPatrol`: parts used as patrol waypoints. `Workspace.StalkerSpawns`: `Spawn1`, `Spawn2`.
- Pits use an invisible `Bridges` collision-group part over each gap so players fall in but the Stalker's
  navmesh path can cross. **Verify in Studio** that pathfinding crosses them; if not, replace with
  `PathfindingLink`s or let the Stalker jump gaps.

## Tuning

Everything is in `Config.luau`. Initial targets only: walk 14, sprint 22, 5s stamina / 4s recover.
A sprinting jump clears roughly 11 studs, a walking jump roughly 7; pits are 6-9 studs, so wide pits demand a sprint.
`Config.UI.ShowNextLightDistance = false` hides the distance readout for harder modes.

## Audio

Sound ids in `Config.Sounds` are empty. Fill in `rbxassetid://...` values and the hum, flicker warning,
light-off sting, breathing and Stalker footsteps switch on. Not implemented yet: ambient ducking before an attack.

## Next steps (from the design)

1. Playtest with real players: unfair jumps, unavoidable deaths, Stalker speed vs sprint.
2. Controlled route randomisation (several designed routes per section).
3. Optional downed/revive mode.
4. The Watcher and the Crawler, once light + movement feel right.
5. Cosmetic shop for coins; more maps.
