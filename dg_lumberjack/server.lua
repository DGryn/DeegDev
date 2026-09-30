--[[
    dg_lumberjack - server.lua

    The server owns ALL gameplay state. Clients only draw it and ask for actions; every action is
    re-validated here (distance, inventory, capacity, state), and nothing the client reports as a
    count, position, tree state or result is trusted without a check.

    State                          Replicated to clients via
    Trees[id]                      GlobalState['lj:tree:<id>'] = { d = depleted, c = chopsLeft }
    GroundItems[id]                GlobalState['lj:item:<id>'] = { k = kind, x, y, z, h }  (nil = removed)
    Loads[plate]                   Entity(vehicle).state.ljLoad = { ['<pool>:<slot>'] = kind }
    PendingChops[src], MillQueue   server only

    API references (checked against source on GitHub, 2026-09-30):
      ox_lib callbacks       https://coxdocs.dev/ox_lib/Modules/Callback/Server
      ox_inventory           https://coxdocs.dev/ox_inventory/Functions/Server#getitemcount
      ESX xPlayer            https://docs.esx-framework.org/legacy/Server/Classes/xPlayer
      State bags             https://docs.fivem.net/docs/scripting-manual/networking/state-bags/
      entityRemoved          https://docs.fivem.net/docs/scripting-reference/events/server-events/#entityremoved
      CreateVehicleServerSetter https://docs.fivem.net/natives/?_0x6AE51D4B
      Load/SaveResourceFile  https://docs.fivem.net/natives/?_0x76A9EE1F / ?_0xA09E7E7B
]]

local ESX = exports['es_extended']:getSharedObject() -- https://docs.esx-framework.org/legacy/Server/Functions/getSharedObject
local RESOURCE = GetCurrentResourceName()

-- Model hashes can come back signed or unsigned depending on the native; normalise before comparing.
local function hash32(h) return h & 0xFFFFFFFF end

local TruckByHash = {}
for name in pairs(Config.Trucks) do TruckByHash[hash32(joaat(name))] = name end

local Trees = {}        -- [treeId] = { chopsLeft, depleted, respawnAt }
local GroundItems = {}  -- [itemId] = { kind, coords, heading, treeId?, createdAt }
local Loads = {}        -- [plate]  = { entity, name, slots = { ['log:1'] = 'log', ... } }
local PendingChops = {} -- [src]    = { treeId, token, startedAt }
local MillQueue = {}    -- { { finishAt, planks } }
local DepotTrucks = {}  -- [src]    = vehicle entity
local nextItemId = 0

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------

local function trim(s) return (s or ''):gsub('^%s+', ''):gsub('%s+$', '') end

local function pedCoords(src) return GetEntityCoords(GetPlayerPed(src)) end

-- Horizontal distance check with a vertical cap (config Z values can be rough; see Config.MaxHeightDelta).
local function near(a, b, radius)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= radius * radius and math.abs(a.z - b.z) <= Config.MaxHeightDelta
end

-- Horizontal-only check for trees and ground items: their Z comes from config and can be rough
-- (the client snaps the props to the ground), so a vertical cap would reject valid actions.
local function near2D(a, b, radius)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= radius * radius
end

local function debugLog(src, msg)
    if Config.Debug then print(('[dg_lumberjack] %s (%d): %s'):format(GetPlayerName(src) or '?', src, msg)) end
end

local function jobAllowed(src)
    if not Config.Job then return true end
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getJob().name == Config.Job
end

------------------------------------------------------------------------------------------------
-- Trees
------------------------------------------------------------------------------------------------

local function syncTree(id)
    local t = Trees[id]
    GlobalState:set(('lj:tree:%d'):format(id), { d = t.depleted, c = t.chopsLeft }, true)
end

local function resetTree(id)
    Trees[id] = { chopsLeft = Config.Trees.chopsPerTree, depleted = false }
    syncTree(id)
end

------------------------------------------------------------------------------------------------
-- Ground items (felled logs and milled planks lying in the world)
------------------------------------------------------------------------------------------------

local function addGroundItem(kind, coords, heading, treeId)
    nextItemId = nextItemId + 1
    local id = nextItemId
    GroundItems[id] = { kind = kind, coords = coords, heading = heading, treeId = treeId, createdAt = os.time() }
    GlobalState:set(('lj:item:%d'):format(id), { k = kind, x = coords.x, y = coords.y, z = coords.z, h = heading }, true)
    GlobalState:set('lj:maxItemId', id, true)
    return id
