--[[
    dg_cocaine - client.lua

    Draw-only client. Plants, the seed NPC and the optional lab props are LOCAL (non-networked)
    entities, spawned only within Config.RenderDistance (lib.points) and deleted when the player
    leaves. ox_target options are only triggers: every action goes to the server through
    lib.callback and the server decides whether it happens and what it gives.

    API references:
      lib.points        https://coxdocs.dev/ox_lib/Modules/Points/Client
      lib.progressBar   https://coxdocs.dev/ox_lib/Modules/Interface/Client/progress
      lib.alertDialog   https://coxdocs.dev/ox_lib/Modules/Interface/Client/alert
      lib.callback      https://coxdocs.dev/ox_lib/Modules/Callback/Client
      ox_target         https://coxdocs.dev/ox_target/Client  (addLocalEntity, addSphereZone)
      ox_inventory      https://coxdocs.dev/ox_inventory/Functions/Client#search
]]

local Plants = {} -- [id] = { data, readyAt (GetGameTimer ms, nil = not watered), point, entity, stage }
local busy = false

local function notify(msg, kind)
    if msg then lib.notify({ title = 'Cocaine', description = msg, type = kind or 'inform' }) end
end

local function has(item, amount)
    return (exports.ox_inventory:Search('count', item) or 0) >= (amount or 1)
end

local function loadModel(model)
    if not IsModelInCdimage(model) then
        print(('^1[dg_cocaine] model %s is not valid, check config.lua^7'):format(model))
        return false
    end
    lib.requestModel(model)
    return true
end

local function deleteEntity(entity)
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        DeleteEntity(entity)
    end
end

-- Runs a progress bar, then asks the server to do the action. One action at a time.
local function action(duration, label, anim, callback, ...)
    if busy then return end
    busy = true

    local done = lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
    })

    if done then
        local ok, msg = lib.callback.await(callback, false, ...)
        notify(msg, ok and 'success' or 'error')
    end

    busy = false
end

------------------------------------------------------------------------------------------------
-- Plants
------------------------------------------------------------------------------------------------

local function progress(plant)
    if not plant.readyAt then return 0.0 end
    local left = (plant.readyAt - GetGameTimer()) / (Config.Plants.growTime * 1000)
    return math.min(1.0, math.max(0.0, 1.0 - left))
end

local function isReady(plant)
    return plant.readyAt ~= nil and GetGameTimer() >= plant.readyAt
end

local function stageFor(plant)
    local p, stage = progress(plant), 1
    if isReady(plant) then p = 1.0 end
    for i, s in ipairs(Config.Plants.stages) do
        if p >= s.from then stage = i end
    end
    return stage
end

local function spawnPlant(id)
    local plant = Plants[id]
    local stage = stageFor(plant)
    local model = Config.Plants.stages[stage].model
    if not loadModel(model) then return end

    local d = plant.data
    local obj = CreateObjectNoOffset(model, d.x, d.y, d.z, false, false, false) -- isNetwork = false
    SetModelAsNoLongerNeeded(model)
    SetEntityHeading(obj, (id * 47) % 360 + 0.0) -- stable "random" rotation per plant
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)

    exports.ox_target:addLocalEntity(obj, {
        {
            name = 'dg_cocaine_water',
            icon = 'fa-solid fa-droplet',
            label = 'Water',
            distance = Config.InteractDistance,
            canInteract = function()
                local p = Plants[id]
                return not busy and p and not p.readyAt and (not Config.Items.water or has(Config.Items.water))
            end,
            onSelect = function()
                action(Config.Plants.waterDuration, 'Watering...', Config.Anims.water, 'dg_cocaine:water', id)
            end,
        },
        {
            name = 'dg_cocaine_fertilise',
            icon = 'fa-solid fa-seedling',
            label = 'Fertilise',
            distance = Config.InteractDistance,
            canInteract = function()
                local p = Plants[id]
                return not busy and p and not p.data.fert and has(Config.Items.fertiliser)
            end,
            onSelect = function()
                action(Config.Plants.fertDuration, 'Fertilising...', Config.Anims.fert, 'dg_cocaine:fertilise', id)
            end,
        },
        {
            name = 'dg_cocaine_harvest',
            icon = 'fa-solid fa-leaf',
            label = 'Harvest',
            distance = Config.InteractDistance,
            canInteract = function()
                local p = Plants[id]
                return not busy and p and isReady(p)
            end,
            onSelect = function()
                action(Config.Plants.harvestDuration, 'Harvesting...', Config.Anims.harvest, 'dg_cocaine:harvest', id)
            end,
        },
    })

    plant.entity, plant.stage = obj, stage
end

local function despawnPlant(id)
    local plant = Plants[id]
    if not plant then return end
    deleteEntity(plant.entity)
    plant.entity, plant.stage = nil, nil
end

local function removePlant(id)
    local plant = Plants[id]
    if not plant then return end
    despawnPlant(id)
    plant.point:remove()
    Plants[id] = nil
end

-- Adds or updates a plant from server data.
local function setPlant(data)
    local plant = Plants[data.id]

    if not plant then
        plant = { data = data }
        Plants[data.id] = plant
        plant.point = lib.points.new({
            coords = vector3(data.x, data.y, data.z),
            distance = Config.RenderDistance,
            onEnter = function() spawnPlant(data.id) end,
            onExit = function() despawnPlant(data.id) end,
        })
    end

    plant.data = data
    plant.readyAt = data.growLeft and (GetGameTimer() + data.growLeft * 1000) or nil
