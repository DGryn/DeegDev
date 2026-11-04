--[[
    recycling_warehouse - client.lua

    The client only shows things and ASKS the server to do things. The server re-checks every
    request (see server.lua), so nothing here can give a player items on its own.

    Performance:
      - Interactions use ox_target, which costs nothing until the player holds the target key.
      - Props, the trader ped and the outlines only exist while the player is near the warehouse
        (lib.points, checked a few times per second by ox_lib).
      - The only per-frame loop runs while a box is being carried.

    APIs used (checked against their source code on GitHub):
      ox_target   addSphereZone, removeZone, addLocalEntity, removeLocalEntity
      ox_lib      lib.points.new, lib.callback.await, lib.progressBar, lib.progressActive,
                  lib.skillCheck, lib.notify, lib.requestModel, lib.requestAnimDict
      NUI         SendNUIMessage, SetNuiFocus, RegisterNUICallback (the screens live in web/)
]]

local RESOURCE = GetCurrentResourceName()
local target = exports.ox_target
local Text = Config.Text

-- Local job state. This is only a mirror of the server's state, used to decide what to show.
local onShift = false
local carrying = false
local carryProp = nil
local teleporting = false
local interiorId = 0

-- Things that only exist while the player is near the warehouse.
local spawnedObjects = {}  -- every prop we created (skip, laptop, pickups)
local pickupEntities = {}  -- [pickupIndex] = entity
local skipEntity = nil     -- the skip prop (outlined while carrying)
local activeSpot = nil     -- the ONE pickup the server told us to use next
local traderPed = nil
local areaLoaded = false

------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------

-- These message keys are shown as green "success" notifications; everything else is red.
local SUCCESS = {
    shiftStarted = true, shiftEnded = true, pickedUp = true, delivered = true, traded = true,
    skillHit = true, goalClaimed = true,
}

-- Shows Config.Text[key], filling in any %s / %d with the extra arguments.
local function notify(key, ...)
    local text = Text[key] or Text.failed
    if select('#', ...) > 0 then text = text:format(...) end

    lib.notify({ description = text, type = SUCCESS[key] and 'success' or 'error' })
end

-- Loads a model safely. Returns the model hash, or nil (with a warning) if it is invalid.
local function loadModel(model)
    local hash = joaat(model)

    if not IsModelValid(hash) then
        lib.print.warn(Text.loadFailed:format(model))
        return nil
    end

    local ok = pcall(lib.requestModel, hash, 10000)
    if not ok then
        lib.print.warn(Text.loadFailed:format(model))
        return nil
    end

    return hash
end

