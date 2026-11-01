Config = {}

---------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------
Config.MaxActive      = 10                      -- max parcels in the world at once
Config.RespawnMinutes = { min = 20, max = 45 }  -- after a parcel is grabbed, that spot waits this long
Config.StreamDistance = 60.0                    -- clients only create the prop when this close (metres)
Config.GrabDistance   = 4.0                     -- server-side max distance between player and spot to grab
Config.RateLimitMs    = 750                     -- min time between two grab/open requests from one player

---------------------------------------------------------------------
-- Parcel sizes
-- item       : ox_inventory item name (must match data/items.lua)
-- model      : world prop (see "Things to verify")
-- chance     : relative chance this size is picked when a parcel spawns
-- openTime   : progress bar length in ms
-- trapChance : 0.0 - 1.0 chance the parcel is trapped (green smoke + police)
-- rolls      : how many times the loot table is rolled
---------------------------------------------------------------------
Config.Sizes = {
    small  = { item = 'parcel_small',  model = 'prop_cs_cardbox_01',   chance = 60, openTime = 3000, trapChance = 0.12, rolls = { min = 1, max = 1 } },
    medium = { item = 'parcel_medium', model = 'prop_cardbordbox_02a', chance = 30, openTime = 5000, trapChance = 0.15, rolls = { min = 1, max = 2 } },
    large  = { item = 'parcel_large',  model = 'prop_cardbordbox_04a', chance = 10, openTime = 8000, trapChance = 0.18, rolls = { min = 2, max = 3 } },
}

---------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------
-- Any ONE of these in the player's inventory lets them cut a parcel open (doesn't need to be equipped).
Config.SharpTools = {
    'WEAPON_KNIFE',
    'WEAPON_SWITCHBLADE',
    'WEAPON_DAGGER',
    'WEAPON_MACHETE',
    -- 'boxcutter', -- add your own item names here
}

-- Animation played during the progress bar (skipped when in a vehicle).
Config.OpenAnim = { dict = 'mini@repair', clip = 'fixing_a_ped' }

---------------------------------------------------------------------
-- Loot (rolled on the server only)
-- Each roll picks ONE entry, weighted by `weight`, and gives min-max of it.
-- Bigger parcels: more rolls and more weight on the valuable stuff.
---------------------------------------------------------------------
Config.Loot = {
    small = {
        { item = 'garbage',  min = 1,  max = 1,   weight = 25 },
        { item = 'paperbag', min = 1,  max = 1,   weight = 15 },
        { item = 'water',    min = 1,  max = 2,   weight = 20 },
        { item = 'burger',   min = 1,  max = 1,   weight = 15 },
        { item = 'bandage',  min = 1,  max = 2,   weight = 12 },
        { item = 'money',    min = 20, max = 80,  weight = 10 },
        { item = 'lockpick', min = 1,  max = 1,   weight = 3 },
    },
    medium = {
        { item = 'garbage',  min = 1,  max = 1,   weight = 10 },
        { item = 'water',    min = 1,  max = 3,   weight = 15 },
        { item = 'sprunk',   min = 1,  max = 3,   weight = 15 },
        { item = 'bandage',  min = 1,  max = 3,   weight = 15 },
        { item = 'money',    min = 50, max = 200, weight = 18 },
        { item = 'lockpick', min = 1,  max = 2,   weight = 10 },
        { item = 'radio',    min = 1,  max = 1,   weight = 8 },
        { item = 'phone',    min = 1,  max = 1,   weight = 6 },
        { item = 'armour',   min = 1,  max = 1,   weight = 3 },
    },
    large = {
        { item = 'bandage',  min = 2,   max = 4,   weight = 10 },
        { item = 'money',    min = 150, max = 500, weight = 25 },
        { item = 'lockpick', min = 1,   max = 3,   weight = 15 },
        { item = 'radio',    min = 1,   max = 1,   weight = 12 },
        { item = 'phone',    min = 1,   max = 1,   weight = 15 },
        { item = 'armour',   min = 1,   max = 1,   weight = 12 },
        { item = 'scrapmetal', min = 2, max = 6,   weight = 11 },
    },
}

