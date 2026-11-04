--[[
    Paste these entries into ox_inventory/data/items.lua, inside the big `return { ... }` table,
    then restart the server (ox_inventory only reads items on start).

    The images reuse pictures that ship with ox_inventory (ox_inventory/web/images), so you don't
    need any new image files. Swap them for your own later if you like:
    put `myitem.png` in ox_inventory/web/images and change `image` to 'myitem.png' (or remove the
    `client` line - ox_inventory then looks for '<item name>.png').

    If you already have items with these names (for example 'plastic' or 'glass'), don't add them
    twice - just keep yours. Weights are in grams.
]]

['recycle_box'] = {
    label = 'Recycle Box',
    weight = 500,
    stack = true,
    close = true,
    description = 'A box of sorted recyclables. Trade it at the warehouse.',
    client = { image = 'paperbag.png' },
},

['plastic'] = {
    label = 'Plastic',
    weight = 100,
    stack = true,
    close = true,
    description = 'Recycled plastic.',
    client = { image = 'trash_can.png' },
},

['glass'] = {
    label = 'Glass',
    weight = 150,
    stack = true,
    close = true,
    description = 'Recycled glass.',
    client = { image = 'trash.png' },
},

['aluminum'] = {
    label = 'Aluminum',
    weight = 100,
    stack = true,
    close = true,
    description = 'Recycled aluminum.',
    client = { image = 'scrapmetal.png' },
},

['copper'] = {
    label = 'Copper',
    weight = 150,
    stack = true,
    close = true,
    description = 'Recycled copper.',
    client = { image = 'scrapmetal.png' },
},