-- Spawns a frozen, client-only prop. Client-only means every player spawns their own copy,
-- so nothing is duplicated on the server and it disappears with the resource.
local function spawnProp(model, coords, snapToGround)
    local hash = loadModel(model)
    if not hash then return nil end

    local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(object, coords.w or 0.0)
    if snapToGround then PlaceObjectOnGroundProperly(object) end
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(hash)

    spawnedObjects[#spawnedObjects + 1] = object
    return object
end

local function deleteEntity(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

------------------------------------------------------------------------------------------------
-- Pickup outlines ("glow")
------------------------------------------------------------------------------------------------

-- Can the player pick up from this prop right now? Used for both the glow and ox_target.
local function isActivePickup(index)
    return onShift and not carrying and index == activeSpot
end

-- Outlines only the assigned pickup prop (when empty-handed) or the skip (when carrying).
-- Called whenever the shift, carry or assigned spot changes.
local function refreshGlow()
    for index, entity in pairs(pickupEntities) do
        if DoesEntityExist(entity) then
            SetEntityDrawOutline(entity, Config.Highlight.enabled and isActivePickup(index))
        end
    end

    if skipEntity and DoesEntityExist(skipEntity) then
        SetEntityDrawOutline(skipEntity, Config.Highlight.enabled and Config.Highlight.skip and onShift and carrying)
    end
end

------------------------------------------------------------------------------------------------
-- Carrying a box
------------------------------------------------------------------------------------------------

local function playCarryAnim()
    lib.requestAnimDict(Config.Carry.animDict)
    -- Flag 49 = loop + upper body only + player can still walk.
    TaskPlayAnim(cache.ped, Config.Carry.animDict, Config.Carry.animClip, 8.0, -8.0, -1, 49, 0, false, false, false)
end

-- Removes the box from the player's hands. Safe to call at any time, even if not carrying.
local function stopCarry()
    carrying = false

    if carryProp and DoesEntityExist(carryProp) then
        DetachEntity(carryProp, true, false)
        deleteEntity(carryProp)
    end
    carryProp = nil

    StopAnimTask(cache.ped, Config.Carry.animDict, Config.Carry.animClip, 1.0)
    refreshGlow()
end

-- The box was lost without being delivered (death, vehicle, leaving). Tell the server too.
local function dropBox(showMessage)
    if not carrying then return end

    stopCarry()
    TriggerServerEvent('recycling_warehouse:boxDropped')
    if showMessage then notify('boxDropped') end
end

-- Runs every frame, but ONLY while carrying. Blocks jump/weapons/etc. and watches for death.
local function carryLoop()
    local nextCheck = 0

    while carrying do
        for _, control in ipairs(Config.Carry.disabledControls) do
            DisableControlAction(0, control, true)
        end

        -- A couple of times per second is plenty for these checks.
        if GetGameTimer() > nextCheck then
            nextCheck = GetGameTimer() + 500
            local ped = cache.ped

            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) then
                dropBox(true)
            elseif not lib.progressActive() and not IsEntityPlayingAnim(ped, Config.Carry.animDict, Config.Carry.animClip, 3) then
                -- Something interrupted the carry animation (e.g. bumping into someone): restart it.
                playCarryAnim()
            end
        end

        Wait(0)
    end
end

-- Puts a box in the player's hands. Returns false if the prop could not be created.
local function startCarry()
    local hash = loadModel(Config.Carry.model)
    if not hash then return false end

    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local networked = Config.Carry.networked

    carryProp = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, networked, networked, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(carryProp, false, false)

    local offset, rotation = Config.Carry.offset, Config.Carry.rotation
    AttachEntityToEntity(carryProp, ped, GetPedBoneIndex(ped, Config.Carry.bone),
        offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
        true, true, false, true, 1, true)

    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    playCarryAnim()
    carrying = true
    refreshGlow()

    -- Let the server know which prop is ours, so it can delete it if we disconnect.
    if networked then
        TriggerServerEvent('recycling_warehouse:registerCarryProp', ObjToNet(carryProp))
    end

    CreateThread(carryLoop)
    return true
end

------------------------------------------------------------------------------------------------
-- Shift
------------------------------------------------------------------------------------------------

-- Both return ok, messageKey so the laptop screen can show the result.
local function startShift()
    local ok, message, spot = lib.callback.await('recycling_warehouse:startShift', false)
    if ok then
        onShift = true
        activeSpot = spot
        refreshGlow()
    end
    return ok, message
end

local function endShift()
    local ok, message = lib.callback.await('recycling_warehouse:endShift', false)

    -- Whatever the server says, make sure the local state is clean.
    stopCarry()
    onShift = false
    activeSpot = nil
    refreshGlow()

    return ok, message
end

------------------------------------------------------------------------------------------------
-- Boxes: pick up and deliver
------------------------------------------------------------------------------------------------

local function pickupBox(index)
    if carrying then return notify('alreadyCarrying') end
    if lib.progressActive() then return end

    -- Short "bend down and grab" animation before the box appears in the hands.
    local finished = lib.progressBar({
        duration = Config.PickupAction.duration,
        label = Text.picking,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = { dict = Config.PickupAction.animDict, clip = Config.PickupAction.animClip, flag = 0 },
    })
    if not finished then return notify('cancelled') end

    local ok, message = lib.callback.await('recycling_warehouse:pickupBox', false, index)
    if not ok then return notify(message) end

    if not startCarry() then
        -- The prop failed to load, so give the "box" back to the server.
        TriggerServerEvent('recycling_warehouse:boxDropped')
        return notify('failed')
    end

    notify(message)
end

local function deliverBox()
    if not carrying or lib.progressActive() then return end

    -- Step 1: the server checks we're allowed and decides if there's a skill check.
    local allowed, startMessage, skill = lib.callback.await('recycling_warehouse:startDeliver', false)
    if not allowed then return notify(startMessage) end

    local finished = lib.progressBar({
        duration = Config.Skip.progressDuration,
        label = Text.recycling,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true, sprint = true },
        anim = { dict = Config.Skip.animDict, clip = Config.Skip.animClip, flag = 48 },
    })

    if not finished then return notify('cancelled') end
    if not carrying then return end -- e.g. died during the progress bar

    -- Optional skill check, only if the server asked for one.
    local hit = false
    if skill then
        hit = lib.skillCheck(skill.difficulty, skill.keys) == true
        if not carrying then return end -- e.g. died during the skill check
    end

    -- Step 2: the server re-checks everything and hands out the reward.
    local ok, message, result = lib.callback.await('recycling_warehouse:finishDeliver', false, hit)
    if not ok then return notify(message) end -- e.g. inventory full: they keep the box

    activeSpot = result.nextSpot
    stopCarry() -- also moves the glow back to the next pickup
    notify(message, result.boxes)

    if result.skill then
        if result.hit then
            notify('skillHit', Config.SkillCheck.bonusBoxes)
        else
            notify('skillMiss')
        end
    end
