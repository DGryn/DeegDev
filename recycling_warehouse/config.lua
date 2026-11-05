--[[
    recycling_warehouse - config.lua

    Everything you might want to change lives in this file. Both the client and the server load it,
    so the server uses the SAME coordinates for its anti-cheat distance checks.

    Coordinate types:
      vec3(x, y, z)           a position
      vec4(x, y, z, heading)  a position plus the direction to face (0-360)

    Values marked PLACEHOLDER are guesses. Player/ped positions (spawnInside, spawnOutside, the trader)
    should be copied while standing on the spot, which gives a Z about 1 m above the floor.
    Replace them with real ones you copy in-game (see README).
]]

Config = {}

-- Prints extra information to the server console (F8 on the client) while you set things up.
Config.Debug = false

-- Chat command that prints your current position + heading as a vec4 and copies it to your
-- clipboard, so you can paste it into this file. Set to false to disable the command.
Config.CoordsCommand = 'rwcoords'

------------------------------------------------------------------------------------------------
-- Interior
------------------------------------------------------------------------------------------------
Config.Interior = {
    -- GTA Online medium cargo warehouse.
    name = 'ex_exec_warehouse_placement_interior_0_int_warehouse_m_dlc_milo',
    reference = vec3(1056.486, -3105.724, -39.004),

    -- true  = this script makes sure the interior is loaded before the player arrives.
    -- false = turn it off if another resource (an IPL loader, for example) already manages this interior.
    loadInterior = true,

    -- Props, the trader and the outlines only exist while you are this close (in metres) to the
    -- reference point. Further away, the resource does nothing, which keeps idle usage near zero.
    streamDistance = 40.0,

    -- Max time (ms) to wait for the interior or the collision to load before fading back in anyway.
    loadTimeout = 5000,

    -- Screen fade duration (ms) when entering and leaving.
    fadeTime = 500,
}

------------------------------------------------------------------------------------------------
-- Entrance (outside) and exit (inside)
------------------------------------------------------------------------------------------------
Config.Entrance = {
    -- Where the player interacts OUTSIDE to go in. PLACEHOLDER: a spot in the docks area.
    coords = vec3(746.8029, -1399.3375, 26.6241),
    radius = 1.5,                                     -- size of the interaction zone
    -- Where the player appears INSIDE the warehouse.
    -- PLACEHOLDER: just inside the door, near the reference point.
    spawnInside = vec4(1048.4857, -3097.1399, -39.0000, 270),

    -- Map blip for the entrance. Set blip = false to hide it.
    blip = { sprite = 365, colour = 2, scale = 0.8 },
}

Config.Exit = {
    -- Where the player interacts INSIDE to leave. PLACEHOLDER: the warehouse door.
    coords = vec3(1048.20, -3097.20, -38.50),
    radius = 1.5,
    -- Where the player appears OUTSIDE after leaving. PLACEHOLDER: next to the entrance.
    spawnOutside = vec4(746.7480, -1399.7970, 26.5920, 183.3706),

    -- Leaving the warehouse ends the shift automatically (any carried box is dropped).
    endShiftOnExit = true,
}

------------------------------------------------------------------------------------------------
-- Laptop (sign in / sign out)
------------------------------------------------------------------------------------------------
Config.Laptop = {
    coords = vec4(1048.5372, -3100.7546, -39.1, 88.0837),
    radius = 0.8,

    -- The warehouse interior has a desk with a laptop on it, so this script normally only adds the
    -- interaction. If you see no laptop there, set spawnProp = true to place one at the coords.
    spawnProp = false,
    model = 'prop_laptop_01a',
}