end

local function loadPlants()
    for id in pairs(Plants) do removePlant(id) end
    for _, data in ipairs(lib.callback.await('dg_cocaine:getPlants', false) or {}) do setPlant(data) end
end

RegisterNetEvent('dg_cocaine:plantUpdated', setPlant)
RegisterNetEvent('dg_cocaine:plantRemoved', removePlant)
RegisterNetEvent('dg_cocaine:reload', loadPlants)

-- Swap models of spawned plants when they reach the next growth stage
CreateThread(function()
    loadPlants()

    while true do
        Wait(10000)
        for id, plant in pairs(Plants) do
            if plant.entity and stageFor(plant) ~= plant.stage then
                despawnPlant(id)
                spawnPlant(id)
            end
        end
    end
end)

-- Seed item (ox_inventory: client = { export = 'dg_cocaine.useSeed' })
exports('useSeed', function()
    if busy then return end

    local pos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 0.8, 0.0)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if not found or IsPedInAnyVehicle(cache.ped, false) then
        return notify('You cannot plant here.', 'error')
    end

    action(Config.Plants.plantDuration, 'Planting...', Config.Anims.plant, 'dg_cocaine:plant', vector3(pos.x, pos.y, groundZ))
end)

------------------------------------------------------------------------------------------------
-- Seed NPC
------------------------------------------------------------------------------------------------

local npc

local function trade()
    local request = lib.callback.await('dg_cocaine:getRequest', false)
    if not request then return notify('He has nothing for you right now.') end

    local answer = lib.alertDialog({
        header = 'Seeds',
        content = ('Bring me %dx %s and I will give you some seeds.'):format(request.amount, request.label),
        centered = true,
        cancel = true,
        labels = { confirm = 'Hand it over', cancel = 'Leave' },
    })
    if answer ~= 'confirm' then return end

    action(Config.SeedNpc.duration, 'Trading...', Config.Anims.trade, 'dg_cocaine:trade', request.id)
end

lib.points.new({
    coords = Config.SeedNpc.coords.xyz,
    distance = Config.RenderDistance,
    onEnter = function()
        if not loadModel(Config.SeedNpc.model) then return end
        local c = Config.SeedNpc.coords
        npc = CreatePed(4, Config.SeedNpc.model, c.x, c.y, c.z - 1.0, c.w, false, true) -- isNetwork = false
        SetModelAsNoLongerNeeded(Config.SeedNpc.model)
        FreezeEntityPosition(npc, true)
        SetEntityInvincible(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)

        exports.ox_target:addLocalEntity(npc, {
            {
                name = 'dg_cocaine_trade',
                icon = 'fa-solid fa-handshake',
                label = 'Talk',
                distance = Config.InteractDistance,
                canInteract = function() return not busy end,
                onSelect = trade,
            },
        })
    end,
    onExit = function()
        deleteEntity(npc)
        npc = nil
    end,
})

------------------------------------------------------------------------------------------------
-- Lab
------------------------------------------------------------------------------------------------

local LabProps = {}
local LabZones = {}

local function canCraft(recipe)
    if busy then return false end
    for _, input in ipairs(recipe.inputs) do
        if not has(input.item, input.count) then return false end
    end
    return true
end

for name, station in pairs(Config.Lab) do
    local options = {}

    for index, recipe in ipairs(Config.Recipes) do
        if recipe.station == name then
            options[#options + 1] = {
                name = ('dg_cocaine_craft_%d'):format(index),
                icon = recipe.icon,
                label = recipe.label,
                distance = Config.InteractDistance,
                canInteract = function() return canCraft(recipe) end,
                onSelect = function()
                    action(recipe.duration, recipe.label .. '...', Config.Anims.craft, 'dg_cocaine:craft', index)
                end,
            }
        end
    end

    LabZones[#LabZones + 1] = exports.ox_target:addSphereZone({
        coords = station.coords,
        radius = station.radius,
        debug = Config.Debug,
        options = options,
    })

    if station.model then
        lib.points.new({
            coords = station.coords,
            distance = Config.RenderDistance,
            onEnter = function()
                if not loadModel(station.model) then return end
                local obj = CreateObjectNoOffset(station.model, station.coords.x, station.coords.y, station.coords.z, false, false, false)
                SetModelAsNoLongerNeeded(station.model)
                SetEntityHeading(obj, station.heading)
                FreezeEntityPosition(obj, true)
                LabProps[name] = obj
            end,
            onExit = function()
                if LabProps[name] then DeleteEntity(LabProps[name]) end
                LabProps[name] = nil
            end,
        })
    end
end

------------------------------------------------------------------------------------------------
-- Bagging (ox_inventory: client = { export = 'dg_cocaine.useBrick' })
------------------------------------------------------------------------------------------------

exports('useBrick', function()
    if busy then return end
    if not has(Config.Items.scales) then return notify('You need scales.', 'error') end
    -- The server decides the real yield (and checks baggies again)
    if not has(Config.Items.baggies, Config.Bagging.bagsPerBrick) then
        return notify(('You need %d baggies.'):format(Config.Bagging.bagsPerBrick), 'error')
    end

    action(Config.Bagging.duration, 'Bagging...', Config.Anims.bag, 'dg_cocaine:bag')
end)

------------------------------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(Plants) do despawnPlant(id) end
    deleteEntity(npc)
    for _, obj in pairs(LabProps) do DeleteEntity(obj) end
    for _, zone in ipairs(LabZones) do exports.ox_target:removeZone(zone) end
end)