end

------------------------------------------------------------------------------------------------
-- Custom screens (laptop + trader). The HTML/CSS/JS is in the web/ folder.
------------------------------------------------------------------------------------------------

local openScreen = nil -- 'laptop', 'trader' or nil

-- Turns a Config.Text key into the final sentence (used for messages shown inside the screens).
local function message(key, ...)
    local text = Text[key] or Text.failed
    if select('#', ...) > 0 then text = text:format(...) end
    return text
end

local function closeScreen()
    if not openScreen then return end
    openScreen = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Asks the server for fresh data and sends it to the open screen.
local function refreshScreen(status)
    if openScreen == 'laptop' then
        local data = lib.callback.await('recycling_warehouse:getLaptopData', false)
        if not data then closeScreen(); return notify('noProfile') end
        SendNUIMessage({ action = 'laptop', data = data, status = status })
    elseif openScreen == 'trader' then
        local data = lib.callback.await('recycling_warehouse:getTraderData', false)
        if not data then closeScreen(); return notify('noProfile') end
        SendNUIMessage({ action = 'trader', data = data, status = status })
    end
end

local function openUi(screen)
    if openScreen then return end
    openScreen = screen

    -- The screen needs the text and style settings the first time; sending them each time is cheap.
    SendNUIMessage({ action = 'setup', text = Config.UIText, ui = Config.UI })
    refreshScreen()

    if openScreen then SetNuiFocus(true, true) end
end

-- Messages from the screens (web/app.js -> post('name', data)).
RegisterNUICallback('close', function(_, cb)
    closeScreen()
    cb(true)
end)

RegisterNUICallback('startShift', function(_, cb)
    local ok, key = startShift()
    cb(true)
    if ok then notify(key) end
    refreshScreen({ ok = ok, text = message(key) })
end)

RegisterNUICallback('endShift', function(_, cb)
    local ok, key = endShift()
    cb(true)
    if ok then notify(key) end
    refreshScreen({ ok = ok, text = message(key) })
end)

RegisterNUICallback('claimGoal', function(data, cb)
    local ok, key = lib.callback.await('recycling_warehouse:claimGoal', false, tonumber(data.index))
    cb(true)
    refreshScreen({ ok = ok, text = message(key) })
end)

RegisterNUICallback('trade', function(data, cb)
    local ok, key, result = lib.callback.await('recycling_warehouse:trade', false, tonumber(data.index), tonumber(data.times))
    cb(true)

    local text
    if ok then
        text = message('traded', result.cost, result.amount, result.label)
    elseif key == 'cannotAfford' then
        text = Config.UIText.notEnough
    else
        text = message(key)
    end

    refreshScreen({ ok = ok, text = text })
end)

------------------------------------------------------------------------------------------------
-- Spawning / despawning the warehouse contents
------------------------------------------------------------------------------------------------

