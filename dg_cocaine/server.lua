--[[
    dg_cocaine - server.lua

    The server owns all state and decides every reward. Clients only draw props and ask for
    actions through lib.callback; every action is re-checked here (items, distance, plant state,
    cooldown) before anything is removed or given.

    State                          Replicated to clients via
    Plants[id] (+ MySQL table)     snapshot callback on join + dg_cocaine:plantUpdated / dg_cocaine:plantRemoved events
    Request (seed NPC)             dg_cocaine:getRequest callback (only when a player talks to the NPC)
    Cooldowns[src], Planting[src]  server only

    API references:
      oxmysql                https://coxdocs.dev/oxmysql
      ox_lib callbacks       https://coxdocs.dev/ox_lib/Modules/Callback/Server
      ox_inventory           https://coxdocs.dev/ox_inventory/Functions/Server
      ESX xPlayer            https://docs.esx-framework.org/legacy/Server/Classes/xPlayer
]]

local ESX = exports['es_extended']:getSharedObject() -- https://docs.esx-framework.org/legacy/Server/Functions/getSharedObject

local Plants = {}      -- [id] = { id, owner, coords (vector3), plantedAt, wateredAt (nil = not watered), fertilised }
local OwnerCount = {}  -- [identifier] = number of active plants
local Cooldowns = {}   -- [src] = { [action] = GetGameTimer() when it may run again }
local Planting = {}    -- [src] = true while a plant insert is running (blocks double plants past the limit)
local Request = nil    -- { id, item, label, amount, seeds = { min, max } }
local nextRequestId = 0

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------

-- Bags made from one brick (and baggies used). Replace this when the skill system exists.
local function GetBagYield(src)
    return Config.Bagging.bagsPerBrick
end

local function pedCoords(src) return GetEntityCoords(GetPlayerPed(src)) end

local function near(src, coords)
    return #(pedCoords(src) - vector3(coords.x, coords.y, coords.z)) <= Config.ServerDistance
end

local function count(src, item)
    return exports.ox_inventory:GetItemCount(src, item) or 0
end

-- Rejects an action that comes back sooner than its progress bar could have finished.
-- Each action may only succeed once per `ms` per player.
local function onCooldown(src, action, ms)
    local now = GetGameTimer()
    local list = Cooldowns[src]
    if not list then list = {}; Cooldowns[src] = list end
    if list[action] and list[action] > now then return true end
    list[action] = now + math.floor(ms * 0.9) -- 10% slack for latency
    return false
end

local function identifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier
end

local function inPlantZone(coords)
    for _, zone in ipairs(Config.PlantZones) do
        if #(vector2(coords.x, coords.y) - zone.coords) <= zone.radius then return true end
    end
    return false
end

------------------------------------------------------------------------------------------------
-- Plants
------------------------------------------------------------------------------------------------

-- What clients get: position, flags and seconds left until ready (nil = not watered yet).
local function clientPlant(p)
    local growLeft
    if p.wateredAt then growLeft = math.max(0, p.wateredAt + Config.Plants.growTime - os.time()) end
    return { id = p.id, x = p.coords.x, y = p.coords.y, z = p.coords.z, fert = p.fertilised, growLeft = growLeft }
end

local function syncPlant(p) TriggerClientEvent('dg_cocaine:plantUpdated', -1, clientPlant(p)) end

local function isReady(p)
    return p.wateredAt ~= nil and os.time() >= p.wateredAt + Config.Plants.growTime
end

local function addPlant(row)
    local p = {
        id = row.id,
        owner = row.owner,
        coords = vector3(row.x, row.y, row.z),
        plantedAt = row.planted_at,
        wateredAt = row.watered_at,
        fertilised = row.fertilised == 1 or row.fertilised == true,
    }
    Plants[p.id] = p
    OwnerCount[p.owner] = (OwnerCount[p.owner] or 0) + 1
    return p
end

local function removePlant(p)
    Plants[p.id] = nil
    OwnerCount[p.owner] = math.max(0, (OwnerCount[p.owner] or 1) - 1)
    TriggerClientEvent('dg_cocaine:plantRemoved', -1, p.id)
end

local function isExpired(p)
    local expire = Config.Plants.expireTime or 0
    return expire > 0 and os.time() >= p.plantedAt + expire
end

