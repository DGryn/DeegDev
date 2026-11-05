--[[
    gryn_gruppe - client/jobs.lua

    Draws the active job from the server's copy of its state: blips, ox_target zones at banks,
    ATMs, pickups and the HQ hand-in, the drop-off NPC, the props inside the van and the prop in
    your hands. Every option runs an ox_lib progress bar, then asks the server; the server
    decides and sends the new state back to the whole group.

    API references:
      lib.progressBar   https://coxdocs.dev/ox_lib/Modules/Interface/Client/progress
      lib.showTextUI    https://coxdocs.dev/ox_lib/Modules/Interface/Client/textui
      ox_target         https://coxdocs.dev/ox_target/Client  (addSphereZone, addGlobalVehicle, addLocalEntity)
]]

local Job = nil      -- last state from the server, nil = not on a job
local zones = {}     -- ox_target zone ids
local blips = {}     -- site blips
local vanBlip = nil
local vanProps = {}  -- local props inside the van
local vanPropsFor = nil -- { entity, count } the props were built for
local carry = nil    -- { kind, prop }
local dropPoint, dropPed = nil, nil
local busy = false
local myId = GetPlayerServerId(PlayerId())

------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------

local function action(duration, label, anim, callback, ...)
    if busy then return end
    busy = true
    local done = lib.progressBar({
        duration = duration, label = label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = anim,
    })
    if done then
        local ok, msg = lib.callback.await(callback, false, ...)
        G6C.Notify(msg, ok and 'success' or 'error')
    end
    busy = false
end

local function jobVan()
    if not Job or not NetworkDoesEntityExistWithNetworkId(Job.vanNet) then return nil end
    return NetToVeh(Job.vanNet)
end

local function isJobVan(entity)
    return Job and NetworkGetEntityIsNetworked(entity) and VehToNet(entity) == Job.vanNet
end

local function atRear(entity)
    local o = Config.VanRearOffset
    local rear = GetOffsetFromEntityInWorldCoords(entity, o.x, o.y, o.z)
    return #(GetEntityCoords(cache.ped) - rear) <= Config.VanRearRange
end

local function myCarry() return Job and Job.carriers[tostring(myId)] end

local function itemLabel() return Job and Job.kind == 'crate' and 'crate' or 'bag' end

------------------------------------------------------------------------------------------------
-- Carrying
------------------------------------------------------------------------------------------------

local function stopCarry()
    if not carry then return end
    if DoesEntityExist(carry.prop) then DeleteEntity(carry.prop) end
    local anim = Config.Carry[carry.kind].anim
    if anim then StopAnimTask(cache.ped, anim.dict, anim.clip, 1.0) end
    carry = nil
end

local function startCarry(kind)
    local c = Config.Carry[kind]
    if not G6C.LoadModel(c.model) then return end
    local pos = GetEntityCoords(cache.ped)
    local prop = CreateObject(c.model, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, cache.ped, GetPedBoneIndex(cache.ped, c.bone), c.offset.x, c.offset.y, c.offset.z,
        c.rot.x, c.rot.y, c.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(c.model)
    carry = { kind = kind, prop = prop }
end

local function syncCarry()
    local kind = myCarry()
    if carry and carry.kind ~= kind then stopCarry() end
    if kind and not carry then startCarry(kind) end
end

-- Keeps the carry animation playing and blocks sprinting, jumping, fighting and vehicles.
CreateThread(function()
    while true do
        if carry then
            local anim = Config.Carry[carry.kind].anim
            if anim and not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3) then
                lib.requestAnimDict(anim.dict)
                TaskPlayAnim(cache.ped, anim.dict, anim.clip, 8.0, 8.0, -1, anim.flag, 0, false, false, false)
            end
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 22, true) -- jump
            DisableControlAction(0, 23, true) -- enter vehicle
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            Wait(0)
        else
            Wait(500)
        end
    end
end)

------------------------------------------------------------------------------------------------
-- Van props, van blip, timer
------------------------------------------------------------------------------------------------

local function clearVanProps()
    for _, p in ipairs(vanProps) do
        if DoesEntityExist(p) then DeleteEntity(p) end
    end
    vanProps, vanPropsFor = {}, nil
end

