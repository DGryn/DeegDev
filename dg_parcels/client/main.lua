--[[
    dg_parcels - client
    Only draws local (non-networked) props near the player, plays the progress bar,
    shows smoke and police blips. Every decision is made by the server.
]]

local parcels = {}   -- [spotId] = size  (copy of the server list)
local props = {}     -- [spotId] = entity handle (only for spots near us)
local isOpening = false
local warnedModels = {}

---------------------------------------------------------------------
-- Props
---------------------------------------------------------------------
local function deleteProp(id)
    local obj = props[id]
    if not obj then return end
    exports.ox_target:removeLocalEntity(obj, 'dg_parcels_grab')
    if DoesEntityExist(obj) then DeleteEntity(obj) end
    props[id] = nil
end

local function spawnProp(id, size)
    local model = Config.Sizes[size].model
    if not IsModelInCdimage(model) then
        if not warnedModels[model] then
            warnedModels[model] = true
            print(('^1[dg_parcels] prop model "%s" does not exist, change it in config.lua^0'):format(model))
        end
        return
    end

    local spot = Config.Locations[id]
    local hash = lib.requestModel(model) -- waits until loaded

    -- The parcel may have been grabbed while the model was loading.
    if parcels[id] ~= size or props[id] then
        SetModelAsNoLongerNeeded(hash)
        return
    end

    -- Last arg false = local only, other players don't see this entity (they make their own).
    local obj = CreateObject(hash, spot.x, spot.y, spot.z - 1.0, false, false, false)
    SetEntityHeading(obj, spot.w)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    props[id] = obj

    exports.ox_target:addLocalEntity(obj, {
        {
            name = 'dg_parcels_grab',
            icon = 'fa-solid fa-box',
            label = 'Grab',
            distance = 2.0,
            onSelect = function()
                TriggerServerEvent('dg_parcels:grab', id) -- silent: server validates and gives the item
            end,
        },
    })
end

-- Streaming loop: create props when close, delete them when far.
CreateThread(function()
    while true do
        local pos = GetEntityCoords(cache.ped)
        -- Loop over a copy: spawnProp waits for the model, and the real list can change meanwhile.
        local snapshot = {}
        for id, size in pairs(parcels) do snapshot[id] = size end
        for id, size in pairs(snapshot) do
            local near = #(pos - Config.Locations[id].xyz) < Config.StreamDistance
            if near and not props[id] then
                spawnProp(id, size)
            elseif not near and props[id] then
                deleteProp(id)
            end
        end
        Wait(1000)
    end
end)

RegisterNetEvent('dg_parcels:add', function(id, size)
    deleteProp(id) -- in case an old prop is still there
    parcels[id] = size
end)

RegisterNetEvent('dg_parcels:remove', function(id)
    parcels[id] = nil
    deleteProp(id)
end)

-- Get the current list when we join or the resource (re)starts.
CreateThread(function()
    local list = lib.callback.await('dg_parcels:getAll', false)
    for _, p in ipairs(list or {}) do parcels[p.id] = p.size end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(props) do deleteProp(id) end
end)

---------------------------------------------------------------------
-- Opening (called by ox_inventory: items.lua has client.export = 'dg_parcels.openParcel')
---------------------------------------------------------------------
exports('openParcel', function(data, slot)
    if isOpening then return end
    isOpening = true

    -- Server checks the item, the tool, room for the loot and that we aren't already opening.
    local ok, duration = lib.callback.await('dg_parcels:startOpen', false, data.name)
    if not ok then
        isOpening = false
        return
    end

    local inVehicle = IsPedInAnyVehicle(cache.ped, false)
    local done = lib.progressBar({
        duration = duration,
        label = 'Cutting the parcel open...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = not inVehicle and { dict = Config.OpenAnim.dict, clip = Config.OpenAnim.clip, flag = 1 } or nil,
    })

    if done then
        lib.callback.await('dg_parcels:finishOpen', false) -- server removes the parcel and gives loot
    else
        TriggerServerEvent('dg_parcels:cancelOpen')     -- parcel stays in the inventory
    end

    isOpening = false
end)

---------------------------------------------------------------------
-- Green smoke (trapped parcel). Sent to everyone; only drawn while we're close,
-- so players who arrive later (e.g. police) still see it.
---------------------------------------------------------------------
RegisterNetEvent('dg_parcels:smoke', function(coords, durationMs)
    CreateThread(function()
        local trap = Config.Trap
        local endTime = GetGameTimer() + durationMs
        local handle

        lib.requestNamedPtfxAsset(trap.Asset)

        while GetGameTimer() < endTime do
            local close = #(GetEntityCoords(cache.ped) - coords) < trap.SmokeDistance
            if close and not handle then
                UseParticleFxAsset(trap.Asset) -- must be called right before starting the effect
                handle = StartParticleFxLoopedAtCoord(trap.Effect, coords.x, coords.y, coords.z - 0.9,
                    0.0, 0.0, 0.0, trap.Scale, false, false, false, false)
                SetParticleFxLoopedColour(handle, trap.Colour.r, trap.Colour.g, trap.Colour.b, false)
            elseif not close and handle then
                StopParticleFxLooped(handle, false)
                handle = nil
            end
            Wait(1000)
        end

        if handle then StopParticleFxLooped(handle, false) end
    end)
end)

---------------------------------------------------------------------
-- Default police alert (from SendPoliceAlert in server/main.lua).
-- Not needed if you switch to your own dispatch.
---------------------------------------------------------------------
RegisterNetEvent('dg_parcels:policeAlert', function(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)

    lib.notify({
        title = 'Dispatch',
        description = ('Suspicious green smoke reported near %s'):format(street),
        type = 'inform',
        duration = 10000,
    })

    local area = AddBlipForRadius(coords.x, coords.y, coords.z, Config.Police.BlipRadius)
    SetBlipColour(area, Config.Police.BlipColour)
    SetBlipAlpha(area, 120)

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Police.BlipSprite)
    SetBlipColour(blip, Config.Police.BlipColour)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Suspicious smoke')
    EndTextCommandSetBlipName(blip)

    SetTimeout(Config.Police.BlipTime * 1000, function()
        RemoveBlip(blip)
        RemoveBlip(area)
    end)
end)

---------------------------------------------------------------------
-- /parcelcoord result (server already checked admin rights)
---------------------------------------------------------------------
RegisterNetEvent('dg_parcels:coord', function(line)
    print(line)
    lib.setClipboard(line)
    lib.notify({ description = 'Coords copied to clipboard (also in F8)', type = 'success' })
end)
