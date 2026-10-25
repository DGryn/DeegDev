-- Everything spawned here is a local (non-networked) entity. The server publishes the drop in
-- GlobalState.airdrop; every client within Config.RenderDistance spawns the same plane, crates,
-- smoke and sound from that data, timed from the moment the flyover started.

local drop = nil       -- copy of GlobalState.airdrop
local startedAt = 0    -- GetGameTimer() when the flyover started (or long ago for late joiners)
local crates = {}      -- [index] = { obj, chute, landed, target }
local smokes = {}      -- [index] = looped particle handle at a picked-up crate's spot
local plane, pilot = nil, nil
local models = nil     -- loaded model hashes while in range
local nextBeep = 0
local isDead, busy = false, false

AddEventHandler('esx:onPlayerDeath', function() isDead = true end)
AddEventHandler('esx:onPlayerSpawn', function() isDead = false end)

local function groundAt(x, y)
    local found, z = GetGroundZFor_3dCoord(x, y, 1000.0, false)
    if not found then return end

    local inWater, waterZ = GetWaterHeightNoWaves(x, y, z + 50.0)
    if inWater and waterZ >= z then return end

    return z
end

-- Server sends candidate lines; we report ground heights for the first line where every crate spot
-- has ground, no water and a reasonable height difference.
lib.callback.register('procaine_airdrop:checkSpot', function(skipChecks, candidates)
    local ped = PlayerPedId()

    if not skipChecks and (isDead or IsEntityDead(ped) or GetInteriorFromEntity(ped) ~= 0) then
        return false
    end

    for index, cand in ipairs(candidates) do
        local zs, minZ, maxZ = {}, math.huge, -math.huge

        for i, pt in ipairs(cand.points) do
            local z = groundAt(pt.x, pt.y)
            if not z then zs = nil break end
            zs[i] = z
            minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
        end

        if zs and maxZ - minZ <= Config.Location.maxHeightDiff then
            return { index = index, zs = zs }
        end
    end

    return false
end)

local function removeCrate(i)
    local c = crates[i]
    if not c then return end

    if c.target then exports.ox_target:removeLocalEntity(c.obj, 'procaine_airdrop_open') end
    if c.chute and DoesEntityExist(c.chute) then DeleteEntity(c.chute) end
    if DoesEntityExist(c.obj) then DeleteEntity(c.obj) end

    crates[i] = nil
end

local function removePlane()
    if pilot and DoesEntityExist(pilot) then DeleteEntity(pilot) end
    if plane and DoesEntityExist(plane) then DeleteEntity(plane) end
    plane, pilot = nil, nil
end

local function stopSmoke()
    for i, handle in pairs(smokes) do
        StopParticleFxLooped(handle, false)
        smokes[i] = nil
    end
end

local function despawnAll()
    for i in pairs(crates) do removeCrate(i) end
    removePlane()
    stopSmoke()
end

local function loadAssets()
    models = {
        plane = lib.requestModel(Config.Plane.model),
        pilot = lib.requestModel(Config.Plane.pilot),
        crate = lib.requestModel(Config.Crate.model),
        chute = lib.requestModel(Config.Crate.chute),
    }
    lib.requestNamedPtfxAsset(Config.Smoke.asset)
end

local function releaseAssets()
    for _, hash in pairs(models) do SetModelAsNoLongerNeeded(hash) end
    RemoveNamedPtfxAsset(Config.Smoke.asset)
    models = nil
end

local function openCrate(i)
    if busy or not drop then return end
    busy = true

    local id = drop.id

    if lib.callback.await('procaine_airdrop:startClaim', false, id, i) then
        local completed = lib.progressBar({
            duration = Config.Claim.duration,
            label = Config.Text.progress,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { scenario = Config.Claim.scenario },
        })

        if completed then
            TriggerServerEvent('procaine_airdrop:finishClaim', id, i)
        else
            TriggerServerEvent('procaine_airdrop:cancelClaim', id, i)
        end
    end

    busy = false
end

local function spawnPlane(pos)
    plane = CreateVehicle(models.plane, pos.x, pos.y, pos.z, drop.heading, false, false)
    SetEntityCollision(plane, false, false) -- flies straight through hills instead of crashing
    FreezeEntityPosition(plane, true)       -- stops the game's flight physics turning or tilting it
    SetEntityInvincible(plane, true)
    SetVehicleEngineOn(plane, true, true, false)
    ControlLandingGear(plane, 3)

    pilot = CreatePedInsideVehicle(plane, 26, models.pilot, -1, false, false)
    SetBlockingOfNonTemporaryEvents(pilot, true)
    SetEntityInvincible(pilot, true)
end

