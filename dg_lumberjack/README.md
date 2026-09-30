# dg_lumberjack

A civilian lumberjack job for ESX Legacy, using ox_lib, ox_inventory and ox_target. The loop:

1. Chop trees.
2. Load the logs onto a truck.
3. Unload them at the mill conveyor.
4. Load the planks the mill produces.
5. Deliver the planks for cash and XP.

## Install

1. Copy `dg_lumberjack/` into your resources folder.
2. Add `ensure dg_lumberjack` to `server.cfg`, after `es_extended`, `ox_lib`, `ox_inventory` and `ox_target`.
3. Make sure OneSync is on.
4. Make sure `data/xp.json` is writable by the server process. It starts as `{}`.
5. Players need a `WEAPON_HATCHET` in ox_inventory, **equipped**, to see the "Chop tree" option.

The resource needs no SQL.

## Before the first test, replace the placeholders in `config.lua`

- **Coordinates.** Replace every `vec3`/`vec4` with real positions you copy in-game: trees, depot ped, truck spawn, mill input/end/output, delivery and blips. Tree Z can be rough because the client snaps trees to the ground (`Config.Trees.snapToGround`).
- **Prop models.** `prop_log_01`, `prop_cons_plank`, `prop_tree_pine_01`, `prop_tree_stump_01` and `s_m_y_construct_01` were not checked. An invalid model prints a red warning in F8 and is skipped.
- **Truck attachment points.** Set `Config.Debug = true`, sit in the truck and run `/ljpoints`. Log points show as orange markers and plank points as blue, for 15 seconds. Adjust `offset`/`rot` until they sit on the bed.

## Where the state lives

| What | Server truth | Clients see it through |
|---|---|---|
| Tree chops left / felled | `Trees[id]` | `GlobalState['lj:tree:<id>']` |
| Ground logs/planks (position, source tree) | `GroundItems[id]` | `GlobalState['lj:item:<id>']` plus a snapshot callback on join |
| Truck bed contents | `Loads[plate]` (tied to the vehicle entity) | `Entity(veh).state.ljLoad` |
| Mill queue, pending chops, depot trucks | server only | — |
| XP | `data/xp.json` (keyed by ESX identifier) | `exports.dg_lumberjack:GetXP(identifier)` |

- Trees, ground items and truck loads live in memory. They reset on restart by design.
- Every prop is a **local** object on each client, built from this state. Other players and late joiners therefore see the same trees, logs and loaded trucks.
- A client removes the props attached to a truck once that vehicle no longer exists locally.
- On the server, the `entityRemoved` event clears a deleted truck's load.

## Server-side validation

Before acting, the server checks:

- **Chop:** the tree isn't felled, the player has a hatchet (`ox_inventory:GetItemCount`), and the player is within range.
  - Each attempt uses a one-time token.
  - The server picks the skill check difficulty.
  - A result is rejected if it arrives before `duration × minFraction` or after `duration + maxExtra`.
  - A failed skill check still uses up a chop.
- **Load:**
  - The item still exists, and removing it is atomic, so it can't be loaded twice.
  - Player → item and truck → item distances are in range.
  - The vehicle model is configured, and its plate matches the tracked entity.
  - The pool has a free slot and the truck's `maxWeight` isn't exceeded.
- **Unload:** the player and the truck are at the mill, and that exact slot really holds a log.
- **Deliver:** the player and the truck are at the delivery point. The payout counts only planks the server tracks. Money is paid with `xPlayer.addAccountMoney`.

Limitation: the server can confirm that a skill check was issued and answered once, at a plausible speed. It cannot prove the minigame wasn't automated on the client.

## Open to civilians

`Config.Job = nil` lets anyone do the job. Set it to a job name to restrict it.

## Vehicle keys

If you run a key system, give keys where `server.lua` says `-- Vehicle keys:` in `lj:spawnTruck`.

## API references

I checked these against the resources' source on GitHub on 2026-09-30:

- ox_lib — `lib.skillCheck(difficulty, inputs?)`, `lib.progressBar`, `lib.callback.register/await`, `lib.points.new`, `lib.getNearbyVehicles`, `lib.requestModel`, `lib.notify`: https://coxdocs.dev/ox_lib — source: https://github.com/communityox/ox_lib
- ox_inventory — `GetItemCount(inv, itemName, metadata?, strict?)`: https://coxdocs.dev/ox_inventory/Functions/Server
- ox_target — `addLocalEntity`, `removeLocalEntity`, `addGlobalVehicle`, `addSphereZone`: https://coxdocs.dev/ox_target/Client
- ESX Legacy — `getSharedObject`, `ESX.GetPlayerFromId`, `xPlayer.addAccountMoney(account, money, reason?)`, `xPlayer.getJob()`, `xPlayer.identifier`: https://docs.esx-framework.org/legacy/Server/Classes/xPlayer
- FiveM:
  - State bags: https://docs.fivem.net/docs/scripting-manual/networking/state-bags/
  - `entityRemoved`: https://docs.fivem.net/docs/scripting-reference/events/server-events/
  - Natives (`CreateVehicleServerSetter`, `SetPedIntoVehicle`, `AttachEntityToEntity`, `SaveResourceFile`): https://docs.fivem.net/natives/
