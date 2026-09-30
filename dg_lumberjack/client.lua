--[[
    dg_lumberjack - client.lua

    Draw-only client. Every tree, ground log/plank and truck-bed prop is a LOCAL (non-networked)
    object built from server state:
      GlobalState['lj:tree:<id>']   → standing tree / falling animation / stump
      GlobalState['lj:item:<id>']   → ground log or plank (spawned only within Config.RenderDistance)
      Entity(veh).state.ljLoad      → props attached to that truck's preset attachment points
    Because each client rebuilds from the same state, late joiners and players driving into range
    see exactly what everyone else sees. All actions go through lib.callback to the server.

    API references (checked against source on GitHub, 2026-09-30):
      lib.skillCheck    https://coxdocs.dev/ox_lib/Modules/Interface/Client/skillcheck
      lib.progressBar   https://coxdocs.dev/ox_lib/Modules/Interface/Client/progress
      lib.callback      https://coxdocs.dev/ox_lib/Modules/Callback/Client
      lib.points        https://coxdocs.dev/ox_lib/Modules/Points/Client
      lib.getNearbyVehicles https://coxdocs.dev/ox_lib/Modules/GetNearbyVehicles/Client
      ox_target         https://coxdocs.dev/ox_target/Client  (addLocalEntity, addGlobalVehicle, addSphereZone)
      State bags        https://docs.fivem.net/docs/scripting-manual/networking/state-bags/
      AttachEntityToEntity https://docs.fivem.net/natives/?_0x6B9BBD38AB0796DF
]]

local function hash32(h) return h & 0xFFFFFFFF end

local TruckByHash = {}
for name in pairs(Config.Trucks) do TruckByHash[hash32(joaat(name))] = name end

local function truckName(veh) return TruckByHash[hash32(GetEntityModel(veh))] end

local Trees = {}      -- [treeId] = { state, entity, isStump }
local Items = {}      -- [itemId] = { data, point, entity }
local TruckProps = {} -- [vehicle] = { sig, props = { [slotKey] = object } }
local PropMeta = {}   -- [object] = { veh, key, kind }  (for truck-bed prop target options)
local ModelOk = {}    -- [hash] = true once loaded
local busy = false

local function notify(msg, kind)
    lib.notify({ title = 'Lumberjack', description = msg, type = kind or 'inform' })
end

local function loadModel(model)
    if ModelOk[model] then return true end
    if not IsModelInCdimage(model) then
        print(('^1[dg_lumberjack] model %s is not valid, check config.lua^7'):format(model))
        return false
    end
    lib.requestModel(model)
    ModelOk[model] = true
    return true
end

local function createLocalObject(model, x, y, z, heading)
    local obj = CreateObjectNoOffset(model, x, y, z, false, false, false) -- isNetwork = false
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    return obj
end

local function deleteObject(obj)
    if obj and DoesEntityExist(obj) then
        exports.ox_target:removeLocalEntity(obj)
        DeleteEntity(obj)
    end
end

local function actionProgress(label)
    return lib.progressBar({
        duration = Config.Load.duration,
        label = label,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = Config.Load.anim.dict, clip = Config.Load.anim.clip },
    })
end

-- Closest configured job truck within Config.TruckRange of `coords`.
local function closestTruck(coords)
    local best, bestDist
    for _, v in ipairs(lib.getNearbyVehicles(coords, Config.TruckRange, true)) do
        if truckName(v.vehicle) then
            local d = #(coords - v.coords)
            if not bestDist or d < bestDist then best, bestDist = v.vehicle, d end
        end
    end
    return best
end

------------------------------------------------------------------------------------------------
-- Trees
------------------------------------------------------------------------------------------------

local chop -- forward declaration

local function despawnTree(id)
    local tree = Trees[id]
    deleteObject(tree.entity)
    tree.entity = nil
end

