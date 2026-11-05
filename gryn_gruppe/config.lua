--[[
    gryn_gruppe - config.lua (shared: loaded by client AND server)

    Every tunable value lives here. Nothing gameplay-related is hardcoded in the scripts.

    !! COORDINATES BELOW ARE PLACEHOLDERS !!
    Stand at each spot in-game and copy your real coords (bank counters, ATMs, crate pickups,
    drop-offs, HQ). Bank and ATM entries are rough positions of the vanilla Fleeca banks and
    ATMs; check every one before going live.
]]

Config = {}

Config.Debug = false -- true: ox_target zone outlines + extra console prints

-- Police ---------------------------------------------------------------------------------------
Config.PoliceJobs = { 'police' } -- ESX job names counted as police
Config.MinPolice  = 2            -- police online needed to use thermite on a van

-- Distances --------------------------------------------------------------------------------------
Config.InteractDistance = 2.0  -- ox_target option distance
Config.ServerDistance   = 6.0  -- server: max distance between the player and the bank / ATM / van / NPC for an action
Config.InviteDistance   = 20.0 -- leader sees players within this range in the invite list
Config.RenderDistance   = 80.0 -- clients spawn the drop-off NPC inside this range

-- HQ (tablet NPC, van spawn, return point, Task 2 hand-in) ---------------------------------------
Config.HQ = {
    npc = {
        model    = `s_m_m_armoured_01`,
        coords   = vec4(-4.42, -654.18, 33.45, 184.0),
        scenario = 'WORLD_HUMAN_CLIPBOARD',
    },
    blip         = { sprite = 67, colour = 27, scale = 0.8, label = 'Gruppe 6' },
    vehicleSpawn = vec4(-4.62, -670.31, 31.94, 186.0), -- the Stockade spawns here
    returnPoint  = vec3(-4.62, -670.31, 31.94),        -- park the Stockade within returnRadius to finish
    returnRadius = 12.0,
    handIn       = vec3(-1.8, -657.4, 33.45),           -- Task 2: carry bags here from the van
}

-- Vehicles ---------------------------------------------------------------------------------------
-- `level` is NOT set here: which level unlocks a vehicle comes from Config.Unlocks below.
Config.Vehicles = {
    stockade = { label = 'Stockade', model = `stockade`, platePrefix = 'G6' },
}
Config.DefaultVehicle      = 'stockade'
Config.VanDestroyedEngine  = -3000.0 -- server: engine health at or below this counts as destroyed
Config.VanCheckInterval    = 2000    -- ms between server checks on each job van

-- Money ------------------------------------------------------------------------------------------
Config.DepositAccount = 'bank'  -- ESX account the deposit is taken from (and refunded to)
Config.PayAccount     = 'bank'  -- ESX account the payout goes to
Config.GroupBonus     = 10      -- % added to the total per extra group member, before the split
Config.MaxGroupSize   = 4       -- leader + 3
Config.InviteTimeout  = 60      -- seconds an invite stays valid

-- Difficulty: deposit (paid by the leader at start, refunded on completion) and pay multiplier.
Config.Difficulty = {
    easy   = { label = 'Easy',   deposit = 2500,  multiplier = 1.0 },
    medium = { label = 'Medium', deposit = 5000,  multiplier = 1.25 },
    hard   = { label = 'Hard',   deposit = 10000, multiplier = 1.5 },
}

-- Cooldown ---------------------------------------------------------------------------------------
Config.Cooldown = 40 -- minutes per player, starting when a job ends (success or failure). Level unlocks can reduce it.

-- Tasks ------------------------------------------------------------------------------------------
-- Pay = items x ratePerItem x difficulty multiplier, then group, level and reputation bonuses.
-- XP  = items x xpPerItem  x difficulty multiplier, then group and level bonuses.
-- `level` is NOT set here: which level unlocks a task comes from Config.Unlocks below.
Config.TaskOrder = { 'atm', 'multibank', 'crate' } -- order of the cards in the tablet
Config.Tasks = {
    atm = {
        label       = 'Bank pickup & ATM run',
        description = 'Collect money bags from one bank, then refill an ATM with each bag.',
        difficulty  = 'easy',
        ratePerItem = 650,
        xpPerItem   = 60,
        rep         = 1,                 -- reputation gained per completed job
        bags        = { base = 3, perExtraMember = 1, max = 6 }, -- solo 3, two 4, three 5, four 6
    },
    multibank = {
        label       = 'Multi-bank collection',
        description = 'Clear several banks in any order and bring every bag back to HQ.',
        difficulty  = 'medium',
        ratePerItem = 700,
        xpPerItem   = 70,
        rep         = 2,
        banks       = { min = 3, max = 5 },
        bagsPerBank = 1,
    },
    crate = {
        label       = 'Private crate delivery',
        description = 'Secure crates from private pickups and hand them to a waiting client.',
        difficulty  = 'hard',
        ratePerItem = 1400,
        xpPerItem   = 120,
        rep         = 3,
        pickups     = { min = 3, max = 5 }, -- one crate at each
        timeLimit   = 30,                   -- minutes, counted from the moment the job starts
    },
}

