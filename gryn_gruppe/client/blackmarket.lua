--[[
    gryn_gruppe - client/blackmarket.lua

    Black market NPC (buy / sell menu in the NUI) and the inventory use of a stolen bag or crate
    (ox_inventory item `client.export = 'gryn_gruppe.openStolen'`).
]]

local BM = Config.BlackMarket
local ped
local busy = false

local function openMenu()
    if G6C.ui then return end
    local data = lib.callback.await('gryn_gruppe:bmOpen', false)
    if not data then return end
    G6C.Send('openMarket', data)
    G6C.Focus('blackmarket')
end

RegisterNUICallback('market', function(body, cb)
    local ok, msg, data
    if body.action == 'buy' then
        ok, msg, data = lib.callback.await('gryn_gruppe:bmBuy', false, body.index, body.amount)
    elseif body.action == 'sell' then
        ok, msg, data = lib.callback.await('gryn_gruppe:bmSell', false, body.slot)
    end
    G6C.Notify(msg, ok and 'success' or 'error')
    cb({ ok = ok, data = data })
end)

lib.points.new({
    coords = BM.npc.coords.xyz,
    distance = Config.RenderDistance,
    onEnter = function()
        ped = G6C.SpawnPed(BM.npc.model, BM.npc.coords, BM.npc.scenario)
        if not ped then return end
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'gryn_gruppe_blackmarket',
                icon = 'fa-solid fa-user-secret',
                label = 'Talk business',
                distance = Config.InteractDistance + 0.5,
                onSelect = openMenu,
            },
        })
    end,
    onExit = function()
        G6C.DeletePed(ped)
        ped = nil
    end,
})

-- Called by ox_inventory when a stolen bag or crate is used. The server rolls the ink chance
-- and pays out.
exports('openStolen', function(data, slot)
    if busy or not slot then return end
    busy = true
    local done = lib.progressBar({
        duration = Config.Progress.openStolen, label = 'Prying it open...', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    })
    if done then
        local ok, msg = lib.callback.await('gryn_gruppe:openStolen', false, slot.slot)
        G6C.Notify(msg, ok and 'success' or 'error')
    end
    busy = false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    G6C.DeletePed(ped)
end)
