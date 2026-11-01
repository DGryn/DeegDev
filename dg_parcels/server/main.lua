--[[
    dg_parcels - server
    The server owns everything that matters: which spots have a parcel, loot rolls,
    trap rolls and every check. Clients only draw props and play the progress bar.
]]

local ESX = exports['es_extended']:getSharedObject()
local ox = exports.ox_inventory

---------------------------------------------------------------------
-- POLICE ALERT
-- Everything in this resource contacts the police ONLY through this function.
-- Default: notification + temporary map blip for every online player whose
-- ESX job is in Config.Police.Jobs (handled by 'dg_parcels:policeAlert' in client/main.lua).
---------------------------------------------------------------------
local function SendPoliceAlert(coords, size)
    -- To use my own dispatch, replace the body of this function with its export call
    for _, job in ipairs(Config.Police.Jobs) do
        for _, xPlayer in pairs(ESX.GetExtendedPlayers('job', job)) do
            TriggerClientEvent('dg_parcels:policeAlert', xPlayer.source, coords)
        end
    end
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local activeParcels = {} -- [spotId] = 'small' | 'medium' | 'large'
local respawnAt     = {} -- [spotId] = os.time() when this spot may spawn again
local opening       = {} -- [src] = { item, size, started, duration, expires }
local savedLoot     = {} -- [license] = { [size] = { [itemName] = count } }
local lastAction    = {} -- [src] = { [action] = GetGameTimer() }
local nextTrapGlobal = 0
local nextTrapPlayer = {} -- [license] = os.time()

-- item name -> size, e.g. itemToSize.parcel_small = 'small'
local itemToSize = {}
for size, data in pairs(Config.Sizes) do itemToSize[data.item] = size end

local function notify(src, text)
    TriggerClientEvent('ox_lib:notify', src, { description = text, type = 'error' })
end

-- License survives reconnects, so leaving and rejoining doesn't reset loot/trap state.
local function getKey(src)
    return GetPlayerIdentifierByType(src, 'license') or tostring(src)
end

-- Returns true if this player did the same action too recently.
local function tooFast(src, action)
    local now = GetGameTimer()
    lastAction[src] = lastAction[src] or {}
    if now - (lastAction[src][action] or 0) < Config.RateLimitMs then return true end
    lastAction[src][action] = now
    return false
end

