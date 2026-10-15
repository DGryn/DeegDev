# dg_cocaine

A cocaine loop for ESX Legacy, built on ox_lib, ox_inventory, ox_target and oxmysql:

1. Trade junk with the seed NPC for coke seeds.
2. Plant the seeds on Cayo Perico or the small islands, then water them. Fertiliser is optional.
3. About 3 hours later, harvest coca leaves. Anyone can harvest any plant.
4. At the hidden lab, the mixer turns leaves into paste, then raw cocaine, then cut cocaine. The press turns cut cocaine into bricks.
5. Use a brick from your inventory, with scales and 25 baggies, to bag it into 25 bags.

## Install

1. Copy `dg_cocaine/` into your resources folder.
2. Run `dg_cocaine.sql` on your database.
3. Add the items below to `ox_inventory/data/items.lua`.
4. Add `ensure dg_cocaine` to `server.cfg`, after `es_extended`, `oxmysql`, `ox_lib`, `ox_inventory` and `ox_target`.
5. Replace the placeholders in `config.lua`: the NPC, lab and planting-zone coordinates, the trade item pool, and the plant models.

## ox_inventory items

```lua
['coke_seed'] = {
    label = 'Coke Seed',
    weight = 10,
    stack = true,
    close = true,
    description = 'Plant it somewhere warm and quiet.',
    client = { export = 'dg_cocaine.useSeed' },
},
['coca_leaf'] = {
    label = 'Coca Leaf',
    weight = 20,
    stack = true,
},
['coca_paste'] = {
    label = 'Coca Paste',
    weight = 200,
    stack = true,
},
['cocaine_raw'] = {
    label = 'Raw Cocaine',
    weight = 200,
    stack = true,
},
['cocaine_cut'] = {
    label = 'Cut Cocaine',
    weight = 200,
    stack = true,
},
['cocaine_brick'] = {
    label = 'Cocaine Brick',
    weight = 1000,
    stack = true,
    close = true,
    description = 'Needs scales and baggies to split up.',
    client = { export = 'dg_cocaine.useBrick' },
},
['cocaine_bag'] = {
    label = 'Bag of Cocaine',
    weight = 40,
    stack = true,
},
```

The seed and brick use `client.export`, so ox_inventory hands the use to this resource instead of removing the item itself. The server removes items only after it has validated the action.

Weights are in grams. With the defaults, one brick (1000) plus 25 baggies turns into 25 bags × 40 = 1000. Bagging gives everything back if the bags don't fit. Check the weight of your existing `baggies` item.

## Where the state lives

| What | Server truth | Clients see it through |
|---|---|---|
| Plants (owner, coords, planted/watered time, fertilised) | `Plants[id]` + MySQL `dg_cocaine_plants` | A `dg_cocaine:getPlants` snapshot on join, then `dg_cocaine:plantUpdated` / `plantRemoved` events |
| Seed NPC request | `Request` (re-rolled every `Config.SeedNpc.rotateMinutes`) | The `dg_cocaine:getRequest` callback when a player talks to the NPC |
| Cooldowns | Server only | None |

- Plant props, the NPC and the optional lab props are local entities.
- They spawn through `lib.points` only within `Config.RenderDistance` and are deleted when you leave, so big batches don't lag.
- Each plant has three growth stages and changes model as it grows.

## Server-side validation

Every action is a `lib.callback`, and the server checks it before anything changes:

- **Plant:** the player has a seed, is near the spot, and the spot is inside a planting zone. The server also checks the per-player limit and that the spot isn't too close to another plant. A lock stops two plant requests from the same player passing the limit at once.
- **Water, fertilise:** the plant exists and is in the right state, the player is near it, and the player has the item.
- **Harvest:** the plant has grown by **server** time and the player is near it. The plant is removed from memory before the reward is given, so it can't be harvested twice.
- **Trade:** the request is still the current one, the player is near the NPC and has the items, and the seeds fit in the inventory.
- **Craft and bag:** the player is near the station (crafting only) and has the inputs, and the outputs fit. The inputs are removed before the outputs are added, and given back if something fails.
- **Cooldowns:** each action can only succeed once per its progress bar duration (minus 10%) per player.

Limitation: the cooldown caps how often an action can succeed. It doesn't prove that the progress bar was shown for the first action.

## Bag yield

`GetBagYield(src)` at the top of the helpers in `server.lua` returns `Config.Bagging.bagsPerBrick`. Replace that function when the skill system exists. The baggies used always equal the yield.
