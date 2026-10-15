--[[
    dg_cocaine - config.lua (shared: loaded by client AND server)

    Every tunable value lives here. Nothing gameplay-related is hardcoded in client.lua/server.lua.

    !! COORDINATES, PROP/PED MODELS AND THE TRADE ITEM POOL BELOW ARE PLACEHOLDERS !!
    Stand at each spot in-game and copy your real coords. Trade items that don't exist in
    ox_inventory are skipped with a console warning when the resource starts.
]]

Config = {}

Config.Debug = false -- true: ox_target zone outlines at the lab

-- Item names (ox_inventory) -------------------------------------------------------------------
Config.Items = {
    seed       = 'coke_seed',
    leaf       = 'coca_leaf',
    paste      = 'coca_paste',
    raw        = 'cocaine_raw',
    cut        = 'cocaine_cut',
    brick      = 'cocaine_brick',
    bag        = 'cocaine_bag',
    gasoline   = 'gasoline',
    procaine   = 'procaine',
    bakingSoda = 'baking_soda',
    scales     = 'scales',
    baggies    = 'baggies',
    fertiliser = 'fertcoke', -- placeholder: the weed script's fertiliser item
    water      = 'water',    -- item used up when watering a plant; nil = watering needs no item
}

-- Streaming / interaction ------------------------------------------------------------------
Config.RenderDistance    = 60.0 -- plant props (and the seed NPC) only exist on a client inside this range
Config.InteractDistance  = 2.0  -- ox_target option distance
Config.ServerDistance    = 5.0  -- server: max distance between the player and the plant/NPC/station they act on

-- 1. Seed NPC ----------------------------------------------------------------------------------
-- The NPC asks everyone for the same thing; the request changes every rotateMinutes.
Config.SeedNpc = {
    model         = `a_m_m_hillbilly_01`,
    coords        = vec4(1702.0, 4917.0, 42.1, 55.0), -- placeholder
    rotateMinutes = 30,
    duration      = 3000, -- ms progress bar for the hand-over
    -- item = what he wants, amount = how many he asks for, seeds = how many he gives
    pool = { -- placeholder item names: replace with junk/material items that exist on your server
        { item = 'scrapmetal', amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'plastic',    amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'rubber',     amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'glass',      amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'copper',     amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'aluminum',   amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'iron',       amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'steel',      amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'cloth',      amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
        { item = 'garbage',    amount = { min = 1, max = 3 }, seeds = { min = 1, max = 3 } },
    },
}

-- 2. Plants --------------------------------------------------------------------------------------
Config.Plants = {
    growTime       = 3 * 60 * 60, -- seconds from watering to harvestable
    maxPerPlayer   = 30,          -- active plants per planter (ESX identifier)
    minSpacing     = 1.0,         -- metres between plants
    plantDuration  = 4000,        -- ms progress bars
    waterDuration  = 3000,
    fertDuration   = 3000,
    harvestDuration = 5000,
    leaves         = { min = 3, max = 5 }, -- coca leaves per harvest
    fertBonus      = { min = 2, max = 3 }, -- extra leaves if fertilised
    -- Growth stages, by growth progress (0.0 = just watered or not watered yet, 1.0 = ready).
    -- Placeholder models (weed props from the Bikers DLC): swap for your own.
    stages = {
        { from = 0.0, model = `bkr_prop_weed_01_small_01c` },
        { from = 0.5, model = `bkr_prop_weed_med_01a` },
        { from = 1.0, model = `bkr_prop_weed_lrg_01a` },
    },
}

-- Seeds can only be planted inside one of these circles (2D: x/y + radius). Placeholders.
Config.PlantZones = {
    { name = 'Cayo Perico',    coords = vec2(4900.0, -5150.0), radius = 1200.0 },
    { name = 'Island (north)', coords = vec2(5600.0, -5900.0), radius = 150.0 },
    { name = 'Island (east)',  coords = vec2(5850.0, -5250.0), radius = 150.0 },
}

-- 3. Lab (no blip: players have to find it) ----------------------------------------------------
-- Each station is an ox_target sphere zone. Set model to also spawn a local prop there (nil = zone only,
-- e.g. when the map already has a table/press at that spot).
Config.Lab = {
    mixer = { label = 'Mixer', coords = vec3(1093.0, -3196.0, -39.0), heading = 0.0, radius = 1.0, model = nil },
    press = { label = 'Press', coords = vec3(1097.0, -3196.0, -39.0), heading = 0.0, radius = 1.0, model = nil },
}

-- One ox_target option per recipe on its station. Inputs are removed and outputs given server-side.
Config.Recipes = {
    {
        station = 'mixer', label = 'Make coca paste', icon = 'fa-solid fa-flask', duration = 8000,
        inputs  = { { item = Config.Items.leaf, count = 10 }, { item = Config.Items.gasoline, count = 1 } },
        outputs = { { item = Config.Items.paste, count = 1 } },
    },
    {
        station = 'mixer', label = 'Make raw cocaine', icon = 'fa-solid fa-flask', duration = 8000,
        inputs  = { { item = Config.Items.paste, count = 1 }, { item = Config.Items.procaine, count = 1 } },
        outputs = { { item = Config.Items.raw, count = 1 } },
    },
    {
        station = 'mixer', label = 'Cut cocaine', icon = 'fa-solid fa-flask', duration = 8000,
        inputs  = { { item = Config.Items.raw, count = 1 }, { item = Config.Items.bakingSoda, count = 1 } },
        outputs = { { item = Config.Items.cut, count = 1 } },
    },
    {
        station = 'press', label = 'Press a brick', icon = 'fa-solid fa-cube', duration = 10000,
        inputs  = { { item = Config.Items.cut, count = 5 } },
        outputs = { { item = Config.Items.brick, count = 1 } },
    },
}

-- 4. Bagging (use a brick from the inventory) ----------------------------------------------------
Config.Bagging = {
    bagsPerBrick = 25,   -- also the number of baggies used. A skill system can replace GetBagYield in server.lua.
    duration     = 15000,
}

-- Progress bar animations (ox_lib anim: scenario or dict/clip)
Config.Anims = {
    plant   = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    water   = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    fert    = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    harvest = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    craft   = { scenario = 'PROP_HUMAN_PARKING_METER' },
    bag     = { scenario = 'PROP_HUMAN_PARKING_METER' },
    trade   = { dict = 'mp_common', clip = 'givetake1_a' },
}
