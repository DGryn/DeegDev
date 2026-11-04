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
    coords = vec3(1017.40, -3112.00, 5.90),
    radius = 1.5,                                     -- size of the interaction zone
    -- Where the player appears INSIDE the warehouse.
    -- PLACEHOLDER: just inside the door, near the reference point.
    spawnInside = vec4(1049.60, -3097.20, -38.00, 270.0),

    -- Map blip for the entrance. Set blip = false to hide it.
    blip = { sprite = 365, colour = 2, scale = 0.8 },
}

Config.Exit = {
    -- Where the player interacts INSIDE to leave. PLACEHOLDER: the warehouse door.
    coords = vec3(1048.20, -3097.20, -38.50),
    radius = 1.5,
    -- Where the player appears OUTSIDE after leaving. PLACEHOLDER: next to the entrance.
    spawnOutside = vec4(1017.40, -3110.50, 5.90, 0.0),

    -- Leaving the warehouse ends the shift automatically (any carried box is dropped).
    endShiftOnExit = true,
}

------------------------------------------------------------------------------------------------
-- Laptop (sign in / sign out)
------------------------------------------------------------------------------------------------
Config.Laptop = {
    coords = vec4(1048.5372, -3100.7546, -38.1755, 88.0837),
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
    { model = 'prop_boxpile_07d',  coords = vec4(1052.50, -3110.50, -39.00, 0.0) },
    { model = 'prop_boxpile_06b',  coords = vec4(1056.50, -3110.50, -39.00, 0.0) },
    { model = 'prop_mb_crate_01a', coords = vec4(1060.50, -3110.50, -39.00, 0.0) },
    { model = 'prop_cratepile_07a', coords = vec4(1064.50, -3110.50, -39.00, 0.0) },
    { model = 'prop_boxpile_07d',  coords = vec4(1060.50, -3101.00, -39.00, 180.0) },
    { model = 'prop_boxpile_06b',  coords = vec4(1064.50, -3101.00, -39.00, 180.0) },
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
    coords = vec4(1062.00, -3104.00, -38.00, 90.0),

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
}
