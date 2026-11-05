--[[
    gryn_gruppe - client/robbery.lua

    Thermite on an active job van's rear doors, the NUI minigame, the door blast and taking loot.
    The server checks everything again (job active, police online, thermite, cooldown, distance,
    minigame timing) before anything opens or is given.
]]

local busy = false
local pendingMinigame = nil

local function atRear(entity)
    local o = Config.VanRearOffset
    local rear = GetOffsetFromEntityInWorldCoords(entity, o.x, o.y, o.z)
    return #(GetEntityCoords(cache.ped) - rear) <= Config.VanRearRange
end

-- The minigame, kept behind one function so it can be swapped for another resource later.
-- Blocks until the player finishes; returns true (passed) or false.
function StartThermiteMinigame(settings)
    if pendingMinigame then return false end
    pendingMinigame = promise.new()
    G6C.Send('minigame', settings or Config.Robbery.minigame)
    G6C.Focus('minigame')
    local result = Citizen.Await(pendingMinigame)
    pendingMinigame = nil
    G6C.Focus(nil)
    return result == true
end
exports('StartThermiteMinigame', StartThermiteMinigame)

RegisterNUICallback('minigameResult', function(body, cb)
    if pendingMinigame then pendingMinigame:resolve(body and body.success == true) end
    cb(true)
end)

local function useThermite(entity)
    if busy then return end
    busy = true
    local netId = VehToNet(entity)

    local ok, settings = lib.callback.await('gryn_gruppe:robStart', false, netId)
    if not ok then
        G6C.Notify(settings, 'error')
        busy = false
        return
    end

    TaskTurnPedToFaceEntity(cache.ped, entity, 1000)
    Wait(1000)
    lib.requestAnimDict('anim@heists@ornate_bank@thermal_charge')
    TaskPlayAnim(cache.ped, 'anim@heists@ornate_bank@thermal_charge', 'thermal_charge', 8.0, 8.0, -1, 49, 0, false, false, false)

    local passed = StartThermiteMinigame(settings)
    ClearPedTasks(cache.ped)

    local success, msg, burn = lib.callback.await('gryn_gruppe:robFinish', false, passed)
    if success then
        G6C.Notify('The doors blew open. Grab what you can.', 'success')
    else
        G6C.Notify(msg, 'error')
        if burn and burn > 0 then
            SetEntityHealth(cache.ped, math.max(101, GetEntityHealth(cache.ped) - burn))
        end
    end
    busy = false
end

local function takeLoot(entity)
    if busy then return end
    busy = true
    local done = lib.progressBar({
        duration = Config.Progress.takeLoot, label = 'Grabbing loot...', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab' },
    })
    if done then
        local ok, msg = lib.callback.await('gryn_gruppe:takeLoot', false, VehToNet(entity))
        G6C.Notify(msg or (ok and 'You grabbed it.'), ok and 'success' or 'error')
    end
    busy = false
end

exports.ox_target:addGlobalVehicle({
    {
        name = 'gryn_gruppe_thermite',
        icon = 'fa-solid fa-fire',
        label = 'Use thermite on the doors',
        distance = 4.0,
        items = Config.Items.thermite,
        canInteract = function(entity)
            return not busy and NetworkGetEntityIsNetworked(entity) and Entity(entity).state.g6Job ~= nil and atRear(entity)
        end,
        onSelect = function(data) useThermite(data.entity) end,
    },
    {
        name = 'gryn_gruppe_loot',
        icon = 'fa-solid fa-sack-dollar',
        label = 'Take loot',
        distance = 4.0,
        canInteract = function(entity)
            return not busy and NetworkGetEntityIsNetworked(entity) and (Entity(entity).state.g6Loot or 0) > 0 and atRear(entity)
        end,
        onSelect = function(data) takeLoot(data.entity) end,
    },
})

-- Sent to everyone; only the client that owns the van makes the blast and breaks the doors,
-- so it happens once and syncs to the rest.
RegisterNetEvent('gryn_gruppe:vanBlown', function(netId)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local van = NetToVeh(netId)
    if NetworkGetEntityOwner(van) ~= PlayerId() then return end

    local o = Config.VanRearOffset
    local rear = GetOffsetFromEntityInWorldCoords(van, o.x, o.y * 0.8, o.z + 0.8)
    AddExplosion(rear.x, rear.y, rear.z, 2, 0.0, true, false, 0.6) -- 2 = sticky bomb look, 0 damage
    SetVehicleDoorBroken(van, 2, false) -- rear left
    SetVehicleDoorBroken(van, 3, false) -- rear right
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if pendingMinigame then pendingMinigame:resolve(false) end
    exports.ox_target:removeGlobalVehicle({ 'gryn_gruppe_thermite', 'gryn_gruppe_loot' })
end)