-- Locations --------------------------------------------------------------------------------------
Config.Banks = { -- bag pickup point inside each bank (stand at the counter)
    { label = 'Fleeca Legion Square',  coords = vec3(149.46, -1042.07, 29.37) },
    { label = 'Fleeca Hawick Ave',     coords = vec3(313.84, -280.28, 54.16) },
    { label = 'Fleeca Burton',         coords = vec3(-351.32, -51.21, 49.04) },
    { label = 'Fleeca Rockford Hills', coords = vec3(-1212.04, -332.05, 37.78) },
    { label = 'Fleeca Great Ocean',    coords = vec3(-2961.12, 483.01, 15.70) },
    { label = 'Fleeca Route 68',       coords = vec3(1175.69, 2708.03, 38.09) },
}

Config.ATMs = {
    vec3(147.66, -1035.71, 29.34),
    vec3(-846.27, -341.28, 38.68),
    vec3(-1205.02, -326.32, 37.84),
    vec3(1153.65, -326.78, 69.21),
    vec3(289.04, -1256.83, 29.44),
    vec3(-56.93, -1752.15, 29.42),
    vec3(33.19, -1348.21, 29.50),
    vec3(-717.62, -915.71, 19.22),
    vec3(380.79, 323.42, 103.57),
    vec3(2558.85, 351.05, 108.62),
}

Config.CratePickups = {
    { label = 'Elysian Island warehouse', coords = vec3(1197.29, -3253.61, 7.10) },
    { label = 'La Mesa storage',          coords = vec3(858.47, -2363.32, 30.35) },
    { label = 'Cypress Flats yard',       coords = vec3(963.52, -1856.09, 31.20) },
    { label = 'Vinewood private lot',     coords = vec3(-176.21, 499.44, 137.65) },
    { label = 'Del Perro offices',        coords = vec3(-1561.29, -583.58, 34.29) },
    { label = 'Mirror Park garage',       coords = vec3(1136.17, -775.15, 57.60) },
}

Config.CrateDropoffs = { -- an NPC waits at the chosen one
    { label = 'Sandy Shores airfield', coords = vec4(1714.21, 3290.42, 41.15, 190.0), model = `s_m_m_highsec_01` },
    { label = 'LSIA cargo',            coords = vec4(-1157.03, -2007.15, 13.18, 315.0), model = `s_m_m_highsec_01` },
    { label = 'Grapeseed farm',        coords = vec4(2556.81, 4680.63, 34.08, 20.0),  model = `s_m_m_highsec_02` },
}

-- Carrying ---------------------------------------------------------------------------------------
-- Props in hand and the inside-the-van props. Tweak offsets if a model sits wrong.
Config.Carry = {
    bag = {
        model = `prop_money_bag_01`,
        bone  = 57005, -- right hand
        offset = vec3(0.42, 0.0, -0.02), rot = vec3(0.0, -90.0, 90.0),
        anim = nil,    -- held in the hand, normal walk
    },
    crate = {
        model = `hei_prop_heist_box`,
        bone  = 60309, -- left hand
        offset = vec3(0.025, 0.08, 0.255), rot = vec3(-145.0, 290.0, 0.0),
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 },
    },
}

-- Positions (relative to the van) for props shown inside the Stockade, one per loaded item.
Config.VanProps = {
    vec3(-0.45, -1.2, 0.35), vec3(0.45, -1.2, 0.35),
    vec3(-0.45, -1.7, 0.35), vec3(0.45, -1.7, 0.35),
    vec3(-0.45, -2.2, 0.35), vec3(0.45, -2.2, 0.35),
    vec3(-0.45, -0.7, 0.35), vec3(0.45, -0.7, 0.35),
}
Config.VanRearOffset = vec3(0.0, -3.8, 0.0) -- point behind the van where load / take / thermite options show
Config.VanRearRange  = 2.0                  -- client: how close to that point the player must stand