------------------------------------------------------------------------------------------------
-- Pickup props (where boxes are collected)
-- Add as many as you like. Each one is a real prop with its own model and position.
-- The server picks ONE of them at a time for each player: only that one glows and only that one
-- can be used. After every delivery a different one is picked. They never run out.
------------------------------------------------------------------------------------------------
Config.Pickups = {
    -- PLACEHOLDER positions spread around the reference point. Replace them with your own.
    { model = 'prop_boxpile_06b',  coords = vec4(1052.9777, -3095.4482, -39.0000, 0) },
    { model = 'prop_boxpile_06b',  coords = vec4(1055.5084, -3095.4558, -39.0000, 2.5461) },
    { model = 'prop_cratepile_07a',  coords = vec4(1057.9218, -3095.4487, -39.0000, 359.4731) },
    { model = 'xm3_prop_xm3_box_wood03a',  coords = vec4(1060.3220, -3095.4653, -39.0000, 344.2460) },
    { model = 'hei_prop_crate_stack_01',  coords = vec4(1062.8383, -3095.5203, -39.0000, 5.3204) },
    { model = 'prop_cratepile_07a',  coords = vec4(1065.2114, -3095.7014, -39.0000, 2.0238) },
    { model = 'prop_boxpile_06b',  coords = vec4(1067.6525, -3095.3992, -39.0000, 2.6559) },
    
    { model = 'prop_boxpile_06b',  coords = vec4(1053.0531, -3102.6299, -39.0000, 176.6396) },
    { model = 'hei_prop_crate_stack_01',  coords = vec4(1055.4275, -3102.4609, -39.0000, 181.3584) },
    { model = 'prop_boxpile_06b',  coords = vec4(1057.9220, -3102.5503, -39.0000, 177.9499) },
    { model = 'prop_cratepile_07a',  coords = vec4(1060.3243, -3102.9175, -39.0000, 2.0134) },
    { model = 'prop_boxpile_06b',  coords = vec4(1062.7971, -3102.6858, -39.0000, 353.2433) },
    { model = 'prop_boxpile_06b',  coords = vec4(1065.2242, -3103.0610, -39.0000, 2.0917) },
    { model = 'prop_cratepile_07a',  coords = vec4(1067.5684, -3102.7734, -39.0000, 354.5059) },


    { model = 'xm3_prop_xm3_box_wood03a',  coords = vec4(1053.0603, -3109.7654, -39.0000, 174.2227) },
    { model = 'prop_boxpile_06b',  coords = vec4(1055.5167, -3109.8130, -39.0000, 182.4992) },
    { model = 'hei_prop_crate_stack_01',  coords = vec4(1057.9010, -3109.7974, -39.0000, 182.8202) },
    { model = 'prop_boxpile_06b',  coords = vec4(1060.3092, -3109.7275, -39.0000, 177.4070) },
    { model = 'xm3_prop_xm3_box_wood03a',  coords = vec4(1062.7003, -3109.7585, -39.0000, 180.8158) },
    { model = 'prop_boxpile_06b',  coords = vec4(1065.1002, -3109.5457, -39.0000, 181.2572) },
    { model = 'hei_prop_crate_stack_01',  coords = vec4(1067.5103, -3109.7551, -39.0000, 182.2997) },






    -- { model = 'prop_boxpile_06b',  coords = vec4(1056.50, -3110.50, -39.00, 0.0) },
    -- { model = 'prop_mb_crate_01a', coords = vec4(1060.50, -3110.50, -39.00, 0.0) },
    -- { model = 'prop_cratepile_07a', coords = vec4(1064.50, -3110.50, -39.00, 0.0) },
    -- { model = 'prop_boxpile_07d',  coords = vec4(1060.50, -3101.00, -39.00, 180.0) },
    -- { model = 'prop_boxpile_06b',  coords = vec4(1064.50, -3101.00, -39.00, 180.0) },
}

-- Animation + short progress bar when picking a box up from a prop.
Config.PickupAction = {
    duration = 1200,                          -- ms
    animDict = 'pickup_object',               -- bend down and grab
    animClip = 'pickup_low',
}

-- Drop the pickup props and the skip onto the floor automatically (the laptop is never moved).
-- Turn this off if you set exact Z values and want them used as-is.
Config.SnapPropsToGround = true

