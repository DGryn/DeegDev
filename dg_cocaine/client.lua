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

local Plants = {} -- [id] = { data, readyAt (GetGameTimer ms, nil = not watered), point, entity, scale }
local busy = false

local function notify(msg, kind)
    if msg then lib.notify({ title = 'Cocaine', description = msg, type = kind or 'inform' }) end
end

local function itemCount(item)
    return exports.ox_inventory:Search('count', item) or 0
end

local function has(item, amount)
    return itemCount(item) >= (amount or 1)
end

local function itemLabel(item)
    local data = exports.ox_inventory:Items(item)
    return data and data.label or item
end

-- 'You need 10x Coca Leaf (you have 4)'
local function needText(item, amount)
    return ('You need %dx %s (you have %d).'):format(amount, itemLabel(item), itemCount(item))
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
-- `check` (optional) returns a message saying what is missing; then nothing runs and the player is told why.
-- It is only a hint for the player: the server checks everything again.
local function action(duration, label, anim, check, callback, ...)
    if busy then return end

    local missing = check and check()
    if missing then return notify(missing, 'error') end

    busy = true

    local done = lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
        prop = anim and anim.prop,
    })

    -- Scenarios (and looped full-body anims) can keep playing after the bar ends, finished or cancelled,
    -- leaving the player stuck in them. Always stop whatever the progress bar started.
    ClearPedTasks(cache.ped)

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

-- 'Needs water' / 'Growth: 45%' / 'Growth: 100% (ready)'. Never shows the time left.
local function growthText(plant)
    if not plant.readyAt then return 'Needs water' end
    if isReady(plant) then return 'Growth: 100% (ready)' end
    return ('Growth: %d%%'):format(math.floor(progress(plant) * 100))
end

-- Plant size for its current growth (rounded so tiny changes don't re-apply the matrix)
local function scaleFor(plant)
    local s = Config.Plants.scale
    local p = isReady(plant) and 1.0 or progress(plant)
    return math.floor((s.min + (s.max - s.min) * p) * 100 + 0.5) / 100
end

-- GTA has no scale native for objects, so the plant's matrix is set with scaled axis vectors.
-- d.z is the ground height saved when it was planted: the (scaled) bottom of the model is put there,
-- then sunk by Config.Plants.zOffset.
local function applyScale(id)
    local plant = Plants[id]
    local obj, d = plant.entity, plant.data
    local scale = scaleFor(plant)
    local minDim = GetModelDimensions(Config.Plants.model)
    local z = d.z - minDim.z * scale + Config.Plants.zOffset

    local h = math.rad((id * 47) % 360) -- stable "random" rotation per plant
    local fx, fy = -math.sin(h) * scale, math.cos(h) * scale
    local rx, ry = math.cos(h) * scale, math.sin(h) * scale
    SetEntityMatrix(obj, fx, fy, 0.0, rx, ry, 0.0, 0.0, 0.0, scale, d.x, d.y, z)
    plant.scale = scale
end

local function spawnPlant(id)
    local plant = Plants[id]
    local model = Config.Plants.model
    if not loadModel(model) then return end

    local d = plant.data
    local obj = CreateObjectNoOffset(model, d.x, d.y, d.z, false, false, false) -- isNetwork = false
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(obj, true)
    plant.entity = obj
    applyScale(id)

    -- The label is refreshed in canInteract, which ox_target runs every time it builds the menu.
    -- Declared first so canInteract can reference the table it belongs to.
    local growthOption
    growthOption = {
        name = 'dg_cocaine_growth',
        icon = 'fa-solid fa-chart-simple',
        label = 'Growth',
        distance = Config.InteractDistance,
        canInteract = function()
            local p = Plants[id]
            if not p then return false end
            growthOption.label = growthText(p)
            return true
        end,
        onSelect = function()
            local p = Plants[id]
            if p then notify(growthText(p)) end
        end,
    }

    exports.ox_target:addLocalEntity(obj, {
        growthOption,
        {
            name = 'dg_cocaine_water',
            icon = 'fa-solid fa-droplet',
            label = 'Water',
            distance = Config.InteractDistance,
            canInteract = function() -- hidden once watered (can't be done again)
                local p = Plants[id]
                return not busy and p and not p.readyAt
            end,
            onSelect = function()
                action(Config.Plants.waterDuration, 'Watering...', Config.Anims.water, function()
                    if Config.Items.water and not has(Config.Items.water) then return needText(Config.Items.water, 1) end
                end, 'dg_cocaine:water', id)
            end,
        },
        {
            name = 'dg_cocaine_fertilise',
            icon = 'fa-solid fa-seedling',
            label = 'Fertilise',
            distance = Config.InteractDistance,
            canInteract = function() -- hidden once fertilised (can't be done again)
                local p = Plants[id]
                return not busy and p and not p.data.fert
            end,
            onSelect = function()
                action(Config.Plants.fertDuration, 'Fertilising...', Config.Anims.fert, function()
                    if not has(Config.Items.fertiliser) then return needText(Config.Items.fertiliser, 1) end
                end, 'dg_cocaine:fertilise', id)
            end,
        },
        {
            name = 'dg_cocaine_harvest',
            icon = 'fa-solid fa-leaf',
            label = 'Harvest',
            distance = Config.InteractDistance,
            canInteract = function()
                return not busy and Plants[id] ~= nil
            end,
            onSelect = function()
                action(Config.Plants.harvestDuration, 'Harvesting...', Config.Anims.harvest, function()
                    local p = Plants[id]
                    if not p then return 'This plant is gone.' end
                    if not p.readyAt then return 'It needs water before it can grow.' end
                    if not isReady(p) then return ('Not ready yet (%d%%).'):format(math.floor(progress(p) * 100)) end
                end, 'dg_cocaine:harvest', id)
            end,
        },
    })

end

local function despawnPlant(id)
    local plant = Plants[id]
    if not plant then return end
    deleteEntity(plant.entity)
    plant.entity, plant.scale = nil, nil
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

-- Grow spawned plants: re-apply their size as growth progresses
CreateThread(function()
    loadPlants()

    while true do
        Wait(10000)
        for id, plant in pairs(Plants) do
            if plant.entity and DoesEntityExist(plant.entity) and scaleFor(plant) ~= plant.scale then
                applyScale(id)
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

    action(Config.Plants.plantDuration, 'Planting...', Config.Anims.plant, function()
        for _, zone in ipairs(Config.PlantZones) do
            if #(vector2(pos.x, pos.y) - zone.coords) <= zone.radius then return end
        end
        return 'Nothing would grow here. Try the islands.'
    end, 'dg_cocaine:plant', vector3(pos.x, pos.y, groundZ))
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
        content = ('Bring me %dx %s and I will give you some seeds.  \nYou have %d.'):format(request.amount, request.label, itemCount(request.item)),
        centered = true,
        cancel = true,
        labels = { confirm = 'Hand it over', cancel = 'Leave' },
    })
    if answer ~= 'confirm' then return end

    action(Config.SeedNpc.duration, 'Trading...', Config.Anims.trade, function()
        if not has(request.item, request.amount) then return needText(request.item, request.amount) end
    end, 'dg_cocaine:trade', request.id)
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

local function teleport(coords)
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(cache.ped, coords.w)
    Wait(500)
    DoScreenFadeIn(500)
end

if Config.LabEntrance.enabled then
    local entrance = Config.LabEntrance

    LabZones[#LabZones + 1] = exports.ox_target:addSphereZone({
        coords = entrance.outside.xyz,
        radius = entrance.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'dg_cocaine_enter_lab',
                icon = 'fa-solid fa-door-open',
                label = 'Enter lab',
                distance = Config.InteractDistance,
                canInteract = function() return not busy end,
                onSelect = function()
                    if entrance.requireKeycard and not has(Config.Items.keycard) then
                        return notify('The door is locked. ' .. needText(Config.Items.keycard, 1), 'error')
                    end
                    local ok, msg = lib.callback.await('dg_cocaine:enterLab', false)
                    if not ok then return notify(msg, 'error') end
                    teleport(entrance.inside)
                end,
            },
        },
    })

    LabZones[#LabZones + 1] = exports.ox_target:addSphereZone({
        coords = entrance.inside.xyz,
        radius = entrance.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'dg_cocaine_exit_lab',
                icon = 'fa-solid fa-door-closed',
                label = 'Exit lab',
                distance = Config.InteractDistance,
                canInteract = function() return not busy end,
                onSelect = function() teleport(entrance.outside) end,
            },
        },
    })