local function spawnTree(id)
    local tree, cfg = Trees[id], Config.Trees.list[id]
    despawnTree(id)

    local depleted = tree.state and tree.state.d
    local model = depleted and Config.Trees.stumpModel or (cfg.model or Config.Trees.model)
    if not loadModel(model) then return end

    local c = cfg.coords
    local z = c.z
    if Config.Trees.snapToGround then
        local found, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 50.0, false)
        if found then z = groundZ end
    end

    tree.entity = createLocalObject(model, c.x, c.y, z, c.w)
    tree.isStump = depleted

    if not depleted then
        exports.ox_target:addLocalEntity(tree.entity, {
            {
                name = 'lj_chop',
                label = 'Chop tree',
                icon = 'fa-solid fa-tree',
                distance = Config.InteractDistance,
                canInteract = function()
                    return not busy and hash32(GetSelectedPedWeapon(cache.ped)) == hash32(Config.HatchetHash)
                end,
                onSelect = function() chop(id) end,
            },
        })
    end
end

-- Tips the standing tree over, then swaps it for the stump.
local function fellTree(id)
    local tree = Trees[id]
    local obj = tree.entity
    if not obj or tree.isStump or not DoesEntityExist(obj) then return spawnTree(id) end

    exports.ox_target:removeLocalEntity(obj)
    CreateThread(function()
        local heading = GetEntityHeading(obj)
        local start = GetGameTimer()
        while DoesEntityExist(obj) do
            local p = math.min((GetGameTimer() - start) / Config.Trees.fallDuration, 1.0)
            SetEntityRotation(obj, p * p * Config.Trees.fallAngle, 0.0, heading, 2, false) -- ease-in, like gravity
            if p >= 1.0 then break end
            Wait(0)
        end
        Wait(Config.Trees.lyingTime)
        -- Only replace if this is still the tree's current prop (player didn't leave range / tree didn't respawn).
        if Trees[id].entity == obj then spawnTree(id) end
    end)
end

local function onTreeState(id, value)
    local tree = Trees[id]
    if not tree then return end
    local wasDepleted = tree.state and tree.state.d
    tree.state = value
    if not tree.entity then return end -- out of range; lib.points onEnter will build the right model

    local isDepleted = value and value.d
    if isDepleted and not wasDepleted then
        fellTree(id)
    elseif not isDepleted and wasDepleted then
        spawnTree(id) -- respawned
    end
end

