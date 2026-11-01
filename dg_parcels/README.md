# dg_parcels

House parcels for ESX Legacy (ox_lib, ox_inventory, ox_target). No database.

Parcels spawn on doorsteps. Grab one with ox_target ("Grab"), carry 1-2 at a time, store them anywhere ox_inventory allows, and use one from the inventory with a sharp tool to cut it open. Bigger parcels have better loot. Some are trapped: green smoke at the spot and a police alert.

## Install

1. Copy `dg_parcels/` into your resources folder. Keep the folder name `dg_parcels` (the item exports point at it).
2. Paste the items below into `ox_inventory/data/items.lua`. Optional: add `parcel_small.png`, `parcel_medium.png`, `parcel_large.png` to `ox_inventory/web/images/`.
3. In `server.cfg`, after `es_extended`, `ox_lib`, `ox_inventory` and `ox_target`: `ensure dg_parcels`
4. Restart the server (ox_inventory only reads items.lua at start).
5. Walk to each spot in `config.lua`, fix it with `/parcelcoord` (admins only), delete the bad ones.

## ox_inventory items

```lua
['parcel_small'] = {
    label = 'Small Parcel',
    weight = 11000,
    stack = false,
    close = true,
    description = 'Somebody is still waiting for this.',
    client = { export = 'dg_parcels.openParcel' },
},
['parcel_medium'] = {
    label = 'Medium Parcel',
    weight = 13500,
    stack = false,
    close = true,
    description = 'Somebody is still waiting for this.',
    client = { export = 'dg_parcels.openParcel' },
},
['parcel_large'] = {
    label = 'Large Parcel',
    weight = 18000,
    stack = false,
    close = true,
    description = 'Heavy. Somebody is still waiting for this.',
    client = { export = 'dg_parcels.openParcel' },
},
```

### Weight maths (default `inventory:weight` = 30000 g)

- Two of a size must fit: weight ≤ 30000 / 2 = **15000**.
- Three must not fit: weight > 30000 / 3 = **10000**.
- So small and medium sit between 10000 and 15000 (11000, 13500): max 2.
- Large is above 15000 (18000): max 1. One large plus one small is 29000 and only fits with near-empty pockets.

If you change `inventory:weight`, keep small/medium between limit/3 and limit/2, and large above limit/2. Change the numbers in items.lua only; the script reads item weights from ox_inventory.

### Trunks, gloveboxes, stashes

Normal ox_inventory behaviour, no custom code. How many parcels fit in a car is set in `ox_inventory/data/vehicles.lua`: the `trunk` and `glovebox` tables (`[vehicle class] = { slots, maxWeight }`), plus per-model overrides in `models`. Stashes use their own `weight`/`slots` in `data/stashes.lua`.

## Notes

- Loot fits check happens while the parcel is still in the inventory (conservative). If it doesn't fit, nothing is removed.
- Loot is rolled once per player per size and kept until it's handed out, so cancelling or filling pockets can't re-roll it.
- Police: replace the body of `SendPoliceAlert` at the top of `server/main.lua` to use your own dispatch.