-- Removes every expired plant from memory, clients and the database.
local function removeExpired()
    local ids = {}
    for _, p in pairs(Plants) do
        if isExpired(p) then
            removePlant(p)
            ids[#ids + 1] = p.id
        end
    end
    if #ids > 0 then
        MySQL.update(('DELETE FROM dg_cocaine_plants WHERE id IN (%s)'):format(table.concat(ids, ',')))
    end
end

MySQL.ready(function()
    local rows = MySQL.query.await('SELECT * FROM dg_cocaine_plants') or {}
    for _, row in ipairs(rows) do addPlant(row) end
    removeExpired()
    print(('[dg_cocaine] loaded %d plants'):format(#rows))
    TriggerClientEvent('dg_cocaine:reload', -1) -- clients that started before us ask again

    CreateThread(function()
        while true do
            Wait(5 * 60000) -- check for expired plants every 5 minutes
            removeExpired()
        end
    end)
end)

lib.callback.register('dg_cocaine:getPlants', function()
    local list = {}
    for _, p in pairs(Plants) do list[#list + 1] = clientPlant(p) end
    return list
end)

lib.callback.register('dg_cocaine:plant', function(src, coords)
    if type(coords) ~= 'vector3' then return false end
    if Planting[src] then return false end

    local owner = identifier(src)
    if not owner then return false end

    if count(src, Config.Items.seed) < 1 then return false, 'You have no seeds.' end
    if not near(src, coords) then return false, 'Too far away.' end
    if not inPlantZone(coords) then return false, 'Nothing would grow here.' end
    if (OwnerCount[owner] or 0) >= Config.Plants.maxPerPlayer then
        return false, ('You already have %d plants growing.'):format(Config.Plants.maxPerPlayer)
    end
    for _, p in pairs(Plants) do
        if #(p.coords - coords) < Config.Plants.minSpacing then return false, 'Too close to another plant.' end
    end
    if onCooldown(src, 'plant', Config.Plants.plantDuration) then return false end

    Planting[src] = true
    if not exports.ox_inventory:RemoveItem(src, Config.Items.seed, 1) then
        Planting[src] = nil
        return false, 'You have no seeds.'
    end

    local now = os.time()
    local id = MySQL.insert.await(
        'INSERT INTO dg_cocaine_plants (owner, x, y, z, planted_at) VALUES (?, ?, ?, ?, ?)',
        { owner, coords.x, coords.y, coords.z, now }
    )
    Planting[src] = nil

    if not id then
        exports.ox_inventory:AddItem(src, Config.Items.seed, 1)
        return false, 'Something went wrong. Your seed was returned.'
    end

    syncPlant(addPlant({ id = id, owner = owner, x = coords.x, y = coords.y, z = coords.z, planted_at = now, fertilised = 0 }))
    return true, 'Seed planted. Water it to start it growing.'
end)

lib.callback.register('dg_cocaine:water', function(src, id)
    local p = Plants[id]
    if not p or p.wateredAt then return false, 'It does not need water.' end
    if not near(src, p.coords) then return false, 'Too far away.' end
    if onCooldown(src, 'water', Config.Plants.waterDuration) then return false end

    if Config.Items.water and not exports.ox_inventory:RemoveItem(src, Config.Items.water, 1) then
        return false, 'You have no water.'
    end

    p.wateredAt = os.time()
    MySQL.update('UPDATE dg_cocaine_plants SET watered_at = ? WHERE id = ?', { p.wateredAt, p.id })
    syncPlant(p)
    return true, 'Watered. It will be ready in a few hours.'
end)

lib.callback.register('dg_cocaine:fertilise', function(src, id)
    local p = Plants[id]
    if not p or p.fertilised then return false, 'It is already fertilised.' end
    if not near(src, p.coords) then return false, 'Too far away.' end
    if onCooldown(src, 'fertilise', Config.Plants.fertDuration) then return false end

    if not exports.ox_inventory:RemoveItem(src, Config.Items.fertiliser, 1) then
        return false, 'You have no fertiliser.'
    end

    p.fertilised = true
    MySQL.update('UPDATE dg_cocaine_plants SET fertilised = 1 WHERE id = ?', { p.id })
    syncPlant(p)
    return true, 'Fertilised.'
end)

lib.callback.register('dg_cocaine:harvest', function(src, id)
    local p = Plants[id]
    if not p or isExpired(p) then return false, 'This plant is dead.' end
    if not isReady(p) then return false, 'It is not ready.' end
    if not near(src, p.coords) then return false, 'Too far away.' end

    local leaves = math.random(Config.Plants.leaves.min, Config.Plants.leaves.max)
    if p.fertilised then leaves = leaves + math.random(Config.Plants.fertBonus.min, Config.Plants.fertBonus.max) end

    if not exports.ox_inventory:CanCarryItem(src, Config.Items.leaf, leaves) then return false, 'You cannot carry that.' end
    if onCooldown(src, 'harvest', Config.Plants.harvestDuration) then return false end

    -- Remove from memory before anything that can yield, so nobody else can harvest it too
    removePlant(p)
    MySQL.update('DELETE FROM dg_cocaine_plants WHERE id = ?', { p.id })

    exports.ox_inventory:AddItem(src, Config.Items.leaf, leaves)
    return true, ('You harvested %d coca leaves.'):format(leaves)
end)

------------------------------------------------------------------------------------------------
-- Seed NPC (one request for everyone, rotated on a timer)
------------------------------------------------------------------------------------------------

local TradePool = {}

local function rotateRequest()
    if #TradePool == 0 then return end
    local entry = TradePool[math.random(#TradePool)]
    nextRequestId = nextRequestId + 1
    Request = {
        id = nextRequestId,
        item = entry.item,
        label = entry.label,
        amount = math.random(entry.amount.min, entry.amount.max),
        seeds = entry.seeds,
    }
end

CreateThread(function()
    for _, entry in ipairs(Config.SeedNpc.pool) do
        local data = exports.ox_inventory:Items(entry.item)
        if data then
            TradePool[#TradePool + 1] = { item = entry.item, label = data.label, amount = entry.amount, seeds = entry.seeds }
        else
            print(('^3[dg_cocaine] trade item "%s" does not exist in ox_inventory, skipped^7'):format(entry.item))
        end
    end

    while true do
        rotateRequest()
        Wait(Config.SeedNpc.rotateMinutes * 60000)
    end
end)

lib.callback.register('dg_cocaine:getRequest', function(src)
    if not Request then return end
    return { id = Request.id, item = Request.item, label = Request.label, amount = Request.amount }
end)

lib.callback.register('dg_cocaine:trade', function(src, requestId)
    if not Request or Request.id ~= requestId then return false, 'He wants something else now. Talk to him again.' end
    if not near(src, Config.SeedNpc.coords) then return false, 'Too far away.' end
    if count(src, Request.item) < Request.amount then
        return false, ('You need %dx %s.'):format(Request.amount, Request.label)
    end

    local seeds = math.random(Request.seeds.min, Request.seeds.max)
    if not exports.ox_inventory:CanCarryItem(src, Config.Items.seed, seeds) then return false, 'You cannot carry that.' end
    if onCooldown(src, 'trade', Config.SeedNpc.duration) then return false end

    if not exports.ox_inventory:RemoveItem(src, Request.item, Request.amount) then return false end
    exports.ox_inventory:AddItem(src, Config.Items.seed, seeds)
    return true, ('He hands you %d seeds.'):format(seeds)
end)

------------------------------------------------------------------------------------------------
-- Lab
------------------------------------------------------------------------------------------------

-- The client teleports itself only after this says yes. Exiting needs no check.
lib.callback.register('dg_cocaine:enterLab', function(src)
    local entrance = Config.LabEntrance
    if not entrance.enabled then return false end
    if not near(src, entrance.outside) then return false, 'Too far away.' end
    if entrance.requireKeycard and count(src, Config.Items.keycard) < 1 then
        return false, 'The door is locked. You need a keycard.'
    end
    return true
end)

lib.callback.register('dg_cocaine:craft', function(src, index)
    local recipe = Config.Recipes[index]
    if not recipe then return false end

    local station = Config.Lab[recipe.station]
    if not near(src, station.coords) then return false, 'Too far away.' end

    for _, input in ipairs(recipe.inputs) do
        if count(src, input.item) < input.count then return false, 'You are missing ingredients.' end
    end
    for _, output in ipairs(recipe.outputs) do
        if not exports.ox_inventory:CanCarryItem(src, output.item, output.count) then return false, 'You cannot carry that.' end
    end
    if onCooldown(src, 'craft', recipe.duration) then return false end

    local removed = {}
    for _, input in ipairs(recipe.inputs) do
        if not exports.ox_inventory:RemoveItem(src, input.item, input.count) then
            for _, r in ipairs(removed) do exports.ox_inventory:AddItem(src, r.item, r.count) end
            return false, 'You are missing ingredients.'
        end
        removed[#removed + 1] = input
    end

    for _, output in ipairs(recipe.outputs) do
        exports.ox_inventory:AddItem(src, output.item, output.count)
    end
    return true, 'Done.'
end)

------------------------------------------------------------------------------------------------
-- Bagging
------------------------------------------------------------------------------------------------

lib.callback.register('dg_cocaine:bag', function(src)
    local yield = GetBagYield(src)

    if count(src, Config.Items.brick) < 1 then return false, 'You have no brick.' end
    if count(src, Config.Items.scales) < 1 then return false, 'You need scales.' end
    if count(src, Config.Items.baggies) < yield then return false, ('You need %d baggies.'):format(yield) end
    if onCooldown(src, 'bag', Config.Bagging.duration) then return false end

    if not exports.ox_inventory:RemoveItem(src, Config.Items.brick, 1) then return false end
    if not exports.ox_inventory:RemoveItem(src, Config.Items.baggies, yield) then
        exports.ox_inventory:AddItem(src, Config.Items.brick, 1)
        return false, ('You need %d baggies.'):format(yield)
    end

    -- Bags weigh more than the brick + baggies that were removed? Then this can fail: give everything back.
    if not exports.ox_inventory:AddItem(src, Config.Items.bag, yield) then
        exports.ox_inventory:AddItem(src, Config.Items.brick, 1)
        exports.ox_inventory:AddItem(src, Config.Items.baggies, yield)
        return false, 'You cannot carry that.'
    end
    return true, ('You bagged the brick into %d bags.'):format(yield)
end)

AddEventHandler('playerDropped', function()
    Cooldowns[source] = nil
    Planting[source] = nil
end)