---------------------------------------------------------------------
-- Trapped parcels
---------------------------------------------------------------------
Config.Trap = {
    SmokeDuration  = 50,       -- seconds the smoke stays
    SmokeDistance  = 250.0,    -- clients within this range see the smoke
    PlayerCooldown = 300,      -- seconds before the same player can trigger another trap
    GlobalCooldown = 60,       -- seconds before ANY player can trigger another trap
    Asset  = 'core',                -- particle asset (see "Things to verify")
    Effect = 'exp_grd_bzgas_smoke', -- looped smoke effect inside that asset
    Scale  = 1.5,
    Colour = { r = 0.0, g = 1.0, b = 0.0 }, -- 0.0 - 1.0 each
}

---------------------------------------------------------------------
-- Police alert (default, used by SendPoliceAlert in server/main.lua)
---------------------------------------------------------------------
Config.Police = {
    Jobs       = { 'police' }, -- ESX job names that receive the alert
    BlipTime   = 120,          -- seconds until the blip is removed
    BlipRadius = 60.0,         -- radius of the search area blip
    BlipSprite = 161,
    BlipColour = 2,            -- green
}

---------------------------------------------------------------------
-- /parcelcoord dev command: ESX groups allowed to use it
-- (players with the ace "command.parcelcoord" are also allowed)
---------------------------------------------------------------------
Config.AdminGroups = { admin = true, superadmin = true }

---------------------------------------------------------------------
-- Parcel spots: where the player stands on the doorstep, heading = facing.
-- !!! UNVERIFIED PLACEHOLDERS !!!
-- These are rough guesses, NOT checked in-game. Some will be off, in walls
-- or in the air. Walk to each one, fix it with /parcelcoord, delete bad ones.
-- Do not reorder the list while the resource is running (spots are tracked by index).
---------------------------------------------------------------------
Config.Locations = {
    -- City (south / east Los Santos)
    vector4(-14.60, -1441.60, 31.10, 180.0),   -- Forum Dr / Grove St area
    vector4(126.70, -1930.00, 21.40, 210.0),   -- Grove St
    vector4(85.40, -1959.20, 21.10, 320.0),    -- Grove St
    vector4(236.50, -1717.80, 29.30, 320.0),   -- Davis
    vector4(1273.90, -1719.70, 54.80, 30.0),   -- El Burro Heights
    vector4(1301.00, -573.90, 71.70, 340.0),   -- Mirror Park / Nikola Pl
    vector4(1060.50, -378.30, 68.20, 40.0),    -- Mirror Park
    vector4(1010.40, -423.40, 65.40, 130.0),   -- Mirror Park

    -- Suburbs / hills / west side
    vector4(-817.00, 178.00, 72.20, 110.0),    -- Rockford Hills
    vector4(7.80, 538.60, 176.00, 150.0),      -- Vinewood Hills
    vector4(-174.70, 502.60, 137.40, 190.0),   -- Vinewood Hills
    vector4(-1294.40, 454.60, 97.50, 0.0),     -- Richman
    vector4(-1150.00, -1520.00, 4.40, 35.0),   -- Vespucci Canals
    vector4(-1100.00, -1600.00, 4.40, 125.0),  -- Vespucci Beach
    vector4(-3093.80, 349.40, 7.50, 255.0),    -- Chumash / Banham Canyon

    -- Rural
    vector4(1973.60, 3815.30, 33.40, 30.0),    -- Sandy Shores
    vector4(1435.60, 3657.30, 34.40, 200.0),   -- Sandy Shores
    vector4(70.00, 3700.00, 39.70, 60.0),      -- Stab City
    vector4(2449.90, 4970.00, 46.60, 45.0),    -- Grapeseed farm
    vector4(1680.00, 4700.00, 43.00, 90.0),    -- Grapeseed
    vector4(-374.00, 6190.00, 31.50, 225.0),   -- Paleto Bay
    vector4(-9.00, 6557.00, 31.90, 45.0),      -- Paleto Bay
}
