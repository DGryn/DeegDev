--[[
    gryn_gruppe - client/main.lua

    HQ NPC + blip, the NUI tablet (open/close/focus), NUI callbacks for the tablet and the
    group invite prompt. The NUI also draws the black market menu and the thermite minigame
    (see client/blackmarket.lua and client/robbery.lua). Everything the tablet does is a server
    callback; the client never decides money, XP or items.

    API references:
      lib.callback      https://coxdocs.dev/ox_lib/Modules/Callback/Client
      lib.points        https://coxdocs.dev/ox_lib/Modules/Points/Client
      ox_target         https://coxdocs.dev/ox_target/Client
      NUI               https://docs.fivem.net/docs/scripting-manual/nui-development/
]]

G6C = { ui = nil } -- shared client state; ui = 'tablet' | 'blackmarket' | 'minigame' | 'invite' | nil

function G6C.Notify(msg, kind)
    if msg then lib.notify({ title = 'Gruppe 6', description = msg, type = kind or 'inform' }) end
end

function G6C.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function G6C.Focus(ui)
    G6C.ui = ui
    SetNuiFocus(ui ~= nil, ui ~= nil)
end

function G6C.LoadModel(model)
    if not IsModelInCdimage(model) then
        print(('^1[gryn_gruppe] model %s is not valid, check config.lua^7'):format(model))
        return false
    end
    lib.requestModel(model)
    return true
end

-- Spawns a local, frozen, invincible NPC. Returns the ped.
function G6C.SpawnPed(model, coords, scenario)
    if not G6C.LoadModel(model) then return nil end
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if scenario then TaskStartScenarioInPlace(ped, scenario, 0, true) end
    SetModelAsNoLongerNeeded(model)
    return ped
end

function G6C.DeletePed(ped)
    if ped and DoesEntityExist(ped) then
        exports.ox_target:removeLocalEntity(ped)
        DeleteEntity(ped)
    end
end

------------------------------------------------------------------------------------------------
-- Tablet
------------------------------------------------------------------------------------------------

local function openTablet()
    if G6C.ui then return end
    local data = lib.callback.await('gryn_gruppe:tablet', false)
    if not data then return G6C.Notify('Get closer to the dispatcher.', 'error') end
    G6C.Send('openTablet', data)
    G6C.Focus('tablet')
end

-- Re-sends fresh data while the tablet is open (group or job changed).
local function refreshTablet()
    if G6C.ui ~= 'tablet' then return end
    local data = lib.callback.await('gryn_gruppe:tablet', false)
    if data then G6C.Send('tabletData', data) end
end

RegisterNetEvent('gryn_gruppe:refresh', refreshTablet)

RegisterNUICallback('close', function(_, cb)
    if G6C.ui == 'minigame' then return cb(false) end -- the minigame ends itself
    G6C.Send('close')
    G6C.Focus(nil)
    cb(true)
end)

-- Generic tablet action: forwards to a server callback, answers the NUI with { ok, msg, data }.
local ACTIONS = {
    claimDaily = 'gryn_gruppe:claimDaily',
    startJob = 'gryn_gruppe:startJob',
    nearby = 'gryn_gruppe:nearbyPlayers',
    invite = 'gryn_gruppe:invite',
    kick = 'gryn_gruppe:kick',
    leaveGroup = 'gryn_gruppe:leaveGroup',
}

RegisterNUICallback('tablet', function(body, cb)
    local name = ACTIONS[body and body.action]
    if not name then return cb({ ok = false }) end

    local ok, msg, data = lib.callback.await(name, false, body.arg)
    if body.action == 'nearby' then return cb({ ok = true, data = ok or {} }) end
    G6C.Notify(msg, ok and 'success' or 'error')
    if body.action == 'startJob' and ok then
        G6C.Send('close')
        G6C.Focus(nil)
    end
    cb({ ok = ok, data = data })
    if ok and not data then refreshTablet() end
end)

------------------------------------------------------------------------------------------------
-- Invites
------------------------------------------------------------------------------------------------

RegisterNetEvent('gryn_gruppe:invited', function(info)
    if G6C.ui and G6C.ui ~= 'tablet' then
        -- Busy in another menu: answer with a dialog instead.
        local answer = lib.alertDialog({
            header = 'Gruppe 6', content = ('%s invited you to their crew.'):format(info.from),
            centered = true, cancel = true, labels = { confirm = 'Accept', cancel = 'Decline' },
        })
        local ok, msg = lib.callback.await('gryn_gruppe:respondInvite', false, answer == 'confirm')
        return G6C.Notify(msg, ok and 'success' or 'error')
    end
    G6C.Send('invite', info)
    if not G6C.ui then G6C.Focus('invite') end
end)

RegisterNUICallback('respondInvite', function(body, cb)
    local ok, msg = lib.callback.await('gryn_gruppe:respondInvite', false, body and body.accept == true)
    G6C.Notify(msg, ok and 'success' or 'error')
    if G6C.ui == 'invite' then G6C.Focus(nil) end
    cb(true)
    refreshTablet()
end)

------------------------------------------------------------------------------------------------
-- HQ NPC and blip
------------------------------------------------------------------------------------------------

local hqPed

CreateThread(function()
    local b = Config.HQ.blip
    local c = Config.HQ.npc.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.colour)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.label)
    EndTextCommandSetBlipName(blip)
end)

lib.points.new({
    coords = Config.HQ.npc.coords.xyz,
    distance = Config.RenderDistance,
    onEnter = function()
        hqPed = G6C.SpawnPed(Config.HQ.npc.model, Config.HQ.npc.coords, Config.HQ.npc.scenario)
        if not hqPed then return end
        exports.ox_target:addLocalEntity(hqPed, {
            {
                name = 'gryn_gruppe_tablet',
                icon = 'fa-solid fa-tablet-screen-button',
                label = 'Open Gruppe 6 tablet',
                distance = Config.InteractDistance + 0.5,
                onSelect = openTablet,
            },
        })
    end,
    onExit = function()
        G6C.DeletePed(hqPed)
        hqPed = nil
    end,
})

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    G6C.DeletePed(hqPed)
end)
