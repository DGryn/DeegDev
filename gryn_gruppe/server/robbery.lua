--[[
    gryn_gruppe - server/robbery.lua

    Thermite on an active job van. The client's minigame result is never trusted on its own:
    the finish callback checks there is a started attempt, that it took a believable amount of
    time, that the job is still active, that the thief is near the van, holds the thermite and
    is off cooldown. Only then is the van marked robbed and its loot made takeable.
]]

local Attempts = {}       -- [src] = { netId, startedAt (GetGameTimer) }
local VanAttempt = {}     -- [netId] = src (one thief at a time per van)
local Robbed = {}         -- [netId] = { van, loot = { { kind, value }, ... } }
local ThiefCooldown = {}  -- [identifier] = os.time() when thermite can be used again

-- Placeholder dispatch. Replace the print with your dispatch resource's export or event,
-- e.g. exports['your_dispatch']:SendAlert({ coords = coords, message = '...' }).
function SendDispatchAlert(coords)
    print(('[gryn_gruppe] DISPATCH: Gruppe 6 Stockade under attack at %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z))
end

local function clearAttempt(src)
    local a = Attempts[src]
    if a then VanAttempt[a.netId] = nil end
    Attempts[src] = nil
    return a
end

lib.callback.register('gryn_gruppe:robStart', function(src, netId)
    if G6.RateLimited(src, 'robStart', 2000) then return false end
    local job = G6.JobByVan(netId)
    local van = G6.EntityFromNet(netId)
    if not job or job.ended or not van then return false, 'This van is not carrying anything.' end
    if G6.IsMember(job.group, src) then return false, 'You cannot rob your own job.' end
    if VanAttempt[netId] or Attempts[src] then return false, 'Someone is already working on it.' end
    if not G6.Near(src, GetEntityCoords(van), Config.ServerDistance + 2.0) then return false, 'Too far away.' end
    if exports.ox_inventory:GetItemCount(src, Config.Items.thermite) < 1 then return false, 'You need thermite.' end
    if G6.PoliceCount() < Config.MinPolice then return false, 'Not enough police in the city.' end

    local id = G6.Identifier(src)
    local until_ = id and ThiefCooldown[id]
    if until_ and until_ > os.time() then
        return false, ('Lay low for %d more min.'):format(math.ceil((until_ - os.time()) / 60))
    end

    Attempts[src] = { netId = netId, startedAt = GetGameTimer() }
    VanAttempt[netId] = src
    SendDispatchAlert(GetEntityCoords(van))
    G6.Log('Robbery started', ('%s on job #%d'):format(G6.Name(src), job.id))
    return true, Config.Robbery.minigame
end)

lib.callback.register('gryn_gruppe:robFinish', function(src, success)
    local attempt = clearAttempt(src)
    if not attempt then return false end

    local elapsed = GetGameTimer() - attempt.startedAt
    local job = G6.JobByVan(attempt.netId)
    local van = G6.EntityFromNet(attempt.netId)
    if not job or job.ended or not van then return false, 'The van is gone.' end
    if elapsed > Config.Robbery.maxAttemptTime * 1000 then return false, 'You took too long.' end
    if not G6.Near(src, GetEntityCoords(van), Config.ServerDistance + 2.0) then return false, 'Too far away.' end

    -- The charge is used up either way.
    if not exports.ox_inventory:RemoveItem(src, Config.Items.thermite, 1) then return false, 'You need thermite.' end
    local id = G6.Identifier(src)
    if id then ThiefCooldown[id] = os.time() + Config.Robbery.cooldown * 60 end

    -- A pass faster than the pattern is even shown is not a real pass.
    if success ~= true or elapsed < Config.Robbery.minigame.showTime then
        G6.Log('Robbery failed', ('%s on job #%d'):format(G6.Name(src), job.id))
        return false, 'The charge fizzled out.', Config.Robbery.burnDamage
    end

    local loot = {}
    for _, kind in ipairs(G6.RobJob(job)) do
        local range = Config.Robbery.lootValue[kind]
        loot[#loot + 1] = { kind = kind, value = math.random(range.min, range.max) }
    end
    Robbed[attempt.netId] = { van = van, loot = loot }
    Entity(van).state:set('g6Loot', #loot, true)
    TriggerClientEvent('gryn_gruppe:vanBlown', -1, attempt.netId)
    G6.Log('Robbery success', ('%s robbed job #%d, %d items in the van'):format(G6.Name(src), job.id, #loot))

    SetTimeout(Config.Robbery.vanCleanup * 1000, function()
        local r = Robbed[attempt.netId]
        if r and r.van == van then
            Robbed[attempt.netId] = nil
            if DoesEntityExist(van) then DeleteEntity(van) end
        end
    end)
    return true
end)

lib.callback.register('gryn_gruppe:takeLoot', function(src, netId)
    if G6.RateLimited(src, 'loot', math.floor(Config.Progress.takeLoot * 0.8)) then return false end
    local r = Robbed[netId]
    if not r or not DoesEntityExist(r.van) then return false, 'Nothing left.' end
    if not G6.Near(src, GetEntityCoords(r.van), Config.ServerDistance + 2.0) then return false, 'Too far away.' end

    local entry = r.loot[#r.loot]
    if not entry then return false, 'Nothing left.' end
    local item = entry.kind == 'crate' and Config.Items.crate or Config.Items.moneybag
    local metadata = { value = entry.value, description = ('Stolen Gruppe 6 %s. Worth about $%s.'):format(entry.kind, entry.value) }
    if not exports.ox_inventory:CanCarryItem(src, item, 1, metadata) then return false, 'You cannot carry that.' end

    table.remove(r.loot)
    exports.ox_inventory:AddItem(src, item, 1, metadata)
    Entity(r.van).state:set('g6Loot', #r.loot, true)
    G6.Log('Loot taken', ('%s took a %s worth $%d'):format(G6.Name(src), entry.kind, entry.value))
    return true
end)

AddEventHandler('playerDropped', function()
    clearAttempt(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, r in pairs(Robbed) do
        if DoesEntityExist(r.van) then DeleteEntity(r.van) end
    end
end)
