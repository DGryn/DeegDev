--[[
    dg_lumberjack - config.lua (shared: loaded by client AND server)

    Every tunable value lives here. Nothing gameplay-related is hardcoded in client.lua/server.lua.

    !! COORDINATES AND PROP MODELS BELOW ARE PLACEHOLDERS !!
    Stand at each spot in-game and copy your real coords, and check every prop model in a
    prop browser (e.g. https://forge.plebmasters.de/objects). An invalid model is skipped with a
    console warning instead of crashing, but nothing will show up for it.
]]

Config = {}

Config.Debug = false            -- true: ox_target zone outlines + /ljpoints command to tune truck attachment points

-- Restrict to an ESX job name (e.g. 'lumberjack'), or nil = open to every civilian.
Config.Job = nil

-- Streaming / interaction ------------------------------------------------------------------
Config.RenderDistance    = 120.0 -- clients spawn/delete local props (trees, ground items, truck loads) inside this range
Config.InteractDistance  = 2.5   -- ox_target option distance
Config.DistanceTolerance = 1.5   -- extra slack on server-side distance checks (latency / ped vs prop origin)
Config.MaxHeightDelta    = 15.0  -- server distance checks are horizontal; this caps the vertical difference
Config.TruckRange        = 8.0   -- max distance between a ground item and the truck it is loaded onto
Config.GroundItemLifetime = 1800 -- seconds before an untouched ground log/plank is removed (0 = never)

-- Hatchet (ox_inventory weapon item) --------------------------------------------------------
Config.HatchetItem = 'WEAPON_HATCHET' -- ox_inventory item name (server check)
Config.HatchetHash = `WEAPON_HATCHET` -- weapon hash (client check: must be equipped to see the Chop option)

-- Chopping -----------------------------------------------------------------------------------
Config.Chop = {
    duration    = 4000,   -- ms progress bar per chop attempt
    maxDistance = 4.0,    -- server: max horizontal distance from tree base while chopping
    minFraction = 0.9,    -- server: finish is rejected if it arrives sooner than duration * minFraction
    maxExtra    = 20000,  -- server: ms allowed after duration for the skill check before the attempt expires
    anim = { dict = 'melee@hatchet@streamed_core', clip = 'plyr_rear_takedown_b' },
}

-- ox_lib skill check. difficulty may be 'easy'|'medium'|'hard', { areaSize = 50, speedMultiplier = 1 },
-- or an array of either (one stage per entry). All stages must pass for the chop to yield a log.
-- https://coxdocs.dev/ox_lib/Modules/Interface/Client/skillcheck
Config.SkillCheck = {
    difficulty = { 'easy', 'easy', 'medium' },
    inputs     = { 'e' },
}

-- Trees --------------------------------------------------------------------------------------
Config.Trees = {
    model         = `prop_tree_pine_01`,   -- default standing tree (per-tree override: model = `...`)
    stumpModel    = `prop_tree_stump_01`,
    chopsPerTree  = 5,                     -- attempts (pass OR fail) before the tree is felled
    respawnTime   = { min = 600, max = 1200 }, -- seconds, random in range
    snapToGround  = true,                  -- client snaps the prop to ground Z (so rough Z in coords is fine)
    fallDuration  = 2500,                  -- ms falling animation
    fallAngle     = 85.0,                  -- degrees of tilt; flip the sign to change fall direction
    lyingTime     = 4000,                  -- ms the felled trunk stays before it becomes the stump
    logDrop       = { min = 1.5, max = 3.0 }, -- ground log spawns this far from the tree base (random direction)
    list = {
        { coords = vec4(-576.0, 5470.0, 60.0, 0.0) },
        { coords = vec4(-584.0, 5462.0, 60.0, 90.0) },
        { coords = vec4(-592.0, 5475.0, 60.0, 45.0) },
        { coords = vec4(-566.0, 5482.0, 60.0, 180.0) },
        { coords = vec4(-600.0, 5488.0, 60.0, 270.0) },
    },
}

-- Physical items (NOT inventory items) -------------------------------------------------------
Config.Items = {
    log   = { label = 'log',   model = `prop_log_01`,     weight = 100 },
    plank = { label = 'planks', model = `prop_cons_plank`, weight = 40 },
}

-- Load / unload interaction ------------------------------------------------------------------
Config.Load = {
    duration = 1500,
    anim = { dict = 'pickup_object', clip = 'pickup_low' },
}

-- Trucks -------------------------------------------------------------------------------------
-- Keyed by spawn name. Each truck has:
--   maxWeight          hard weight limit across everything on the bed
--   log = { max, points }   slot pool for logs
--   plank = { max, points } separate slot pool for planks, OR plank = 'log' to share the log pool
--                           (same slots, same attachment points, same max)
-- points: offset (vec3, relative to vehicle origin) and rot (vec3, degrees) per slot.
-- Tune with Config.Debug = true and /ljpoints while sitting in the truck.
Config.Trucks = {
    bison = {
        label = 'Bison pickup',
        type = 'automobile',       -- CreateVehicleServerSetter type
        maxWeight = 250,
        log = {
            max = 2,
            points = {
                { offset = vec3(-0.35, -1.80, 0.45), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3( 0.35, -1.80, 0.45), rot = vec3(0.0, 0.0, 90.0) },
            },
        },
        plank = 'log',
    },
    flatbed = {
        label = 'Flatbed',
        type = 'automobile',
        maxWeight = 1000,
        log = {
            max = 6,
            points = {
                { offset = vec3(-0.45, -1.5, 0.95), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3( 0.45, -1.5, 0.95), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3(-0.45, -3.2, 0.95), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3( 0.45, -3.2, 0.95), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3( 0.00, -1.5, 1.45), rot = vec3(0.0, 0.0, 90.0) },
                { offset = vec3( 0.00, -3.2, 1.45), rot = vec3(0.0, 0.0, 90.0) },
            },
        },
        plank = {
            max = 8,
            points = {
                { offset = vec3(-0.5, -1.0, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3( 0.5, -1.0, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3(-0.5, -2.2, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3( 0.5, -2.2, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3(-0.5, -3.4, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3( 0.5, -3.4, 0.95), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3(-0.5, -1.0, 1.15), rot = vec3(0.0, 0.0, 0.0) },
                { offset = vec3( 0.5, -1.0, 1.15), rot = vec3(0.0, 0.0, 0.0) },
            },
        },
    },
}

-- Depot (inside the mill yard) ---------------------------------------------------------------
Config.Depot = {
    ped          = { model = `s_m_y_construct_01`, coords = vec4(-566.0, 5325.0, 73.6, 70.0) }, -- ped = nil → plain target zone
    zoneRadius   = 1.2,                                -- used only when ped = nil
    spawn        = vec4(-575.0, 5320.0, 70.3, 160.0),  -- truck spawn point
    returnRadius = 15.0,                               -- truck must be this close to spawn to be returned
    deleteOnDrop = true,                               -- delete a player's depot truck when they disconnect
    platePrefix  = 'LJ',
}

-- Lumber mill --------------------------------------------------------------------------------
Config.Mill = {
    input        = vec3(-552.0, 5330.0, 73.6), -- where logs are unloaded (player must be within radius)
    conveyorEnd  = vec3(-545.0, 5340.0, 73.6), -- visual only: log slides input → conveyorEnd
    conveyorHeading = 30.0,
    output       = vec4(-540.0, 5345.0, 73.6, 30.0), -- planks appear around here
    outputSpread = 1.5,
    radius       = 8.0,     -- player → input
    truckRadius  = 15.0,    -- truck → input
    processTime  = 20,      -- seconds per log
    planksPerLog = 3,
}

-- Delivery -----------------------------------------------------------------------------------
Config.Delivery = {
    coords = vec3(1200.0, -1300.0, 35.0),
    radius = 15.0,           -- player and truck must both be inside
}

-- Rewards (paid server-side, linear in quantity delivered) -----------------------------------
Config.Reward = {
    account    = 'money',    -- ESX account: 'money' | 'bank'
    perPlank   = 120,
    xpPerPlank = 2,
}

-- XP is stored in a JSON file inside this resource, keyed by ESX identifier.
Config.XP = {
    file = 'data/xp.json',
    saveInterval = 60,       -- seconds between flushes (also flushed on resource stop)
}

-- Map blips (set to nil to hide) -------------------------------------------------------------
Config.Blips = {
    { coords = vec3(-584.0, 5472.0, 60.0), sprite = 77,  color = 25, label = 'Lumberjack: Forest' },
    { coords = vec3(-552.0, 5330.0, 73.6), sprite = 478, color = 25, label = 'Lumberjack: Mill & Depot' },
    { coords = vec3(1200.0, -1300.0, 35.0), sprite = 478, color = 2,  label = 'Lumberjack: Delivery' },
}