-- ox_lib progress bars (ms) ---------------------------------------------------------------------
Config.Progress = {
    takeAtSite = 3500, -- bank counter / crate pickup
    loadVan    = 2500,
    takeFromVan = 2000,
    deliver    = 3500, -- ATM, HQ hand-in, drop-off NPC
    openStolen = 8000,
    takeLoot   = 2500,
}

-- Levels -----------------------------------------------------------------------------------------
-- XP needed to go from level n to n + 1 = floor(base * growth ^ (n - 1)).
Config.Levels = { max = 25, base = 500, growth = 1.2 }

-- Unlock table: the single source for everything a level gives. The tablet's Progress page is
-- built from this. Each entry may set:
--   tasks             task keys from Config.Tasks that become available
--   vehicles          vehicle keys from Config.Vehicles
--   moneyBonus        % (replaces the previous level's value, no stacking, no cap)
--   xpBonus           % (replaces the previous level's value)
--   cooldownReduction minutes (replaces the previous level's value)
--   items             black market item names that become buyable at this level
-- Placeholder values: tune freely.
Config.Unlocks = {
    [1]  = { tasks = { 'atm' }, vehicles = { 'stockade' }, moneyBonus = 0, xpBonus = 0, cooldownReduction = 0 },
    [3]  = { moneyBonus = 2, xpBonus = 2 },
    [5]  = { tasks = { 'multibank' }, moneyBonus = 5, xpBonus = 5, cooldownReduction = 5 },
    [8]  = { moneyBonus = 7, xpBonus = 7 },
    [10] = { tasks = { 'crate' }, moneyBonus = 10, xpBonus = 10, cooldownReduction = 10 },
    [15] = { moneyBonus = 15, xpBonus = 15 },
    [20] = { moneyBonus = 20, xpBonus = 20, cooldownReduction = 12 },
    [25] = { moneyBonus = 25, xpBonus = 25, cooldownReduction = 15 },
}

-- Reputation: rises with each completed job (Config.Tasks[x].rep), gives a payout bonus per tier.
Config.Reputation = { tierSize = 10, bonusPerTier = 1 } -- +1% pay for every 10 rep

-- Daily reward: one claim per 24 hours. "Today" stats reset on the same 24-hour cycle.
Config.Daily = { money = 2500, xp = 250 }

-- Items ------------------------------------------------------------------------------------------
Config.Items = {
    thermite = 'g6_thermite',
    moneybag = 'g6_moneybag',
    crate    = 'g6_crate',
    dirty    = 'black_money', -- ox_inventory item used for dirty cash
}

-- Robbery ----------------------------------------------------------------------------------------
Config.Robbery = {
    cooldown       = 25,   -- minutes per thief before they can use thermite again
    burnDamage     = 0,    -- health taken from the thief on a failed minigame (0 = none)
    vanCleanup     = 600,  -- seconds a robbed van stays before it is deleted
    lootValue = {          -- cash value stored in a stolen item's metadata
        bag   = { min = 2500, max = 4000 },
        crate = { min = 6000, max = 9000 },
    },
    minigame = {
        grid      = 6,     -- 6 x 6 cells
        cells     = 8,     -- cells to remember
        showTime  = 3000,  -- ms the pattern is shown
        timeLimit = 15000, -- ms to click them back
        mistakes  = 2,     -- wrong clicks allowed
    },
    maxAttemptTime = 60,   -- seconds: a minigame result arriving later than this is rejected
}

-- Black market -----------------------------------------------------------------------------------
Config.BlackMarket = {
    npc = {
        model    = `g_m_m_chicold_01`,
        coords   = vec4(723.43, -1066.89, 28.31, 90.0),
        scenario = 'WORLD_HUMAN_SMOKING',
    },
    -- currency: 'clean' (ESX cash) or 'dirty' (black_money item). rep: optional G6 reputation needed.
    -- A level requirement for an item comes from Config.Unlocks (its `items` list), if it is listed there.
    shop = {
        { item = 'g6_thermite', label = 'Thermite charge', price = 15000, currency = 'dirty', rep = 0 },
    },
    sellPercent = 70,   -- NPC pays this % of a stolen item's stored value, in clean cash
    openPercent = 130,  -- opening it yourself pays this % of the value, in dirty cash
    inkChance   = 25,   -- % chance an opened bag is inked and the money destroyed (20-30 suggested)
}

-- Logging (both off by default) ------------------------------------------------------------------
Config.Logging = {
    console = false,
    webhook = '', -- Discord webhook URL, '' = off
}
