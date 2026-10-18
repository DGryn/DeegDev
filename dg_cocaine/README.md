# dg_cocaine

A cocaine loop for ESX Legacy, built on ox_lib, ox_inventory, ox_target and oxmysql:

1. Trade junk with the seed NPC for coke seeds.
2. Plant the seeds on Cayo Perico or the small islands, then water them. Fertiliser is optional.
3. About 2 hours later (`Config.Plants.growTime`), harvest coca leaves. Plants are removed 3 days after planting (`Config.Plants.expireTime`), harvested or not. Anyone can harvest any plant.
4. At the hidden lab (enter through a door that needs a `cokelab_keycard`), the mixer turns leaves into paste, then raw cocaine, then cut cocaine. The press turns cut cocaine into bricks.
5. Use a brick from your inventory, with scales and 25 baggies, to bag it into 25 bags.

## Install

1. Copy `dg_cocaine/` into your resources folder.
2. Run `dg_cocaine.sql` on your database.
3. Add the items below to `ox_inventory/data/items.lua`.
4. Add `ensure dg_cocaine` to `server.cfg`, after `es_extended`, `oxmysql`, `ox_lib`, `ox_inventory` and `ox_target`.
5. Replace the placeholders in `config.lua`: the NPC, lab, lab entrance and planting-zone coordinates, the trade item pool, and the bush models.
6. The default lab coordinates are inside the Bikers DLC cocaine lab interior. That interior has to be loaded (for example with bob74_ipl). Or set `Config.LabEntrance.enabled = false` and put the stations wherever you want.

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
['cokelab_keycard'] = {
    label = 'Lab Keycard',
    weight = 10,
    stack = false,
    close = true,
    description = 'Opens a door somewhere.',
},
```

The seed and brick use `client.export`, so ox_inventory hands the use to this resource instead of removing the item itself. The server removes items only after it has validated the action.

Weights are in grams. With the defaults, one brick (1000) plus 25 baggies turns into 25 bags × 40 = 1000. Bagging gives everything back if the bags don't fit. Check the weight of your existing `baggies` item.

## Targeting

Every plant, the NPC, the lab door and the lab stations always show their options. Picking one you can't do yet tells you why, and no progress bar runs:

- "Not ready yet (45%)." / "It needs water before it can grow."

Each plant also has a growth line in its target menu: "Needs water", "Growth: 45%" or "Growth: 100% (ready)". Selecting it shows the same text as a notification. It never shows the time left.
- "You need 10x Coca Leaf (you have 4). You need 1x Gasoline (you have 0)."
- "The door is locked. You need 1x Lab Keycard (you have 0)."

The only options that are hidden are steps that can't be repeated: **Water** after a plant is watered, and **Fertilise** after it's fertilised. These hints come from the client. The server still checks everything again.

## Lab entrance

Decorative lab props live in `Config.LabProps`. Each entry has a model and a `vec4` position and heading. You can add as many as you like, or turn them all off with `enabled = false`. They're local objects that spawn together near `center`, with no interaction. The mixer and press can also each get their own prop through `Config.Lab.<station>.model`.

`Config.LabEntrance`:
- `enabled`: turns the door targets on or off.
- `requireKeycard`: turns the keycard check on or off. The server checks for the keycard, and the card is never used up.
- `outside` / `inside`: the two teleport points.

"Exit lab" inside needs no card. The mixer and press don't check for the card, so anyone already inside can use them.

## Where the state lives

| What | Server truth | Clients see it through |
|---|---|---|
| Plants (owner, coords, planted/watered time, fertilised) | `Plants[id]` + MySQL `dg_cocaine_plants` | A `dg_cocaine:getPlants` snapshot on join, then `dg_cocaine:plantUpdated` / `plantRemoved` events |
| Seed NPC request | `Request` (re-rolled every `Config.SeedNpc.rotateMinutes`) | The `dg_cocaine:getRequest` callback when a player talks to the NPC |
| Cooldowns | Server only | None |

- Plant props, the NPC and the optional lab props are local entities.
- They spawn through `lib.points` only within `Config.RenderDistance` and are deleted when you leave, so big batches don't lag.
- Each plant is one `h4_prop_bush_cocaplant_01` that grows from `scale.min` to `scale.max` as it grows (`Config.Plants`).

## Server-side validation

Every action is a `lib.callback`, and the server checks it before anything changes:

- **Plant:** the player has a seed, is near the spot, and the spot is inside a planting zone. The server also checks the per-player limit and that the spot isn't too close to another plant. A lock stops two plant requests from the same player passing the limit at once.
- **Water, fertilise:** the plant exists and is in the right state, the player is near it, and the player has the item.
- **Harvest:** the plant has grown by **server** time and the player is near it. The plant is removed from memory before the reward is given, so it can't be harvested twice.
- **Trade:** the request is still the current one, the player is near the NPC and has the items, and the seeds fit in the inventory.
- **Craft and bag:** the player is near the station (crafting only) and has the inputs, and the outputs fit. The inputs are removed before the outputs are added, and given back if something fails.
- **Cooldowns:** each action can only succeed once per its progress bar duration (minus 10%) per player.

Limitation: the cooldown caps how often an action can succeed. It doesn't prove that the progress bar was shown for the first action.

## Lab minigames

The four mixer and press recipes open an NUI minigame instead of a progress bar. A recipe's `minigame` field picks the game: `pour`, `sliders`, `grid` or `pressure`. Remove the field to bring back the progress bar. Settings for every game are in `Config.Minigames`.

How a craft works:

1. The player picks a station option. The server checks the items, the distance and the cooldown, then opens a session with a one-use token.
2. The client opens the NUI.
3. When the game ends, the score goes back with the token. The server rejects the result if any of these is true:
   - the token is missing, wrong or already used;
   - the session is older than `sessionTimeout`;
   - the result arrived sooner than the game's `minTime`;
   - the player is out of range.

   It then clamps the score to 0-100 and gets a multiplier from `GetYieldMultiplier(score, src)` in `server.lua`, which uses `Config.Minigames.tiers`.
4. The inputs are removed and the outputs are rolled. The fractional part of the multiplier is a chance of one extra, and every output is at least `minOutput`.
   - A score under `fail.below` wastes an extra `fail.extraLoss` of the inputs.
   - Cancelling (ESC, the close button or dying) gives nothing and loses `cancelLoss` of the inputs.

## Bag yield

`GetBagYield(src)` at the top of the helpers in `server.lua` returns `Config.Bagging.bagsPerBrick`. Replace that function when the skill system exists. The baggies used always equal the yield.
