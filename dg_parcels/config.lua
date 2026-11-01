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
    vector4(-14.16, -1442.37, 31.10, 0.0),   -- Forum Dr / Grove St area
    vector4(-64.09, -1449.86, 32.52, 14.2), -- forum dr
    vector4(126.70, -1930.00, 21.40, 210.0),   -- Grove St
    vector4(85.40, -1959.20, 21.10, 320.0),    -- Grove St
    vector4(55.71, -1921.08, 21.63, 147.4), -- Grove St
    vector4(23.67, -1896.36, 22.96, 138.9), -- GST
    vector4(-33.26, -1847.39, 26.18, 90.7), -- gst
    vector4(491.68, -1715.21, 29.31, 65.2), -- James Town
    vector4(473.97, -1775.53, 28.69, 87.9), -- Jms T
    vector4(495.48, -1822.00, 28.86, 184.3), -- Jms t
    vector4(399.82, -1864.60, 26.70, 116.2), -- Jms T
    vector4(236.50, -1717.80, 29.30, 320.0),   -- Davis
    vector4(1273.90, -1719.70, 54.80, 30.0),   -- El Burro Heights
    vector4(1301.00, -573.90, 71.70, 340.0),   -- Mirror Park / Nikola Pl
    vector4(1060.50, -378.30, 68.20, 40.0),    -- Mirror Park
    vector4(1010.40, -423.40, 65.40, 130.0),   -- Mirror Park
    vector4(1302.67, -528.66, 71.45, 345.8), -- Nik
    vector4(1347.97, -547.60, 73.88, 343.0), -- nik
    vector4(1385.64, -592.89, 74.47, 235.3), -- Nikk

    -- Beach front
    vector4(-1968.22, -532.44, 12.16, 326.0), -- Beach Front
    vector4(-1849.40, -632.60, 11.15, 328.8), -- Beach Front
    vector4(-1814.53, -665.00, 10.78, 326.0), -- Beach Front
    vector4(-1791.74, -683.74, 10.63, 323.1), -- Beach Front
    vector4(-1753.58, -724.73, 10.34, 328.8), -- Beach Front


    -- Rural
    vector4(2176.06, 3320.61, 45.96, 28.3), -- Trailer
    vector4(2202.59, 3318.91, 46.11, 107.7), -- Trailer
    vector4(55.32, 3741.75, 39.68, 39.7), -- Stab City Trailer
    vector4(34.36, 3666.29, 39.71, 62.4), -- Stab city trailer

    vector4(1879.71, 3920.74, 33.19, 283.5), -- sandy

    vector4(1973.60, 3815.30, 33.40, 30.0),    -- Sandy Shores
    vector4(1435.60, 3657.30, 34.40, 200.0),   -- Sandy Shores
    vector4(70.00, 3700.00, 39.70, 60.0),      -- Stab City
    vector4(2449.90, 4970.00, 46.60, 45.0),    -- Grapeseed farm
    vector4(1680.00, 4700.00, 43.00, 90.0),    -- Grapeseed
    vector4(-374.00, 6190.00, 31.50, 225.0),   -- Paleto Bay
    vector4(-9.00, 6557.00, 31.90, 45.0),      -- Paleto Bay
}
