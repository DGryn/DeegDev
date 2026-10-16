Config = {}

-- Loot: every crate in the line holds Config.PerCrate of the item
Config.Item = 'procaine'
Config.PerCrate = 1
Config.CrateCount = { min = 15, max = 20 } -- number of crates per drop (= total procaine at 1 per crate)

-- Timing
Config.Interval = { min = 45, max = 90 } -- minutes between drops (counted from when the previous drop ended)
Config.DropDelay = { min = 5, max = 10 } -- minutes between picking a location and the plane arriving
Config.DespawnTime = 30                  -- minutes after landing before unclaimed crates are removed
Config.RetryDelay = 60                   -- seconds before retrying when no player/location was eligible

-- Player eligibility
Config.MinPlayers = 1
Config.RoutingBucket = 0 -- only players in this bucket can be picked

-- Location
Config.Location = {
    offset = { min = 50, max = 150 }, -- metres from the picked player's position to the centre of the line
    searchRadius = 100.0,             -- how far around that point to look for valid ground if it is unsuitable
    attempts = 15,                    -- candidate spots tried per player before moving on to another player
    maxHeightDiff = 12.0,             -- max ground height difference along the line (rejects cliffs/rooftops)
    spacing = { min = 4.0, max = 10.0 }, -- random metres between each crate and the next
    timeout = 5000,                   -- ms to wait for the picked player's client to check the ground
}

-- Plane (local entities, deleted after the flyover)
Config.Plane = {
    model = 'streamer216',
    pilot = 's_m_m_pilot_01',
    height = 150.0,    -- metres above the highest crate spot
    speed = 50.0,      -- metres per second
    distance = 1000.0, -- metres the plane starts before (and ends after) the centre of the line
    headingOffset = 0.0, -- degrees added to the model's rotation if its nose doesn't point along the path (try 90.0 / -90.0)
}

-- Crates
Config.Crate = {
    model = 'prop_mp_drug_package',
    chute = 'p_cargo_chute_s',
    chuteOffset = vector3(0.0, 0.0, 0.1),
    fallSpeed = 6.0, -- metres per second under the parachute
    dropBelow = 10.0, -- crates appear this far below the plane (clears the Titan's fuselage so they're visible immediately)
}

-- Red smoke left at the spot of every crate that has been picked up (until the drop ends)
Config.Smoke = {
    asset = 'core',
    name = 'exp_grd_flare',
    scale = 1.0,
    colour = { 1.0, 0.0, 0.0 },
}

-- Beeping on every crate that is still on the ground
Config.Sound = {
    name = 'Beep_Red',
    set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
    radius = 100.0,  -- audible range (the game engine handles volume falloff with distance)
    interval = 1000, -- ms between beeps
}

-- Clients only spawn the plane/crates/smoke while within this distance of the drop. Keep it above Config.Sound.radius.
Config.RenderDistance = 400.0

-- Claiming
Config.Claim = {
    distance = 2.0,       -- ox_target interaction distance
    serverDistance = 5.0, -- max distance the server accepts (allows for latency)
    duration = 3500,      -- progress bar length in ms
    scenario = 'PROP_HUMAN_BUM_BIN',
}

-- Admin: /airdrop (random player, no delay) or /airdrop here (at your position, no delay)
Config.Admin = {
    command = 'airdrop',
    groups = { admin = true, superadmin = true },
}

Config.Text = {
    target = 'pick up',
    progress = 'Picking up procaine...',
    received = 'You picked up %d procaine.',
    taken = 'This procaine has already been taken.',
    busy = 'Someone is already picking this up.',
    tooFar = 'You are too far from the procaine.',
    full = 'You cannot carry that.',
    noPermission = 'You are not allowed to use this command.',
    adminStarted = 'Airdrop started.',
    adminActive = 'An airdrop is already in progress.',
    adminFailed = 'Could not find a valid drop location.',
}