local function buildVanProps(van, count)
    clearVanProps()
    local c = Config.Carry[Job.kind]
    if count > 0 and G6C.LoadModel(c.model) then
        for i = 1, math.min(count, #Config.VanProps) do
            local o = Config.VanProps[i]
            local prop = CreateObject(c.model, 0.0, 0.0, 0.0, false, false, false)
            SetEntityCollision(prop, false, false)
            AttachEntityToEntity(prop, van, 0, o.x, o.y, o.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
            vanProps[#vanProps + 1] = prop
        end
        SetModelAsNoLongerNeeded(c.model)
    end
    vanPropsFor = { entity = van, count = count }
end

local function fmtTime(s)
    return ('%02d:%02d'):format(math.floor(s / 60), s % 60)
end

CreateThread(function()
    local textShown = false
    while true do
        Wait(1000)
        local van = jobVan()

        if Job and van then
            if not vanPropsFor or vanPropsFor.entity ~= van or vanPropsFor.count ~= Job.counts.van then
                buildVanProps(van, Job.counts.van)
            end
            if not vanBlip or not DoesBlipExist(vanBlip) or GetBlipInfoIdEntityIndex(vanBlip) ~= van then
                if vanBlip then RemoveBlip(vanBlip) end
                vanBlip = AddBlipForEntity(van)
                SetBlipSprite(vanBlip, 67)
                SetBlipColour(vanBlip, 27)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName('Stockade')
                EndTextCommandSetBlipName(vanBlip)
            end
        elseif vanPropsFor then
            clearVanProps()
        end

        if Job and Job.timeLeft then
            Job.timeLeft = math.max(0, Job.timeLeft - 1)
            lib.showTextUI(('Crate delivery · %s left'):format(fmtTime(Job.timeLeft)), { position = 'top-center', icon = 'stopwatch' })
            textShown = true
        elseif textShown then
            lib.hideTextUI()
            textShown = false
        end
    end
end)

------------------------------------------------------------------------------------------------
-- Sites: blips, zones, drop-off NPC
------------------------------------------------------------------------------------------------

local SITE_BLIP = {
    bank    = { sprite = 108, colour = 2,  label = 'Bank pickup' },
    pickup  = { sprite = 478, colour = 5,  label = 'Crate pickup' },
    atm     = { sprite = 277, colour = 2,  label = 'ATM drop-off' },
    hq      = { sprite = 67,  colour = 27, label = 'HQ hand-in' },
    dropoff = { sprite = 280, colour = 5,  label = 'Crate drop-off' },
}

local function clearSites()
    for _, id in ipairs(zones) do exports.ox_target:removeZone(id) end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    zones, blips = {}, {}
    if dropPoint then dropPoint:remove() dropPoint = nil end
    G6C.DeletePed(dropPed)
    dropPed = nil
end

local function addBlip(coords, style, label, route)
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, style.sprite)
    SetBlipColour(b, style.colour)
    SetBlipScale(b, 0.85)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or style.label)
    EndTextCommandSetBlipName(b)
    if route then SetBlipRoute(b, true) SetBlipRouteColour(b, style.colour) end
    blips[#blips + 1] = b
end

local function addZone(coords, option)
    option.distance = Config.InteractDistance
    zones[#zones + 1] = exports.ox_target:addSphereZone({
        coords = vec3(coords.x, coords.y, coords.z), radius = 1.2, debug = Config.Debug, options = { option },
    })
end

local function deliverOption(site, label, icon)
    return {
        name = 'gryn_gruppe_deliver_' .. site.id, icon = icon, label = label,
        canInteract = function() return myCarry() ~= nil and not busy end,
        onSelect = function()
            action(Config.Progress.deliver, 'Handing over...', nil, 'gryn_gruppe:deliver', site.id)
        end,
    }
end

local function buildSites()
    clearSites()
    if not Job then return end
    local routed = false

    for _, site in ipairs(Job.sites) do
        local active = false
        if (site.type == 'bank' or site.type == 'pickup') and Job.phase == 'collect' and site.remaining > 0 then
            active = true
            addZone(site.coords, {
                name = 'gryn_gruppe_take_' .. site.id,
                icon = site.type == 'bank' and 'fa-solid fa-sack-dollar' or 'fa-solid fa-box',
                label = ('Collect %s (%d left)'):format(itemLabel(), site.remaining),
                canInteract = function() return not myCarry() and not busy end,
                onSelect = function()
                    action(Config.Progress.takeAtSite, 'Collecting...', nil, 'gryn_gruppe:takeFromSite', site.id)
                end,
            })
        elseif site.type == 'atm' and Job.phase == 'deliver' and not site.done then
            active = true
            addZone(site.coords, deliverOption(site, 'Refill ATM', 'fa-solid fa-money-bill-transfer'))
        elseif site.type == 'hq' and Job.phase == 'collect' then
            active = true
            addZone(site.coords, deliverOption(site, 'Hand in bag', 'fa-solid fa-building-shield'))
        elseif site.type == 'dropoff' and Job.phase == 'deliver' and not site.done then
            active = true
            local c = site.coords
            dropPoint = lib.points.new({
                coords = vec3(c.x, c.y, c.z), distance = Config.RenderDistance,
                onEnter = function()
                    dropPed = G6C.SpawnPed(site.model, c, 'WORLD_HUMAN_GUARD_STAND')
                    if dropPed then
                        local opt = deliverOption(site, 'Hand over crate', 'fa-solid fa-handshake')
                        opt.distance = Config.InteractDistance
                        exports.ox_target:addLocalEntity(dropPed, { opt })
                    end
                end,
                onExit = function() G6C.DeletePed(dropPed) dropPed = nil end,
            })
        end

        if active then
            addBlip(site.coords, SITE_BLIP[site.type], site.label, not routed)
            routed = true
        end
    end

    if Job.phase == 'return' then
        addBlip(Config.HQ.returnPoint, SITE_BLIP.hq, 'Return the Stockade', true)
    end
end

------------------------------------------------------------------------------------------------
-- Van options (registered once; only show for your own job van)
------------------------------------------------------------------------------------------------

exports.ox_target:addGlobalVehicle({
    {
        name = 'gryn_gruppe_load',
        icon = 'fa-solid fa-truck-ramp-box',
        label = 'Load into Stockade',
        distance = 4.0,
        canInteract = function(entity) return isJobVan(entity) and myCarry() and atRear(entity) and not busy end,
        onSelect = function()
            action(Config.Progress.loadVan, 'Loading...', nil, 'gryn_gruppe:loadVan')
        end,
    },
    {
        name = 'gryn_gruppe_unload',
        icon = 'fa-solid fa-hand-holding-dollar',
        label = 'Take from Stockade',
        distance = 4.0,
        canInteract = function(entity)
            return isJobVan(entity) and not myCarry() and Job.counts.van > 0 and atRear(entity) and not busy
                and (Job.phase == 'deliver' or Job.task == 'multibank')
        end,
        onSelect = function()
            action(Config.Progress.takeFromVan, 'Unloading...', nil, 'gryn_gruppe:takeFromVan')
        end,
    },
    {
        name = 'gryn_gruppe_return',
        icon = 'fa-solid fa-flag-checkered',
        label = 'Return Stockade',
        distance = 4.0,
        canInteract = function(entity)
            return isJobVan(entity) and Job.phase == 'return'
                and #(GetEntityCoords(entity) - Config.HQ.returnPoint) <= Config.HQ.returnRadius
        end,
        onSelect = function()
            local ok, msg = lib.callback.await('gryn_gruppe:returnVan', false)
            G6C.Notify(msg, ok and 'success' or 'error')
        end,
    },
})

------------------------------------------------------------------------------------------------
-- State from the server
------------------------------------------------------------------------------------------------

local function clearJob()
    Job = nil
    stopCarry()
    clearVanProps()
    clearSites()
    if vanBlip then RemoveBlip(vanBlip) vanBlip = nil end
    lib.hideTextUI()
end

RegisterNetEvent('gryn_gruppe:jobState', function(state)
    local rebuild = not Job or Job.phase ~= state.phase or #Job.sites ~= #state.sites
    if not rebuild then
        for i, s in ipairs(state.sites) do
            local old = Job.sites[i]
            if old.remaining ~= s.remaining or old.done ~= s.done then rebuild = true break end
        end
    end
    Job = state
    if rebuild then buildSites() end
    syncCarry()
end)

RegisterNetEvent('gryn_gruppe:jobEnded', clearJob)

-- If you go down while carrying, drop the prop (the server returns the item when you leave).
AddEventHandler('esx:onPlayerDeath', stopCarry)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearJob()
    exports.ox_target:removeGlobalVehicle({ 'gryn_gruppe_load', 'gryn_gruppe_unload', 'gryn_gruppe_return' })
end)
