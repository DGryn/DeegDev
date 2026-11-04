--[[
    recycling_warehouse - server.lua

    The server is the authority. The client only ASKS to do things; every request is checked here:
      - Start shift      -> not already on shift, standing at the laptop
      - Pick up a box    -> on shift, empty-handed, standing at a real pickup prop from the config
      - Deliver a box    -> on shift, carrying, standing at the skip, enough time has passed,
                            room in the inventory for the recycle box
      - Trade            -> standing at the trader, a real material from the config, enough recycle
                            boxes, room for the materials; the cost is removed BEFORE materials are given

    Player state lives only in the `Players` table below and is wiped on disconnect / logout.
    Nothing the client sends (counts, items, amounts) is trusted - it only sends an index number,
    which is looked up in the config here.

    APIs used (checked against their source code on GitHub):
      ox_lib callbacks   lib.callback.register(name, function(source, ...) return ... end)
      ox_inventory       GetItemCount(inv, item), CanCarryItem(inv, item, count),
                         CanSwapItem(inv, firstItem, firstCount, testItem, testCount),
                         AddItem(inv, item, count) / RemoveItem(inv, item, count) -> success, response
      ESX                'esx:playerLogout' and 'esx:onPlayerDeath' server events
]]

local RESOURCE = GetCurrentResourceName()
local inventory = exports.ox_inventory

-- Players[src] = { onShift = true, carrying = false, pickedUpAt = 0, propNetId = nil }
local Players = {}

-- Hashes can come back signed or unsigned depending on the native, so compare them like this.
local function hash32(h) return h & 0xFFFFFFFF end
local CARRY_HASH = hash32(joaat(Config.Carry.model))

local function debugLog(src, msg)
    if Config.Debug then
        print(('[%s] %s (%d): %s'):format(RESOURCE, GetPlayerName(src) or '?', src, msg))
    end
end

-- Is the player within `range` (plus lag tolerance) of `target`?
-- Uses the server's own view of the player's position (needs OneSync), never a client-sent position.
local function isNear(src, target, range)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end

    local distance = #(GetEntityCoords(ped) - vec3(target.x, target.y, target.z))
    return distance <= range + Config.Distance.serverTolerance
end

------------------------------------------------------------------------------------------------
-- Carried box prop cleanup
------------------------------------------------------------------------------------------------

-- Deletes the player's networked box prop (if the server knows about one).
-- The client normally deletes it itself; this is the backstop for disconnects and crashes.
local function deleteCarryProp(state)
    if not state.propNetId then return end

    local entity = NetworkGetEntityFromNetworkId(state.propNetId)
    -- Double-check it is still our box model before deleting, in case the net ID was reused.
    if entity ~= 0 and DoesEntityExist(entity) and hash32(GetEntityModel(entity)) == CARRY_HASH then
        DeleteEntity(entity)
    end

    state.propNetId = nil
end

-- Ends the carry on the server side (box lost, no reward).
local function clearCarry(state)
    state.carrying = false
    state.pickedUpAt = 0
    deleteCarryProp(state)
end

-- Fully removes a player's job state.
local function clearPlayer(src)
    local state = Players[src]
    if not state then return end

    clearCarry(state)
    Players[src] = nil
    debugLog(src, 'job state cleared')
end

------------------------------------------------------------------------------------------------
-- Shift
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:startShift', function(source)
    if Players[source] then return false, 'alreadyOnShift' end
    if not isNear(source, Config.Laptop.coords, Config.Distance.laptop) then return false, 'tooFar' end

    Players[source] = { onShift = true, carrying = false, pickedUpAt = 0, propNetId = nil }
    debugLog(source, 'started shift')
    return true, 'shiftStarted'
end)

-- No distance check: ending a shift only takes things away from the player, so it is always allowed.
lib.callback.register('recycling_warehouse:endShift', function(source)
    if not Players[source] then return false, 'notOnShift' end

    clearPlayer(source)
    return true, 'shiftEnded'
end)

------------------------------------------------------------------------------------------------
-- Boxes
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:pickupBox', function(source, spotIndex)
    local state = Players[source]
    if not state then return false, 'notOnShift' end
    if state.carrying then return false, 'alreadyCarrying' end

    -- The client only sends which spot it used. The position comes from OUR config.
    local spot = type(spotIndex) == 'number' and Config.Pickups[spotIndex]
    if not spot then return false, 'failed' end
    if not isNear(source, spot.coords, Config.Distance.pickup) then return false, 'tooFar' end

    state.carrying = true
    state.pickedUpAt = GetGameTimer()
    debugLog(source, ('picked up a box at spot %d'):format(spotIndex))
    return true, 'pickedUp'