end

-- Lists every missing input, e.g. 'You need 10x Coca Leaf (you have 4). You need 1x Gasoline (you have 0).'
local function missingInputs(recipe)
    local lines = {}
    for _, input in ipairs(recipe.inputs) do
        if not has(input.item, input.count) then lines[#lines + 1] = needText(input.item, input.count) end
    end
    if #lines > 0 then return table.concat(lines, ' ') end
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
                canInteract = function() return not busy end,
                onSelect = function()
                    action(recipe.duration, recipe.label .. '...', Config.Anims.craft, function()
                        return missingInputs(recipe)
                    end, 'dg_cocaine:craft', index)
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

if Config.LabProps.enabled then
    lib.points.new({
        coords = Config.LabProps.center,
        distance = Config.RenderDistance,
        onEnter = function()
            for i, prop in ipairs(Config.LabProps.list) do
                if loadModel(prop.model) then
                    local c = prop.coords
                    local obj = CreateObjectNoOffset(prop.model, c.x, c.y, c.z, false, false, false) -- isNetwork = false
                    SetModelAsNoLongerNeeded(prop.model)
                    SetEntityHeading(obj, c.w)
                    FreezeEntityPosition(obj, true)
                    LabProps['decor:' .. i] = obj
                end
            end
        end,
        onExit = function()
            for i in ipairs(Config.LabProps.list) do
                local key = 'decor:' .. i
                if LabProps[key] then DeleteEntity(LabProps[key]) end
                LabProps[key] = nil
            end
        end,
    })
end

------------------------------------------------------------------------------------------------
-- Bagging (ox_inventory: client = { export = 'dg_cocaine.useBrick' })
------------------------------------------------------------------------------------------------

exports('useBrick', function()
    -- The server decides the real yield (and checks scales and baggies again)
    action(Config.Bagging.duration, 'Bagging...', Config.Anims.bag, function()
        if not has(Config.Items.scales) then return needText(Config.Items.scales, 1) end
        if not has(Config.Items.baggies, Config.Bagging.bagsPerBrick) then
            return needText(Config.Items.baggies, Config.Bagging.bagsPerBrick)
        end
    end, 'dg_cocaine:bag')
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