-- One chop attempt: server token → progress bar → skill check → server validates and applies.
function chop(id)
    if busy then return end
    busy = true

    local ok, token, difficulty, inputs = lib.callback.await('lj:startChop', false, id)
    if not ok then
        busy = false
        return notify(token or 'You cannot chop this right now.', 'error')
    end

    local tree = Trees[id].entity
    if tree then
        TaskTurnPedToFaceEntity(cache.ped, tree, 600)
        Wait(600)
    end

    local anim = Config.Chop.anim
    local finished = lib.progressBar({
        duration = Config.Chop.duration,
        label = 'Chopping...',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = anim.dict, clip = anim.clip, flag = 1 },
    })
    if not finished then
        TriggerServerEvent('lj:cancelChop')
        busy = false
        return
    end

    -- Keep swinging while the skill check is on screen.
    lib.requestAnimDict(anim.dict)
    TaskPlayAnim(cache.ped, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    local success = lib.skillCheck(difficulty, inputs)
    ClearPedTasks(cache.ped)

    local accepted, yielded, chopsLeft = lib.callback.await('lj:finishChop', false, token, success == true)
    busy = false

    if not accepted then return notify(yielded, 'error') end
    if yielded then
        notify('A log drops to the ground.', 'success')
    else
        notify('Bad swing, no usable log.', 'error')
    end
    if chopsLeft <= 0 then notify('Timber! The tree is down.', 'inform') end
end

------------------------------------------------------------------------------------------------
-- Ground items (logs / planks)
------------------------------------------------------------------------------------------------

local removeItem -- forward declaration

local function despawnItem(item)
    deleteObject(item.entity)
    item.entity = nil
end

local function loadItem(id)
    local item = Items[id]
    if busy or not item or not item.entity then return end

    local truck = closestTruck(GetEntityCoords(item.entity))
    if not truck then return notify('Park a job truck closer first.', 'error') end

    busy = true
    if actionProgress('Loading...') then
        local ok, msg, stale = lib.callback.await('lj:loadItem', false, id, NetworkGetNetworkIdFromEntity(truck))
        notify(msg, ok and 'success' or 'error')
        if stale then removeItem(id) end
    end
    busy = false
end

local function spawnItem(id)
    local item = Items[id]
    if not item or item.entity then return end
    local d = item.data
    local cfg = Config.Items[d.k]
    if not cfg or not loadModel(cfg.model) then return end

    local obj = CreateObjectNoOffset(cfg.model, d.x, d.y, d.z, false, false, false)
    SetEntityHeading(obj, d.h or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    item.entity = obj

    exports.ox_target:addLocalEntity(obj, {
        {
            name = 'lj_load',
            label = ('Load %s onto truck'):format(cfg.label),
            icon = 'fa-solid fa-truck-ramp-box',
            distance = Config.InteractDistance,
            canInteract = function() return not busy end,
            onSelect = function() loadItem(id) end,
        },
    })
end

function removeItem(id)
    local item = Items[id]
    if not item then return end
    despawnItem(item)
    item.point:remove()
    Items[id] = nil
end

local function addItem(id, data)
    removeItem(id)
    local item = { data = data }
    Items[id] = item
    item.point = lib.points.new({
        coords = vec3(data.x, data.y, data.z),
        distance = Config.RenderDistance,
        onEnter = function() spawnItem(id) end,
        onExit = function() despawnItem(item) end,
    })
end

------------------------------------------------------------------------------------------------
-- Truck bed props
------------------------------------------------------------------------------------------------

local function loadSignature(slots)
    if not slots then return '' end
    local keys = {}
    for key, kind in pairs(slots) do keys[#keys + 1] = key .. '=' .. kind end
    table.sort(keys)
    return table.concat(keys, ',')
end

local function clearTruck(veh)
    local entry = TruckProps[veh]
    if not entry then return end
    for _, obj in pairs(entry.props) do
        PropMeta[obj] = nil
        deleteObject(obj)
    end
    TruckProps[veh] = nil
end

local truckPropOptions -- defined below (needs unload/deliver functions)

-- (Re)builds the attached props for `veh` from its replicated load. No yields: models are preloaded.
local function buildTruck(veh, slots)
    local name = truckName(veh)
    if not name then return end
    local sig = loadSignature(slots)
    local entry = TruckProps[veh]
    if entry and entry.sig == sig then return end
    clearTruck(veh)
    if sig == '' then return end

    local cfg = Config.Trucks[name]
    entry = { sig = sig, props = {} }
    TruckProps[veh] = entry

    local vc = GetEntityCoords(veh)
    for key, kind in pairs(slots) do
        local poolName, index = key:match('^(%a+):(%d+)$')
        local pool = poolName and cfg[poolName]
        local point = type(pool) == 'table' and pool.points[tonumber(index)]
        local item = Config.Items[kind]
        if point and item and ModelOk[item.model] then
            local obj = CreateObjectNoOffset(item.model, vc.x, vc.y, vc.z, false, false, false)
            SetEntityCollision(obj, false, false)
            AttachEntityToEntity(obj, veh, 0,
                point.offset.x, point.offset.y, point.offset.z,
                point.rot.x, point.rot.y, point.rot.z,
                false, false, false, false, 2, true)
            entry.props[key] = obj
            PropMeta[obj] = { veh = veh, key = key, kind = kind }
            exports.ox_target:addLocalEntity(obj, truckPropOptions)
        end
    end
end

-- Immediate update when the server changes a truck's load (only fires for vehicles we have).
AddStateBagChangeHandler('ljLoad', nil, function(bagName, _, value)
    local veh = GetEntityFromStateBagName(bagName)
    if veh == 0 then return end
    buildTruck(veh, value)
end)

local function unloadLog(prop)
    local meta = PropMeta[prop]
    if busy or not meta then return end
    busy = true
    if actionProgress('Unloading onto conveyor...') then
        local ok, msg = lib.callback.await('lj:unloadLog', false, NetworkGetNetworkIdFromEntity(meta.veh), meta.key)
        notify(msg, ok and 'success' or 'error')
    end
    busy = false
end

local function hasPlanks(veh)
    local slots = Entity(veh).state.ljLoad
    if not slots then return false end
    for _, kind in pairs(slots) do
        if kind == 'plank' then return true end
    end
    return false
end

local function atDelivery()
    return #(GetEntityCoords(cache.ped) - Config.Delivery.coords) < Config.Delivery.radius
end

local function deliver(veh)
    if busy or not veh then return end
    busy = true
    if actionProgress('Handing over planks...') then
        local ok, count, pay, xp, total = lib.callback.await('lj:deliver', false, NetworkGetNetworkIdFromEntity(veh))
        if ok then
            notify(('Delivered %d planks: $%d, +%d XP (total %d).'):format(count, pay, xp, total), 'success')
        else
            notify(count, 'error')
        end
    end
    busy = false
end

truckPropOptions = {
    {
        name = 'lj_unload_log',
        label = 'Unload log onto conveyor',
        icon = 'fa-solid fa-industry',
        distance = Config.InteractDistance,
        canInteract = function(entity)
            local meta = PropMeta[entity]
            return not busy and meta and meta.kind == 'log'
                and #(GetEntityCoords(cache.ped) - Config.Mill.input) < Config.Mill.radius
        end,
        onSelect = function(data) unloadLog(data.entity) end,
    },
    {
        name = 'lj_deliver_prop',
        label = 'Deliver planks',
        icon = 'fa-solid fa-hand-holding-dollar',
        distance = Config.InteractDistance,
        canInteract = function(entity)
            local meta = PropMeta[entity]
            return not busy and meta and meta.kind == 'plank' and atDelivery()
        end,
        onSelect = function(data) deliver(PropMeta[data.entity] and PropMeta[data.entity].veh) end,
    },
}

-- The truck body itself also offers delivery (props may not cover every angle).
exports.ox_target:addGlobalVehicle({
    {
        name = 'lj_deliver',
        label = 'Deliver planks',
        icon = 'fa-solid fa-hand-holding-dollar',
        distance = 3.0,
        canInteract = function(entity)
            return not busy and truckName(entity) and atDelivery() and hasPlanks(entity)
        end,
        onSelect = function(data) deliver(data.entity) end,
    },
})

-- Reconcile loop: rebuilds trucks that streamed in (late join / drove into range) and deletes
-- props whose vehicle was deleted or left range. The state bag is always the source of truth.
CreateThread(function()
    while true do
        local coords = GetEntityCoords(cache.ped)
        for veh in pairs(TruckProps) do
            if not DoesEntityExist(veh) or #(GetEntityCoords(veh) - coords) > Config.RenderDistance * 1.5 then
                clearTruck(veh)
            end
        end
        for _, v in ipairs(lib.getNearbyVehicles(coords, Config.RenderDistance, true)) do
            if truckName(v.vehicle) then buildTruck(v.vehicle, Entity(v.vehicle).state.ljLoad) end
        end
        Wait(1000)
    end
end)

------------------------------------------------------------------------------------------------
-- Mill conveyor visual
------------------------------------------------------------------------------------------------

-- lj:client:conveyor(seconds) — from server on every accepted unload. Purely cosmetic: slides a
-- local log from the conveyor input to its end over the processing time.
RegisterNetEvent('lj:client:conveyor', function(seconds)
    local from, to = Config.Mill.input, Config.Mill.conveyorEnd
    if #(GetEntityCoords(cache.ped) - from) > Config.RenderDistance then return end
    local model = Config.Items.log.model
    if not ModelOk[model] then return end

    local obj = createLocalObject(model, from.x, from.y, from.z, Config.Mill.conveyorHeading)
    SetEntityCollision(obj, false, false)
    local start, ms = GetGameTimer(), seconds * 1000
    while DoesEntityExist(obj) do
        local p = math.min((GetGameTimer() - start) / ms, 1.0)
        SetEntityCoordsNoOffset(obj, from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p, from.z + (to.z - from.z) * p, false, false, false)
        if p >= 1.0 then break end
        Wait(0)
    end
    DeleteEntity(obj)
end)

------------------------------------------------------------------------------------------------
-- Depot
------------------------------------------------------------------------------------------------

local function depotOptions()
    local options = {}
    for name, cfg in pairs(Config.Trucks) do
        options[#options + 1] = {
            name = 'lj_take_' .. name,
            label = 'Take out ' .. cfg.label,
            icon = 'fa-solid fa-truck-pickup',
            distance = Config.InteractDistance,
            onSelect = function()
                local ok, msg = lib.callback.await('lj:spawnTruck', false, name)
                notify(msg, ok and 'success' or 'error')
            end,
        }
    end
    options[#options + 1] = {
        name = 'lj_return',
        label = 'Return job truck',
        icon = 'fa-solid fa-rotate-left',
        distance = Config.InteractDistance,
        onSelect = function()
            local ok, msg = lib.callback.await('lj:returnTruck', false)
            notify(msg, ok and 'success' or 'error')
        end,
    }
    return options
end

local function setupDepot()
    local ped = Config.Depot.ped
    if not ped then
        exports.ox_target:addSphereZone({
            coords = Config.Depot.spawn.xyz,
            radius = Config.Depot.zoneRadius,
            debug = Config.Debug,
            options = depotOptions(),
        })
        return
    end

    local entity
    lib.points.new({
        coords = ped.coords.xyz,
        distance = Config.RenderDistance,
        onEnter = function()
            if not loadModel(ped.model) then return end
            local c = ped.coords
            entity = CreatePed(4, ped.model, c.x, c.y, c.z - 1.0, c.w, false, true)
            FreezeEntityPosition(entity, true)
            SetEntityInvincible(entity, true)
            SetBlockingOfNonTemporaryEvents(entity, true)
            exports.ox_target:addLocalEntity(entity, depotOptions())
        end,
        onExit = function()
            deleteObject(entity)
            entity = nil
        end,
    })
end

------------------------------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------------------------------

-- Tree and ground-item changes arrive as GlobalState keys.
AddStateBagChangeHandler(nil, 'global', function(_, key, value)
    local treeId = key:match('^lj:tree:(%d+)$')
    if treeId then return onTreeState(tonumber(treeId), value) end

    local itemId = key:match('^lj:item:(%d+)$')
    if itemId then
        itemId = tonumber(itemId)
        if value then addItem(itemId, value) else removeItem(itemId) end
    end
end)

CreateThread(function()
    -- Preload every prop model once so building truck props never yields mid-build.
    for _, item in pairs(Config.Items) do loadModel(item.model) end
    loadModel(Config.Trees.model)
    loadModel(Config.Trees.stumpModel)
    for _, cfg in ipairs(Config.Trees.list) do
        if cfg.model then loadModel(cfg.model) end
    end

    for id, cfg in ipairs(Config.Trees.list) do
        Trees[id] = { state = GlobalState[('lj:tree:%d'):format(id)] }
        lib.points.new({
            coords = cfg.coords.xyz,
            distance = Config.RenderDistance,
            onEnter = function() spawnTree(id) end,
            onExit = function() despawnTree(id) end,
        })
    end

    for _, item in ipairs(lib.callback.await('lj:getGroundItems', false) or {}) do
        addItem(item.id, item)
    end

    for _, b in ipairs(Config.Blips or {}) do
        local blip = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
        SetBlipSprite(blip, b.sprite)
        SetBlipColour(blip, b.color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(b.label)
        EndTextCommandSetBlipName(blip)
    end

    setupDepot()
end)

------------------------------------------------------------------------------------------------
-- Debug: /ljpoints draws the attachment points of your current/last truck for 15s
------------------------------------------------------------------------------------------------

if Config.Debug then
    RegisterCommand('ljpoints', function()
        local veh = GetVehiclePedIsIn(cache.ped, true)
        local name = veh ~= 0 and truckName(veh)
        if not name then return notify('Sit in (or next to) a configured truck.', 'error') end
        local cfg = Config.Trucks[name]
        local untilTime = GetGameTimer() + 15000
        CreateThread(function()
            while GetGameTimer() < untilTime and DoesEntityExist(veh) do
                for poolName, color in pairs({ log = { 255, 140, 0 }, plank = { 0, 200, 255 } }) do
                    local pool = cfg[poolName]
                    if type(pool) == 'table' then
                        for _, p in ipairs(pool.points) do
                            local w = GetOffsetFromEntityInWorldCoords(veh, p.offset.x, p.offset.y, p.offset.z)
                            DrawMarker(28, w.x, w.y, w.z, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 0.12, color[1], color[2], color[3], 200, false, false, 2, false, nil, nil, false)
                        end
                    end
                end
                Wait(0)
            end
        end)
    end, false)
end