end

local function removeGroundItem(id)
    GroundItems[id] = nil
    GlobalState:set(('lj:item:%d'):format(id), nil, true)
end

------------------------------------------------------------------------------------------------
-- Truck loads (keyed by plate, tied to the specific vehicle entity)
------------------------------------------------------------------------------------------------

-- Resolves a client-sent netId to a configured job truck and its load record.
-- Returns vehicle, load, or nil + reason.
local function resolveTruck(netId)
    if type(netId) ~= 'number' then return nil, 'Invalid vehicle.' end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then
        return nil, 'Invalid vehicle.'
    end

    local name = TruckByHash[hash32(GetEntityModel(veh))]
    if not name then return nil, 'That vehicle cannot haul timber.' end

    local plate = trim(GetVehicleNumberPlateText(veh))
    local load = Loads[plate]
    if load and load.entity ~= veh then
        -- Same plate on a different entity: keep the original if it still exists (duplicate plate).
        if DoesEntityExist(load.entity) then return nil, 'Duplicate plate; this truck cannot be used.' end
        load = nil
    end
    if not load then
        load = { entity = veh, name = name, slots = {} }
        Loads[plate] = load
    end
    return veh, load
end

local function syncLoad(veh, load)
    Entity(veh).state:set('ljLoad', load.slots, true)
end