local function spawnTrader()
    local cfg = Config.Trader
    local hash = loadModel(cfg.model)
    if not hash then return end

    -- Coords are copied from a standing player (body centre), so lower by 1 m to put the feet on the floor.
    traderPed = CreatePed(4, hash, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, false)
    SetModelAsNoLongerNeeded(hash)

    FreezeEntityPosition(traderPed, true)
    SetEntityInvincible(traderPed, true)
    SetBlockingOfNonTemporaryEvents(traderPed, true) -- ignores gunshots, being pushed, etc.

    if cfg.scenario then
        TaskStartScenarioInPlace(traderPed, cfg.scenario, 0, true)
    elseif cfg.animDict and cfg.animClip then
        lib.requestAnimDict(cfg.animDict)
        TaskPlayAnim(traderPed, cfg.animDict, cfg.animClip, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    target:addLocalEntity(traderPed, {
        {
            name = 'recycling_warehouse:trade',
            label = Text.trader,
            icon = Config.Icons.trader,
            distance = Config.Distance.trader,
            canInteract = function() return not cfg.requireShift or onShift end,
            onSelect = function() openUi('trader') end,
        },
    })
end

local function spawnArea()
    if areaLoaded then return end
    areaLoaded = true

    local colour = Config.Highlight.colour
    SetEntityDrawOutlineColor(colour.r, colour.g, colour.b, colour.a)

    -- Skip (recycle point)
    local skip = Config.Skip.spawnProp and spawnProp(Config.Skip.model, Config.Skip.coords, Config.SnapPropsToGround)
    skipEntity = skip or nil
    if skip then
        target:addLocalEntity(skip, {
            {
                name = 'recycling_warehouse:deliver',
                label = Text.deliver,
                icon = Config.Icons.deliver,
                distance = Config.Distance.skip,
                canInteract = function() return onShift and carrying end,
                onSelect = deliverBox,
            },
        })
    end

    -- Optional laptop prop (the interaction itself is a zone, created in setupZones).
    -- Not snapped to the ground, so it stays on the desk.
    if Config.Laptop.spawnProp then
        spawnProp(Config.Laptop.model, Config.Laptop.coords, false)
    end

    -- Pickup props
    for index, pickup in ipairs(Config.Pickups) do
        local entity = spawnProp(pickup.model, pickup.coords, Config.SnapPropsToGround)

        if entity then
            pickupEntities[index] = entity

            target:addLocalEntity(entity, {
                {
                    name = 'recycling_warehouse:pickup',
                    label = Text.pickup,
                    icon = Config.Icons.pickup,
                    distance = Config.Distance.pickup,
                    -- Only the assigned prop shows the option, so you can't loot any of them.
                    canInteract = function() return isActivePickup(index) end,
                    onSelect = function() pickupBox(index) end,
                },
            })
        end
    end

    refreshGlow() -- light up the assigned prop if we are already on shift
    spawnTrader()
end

local function despawnArea()
    if not areaLoaded then return end
    areaLoaded = false

    -- A box can't leave the warehouse.
    dropBox(false)

    for _, entity in ipairs(spawnedObjects) do
        SetEntityDrawOutline(entity, false)
        target:removeLocalEntity(entity)
        deleteEntity(entity)
    end
    spawnedObjects = {}
    pickupEntities = {}
    skipEntity = nil

    if traderPed then
        target:removeLocalEntity(traderPed)
        deleteEntity(traderPed)
        traderPed = nil
    end
end

------------------------------------------------------------------------------------------------
-- Entering and leaving
------------------------------------------------------------------------------------------------

-- Makes sure the warehouse interior is in memory and ready before the player is placed in it.
local function loadWarehouseInterior()
    local ref = Config.Interior.reference

    interiorId = GetInteriorAtCoordsWithType(ref.x, ref.y, ref.z, Config.Interior.name)
    if interiorId == 0 then interiorId = GetInteriorAtCoords(ref.x, ref.y, ref.z) end
    if interiorId == 0 then
        lib.print.warn('Warehouse interior not found at Config.Interior.reference')
        return
    end

    if IsInteriorDisabled(interiorId) then DisableInterior(interiorId, false) end
    PinInteriorInMemory(interiorId)

    local timeout = GetGameTimer() + Config.Interior.loadTimeout
    while not IsInteriorReady(interiorId) and GetGameTimer() < timeout do
        Wait(0)
    end
end

-- Fade out, move the player, wait for the floor to load, fade in.
local function teleport(destination, intoWarehouse)
    if teleporting then return end
    teleporting = true

    local fade = Config.Interior.fadeTime
    DoScreenFadeOut(fade)
    while not IsScreenFadedOut() do Wait(0) end

    if intoWarehouse and Config.Interior.loadInterior then
        loadWarehouseInterior()
    end

    local ped = cache.ped
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(destination.x, destination.y, destination.z)
    SetEntityCoords(ped, destination.x, destination.y, destination.z, false, false, false, false)
    SetEntityHeading(ped, destination.w)

    -- Wait until the ground under the player exists, so they don't fall through the floor.
    local timeout = GetGameTimer() + Config.Interior.loadTimeout
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(destination.x, destination.y, destination.z)
        Wait(0)
    end

    FreezeEntityPosition(ped, false)

    -- Leaving: the interior no longer needs to be kept in memory.
    if not intoWarehouse and interiorId ~= 0 then
        UnpinInterior(interiorId)
        interiorId = 0
    end

    Wait(250) -- a short pause so the world is drawn before the fade-in
    DoScreenFadeIn(fade)
    teleporting = false
end

local function enterWarehouse()
    teleport(Config.Entrance.spawnInside, true)
end

local function leaveWarehouse()
    if Config.Exit.endShiftOnExit and onShift then
        local ok, key = endShift()
        if ok then notify(key) end
    else
        dropBox(false)
    end

    teleport(Config.Exit.spawnOutside, false)
end

------------------------------------------------------------------------------------------------
-- Setup: zones, blip and the "near the warehouse" point
------------------------------------------------------------------------------------------------

local zoneIds = {}
local blip = nil

local function setupZones()
    -- Entrance (outside)
    zoneIds[#zoneIds + 1] = target:addSphereZone({
        coords = Config.Entrance.coords,
        radius = Config.Entrance.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'recycling_warehouse:enter',
                label = Text.enter,
                icon = Config.Icons.enter,
                distance = Config.Distance.door,
                onSelect = enterWarehouse,
            },
        },
    })

    -- Exit (inside)
    zoneIds[#zoneIds + 1] = target:addSphereZone({
        coords = Config.Exit.coords,
        radius = Config.Exit.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'recycling_warehouse:exit',
                label = Text.exit,
                icon = Config.Icons.exit,
                distance = Config.Distance.door,
                onSelect = leaveWarehouse,
            },
        },
    })

    -- Laptop: opens the shift terminal screen (start/end shift, goals, level, stats, rates).
    zoneIds[#zoneIds + 1] = target:addSphereZone({
        coords = Config.Laptop.coords.xyz,
        radius = Config.Laptop.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'recycling_warehouse:laptop',
                label = Text.useLaptop,
                icon = Config.Icons.laptop,
                distance = Config.Distance.laptop,
                canInteract = function() return not carrying end,
                onSelect = function() openUi('laptop') end,
            },
        },
    })
