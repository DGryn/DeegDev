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
    keycard    = 'cokelab_keycard', -- lab entrance (see Config.LabEntrance)
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
    growTime       = 1 * 60 * 60, -- seconds from watering to harvestable
    maxPerPlayer   = 30,          -- active plants per planter (ESX identifier)
    minSpacing     = 1.0,         -- metres between plants
    plantDuration  = 4000,        -- ms progress bars
    waterDuration  = 3000,
    fertDuration   = 3000,
    harvestDuration = 5000,
    leaves         = { min = 3, max = 5 }, -- coca leaves per harvest
    fertBonus      = { min = 2, max = 3 }, -- extra leaves if fertilised
    -- Growth stages, by growth progress (0.0 = just watered or not watered yet, 1.0 = ready).
    -- Props can't be scaled, so the plant swaps model: small bush -> medium bush -> large bush.
    -- !! UNVERIFIED stock bush models: check them in a prop browser and swap if needed. !!
    -- zOffset (metres) sinks the model into the ground; negative = lower. A stage can override it.
    zOffset = -0.3,
    stages = {
        { from = 0.0, model = `prop_bush_med_01` },
        { from = 0.5, model = `prop_bush_med_03` },
        { from = 1.0, model = `prop_bush_lrg_04b`, zOffset = -0.5 },
    },
}

-- Seeds can only be planted inside one of these circles (2D: x/y + radius). Placeholders.
Config.PlantZones = {
    { name = 'Cayo Perico',    coords = vec2(4900.0, -5150.0), radius = 1200.0 },
    { name = 'Island (north)', coords = vec2(5600.0, -5900.0), radius = 150.0 },
    { name = 'Island (east)',  coords = vec2(5850.0, -5250.0), radius = 150.0 },
    { name = 'TEST PLACE',  coords = vec2(345.0169, 3607.8430), radius = 500.0 },
}

-- 3. Lab (no blip: players have to find it) ----------------------------------------------------

-- Entrance: 'Enter lab' at the outside door teleports you inside, 'Exit lab' inside teleports you back.
-- Placeholder coords: the inside point is the Bikers DLC cocaine lab interior (needs the interior loaded, e.g. bob74_ipl).
Config.LabEntrance = {
    enabled        = true,  -- false: no entrance targets (use this if your lab is not an interior)
    requireKeycard = true,  -- false: anyone can enter. The keycard is never used up.
    outside = vec4(387.5107, 3584.6167, 33.2922, 349.2986),     -- door target + where 'Exit lab' puts you
    inside  = vec4(1088.7, -3187.6, -38.99, 180.0), -- where 'Enter lab' puts you + exit target
    radius  = 1.0,
}

-- Each station is an ox_target sphere zone. Set model to also spawn a local prop there (nil = zone only,
-- e.g. when the map already has a table/press at that spot).
Config.Lab = {
    mixer = { label = 'Mixer', coords = vec3(1093.0, -3196.0, -39.0), heading = 0.0, radius = 1.0, model = nil },
    press = { label = 'Press', coords = vec3(1102.0404, -3196.2, -38.9935), heading = 0.0, radius = 1.0, model = nil },
}

-- Decorative props inside the lab (local objects, no interaction). Spawned together while a player is within
-- Config.RenderDistance of `center`. Add, remove or move entries freely; a prop that doesn't exist prints a
-- warning in F8 and is skipped. !! Models are UNVERIFIED Bikers DLC coke-lab props and coords are placeholders. !!
-- Tip: if you load the interior with bob74_ipl, its entity sets can already furnish the lab.
Config.LabProps = {
    enabled = true,
    center  = vec3(1095.0, -3196.0, -39.0),
    list = {
        { model = `bkr_prop_coke_table01a`,    coords = vec4(1101.9429, -3194.5933, -39.9934, 90.3500) },
        { model = `bkr_prop_coke_block_01a`,   coords = vec4(1101.9133, -3195.0569, -39.9935, 333.8120) },
        { model = `bkr_prop_coke_block_01a`,   coords = vec4(1101.9133, -3194.0569, -39.9935, 200.8120) },
        { model = `bkr_prop_coke_press_01aa`,   coords = vec4(1101.9513, -3196.3477, -39.05, 90) },
        { model = `h4_prop_h4_table_isl_01a`,   coords = vec4(1101.9513, -3196.9, -39.9934, 90) },
        { model = `bkr_prop_coke_cutblock_01`, coords = vec4(1101.9513, -3196.3477, -38.78, 90) },
        { model = `bkr_prop_coke_block_01a`,   coords = vec4(1101.9513, -3197.3477, -39.05, 90) },

    },
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

-- Progress bar animations (ox_lib anim: scenario or dict/clip/flag). An optional `prop` is held during the
-- bar (ox_lib progress prop: model, bone, pos, rot). Water/fert anims and the can offsets are UNVERIFIED: tweak in-game.
Config.Anims = {
    plant   = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    water   = {
        dict = 'weapon@w_sp_jerrycan', clip = 'fire', flag = 49, -- pouring, upper body only
        prop = { model = `prop_wateringcan`, bone = 28422, pos = vec3(0.4, 0.1, 0), rot = vec3(90.0, 180.0, 0.0) },
    },
    fert    = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 }, -- kneeling, full body
    harvest = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    craft   = { scenario = 'PROP_HUMAN_PARKING_METER' },
    bag     = { scenario = 'PROP_HUMAN_PARKING_METER' },
    trade   = { dict = 'mp_common', clip = 'givetake1_a' },
}
