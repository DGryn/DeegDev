-- Server owns all drop state. While a drop is pending (picked but waiting for the delay) its
-- location only exists here. Once the plane is due, a copy is published in GlobalState.airdrop
-- so every client (including late joiners) can render the same crates at the same spots.

local drop = nil  -- { id, phase = 'pending' | 'flyover' | 'landed', heading, planeZ, center, props, taken, landTime }
local locks = {}  -- [crateIndex] = { src, time } while someone is running the progress bar
local cycle = 0   -- only the most recently scheduled timer is allowed to fire
local nextId = 0

local function notify(src, msg, type)
    if src and src > 0 then
        TriggerClientEvent('ox_lib:notify', src, { description = msg, type = type or 'inform' })
    else
        print(('[procaine_airdrop] %s'):format(msg))
    end
end

local function randomBetween(range)
    return math.random(range.min, range.max)
end

local function schedule(seconds, fn)
    cycle = cycle + 1
    local token = cycle
    SetTimeout(seconds * 1000, function()
        if token == cycle then fn() end
    end)
end

local function publish()
    if not drop or drop.phase == 'pending' then
        GlobalState.airdrop = nil
        return
    end

    GlobalState.airdrop = {
        id = drop.id,
        phase = drop.phase,
        heading = drop.heading,
        planeZ = drop.planeZ,
        center = drop.center,
        props = drop.props,
        taken = drop.taken,
    }
end

-- Calls a client callback with a timeout so a player who doesn't answer can't stall the server.
local function clientCall(src, name, ...)
    local p = promise.new()
    local done = false

    lib.callback(name, src, function(result)
        if done then return end
        done = true
        p:resolve(result)
    end, ...)

    SetTimeout(Config.Location.timeout, function()
        if done then return end
        done = true
        p:resolve(false)
    end)

    return Citizen.Await(p)
end

-- Builds candidate lines (centre, heading and crate x/y) around a player's position.
-- The first candidate is the offset spot; the rest are random spots within the search radius around it.
local function makeCandidates(origin, count, here)
    local candidates = {}
    local dist = here and 0.0 or randomBetween(Config.Location.offset)
    local angle = math.random() * 2 * math.pi
    local baseX, baseY = origin.x + math.cos(angle) * dist, origin.y + math.sin(angle) * dist

    for a = 1, Config.Location.attempts do
        local cx, cy = baseX, baseY

        if a > 1 then
            local r = math.random() * Config.Location.searchRadius
            local ang = math.random() * 2 * math.pi
            cx, cy = baseX + math.cos(ang) * r, baseY + math.sin(ang) * r
        end

        local heading = math.random(0, 359) + 0.0
        local rad = math.rad(heading)
        local dx, dy = -math.sin(rad), math.cos(rad)
        local spacing = Config.Location.spacing
        local offsets, length = { 0.0 }, 0.0

        for i = 2, count do
            length = length + spacing.min + math.random() * (spacing.max - spacing.min)
            offsets[i] = length
        end

        local points = {}

        for i = 1, count do
            local s = offsets[i] - length / 2 -- centre the line on cx, cy
            points[i] = { x = cx + dx * s, y = cy + dy * s, s = s }
        end

        candidates[a] = { x = cx, y = cy, heading = heading, points = points }
    end

    return candidates
end

-- Asks the player's client (which has collision loaded around them) for ground heights along the
-- candidate lines. The client only reports ground Z; the server picked the spots and the loot.
local function findDrop(src, here)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end

    local count = randomBetween(Config.CrateCount)
    local candidates = makeCandidates(GetEntityCoords(ped), count, here)
    local result = clientCall(src, 'procaine_airdrop:checkSpot', here, candidates)

    if type(result) ~= 'table' or type(result.zs) ~= 'table' then return end

    local cand = candidates[result.index]
    if not cand or #result.zs ~= count then return end

    local maxZ = -math.huge
    for i = 1, count do
        local z = tonumber(result.zs[i])
        if not z then return end
        result.zs[i] = z
        maxZ = math.max(maxZ, z)
    end

    local planeZ = maxZ + Config.Plane.height
    local dropZ = planeZ - Config.Crate.dropBelow
    local props, taken, landTime = {}, {}, 0

    for i, pt in ipairs(cand.points) do
        local z = result.zs[i]
        local t = (Config.Plane.distance + pt.s) / Config.Plane.speed -- when the plane is overhead
        props[i] = { x = pt.x, y = pt.y, z = z, t = t }
        taken[i] = false
        landTime = math.max(landTime, t + (dropZ - z) / Config.Crate.fallSpeed)
    end

    local mid = math.floor((count + 1) / 2)
    nextId = nextId + 1

    return {
        id = nextId,
        phase = 'pending',
        heading = cand.heading,
        planeZ = planeZ,
        center = { x = cand.x, y = cand.y, z = result.zs[mid] },
        props = props,
        taken = taken,
        landTime = math.ceil(landTime) + 2,
    }