end

local function setupBlip()
    local cfg = Config.Entrance.blip
    if not cfg then return end

    local coords = Config.Entrance.coords
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.colour)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Text.blip)
    EndTextCommandSetBlipName(blip)
end

local areaPoint = lib.points.new({
    coords = Config.Interior.reference,
    distance = Config.Interior.streamDistance,
    onEnter = spawnArea,
    onExit = despawnArea,
})

setupZones()
setupBlip()

-- Helper for filling in the config: prints and copies your position + heading as a vec4.
if Config.CoordsCommand then
    RegisterCommand(Config.CoordsCommand, function()
        local coords = GetEntityCoords(cache.ped)
        local text = ('vec4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, GetEntityHeading(cache.ped))

        print(text)
        lib.setClipboard(text)
        lib.notify({ description = Text.coordsCopied:format(text), type = 'inform' })
    end, false)
end

------------------------------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------------------------------

-- ESX character logout / switch: the server clears its side, we clear ours.
RegisterNetEvent('esx:onPlayerLogout', function()
    closeScreen()
    stopCarry()
    onShift = false
    activeSpot = nil
    refreshGlow()
end)

-- Resource stop/restart: remove everything this script created.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end

    stopCarry()
    despawnArea()
    areaPoint:remove()
    if openScreen then SetNuiFocus(false, false) end

    for _, id in ipairs(zoneIds) do target:removeZone(id) end
    if blip then RemoveBlip(blip) end
    if interiorId ~= 0 then UnpinInterior(interiorId) end

    -- If we were stopped in the middle of a teleport, don't leave the screen black or the player frozen.
    if teleporting then
        FreezeEntityPosition(cache.ped, false)
        DoScreenFadeIn(0)
    end
end)