-- Outline ("glow") on the ONE pickup prop the player should go to next.
-- It shows while they are on shift and empty-handed.
Config.Highlight = {
    enabled = true,
    colour = { r = 80, g = 200, b = 255, a = 255 },
    skip = true,                              -- also outline the skip while you carry a box
}

------------------------------------------------------------------------------------------------
-- Carrying
------------------------------------------------------------------------------------------------
Config.Carry = {
    model = 'hei_prop_heist_box',
    animDict = 'anim@heists@box_carry@',
    animClip = 'idle',

    -- How the box sits in the hands. bone 60309 is the left hand.
    bone = 60309,
    offset = vec3(0.025, 0.08, 0.255),
    rotation = vec3(-145.0, 290.0, 0.0),

    -- true  = other players see the box too (networked prop).
    -- false = only the carrier sees it. Use false if your server runs `sv_entityLockdown strict`,
    --         which blocks props created by clients.
    networked = true,

    -- Controls blocked while carrying: jump, enter vehicle, attack, aim, cover, weapon wheel.
    -- Sprinting is allowed. Add 21 to this list if you want to block it again.
    -- See https://docs.fivem.net/docs/game-references/controls/ for the numbers.
    disabledControls = { 22, 23, 24, 25, 44, 37 },
}

------------------------------------------------------------------------------------------------
-- Recycle point (the skip)
------------------------------------------------------------------------------------------------
Config.Skip = {
    model = 'prop_skip_01a',
    coords = vec4(1049.4326, -3108.0991, -38.8165, 156.8765),
    spawnProp = true,

    progressDuration = 3000,                  -- ms
    animDict = 'mp_common',                   -- arms push forward at chest height (tip the box in)
    animClip = 'givetake1_a',
    -- Alternatives to try: 'anim@heists@narcotics@trash' + 'throw_b' (overhead throw),
    --                      'pickup_object' + 'putdown_low' (put down low)
}

-- The item given for every box thrown into the skip.
Config.RecycleItem = 'recycle_box'
Config.RecycleAmount = 1

------------------------------------------------------------------------------------------------
-- Trader NPC
------------------------------------------------------------------------------------------------
Config.Trader = {
    model = 's_m_y_dockwork_01',
    -- PLACEHOLDER. Copy this while standing where the ped should stand (the script lowers it by 1 m
    -- so the feet touch the floor, because your copied Z is the centre of your body).
    coords = vec4(1049.2433, -3094.9302, -38.9999, 211.7741),

    -- Idle behaviour. Use a scenario OR an animation. If scenario is set, it wins.
    -- Scenario list: https://github.com/DioneB/gtav-scenarios
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    animDict = nil,                           -- e.g. 'amb@world_human_stand_impatient@male@no_sign@idle_a'
    animClip = nil,                           -- e.g. 'idle_a'

    -- Players can trade without being on shift (true = they must be signed in).
    requireShift = false,
}

-- Materials the trader offers. cost = recycle boxes taken, amount = items given.
-- These are PLACEHOLDER item names: add them to ox_inventory (see README) or use your own.
Config.Materials = {
    { item = 'plastic',  label = 'Plastic',  cost = 1, amount = 3 },
    { item = 'glass',    label = 'Glass',    cost = 1, amount = 2 },
    { item = 'aluminum', label = 'Aluminum', cost = 2, amount = 3 },
    { item = 'copper',   label = 'Copper',   cost = 3, amount = 2 },
}

------------------------------------------------------------------------------------------------
-- Interaction distances (metres)
-- The client uses these for ox_target. The server re-checks them with extra tolerance for lag.
------------------------------------------------------------------------------------------------
Config.Distance = {
    door = 2.0,
    laptop = 2.0,
    pickup = 2.5,
    skip = 3.0,
    trader = 2.5,
    serverTolerance = 2.0,                    -- added on top of the above for the server check
}