end

local function pickDrop()
    local players = GetPlayers()
    if #players < Config.MinPlayers then return end

    for i = #players, 2, -1 do
        local j = math.random(i)
        players[i], players[j] = players[j], players[i]
    end

    for _, id in ipairs(players) do
        local src = tonumber(id)
        if GetPlayerRoutingBucket(src) == Config.RoutingBucket then
            local found = findDrop(src, false)
            if found then return found end
        end
    end
end

local tryStart, startFlyover, finish

finish = function()
    drop = nil
    locks = {}
    publish()
    schedule(randomBetween(Config.Interval) * 60, tryStart)
end

startFlyover = function()
    if not drop or drop.phase ~= 'pending' then return end

    drop.phase = 'flyover'
    publish()

    schedule(drop.landTime, function()
        if not drop then return end
        drop.phase = 'landed'
        publish()
        schedule(Config.DespawnTime * 60, finish)
    end)
end

tryStart = function()
    if drop then return end

    local found = pickDrop()
    if not found then
        return schedule(Config.RetryDelay, tryStart)
    end

    drop = found
    schedule(randomBetween(Config.DropDelay) * 60, startFlyover)
end

CreateThread(function()
    GlobalState.airdrop = nil
    schedule(randomBetween(Config.Interval) * 60, tryStart)
end)

local function isNear(src, prop)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(prop.x, prop.y, prop.z)) <= Config.Claim.serverDistance
end

local function claimable(id, index)
    return drop and drop.id == id and drop.phase == 'landed'
        and type(index) == 'number' and drop.props[index] ~= nil
end

lib.callback.register('procaine_airdrop:startClaim', function(src, id, index)
    if not claimable(id, index) or drop.taken[index] then
        notify(src, Config.Text.taken, 'error')
        return false
    end

    local lock = locks[index]
    if lock and lock.src ~= src and GetGameTimer() - lock.time < Config.Claim.duration + 5000 then
        notify(src, Config.Text.busy, 'error')
        return false
    end

    if not isNear(src, drop.props[index]) then
        notify(src, Config.Text.tooFar, 'error')
        return false
    end

    locks[index] = { src = src, time = GetGameTimer() }
    return true
end)

RegisterNetEvent('procaine_airdrop:cancelClaim', function(id, index)
    local src = source
    if not claimable(id, index) then return end
    if locks[index] and locks[index].src == src then locks[index] = nil end
end)

RegisterNetEvent('procaine_airdrop:finishClaim', function(id, index)
    local src = source
    if not claimable(id, index) or drop.taken[index] then return end

    local lock = locks[index]
    if not lock or lock.src ~= src then return end
    locks[index] = nil

    -- The progress bar must actually have run
    if GetGameTimer() - lock.time < Config.Claim.duration - 500 then return end

    if not isNear(src, drop.props[index]) then
        return notify(src, Config.Text.tooFar, 'error')
    end

    if not exports.ox_inventory:CanCarryItem(src, Config.Item, Config.PerCrate) then
        return notify(src, Config.Text.full, 'error')
    end

    drop.taken[index] = true

    if not exports.ox_inventory:AddItem(src, Config.Item, Config.PerCrate) then
        drop.taken[index] = false
        return notify(src, Config.Text.full, 'error')
    end

    notify(src, Config.Text.received:format(Config.PerCrate), 'success')

    for i = 1, #drop.taken do
        if not drop.taken[i] then return publish() end
    end

    finish()
end)

AddEventHandler('playerDropped', function()
    local src = source
    for i, lock in pairs(locks) do
        if lock.src == src then locks[i] = nil end
    end
end)

RegisterCommand(Config.Admin.command, function(src, args)
    if src > 0 then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer or not Config.Admin.groups[xPlayer.getGroup()] then
            return notify(src, Config.Text.noPermission, 'error')
        end
    end

    local here = args[1] == 'here'
    if here and src == 0 then
        return print('[procaine_airdrop] "here" cannot be used from the console')
    end

    if drop and drop.phase ~= 'pending' then
        return notify(src, Config.Text.adminActive, 'error')
    end

    CreateThread(function()
        local found
        if here then
            found = findDrop(src, true)
        elseif drop then
            found = drop -- a drop is already waiting on its delay: skip the delay
        else
            found = pickDrop()
        end

        if not found then
            return notify(src, Config.Text.adminFailed, 'error')
        end

        if drop and drop ~= found and drop.phase ~= 'pending' then
            return notify(src, Config.Text.adminActive, 'error')
        end

        drop = found
        locks = {}
        startFlyover()
        notify(src, Config.Text.adminStarted, 'success')
    end)
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        GlobalState.airdrop = nil
    end
end)