-- Picks a free attachment slot for `kind`, enforcing the pool max and the truck's weight limit.
local function findFreeSlot(load, kind)
    local cfg = Config.Trucks[load.name]
    local poolName = type(cfg[kind]) == 'string' and cfg[kind] or kind
    local pool = cfg[poolName]
    if type(pool) ~= 'table' then return nil, 'This truck cannot carry that.' end

    local used, weight = 0, 0
    local prefix = poolName .. ':'
    for key, k in pairs(load.slots) do
        weight = weight + Config.Items[k].weight
        if key:sub(1, #prefix) == prefix then used = used + 1 end
    end

    local capacity = math.min(pool.max, #pool.points)
    if used >= capacity then return nil, 'The truck bed is full.' end
    if weight + Config.Items[kind].weight > cfg.maxWeight then return nil, 'That would overload the truck.' end

    for i = 1, capacity do
        local key = prefix .. i
        if not load.slots[key] then return key end
    end
    return nil, 'The truck bed is full.'
end

------------------------------------------------------------------------------------------------
-- XP (JSON file)
------------------------------------------------------------------------------------------------

local XP = json.decode(LoadResourceFile(RESOURCE, Config.XP.file) or '{}') or {}
local xpDirty = false

local function saveXP()
    if not xpDirty then return end
    SaveResourceFile(RESOURCE, Config.XP.file, json.encode(XP), -1)
    xpDirty = false
end

local function addXP(identifier, amount)
    XP[identifier] = (XP[identifier] or 0) + amount
    xpDirty = true
    return XP[identifier]
end

-- exports.dg_lumberjack:GetXP(identifier) -> number. Read-only accessor for other resources.
exports('GetXP', function(identifier) return XP[identifier] or 0 end)

------------------------------------------------------------------------------------------------
-- Callbacks: chopping
------------------------------------------------------------------------------------------------

-- lj:startChop(treeId) -> ok, token|errorMsg, difficulty, inputs
-- Validates the chop can start and issues a one-time token. The server chooses the skill check
-- difficulty so the client cannot request an easier one.
lib.callback.register('lj:startChop', function(src, treeId)
    local cfg, tree = Config.Trees.list[treeId], Trees[treeId]
    if not cfg or not tree then return false, 'Invalid tree.' end
    if tree.depleted then return false, 'This tree has already been felled.' end
    if not jobAllowed(src) then return false, 'You are not employed as a lumberjack.' end
    if not near2D(pedCoords(src), cfg.coords, Config.Chop.maxDistance + Config.DistanceTolerance) then
        return false, 'You are too far from the tree.'
    end
    if exports.ox_inventory:GetItemCount(src, Config.HatchetItem) < 1 then
        return false, 'You need a hatchet.'
    end

    local pending = PendingChops[src]
    if pending and GetGameTimer() - pending.startedAt < Config.Chop.duration + Config.Chop.maxExtra then
        return false, 'You are already chopping.'
    end

    local token = ('%08x%08x'):format(math.random(0, 0x7FFFFFFF), GetGameTimer() & 0xFFFFFFFF)
    PendingChops[src] = { treeId = treeId, token = token, startedAt = GetGameTimer() }
    return true, token, Config.SkillCheck.difficulty, Config.SkillCheck.inputs
end)

-- lj:cancelChop — client cancelled the progress bar; discard the pending attempt (no damage dealt).
RegisterNetEvent('lj:cancelChop', function()
    PendingChops[source] = nil
end)

-- lj:finishChop(token, success) -> ok, yieldedLog|errorMsg, chopsLeft
-- Consumes the token. Rejects results that arrive too early (skipped progress bar), too late
-- (expired) or without a matching token. A reported failure still damages the tree.
-- Note: the server cannot prove the minigame itself was not automated client-side; this bounds
-- what a cheater can do to "one plausible attempt per token, at normal speed".
lib.callback.register('lj:finishChop', function(src, token, success)
    local pending = PendingChops[src]
    PendingChops[src] = nil
    if not pending or type(token) ~= 'string' or pending.token ~= token then
        return false, 'Chop attempt not recognised.'
    end

    local elapsed = GetGameTimer() - pending.startedAt
    if elapsed < Config.Chop.duration * Config.Chop.minFraction then return false, 'Too fast.' end
    if elapsed > Config.Chop.duration + Config.Chop.maxExtra then return false, 'Chop attempt expired.' end

    local id = pending.treeId
    local tree, cfg = Trees[id], Config.Trees.list[id]
    if tree.depleted then return false, 'This tree has already been felled.' end
    if not near2D(pedCoords(src), cfg.coords, Config.Chop.maxDistance + Config.DistanceTolerance) then
        return false, 'You moved away from the tree.'
    end

    tree.chopsLeft = tree.chopsLeft - 1

    local yielded = success == true
    if yielded then
        local angle = math.random() * 2 * math.pi
        local dist = Config.Trees.logDrop.min + math.random() * (Config.Trees.logDrop.max - Config.Trees.logDrop.min)
        local c = cfg.coords
        addGroundItem('log', vec3(c.x + math.cos(angle) * dist, c.y + math.sin(angle) * dist, c.z), math.random(0, 359) + 0.0, id)
    end

    if tree.chopsLeft <= 0 then
        tree.depleted = true
        tree.respawnAt = os.time() + math.random(Config.Trees.respawnTime.min, Config.Trees.respawnTime.max)
        -- Tells clients to play the fall animation, away from the player who felled it.
        TriggerClientEvent('lj:client:treeFelled', -1, id, src)
    end
    syncTree(id)

    return true, yielded, tree.chopsLeft
end)

------------------------------------------------------------------------------------------------
-- Callbacks: ground items / truck bed
------------------------------------------------------------------------------------------------

-- lj:getGroundItems() -> array of { id, k, x, y, z, h }
-- Snapshot for clients that just started (late join / resource restart). Later changes arrive
-- through the GlobalState 'lj:item:<id>' keys.
lib.callback.register('lj:getGroundItems', function()
    local list = {}
    for id, item in pairs(GroundItems) do
        list[#list + 1] = { id = id, k = item.kind, x = item.coords.x, y = item.coords.y, z = item.coords.z, h = item.heading }
    end
    return list
end)

-- lj:loadItem(itemId, truckNetId) -> ok, msg, stale
-- Moves a ground log/plank onto a free attachment slot of the truck. This handler never yields,
-- so validation + removal are atomic: two players racing for one item → exactly one succeeds.
-- `stale = true` tells the client the item no longer exists so it can drop its local copy.
lib.callback.register('lj:loadItem', function(src, itemId, netId)
    local ok, msg, stale = (function()
        local item = GroundItems[itemId]
        if not item then return false, 'Someone already took that.', true end
        if not jobAllowed(src) then return false, 'You are not employed as a lumberjack.' end

        if not near2D(pedCoords(src), item.coords, Config.Load.maxDistance) then
            return false, 'You are too far away.'
        end

        local veh, load = resolveTruck(netId)
        if not veh then return false, load end
        if not near2D(GetEntityCoords(veh), item.coords, Config.TruckRange + Config.DistanceTolerance) then
            return false, 'Park the truck closer.'
        end

        local key, err = findFreeSlot(load, item.kind)
        if not key then return false, err end

        removeGroundItem(itemId)
        load.slots[key] = item.kind
        syncLoad(veh, load)
        debugLog(src, ('loaded %s #%d into slot %s of %s'):format(item.kind, itemId, key, load.name))
        return true, ('Loaded %s onto the truck.'):format(Config.Items[item.kind].label)
    end)()

    if not ok then debugLog(src, ('load item #%s rejected: %s'):format(tostring(itemId), tostring(msg))) end
    return ok, msg, stale
end)

------------------------------------------------------------------------------------------------
-- Callbacks: mill
------------------------------------------------------------------------------------------------

-- lj:unloadLog(truckNetId, slotKey?) -> ok, msg
-- Removes one tracked log from the truck at the mill and queues it for processing.
-- slotKey is optional: when targeting the truck body instead of a specific log, any log is taken.
-- Broadcasts lj:client:conveyor so nearby clients play the conveyor visual.
lib.callback.register('lj:unloadLog', function(src, netId, key)
    if key ~= nil and type(key) ~= 'string' then return false, 'Invalid slot.' end
    if not near(pedCoords(src), Config.Mill.input, Config.Mill.radius) then
        return false, 'Go to the log drop-off at the mill conveyor.'
    end

    local veh, load = resolveTruck(netId)
    if not veh then return false, load end
    if not near(GetEntityCoords(veh), Config.Mill.input, Config.Mill.truckRadius) then
        return false, 'Park the truck closer to the conveyor.'
    end
    if key == nil then
        for k, kind in pairs(load.slots) do
            if kind == 'log' then key = k break end
        end
        if not key then return false, 'There are no logs on this truck.' end
    elseif load.slots[key] ~= 'log' then
        return false, 'There is no log there.'
    end

    load.slots[key] = nil
    syncLoad(veh, load)

    MillQueue[#MillQueue + 1] = { finishAt = os.time() + Config.Mill.processTime, planks = Config.Mill.planksPerLog }
    TriggerClientEvent('lj:client:conveyor', -1, Config.Mill.processTime)
    return true, ('Log on the conveyor. Planks ready in %ds.'):format(Config.Mill.processTime)
end)

------------------------------------------------------------------------------------------------
-- Callbacks: delivery
------------------------------------------------------------------------------------------------

-- lj:deliver(truckNetId) -> ok, count|errorMsg, pay, xpGained, xpTotal
-- Counts planks the SERVER has tracked on this truck, removes them and pays count * rate.
lib.callback.register('lj:deliver', function(src, netId)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false, 'Player not loaded.' end
    if not jobAllowed(src) then return false, 'You are not employed as a lumberjack.' end
    if not near(pedCoords(src), Config.Delivery.coords, Config.Delivery.radius) then
        return false, 'You are not at the delivery point.'
    end

    local veh, load = resolveTruck(netId)
    if not veh then return false, load end
    if not near(GetEntityCoords(veh), Config.Delivery.coords, Config.Delivery.radius) then
        return false, 'Bring the truck to the delivery point.'
    end

    local count = 0
    for key, kind in pairs(load.slots) do
        if kind == 'plank' then
            load.slots[key] = nil
            count = count + 1
        end
    end
    if count == 0 then return false, 'There are no planks on this truck.' end
    syncLoad(veh, load)

    local pay = count * Config.Reward.perPlank
    xPlayer.addAccountMoney(Config.Reward.account, pay, 'Lumberjack delivery')
    local xp = count * Config.Reward.xpPerPlank
    local total = addXP(xPlayer.identifier, xp)
    return true, count, pay, xp, total
end)

------------------------------------------------------------------------------------------------
-- Callbacks: depot
------------------------------------------------------------------------------------------------

local function spawnBlocked(coords)
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - coords) < 3.0 then return true end
    end
    return false
end

-- lj:spawnTruck(truckName) -> ok, msg
-- Spawns a configured job truck server-side (so the server knows the entity/plate from birth)
-- and seats the player in it. One depot truck per player.
lib.callback.register('lj:spawnTruck', function(src, name)
    local cfg = Config.Trucks[name]
    if not cfg then return false, 'Unknown truck.' end
    if not jobAllowed(src) then return false, 'You are not employed as a lumberjack.' end
    if not near(pedCoords(src), Config.Depot.spawn, Config.Depot.returnRadius + 10.0) then
        return false, 'You are too far from the depot.'
    end
    if DepotTrucks[src] and DoesEntityExist(DepotTrucks[src]) then
        return false, 'You already have a job truck out.'
    end
    local sp = Config.Depot.spawn
    if spawnBlocked(sp.xyz) then return false, 'The spawn point is blocked.' end

    local veh = CreateVehicleServerSetter(joaat(name), cfg.type or 'automobile', sp.x, sp.y, sp.z, sp.w)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) do
        if GetGameTimer() > timeout then return false, 'Truck failed to spawn.' end
        Wait(0)
    end

    local plate = ('%s%06d'):format(Config.Depot.platePrefix, math.random(0, 999999)):sub(1, 8)
    SetVehicleNumberPlateText(veh, plate)
    DepotTrucks[src] = veh

    -- Wait for a client to take network ownership before seating the ped.
    timeout = GetGameTimer() + 3000
    while NetworkGetEntityOwner(veh) == -1 and GetGameTimer() < timeout do Wait(0) end
    SetPedIntoVehicle(GetPlayerPed(src), veh, -1)

    -- Vehicle keys: if your server uses a key resource, give keys for `plate` here.
    return true, ('%s ready (plate %s).'):format(cfg.label, plate)
end)

-- lj:returnTruck() -> ok, msg
-- Deletes the player's depot truck if it is parked at the depot. Anything still on it is lost.
lib.callback.register('lj:returnTruck', function(src)
    local veh = DepotTrucks[src]
    if not veh or not DoesEntityExist(veh) then
        DepotTrucks[src] = nil
        return false, 'You have no job truck out.'
    end
    if not near(GetEntityCoords(veh), Config.Depot.spawn, Config.Depot.returnRadius) then
        return false, 'Park the truck at the depot first.'
    end
    DeleteEntity(veh) -- entityRemoved below clears its load record
    DepotTrucks[src] = nil
    return true, 'Truck returned.'
end)

------------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------------

-- entityRemoved (OneSync server event): a vehicle was deleted/despawned → drop its load record so
-- the plate cannot later "inherit" logs that no longer exist. Clients delete their attached props
-- on their own when the vehicle entity disappears.
AddEventHandler('entityRemoved', function(entity)
    for plate, load in pairs(Loads) do
        if load.entity == entity then Loads[plate] = nil end
    end
    for src, veh in pairs(DepotTrucks) do
        if veh == entity then DepotTrucks[src] = nil end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    PendingChops[src] = nil
    local veh = DepotTrucks[src]
    if veh and Config.Depot.deleteOnDrop and DoesEntityExist(veh) then DeleteEntity(veh) end
    DepotTrucks[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE then saveXP() end
end)

-- Init: trees are fresh after every restart (by design); clear ground-item keys left in
-- GlobalState by a previous run of this resource during the same server session.
CreateThread(function()
    for i = 1, GlobalState['lj:maxItemId'] or 0 do
        GlobalState:set(('lj:item:%d'):format(i), nil, true)
    end
    GlobalState:set('lj:maxItemId', 0, true)

    for id in ipairs(Config.Trees.list) do resetTree(id) end
end)

-- Ticker: tree respawns, mill output, ground item expiry, XP flush.
CreateThread(function()
    local lastSave = os.time()
    while true do
        Wait(1000)
        local now = os.time()

        for id, tree in pairs(Trees) do
            if tree.depleted and now >= tree.respawnAt then resetTree(id) end
        end

        for i = #MillQueue, 1, -1 do
            local job = MillQueue[i]
            if now >= job.finishAt then
                table.remove(MillQueue, i)
                local o = Config.Mill.output
                for _ = 1, job.planks do
                    local a, r = math.random() * 2 * math.pi, math.random() * Config.Mill.outputSpread
                    addGroundItem('plank', vec3(o.x + math.cos(a) * r, o.y + math.sin(a) * r, o.z), o.w)
                end
            end
        end

        if Config.GroundItemLifetime > 0 then
            for id, item in pairs(GroundItems) do
                if now - item.createdAt >= Config.GroundItemLifetime then removeGroundItem(id) end
            end
        end

        if now - lastSave >= Config.XP.saveInterval then
            saveXP()
            lastSave = now
        end
    end
end)
