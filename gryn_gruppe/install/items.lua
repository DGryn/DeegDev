-- Add these entries to ox_inventory/data/items.lua (inside the returned table).
-- Images: put g6_thermite.png, g6_moneybag.png and g6_crate.png (100x100 recommended)
-- in ox_inventory/web/images/. black_money is ox_inventory's default dirty cash item.

['g6_thermite'] = {
    label = 'Thermite Charge',
    weight = 1000,
    stack = true,
    close = true,
    description = 'Burns through a Stockade door lock.',
},
['g6_moneybag'] = {
    label = 'G6 Money Bag',
    weight = 2500,
    stack = false,
    close = true,
    description = 'A sealed Gruppe 6 cash bag. Might be dye-packed.',
    client = { export = 'gryn_gruppe.openStolen' },
},
['g6_crate'] = {
    label = 'G6 Crate',
    weight = 8000,
    stack = false,
    close = true,
    description = 'A locked private crate from a Gruppe 6 run.',
    client = { export = 'gryn_gruppe.openStolen' },
},