local function spawnCrate(i, p, z, falling)
    local obj = CreateObject(models.crate, p.x, p.y, z, false, false, false)
    SetEntityHeading(obj, drop.heading)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)

    local c = { obj = obj }

    if falling then
        local off = Config.Crate.chuteOffset
        c.chute = CreateObject(models.chute, p.x, p.y, z, false, false, false)
        AttachEntityToEntity(c.chute, obj, 0, off.x, off.y, off.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    end

    crates[i] = c
    return c
end

local function landCrate(i, c, p)
    if c.chute then
        DeleteEntity(c.chute)
        c.chute = nil
    end

    SetEntityCoordsNoOffset(c.obj, p.x, p.y, p.z, false, false, false)
    PlaceObjectOnGroundProperly(c.obj)
    SetEntityCollision(c.obj, true, true)
    c.landed = true

    exports.ox_target:addLocalEntity(c.obj, {
        {
            name = 'procaine_airdrop_open',
            icon = 'fa-solid fa-parachute-box',
            label = Config.Text.target,
            distance = Config.Claim.distance,
            canInteract = function()
                return drop ~= nil and drop.phase == 'landed' and not drop.taken[i] and not busy
            end,
            onSelect = function()
                openCrate(i)
            end,
        },
    })
    c.target = true
end

local function startSmoke(i, p)
    local colour = Config.Smoke.colour

    UseParticleFxAsset(Config.Smoke.asset)
    local handle = StartParticleFxLoopedAtCoord(Config.Smoke.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, Config.Smoke.scale, false, false, false, false)
    SetParticleFxLoopedColour(handle, colour[1], colour[2], colour[3], false)
    smokes[i] = handle
end

-- Runs while in range. Returns how long to wait before the next update.
local function update(pos)
    local elapsed = (GetGameTimer() - startedAt) / 1000
    local animating = false

    -- Plane: flies along the line from Config.Plane.distance before the centre to the same distance after
    local planeEnd = Config.Plane.distance * 2 / Config.Plane.speed
    if elapsed < planeEnd then
        animating = true

        local rad = math.rad(drop.heading)
        local dir = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local yaw = GetHeadingFromVector_2d(dir.x, dir.y) + Config.Plane.headingOffset
        local planePos = vector3(drop.center.x, drop.center.y, drop.planeZ)
            + dir * (Config.Plane.speed * elapsed - Config.Plane.distance)

        if not plane then spawnPlane(planePos) end

        -- The plane is frozen (no physics) and placed every frame, nose pointing along the flight path
        SetEntityCoordsNoOffset(plane, planePos.x, planePos.y, planePos.z, false, false, false)
        SetEntityRotation(plane, 0.0, 0.0, yaw, 2, true)
    elseif plane then
        removePlane()
    end

    -- Crates: released as the plane passes overhead, then fall under a parachute to the ground Z
    local dropZ = drop.planeZ - Config.Crate.dropBelow

    for i, p in ipairs(drop.props) do
        if drop.taken[i] then
            if not smokes[i] then startSmoke(i, p) end
        elseif elapsed >= p.t then
            local z = dropZ - (elapsed - p.t) * Config.Crate.fallSpeed
            local c = crates[i]

            if z > p.z then
                animating = true
                c = c or spawnCrate(i, p, z, true)
                SetEntityCoordsNoOffset(c.obj, p.x, p.y, z, false, false, false)
            else
                c = c or spawnCrate(i, p, p.z, false)
                if not c.landed then landCrate(i, c, p) end
            end
        end
    end

    -- Beeping on every landed crate within the sound radius
    local now = GetGameTimer()
    if now >= nextBeep then
        nextBeep = now + Config.Sound.interval

        for i, c in pairs(crates) do
            local p = drop.props[i]
            if c.landed and #(pos - vector3(p.x, p.y, p.z)) <= Config.Sound.radius then
                PlaySoundFromCoord(-1, Config.Sound.name, p.x, p.y, p.z, Config.Sound.set, false, Config.Sound.radius, false)
            end
        end
    end

    return animating and 0 or 250
end

local function setDrop(value, live)
    if not value then
        if busy and lib.progressActive() then lib.cancelProgress() end
        despawnAll()
        drop = nil
        return
    end

    if not drop or drop.id ~= value.id then
        despawnAll()
        -- Received live at the start of the flyover: play it from the start.
        -- Joined mid-drop: treat everything as already landed.
        startedAt = (live and value.phase == 'flyover') and GetGameTimer() or (GetGameTimer() - 3600000)
    end

    drop = value

    for i in pairs(crates) do
        if drop.taken[i] then removeCrate(i) end
    end
end

AddStateBagChangeHandler('airdrop', 'global', function(_, _, value)
    setDrop(value, true)
end)

CreateThread(function()
    setDrop(GlobalState.airdrop, false)

    while true do
        local sleep = 1000

        if drop then
            local pos = GetEntityCoords(PlayerPedId())
            local center = vector3(drop.center.x, drop.center.y, drop.center.z)

            if #(pos - center) <= Config.RenderDistance then
                if not models then loadAssets() end
                if drop then sleep = update(pos) end
            elseif models then
                despawnAll()
                releaseAssets()
            end
        elseif models then
            releaseAssets()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        despawnAll()
    end
end)
