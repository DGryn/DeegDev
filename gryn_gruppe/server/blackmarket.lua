--[[
    gryn_gruppe - server/blackmarket.lua

    Black market NPC: buy items (clean or dirty cash), sell stolen bags and crates for clean cash.
    Opening a stolen item yourself (used from the inventory) pays more, in dirty cash, but may be
    inked. Every price and value is worked out here; the client only sends what it picked.
]]

local BM = Config.BlackMarket
local STOLEN = { [Config.Items.moneybag] = true, [Config.Items.crate] = true }

local function nearNpc(src)
    return G6.Near(src, BM.npc.coords, Config.ServerDistance + 2.0)
end

local function shopEntry(index)
    return type(index) == 'number' and BM.shop[index] or nil
end

-- Why a player cannot buy an entry (nil = they can).
local function lockReason(src, entry)
    local row = G6.GetData(src)
    if not row then return 'Unavailable.' end
    local level = G6.UnlockLevel('items', entry.item)
    if level and row.level < level then return ('Needs Gruppe 6 level %d.'):format(level) end
    if entry.rep and entry.rep > 0 and row.reputation < entry.rep then return ('Needs %d reputation.'):format(entry.rep) end
    return nil
end

local function stolenSlots(src)
    local list = {}
    for name in pairs(STOLEN) do
        for _, slot in ipairs(exports.ox_inventory:Search(src, 'slots', name) or {}) do
            local value = slot.metadata and tonumber(slot.metadata.value) or 0
            list[#list + 1] = {
                slot = slot.slot, name = name, label = slot.label or name, value = value,
                price = math.floor(value * BM.sellPercent / 100),
            }
        end
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

local function menuData(src)
    local shop = {}
    for i, entry in ipairs(BM.shop) do
        shop[#shop + 1] = { index = i, item = entry.item, label = entry.label, price = entry.price, currency = entry.currency, locked = lockReason(src, entry) }
    end
    return {
        shop = shop,
        stolen = stolenSlots(src),
        sellPercent = BM.sellPercent,
        clean = G6.GetMoney(src, 'money'),
        dirty = exports.ox_inventory:GetItemCount(src, Config.Items.dirty) or 0,
    }
end

lib.callback.register('gryn_gruppe:bmOpen', function(src)
    if not nearNpc(src) then return nil end
    return menuData(src)
end)

lib.callback.register('gryn_gruppe:bmBuy', function(src, index, amount)
    if G6.RateLimited(src, 'bmBuy', 500) then return false end
    local entry = shopEntry(index)
    amount = math.floor(tonumber(amount) or 1)
    if not entry or amount < 1 or amount > 10 then return false end
    if not nearNpc(src) then return false, 'Too far away.' end
    local locked = lockReason(src, entry)
    if locked then return false, locked end
    if not exports.ox_inventory:CanCarryItem(src, entry.item, amount) then return false, 'You cannot carry that.' end

    local cost = entry.price * amount
    if entry.currency == 'dirty' then
        if (exports.ox_inventory:GetItemCount(src, Config.Items.dirty) or 0) < cost then return false, 'Not enough dirty cash.' end
        if not exports.ox_inventory:RemoveItem(src, Config.Items.dirty, cost) then return false end
    else
        if not G6.RemoveMoney(src, 'money', cost, 'Black market') then return false, 'Not enough cash.' end
    end

    exports.ox_inventory:AddItem(src, entry.item, amount)
    G6.Log('Black market buy', ('%s bought %dx %s for $%d (%s)'):format(G6.Name(src), amount, entry.item, cost, entry.currency))
    return true, ('Bought %dx %s.'):format(amount, entry.label), menuData(src)
end)

lib.callback.register('gryn_gruppe:bmSell', function(src, slotId)
    if G6.RateLimited(src, 'bmSell', 500) then return false end
    if not nearNpc(src) then return false, 'Too far away.' end
    local slot = type(slotId) == 'number' and exports.ox_inventory:GetSlot(src, slotId)
    if not slot or not STOLEN[slot.name] then return false end

    local value = slot.metadata and tonumber(slot.metadata.value) or 0
    local price = math.floor(value * BM.sellPercent / 100)
    if not exports.ox_inventory:RemoveItem(src, slot.name, 1, nil, slotId) then return false end
    G6.AddMoney(src, 'money', price, 'Black market sale')
    G6.Log('Black market sell', ('%s sold a %s (value $%d) for $%d'):format(G6.Name(src), slot.name, value, price))
    return true, ('Sold for $%s.'):format(price), menuData(src)
end)

-- Used from the inventory (client export openStolen), after the progress bar.
lib.callback.register('gryn_gruppe:openStolen', function(src, slotId)
    if G6.RateLimited(src, 'open', math.floor(Config.Progress.openStolen * 0.8)) then return false end
    local slot = type(slotId) == 'number' and exports.ox_inventory:GetSlot(src, slotId)
    if not slot or not STOLEN[slot.name] then return false end

    local value = slot.metadata and tonumber(slot.metadata.value) or 0
    if not exports.ox_inventory:RemoveItem(src, slot.name, 1, nil, slotId) then return false end

    if math.random(100) <= BM.inkChance then
        G6.Log('Stolen item opened', ('%s opened a %s: inked'):format(G6.Name(src), slot.name))
        return false, 'A dye pack went off. The money is ruined.'
    end

    local payout = math.floor(value * BM.openPercent / 100)
    exports.ox_inventory:AddItem(src, Config.Items.dirty, payout)
    G6.Log('Stolen item opened', ('%s opened a %s: $%d dirty'):format(G6.Name(src), slot.name, payout))
    return true, ('You count out $%s in marked bills.'):format(payout)
end)