------------------------------------------------------------------------------------------------
-- ox_target icons (Font Awesome 6 names: https://fontawesome.com/search?ic=free)
------------------------------------------------------------------------------------------------
Config.Icons = {
    enter = 'fa-solid fa-door-open',
    exit = 'fa-solid fa-door-closed',
    startShift = 'fa-solid fa-right-to-bracket',
    endShift = 'fa-solid fa-right-from-bracket',
    pickup = 'fa-solid fa-box',
    deliver = 'fa-solid fa-recycle',
    trader = 'fa-solid fa-handshake',
    material = 'fa-solid fa-cubes',
    balance = 'fa-solid fa-box-open',
    laptop = 'fa-solid fa-laptop',
}

------------------------------------------------------------------------------------------------
-- All player-facing text
-- %s / %d are filled in by the script, in the order shown in the comment next to them.
------------------------------------------------------------------------------------------------
Config.Text = {
    blip = 'Recycling Warehouse',

    -- ox_target labels
    enter = 'Enter warehouse',
    exit = 'Leave warehouse',
    startShift = 'Start shift',
    endShift = 'End shift',
    pickup = 'Pick up box',
    deliver = 'Throw box in the skip',
    trader = 'Trade recycle boxes',

    -- progress bar
    recycling = 'Recycling box...',

    -- notifications
    shiftStarted = 'Shift started. Collect the highlighted box and take it to the skip.',
    shiftEnded = 'Shift ended. Thanks for your work!',
    alreadyOnShift = 'You are already on shift.',
    notOnShift = 'You are not on shift. Sign in at the laptop.',
    alreadyCarrying = 'You can only carry one box at a time.',
    notCarrying = 'You are not carrying a box.',
    picking = 'Picking up box...',
    pickedUp = 'Take the box to the skip.',
    wrongSpot = 'Not that one. Look for the highlighted box.',
    delivered = 'You received %d recycle box(es). Go to the next highlighted box.', -- amount
    boxDropped = 'You dropped the box.',
    tooFast = 'Slow down.',
    tooFar = 'You are too far away.',
    inventoryFull = 'You cannot carry any more.',
    cancelled = 'Cancelled.',
    failed = 'Something went wrong. Please try again.',
    loadFailed = 'Could not load a model: %s',          -- model name
    coordsCopied = 'Copied to clipboard: %s',             -- the vec4 text

    -- trader menu
    traderTitle = 'Recycling Trader',
    balance = 'Your recycle boxes: %d',               -- count
    materialDesc = 'Costs %d recycle box(es) - you get %d', -- cost, amount
    cannotAfford = 'You need %d recycle box(es) for %s. You have %d.', -- cost, label, count
    traded = 'You traded %d recycle box(es) for %dx %s.', -- cost, amount, label

    -- added with levels / goals / skill check / rare finds / custom UI
    useLaptop = 'Use laptop',
    skillHit = 'Clean throw! +%d bonus box(es).',      -- bonus boxes
    skillMiss = 'Missed the skill check.',
    levelUp = 'Level up! You are now level %d.',       -- level
    rareFind = 'While sorting the box you found %dx %s!', -- amount, item label
    rareNoRoom = 'You found %s but had no room for it.', -- item label
    goalDone = 'Goal complete: %s',                    -- goal text
    goalClaimLater = 'Goal complete: %s. No room for the reward - claim it at the laptop.', -- goal text
    goalClaimed = 'Reward claimed.',
    notClaimable = 'That reward cannot be claimed.',
    invalidAmount = 'Choose a valid amount.',
    noProfile = 'Your job profile could not be loaded. Try again in a moment.',
}

------------------------------------------------------------------------------------------------
-- Database
-- One table stores each character's XP, lifetime stats and today's goals.
------------------------------------------------------------------------------------------------
-- true = the script creates the table on start if it is missing. You can also run
-- install/recycling_warehouse.sql yourself and set this to false.
Config.AutoCreateTable = true

------------------------------------------------------------------------------------------------
-- Daily reset
-- At this hour of the SERVER's clock (0-23) the trade rates change and new goals become available.
------------------------------------------------------------------------------------------------
Config.DailyResetHour = 0

------------------------------------------------------------------------------------------------
-- Skill check at the skip
-- After the progress bar there is a chance of a quick ox_lib skill check.
-- Hit = bonus boxes and bonus XP. Miss (or no check) = the normal amount.
------------------------------------------------------------------------------------------------
Config.SkillCheck = {
    enabled = true,
    chance = 35,                              -- % of deliveries that ask for a skill check
    difficulty = { 'easy', 'medium' },        -- one entry per circle: 'easy', 'medium' or 'hard'
    keys = { 'e' },                           -- keys the player may have to press
    bonusBoxes = 1,                           -- extra recycle boxes for a hit
    bonusXp = 15,                             -- extra XP for a hit
}

------------------------------------------------------------------------------------------------
-- Experience and levels
------------------------------------------------------------------------------------------------
Config.Xp = {
    perBox = 10,                              -- XP for every box delivered
}

-- xp = total XP needed to reach the level. The perks of your CURRENT level apply (they don't add up):
--   bonusBoxes  extra recycle boxes per delivery
--   tradeBonus  % extra materials from every trade
--   rareChance  % added to Config.RareFinds.chance
Config.Levels = {
    { xp = 0,    bonusBoxes = 0, tradeBonus = 0,  rareChance = 0 }, -- level 1
    { xp = 150,  bonusBoxes = 0, tradeBonus = 5,  rareChance = 0 }, -- level 2
    { xp = 400,  bonusBoxes = 0, tradeBonus = 10, rareChance = 1 }, -- level 3
    { xp = 800,  bonusBoxes = 1, tradeBonus = 10, rareChance = 1 }, -- level 4
    { xp = 1400, bonusBoxes = 1, tradeBonus = 15, rareChance = 2 }, -- level 5
    { xp = 2200, bonusBoxes = 1, tradeBonus = 20, rareChance = 3 }, -- level 6
    { xp = 3200, bonusBoxes = 2, tradeBonus = 25, rareChance = 4 }, -- level 7
}

------------------------------------------------------------------------------------------------
-- Daily trade rates
-- Every day each material in Config.Materials gets a rating that changes how much you GET per
-- trade (cost stays the same). The rates are worked out from the date, so a restart does not
-- change them and everyone sees the same rates.
------------------------------------------------------------------------------------------------
Config.Market = {
    ratings = {
        { key = 'great',  label = 'Great value', multiplier = 1.5 },
        { key = 'normal', label = 'Normal',      multiplier = 1.0 },
        { key = 'poor',   label = 'Poor value',  multiplier = 0.6 },
    },
    -- Handed to one random material each, every day (so there is always one great and one poor deal).
    guaranteed = { 'great', 'poor' },
    -- Every other material picks one of these at random. Repeat a key to make it more likely.
    randomPool = { 'normal', 'normal', 'great', 'poor' },

    -- The trader screen lets players do up to this many trades of one material in a single click.
    maxTradesAtOnce = 20,
}

------------------------------------------------------------------------------------------------
-- Daily shift goals
-- The first shift of the day gives each player `perDay` random goals from the pool.
--   type    'deliver' = boxes delivered     'skill' = skill checks hit
--           'trade'   = trades made         'spend' = recycle boxes spent at the trader
--   label   %d is replaced with the target
--   reward  items and/or xp. Given automatically when the goal is finished; if the inventory is
--           full, the player can claim it at the laptop instead.
-- Each id must be unique.
------------------------------------------------------------------------------------------------
Config.Goals = {
    enabled = true,
    perDay = 3,
    pool = {
        { id = 'deliver10', type = 'deliver', target = 10, label = 'Deliver %d boxes',
          reward = { xp = 40, items = { { item = 'plastic', count = 6 } } } },
        { id = 'deliver25', type = 'deliver', target = 25, label = 'Deliver %d boxes',
          reward = { xp = 100, items = { { item = 'aluminum', count = 6 } } } },
        { id = 'skill3', type = 'skill', target = 3, label = 'Hit %d skill checks',
          reward = { xp = 50, items = { { item = 'glass', count = 6 } } } },
        { id = 'skill6', type = 'skill', target = 6, label = 'Hit %d skill checks',
          reward = { xp = 90, items = { { item = 'copper', count = 4 } } } },
        { id = 'trade2', type = 'trade', target = 2, label = 'Make %d trades',
          reward = { xp = 30, items = { { item = 'recycle_box', count = 2 } } } },
        { id = 'spend10', type = 'spend', target = 10, label = 'Spend %d recycle boxes at the trader',
          reward = { xp = 60, items = { { item = 'copper', count = 3 } } } },
    },
}

------------------------------------------------------------------------------------------------
-- Rare finds
-- Each delivered box has a small chance to contain something unusual. Use items from your other
-- jobs here. weight = how likely compared to the others; min/max = how many.
------------------------------------------------------------------------------------------------
Config.RareFinds = {
    enabled = true,
    chance = 3,                               -- % per box (levels add their rareChance on top)
    items = {
        { item = 'circuit_board', weight = 50, min = 1, max = 2 },
        { item = 'copper_wire',   weight = 35, min = 1, max = 3 },
        { item = 'gold_watch',    weight = 15, min = 1, max = 1 },
    },
}

------------------------------------------------------------------------------------------------
-- Custom screens (laptop + trader)
------------------------------------------------------------------------------------------------
Config.UI = {
    brand = 'Paradox Roleplay',               -- small server name shown on both screens
    logo = nil,                               -- e.g. 'logo.png' placed in recycling_warehouse/web/ (nil = no logo)
    accent = '#8b5cf6',                       -- main purple; everything else is tuned around it
}

-- All text on the custom screens. %d / %s are filled in, in the order given in the comment.
-- Write %% for a literal percent sign.
Config.UIText = {
    -- laptop
    laptopTitle = 'Recycling Warehouse',
    onShift = 'On shift',
    offShift = 'Signed out',
    startShift = 'Start shift',
    endShift = 'End shift',
    level = 'Level',
    xpProgress = '%d / %d XP',                -- xp into this level, xp needed for the next
    maxLevel = 'Max level',
    perksNow = 'Your perks',
    perksNext = 'At level %d',                -- next level
    perkBonusBoxes = '+%d box(es) per delivery',
    perkTradeBonus = '+%d%% materials from trades',
    perkRareChance = '+%d%% rare find chance',
    noPerks = 'No perks yet - keep recycling.',
    goalsTitle = "Today's goals",
    goalsEmpty = "Start a shift to get today's goals.",
    goalsOff = 'Goals are switched off.',
    reward = 'Reward: %s',                    -- reward text
    claim = 'Claim',
    claimed = 'Claimed',
    statsTitle = 'Lifetime',
    statBoxes = 'Boxes delivered',
    statSkill = 'Skill checks hit',
    statTrades = 'Trades',
    statRare = 'Rare finds',
    statGoals = 'Goals done',
    statShifts = 'Shifts',
    marketTitle = "Today's trade rates",
    resetsIn = 'New rates and goals in %s',   -- time like 5h 12m
    close = 'Close',

    -- trader
    traderTitle = 'Recycling Trader',
    traderSubtitle = 'Swap your recycle boxes for materials. Rates change daily.',
    yourBoxes = 'Your recycle boxes',
    levelBonus = 'Level bonus +%d%%',         -- trade bonus
    costEach = '%d box(es) each',             -- cost per trade
    getsEach = 'You get %d per trade',        -- amount per trade
    total = '%d box(es) for %dx %s',          -- total cost, total amount, label
    trade = 'Trade',
    notEnough = 'Not enough boxes',
}