-- Picks one entry from a list of tables that each have a `weight`.
local function pickWeighted(list)
    local total = 0
    for _, entry in ipairs(list) do total = total + entry.weight end
    local roll = math.random() * total
    for _, entry in ipairs(list) do
        roll = roll - entry.weight
        if roll <= 0 then return entry end
    end
    return list[#list]
end

---------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------
local sizeChances = {
    { size = 'small',  weight = Config.Sizes.small.chance },
    { size = 'medium', weight = Config.Sizes.medium.chance },
    { size = 'large',  weight = Config.Sizes.large.chance },
}

local function spawnTick()
    local now = os.time()
    local active, free = 0, {}

    for id = 1, #Config.Locations do
        if activeParcels[id] then
            active = active + 1
        elseif (respawnAt[id] or 0) <= now then
            free[#free + 1] = id
        end
    end

    -- Fill random free spots until we hit the limit.
    while active < Config.MaxActive and #free > 0 do
        local id = table.remove(free, math.random(#free))
        local size = pickWeighted(sizeChances).size
        activeParcels[id] = size
        active = active + 1
        TriggerClientEvent('dg_parcels:add', -1, id, size)
    end
end

CreateThread(function()
    while true do
        spawnTick()
        Wait(30000)
    end
end)

-- Players joining (or the client script restarting) ask for the current list.
-- Sent as a plain list because sparse number-keyed tables don't survive the network well.
lib.callback.register('dg_parcels:getAll', function()
    local list = {}
    for id, size in pairs(activeParcels) do list[#list + 1] = { id = id, size = size } end
    return list
end)

---------------------------------------------------------------------
-- Grabbing
---------------------------------------------------------------------
RegisterNetEvent('dg_parcels:grab', function(id)
    local src = source
    if type(id) ~= 'number' or not Config.Locations[id] then return end
    if tooFast(src, 'grab') then return end

    local size = activeParcels[id]
    if not size then return end -- already taken (or never existed)

    local spot = Config.Locations[id]
    if #(GetEntityCoords(GetPlayerPed(src)) - spot.xyz) > Config.GrabDistance then return end

    local item = Config.Sizes[size].item
    if not ox:CanCarryItem(src, item, 1) then
        notify(src, "You can't carry that, you're too heavy")
        return
    end

    -- Claim it before giving the item. Server Lua runs one event at a time and
    -- nothing above yields, so a second grab for this spot will see nil and stop.
    activeParcels[id] = nil
    if not ox:AddItem(src, item, 1) then
        activeParcels[id] = size -- give it back to the world, clients never removed it
        return
    end

    respawnAt[id] = os.time() + math.random(Config.RespawnMinutes.min, Config.RespawnMinutes.max) * 60
    TriggerClientEvent('dg_parcels:remove', -1, id)
end)

---------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------
local function hasTool(src)
    for _, name in ipairs(Config.SharpTools) do
        if (ox:GetItemCount(src, name) or 0) > 0 then return true end
    end
    return false
end

-- Loot is rolled once per player per size and kept until it's actually handed out.
-- Without this, players could cancel / fill their pockets to re-roll for better loot.
local function getLoot(src, size)
    local key = getKey(src)
    savedLoot[key] = savedLoot[key] or {}
    if savedLoot[key][size] then return savedLoot[key][size] end

    local loot = {}
    local rolls = Config.Sizes[size].rolls
    for _ = 1, math.random(rolls.min, rolls.max) do
        local entry = pickWeighted(Config.Loot[size])
        if ox:Items(entry.item) then
            loot[entry.item] = (loot[entry.item] or 0) + math.random(entry.min, entry.max)
        else
            print(('^3[dg_parcels] loot item "%s" does not exist in ox_inventory, skipped^0'):format(entry.item))
        end
    end

    savedLoot[key][size] = loot
    return loot
end

-- Every item must fit (slots + weight) and the total weight must fit too.
-- This is checked while the parcel is still in the inventory, so it's on the safe side.
local function canCarryLoot(src, loot)
    local totalWeight = 0
    for name, count in pairs(loot) do
        if not ox:CanCarryItem(src, name, count) then return false end
        totalWeight = totalWeight + (ox:Items(name).weight or 0) * count
    end
    return ox:CanCarryWeight(src, totalWeight)
end

local function maybeTrap(src, size)
    if math.random() >= Config.Sizes[size].trapChance then return end

    local now, key = os.time(), getKey(src)
    if now < nextTrapGlobal or now < (nextTrapPlayer[key] or 0) then return end
    nextTrapGlobal = now + Config.Trap.GlobalCooldown
    nextTrapPlayer[key] = now + Config.Trap.PlayerCooldown

    -- Where it was opened: the vehicle if they're in one, otherwise the player.
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local coords = GetEntityCoords(vehicle ~= 0 and vehicle or ped)

    TriggerClientEvent('dg_parcels:smoke', -1, coords, Config.Trap.SmokeDuration * 1000)
    SendPoliceAlert(coords, size)
end

-- Step 1: the client used a parcel item. Check everything, then let it start the progress bar.
lib.callback.register('dg_parcels:startOpen', function(src, itemName)
    local size = itemToSize[itemName]
    if not size or tooFast(src, 'open') then return false end

    local current = opening[src]
    if current and GetGameTimer() < current.expires then return false end -- already opening one

    if (ox:GetItemCount(src, itemName) or 0) < 1 then return false end

    if not hasTool(src) then
        notify(src, 'You need something sharp to cut this open')
        return false
    end

    if not canCarryLoot(src, getLoot(src, size)) then
        notify(src, "You don't have room for what's inside")
        return false
    end

    local duration = Config.Sizes[size].openTime
    opening[src] = {
        item = itemName,
        size = size,
        started = GetGameTimer(),
        duration = duration,
        expires = GetGameTimer() + duration + 15000, -- forgets a stuck/abandoned open after this
    }
    return true, duration
end)

-- Step 2: the progress bar finished. Check again, then swap the parcel for the loot.
lib.callback.register('dg_parcels:finishOpen', function(src)
    local job = opening[src]
    opening[src] = nil -- clear first so a second finish request does nothing
    if not job then return false end

    local now = GetGameTimer()
    if now - job.started < job.duration - 500 then return false end -- bar was skipped
    if now > job.expires then return false end

    -- Re-check: the item could have been dropped/moved during the bar.
    if (ox:GetItemCount(src, job.item) or 0) < 1 then return false end
    if not hasTool(src) then
        notify(src, 'You need something sharp to cut this open')
        return false
    end

    local loot = getLoot(src, job.size)
    if not canCarryLoot(src, loot) then
        notify(src, "You don't have room for what's inside")
        return false
    end

    if not ox:RemoveItem(src, job.item, 1) then return false end

    for name, count in pairs(loot) do
        if not ox:AddItem(src, name, count) then
            print(('^1[dg_parcels] failed to give %sx %s to %s^0'):format(count, name, src))
        end
    end
    savedLoot[getKey(src)][job.size] = nil -- next parcel of this size gets a fresh roll

    if not next(loot) then
        TriggerClientEvent('ox_lib:notify', src, { description = 'It was empty', type = 'inform' })
    end

    maybeTrap(src, job.size)
    return true
end)

RegisterNetEvent('dg_parcels:cancelOpen', function()
    opening[source] = nil
end)

AddEventHandler('playerDropped', function()
    opening[source] = nil -- nothing is given if they leave mid-bar
    lastAction[source] = nil
end)

---------------------------------------------------------------------
-- Dev command: /parcelcoord prints a config-ready vector4
---------------------------------------------------------------------
RegisterCommand('parcelcoord', function(src)
    if src == 0 then return print('[dg_parcels] /parcelcoord must be used in-game') end

    local xPlayer = ESX.GetPlayerFromId(src)
    local allowed = IsPlayerAceAllowed(src, 'command.parcelcoord')
        or (xPlayer and Config.AdminGroups[xPlayer.getGroup()])
    if not allowed then return end

    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local line = ('vector4(%.2f, %.2f, %.2f, %.1f),'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    print(('[dg_parcels] %s: %s'):format(GetPlayerName(src), line))
    TriggerClientEvent('dg_parcels:coord', src, line)
end, false)