end)

-- The client tells us the network ID of the box prop it created, so we can delete it if the player
-- disconnects. We only accept a box model, owned by that player, while they are carrying.
RegisterNetEvent('recycling_warehouse:registerCarryProp', function(netId)
    local src = source
    local state = Players[src]
    if not state or not state.carrying or state.propNetId or type(netId) ~= 'number' then return end

    -- The entity can take a moment to appear on the server after the client creates it.
    for _ = 1, 20 do
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity ~= 0 and DoesEntityExist(entity) then
            if hash32(GetEntityModel(entity)) == CARRY_HASH and NetworkGetEntityOwner(entity) == src then
                -- Re-check: the carry may have ended while we were waiting.
                if Players[src] == state and state.carrying then
                    state.propNetId = netId
                end
            end
            return
        end

        Wait(100)
    end
end)

lib.callback.register('recycling_warehouse:deliverBox', function(source)
    local state = Players[source]
    if not state then return false, 'notOnShift' end
    if not state.carrying then return false, 'notCarrying' end
    if not isNear(source, Config.Skip.coords, Config.Distance.skip) then return false, 'tooFar' end

    -- A real delivery always includes the full progress bar, so it can't happen faster than that.
    -- This stops "pick up + deliver" being fired instantly in a loop.
    if GetGameTimer() - state.pickedUpAt < Config.Skip.progressDuration then
        return false, 'tooFast'
    end

    if not inventory:CanCarryItem(source, Config.RecycleItem, Config.RecycleAmount) then
        return false, 'inventoryFull' -- they keep the box and can try again after making space
    end

    local success = inventory:AddItem(source, Config.RecycleItem, Config.RecycleAmount)
    if not success then return false, 'failed' end

    clearCarry(state)
    debugLog(source, 'delivered a box')
    return true, 'delivered'
end)

-- The client says it lost the box (death, getting in a vehicle, leaving the area).
-- Trusting this is safe: it can only take the box away, never give anything.
RegisterNetEvent('recycling_warehouse:boxDropped', function()
    local state = Players[source]
    if state then clearCarry(state) end
end)

------------------------------------------------------------------------------------------------
-- Trader
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:getRecycleCount', function(source)
    return inventory:GetItemCount(source, Config.RecycleItem) or 0
end)

-- Returns: success, messageKey, current recycle box count (so the menu can refresh).
lib.callback.register('recycling_warehouse:trade', function(source, materialIndex)
    local count = inventory:GetItemCount(source, Config.RecycleItem) or 0

    if Config.Trader.requireShift and not Players[source] then return false, 'notOnShift', count end
    if not isNear(source, Config.Trader.coords, Config.Distance.trader) then return false, 'tooFar', count end

    -- The client only sends a number; the item, cost and amount all come from our config.
    local material = type(materialIndex) == 'number' and Config.Materials[materialIndex]
    if not material then return false, 'failed', count end

    if count < material.cost then return false, 'cannotAfford', count end

    -- Weight check that accounts for the recycle boxes being removed first.
    if not inventory:CanSwapItem(source, Config.RecycleItem, material.cost, material.item, material.amount) then
        return false, 'inventoryFull', count
    end

    -- 1) Take the cost.
    if not inventory:RemoveItem(source, Config.RecycleItem, material.cost) then
        return false, 'failed', count
    end

    -- 2) Give the materials. If that fails (e.g. no free slot), refund the cost.
    if not inventory:AddItem(source, material.item, material.amount) then
        inventory:AddItem(source, Config.RecycleItem, material.cost)
        return false, 'inventoryFull', count
    end

    debugLog(source, ('traded %d %s for %dx %s'):format(material.cost, Config.RecycleItem, material.amount, material.item))
    return true, 'traded', count - material.cost
end)

------------------------------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------------------------------

-- Disconnect.
AddEventHandler('playerDropped', function()
    clearPlayer(source)
end)

-- ESX character logout / switch (esx_multicharacter). The client also resets itself.
AddEventHandler('esx:playerLogout', function(playerId)
    clearPlayer(playerId)
end)

-- ESX death: the box is lost (the shift stays active).
RegisterNetEvent('esx:onPlayerDeath', function()
    local state = Players[source]
    if state then clearCarry(state) end
end)

-- Resource stop/restart: delete any box props the server knows about. State is lost anyway.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end

    for _, state in pairs(Players) do
        deleteCarryProp(state)
    end
end)
