--[[
    recycling_warehouse - server.lua

    The server is the authority. The client only ASKS to do things; every request is checked here:
      - Start shift      -> not already on shift, standing at the laptop
      - Pick up a box    -> on shift, empty-handed, standing at THE pickup prop the server assigned
      - Deliver a box    -> two steps: "start" (on shift, carrying, at the skip; the server decides
                            whether there is a skill check) and "finish" (same checks again, plus the
                            progress bar time has really passed, plus room in the inventory)
      - Trade            -> standing at the trader, a real material, a sane amount, enough recycle
                            boxes, room for the materials; the cost is removed BEFORE materials are given
      - Claim a goal     -> standing at the laptop, goal finished and not yet claimed

    Two kinds of player data:
      Players[src]   the current shift (memory only, wiped on disconnect / logout / shift end)
      Profiles[src]  XP, lifetime stats and today's goals (loaded from / saved to the database)

    APIs used (checked against their source code on GitHub):
      ox_lib         lib.callback.register, 'ox_lib:notify' client event
      ox_inventory   GetItemCount, CanCarryItem, CanSwapItem, AddItem, RemoveItem, Items
      oxmysql        MySQL.ready, MySQL.single.await, MySQL.query, MySQL.update
      ESX            ESX.GetPlayerFromId(src).identifier, 'esx:playerLogout', 'esx:onPlayerDeath'
]]

local RESOURCE = GetCurrentResourceName()

-- oxmysql's MySQL helper is loaded by fxmanifest.lua ('@oxmysql/lib/MySQL.lua'). If it's missing,
-- stop here with a clear message instead of crashing later.
if not MySQL then
    error('oxmysql is not loaded. Check that fxmanifest.lua lists \'@oxmysql/lib/MySQL.lua\' under server_scripts, '
        .. 'that oxmysql starts before this resource, and type "refresh" in the console after changing fxmanifest.lua.')
end

local ESX = exports.es_extended:getSharedObject()
local inventory = exports.ox_inventory
local Text = Config.Text

local Players = {}   -- [src] = { carrying, pickedUpAt, propNetId, activeSpot, delivery }
local Profiles = {}  -- [src] = { identifier, xp, boxes, skillHits, trades, rareFinds, goalsCompleted, shifts, goalsDay, goals }

-- Hashes can come back signed or unsigned depending on the native, so compare them like this.
local function hash32(h) return h & 0xFFFFFFFF end
local CARRY_HASH = hash32(joaat(Config.Carry.model))

------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------

local function debugLog(src, msg)
    if Config.Debug then
        print(('[%s] %s (%d): %s'):format(RESOURCE, GetPlayerName(src) or '?', src, msg))
    end
end

-- Sends an ox_lib notification to one player. `key` is a Config.Text entry.
local function notify(src, key, kind, ...)
    local text = Text[key] or Text.failed
    if select('#', ...) > 0 then text = text:format(...) end
    TriggerClientEvent('ox_lib:notify', src, { description = text, type = kind or 'inform' })
end

-- Is the player within `range` (plus lag tolerance) of `target`?
-- Uses the server's own view of the player's position (needs OneSync), never a client-sent position.
local function isNear(src, target, range)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end

    local distance = #(GetEntityCoords(ped) - vec3(target.x, target.y, target.z))
    return distance <= range + Config.Distance.serverTolerance
end

-- The label ox_inventory uses for an item, e.g. 'copper' -> 'Copper'.
local function itemLabel(name)
    local item = inventory:Items(name)
    return item and item.label or name
end

-- Rolls a number from 0 to 100 and returns true with `percent` % chance.
local function chance(percent)
    return math.random() * 100 < percent
end

------------------------------------------------------------------------------------------------
-- Days, levels and the daily market
------------------------------------------------------------------------------------------------

-- The "day" a moment belongs to, shifted by the reset hour. E.g. with reset hour 6, 03:00 on the
-- 5th still counts as the 4th.
local function dayKey()
    return os.date('%Y-%m-%d', os.time() - Config.DailyResetHour * 3600)
end

local function secondsUntilReset()
    local now = os.time()
    local t = os.date('*t', now)
    t.hour, t.min, t.sec = Config.DailyResetHour, 0, 0

    local reset = os.time(t)
    if reset <= now then reset = reset + 86400 end
    return reset - now
end

-- Level number (1, 2, 3...) for an amount of XP.
local function levelFromXp(xp)
    local level = 1
    for i, data in ipairs(Config.Levels) do
        if xp >= data.xp then level = i end
    end
    return level
end

local function perksFor(level)
    local data = Config.Levels[level] or {}
    return {
        bonusBoxes = data.bonusBoxes or 0,
        tradeBonus = data.tradeBonus or 0,
        rareChance = data.rareChance or 0,
    }
end

-- A tiny random number generator that always gives the same numbers for the same text.
-- Seeding it with the date means everyone gets the same rates all day, even after a restart.
local function seededRandom(seedText)
    local seed = 0
    for i = 1, #seedText do
        seed = (seed * 31 + seedText:byte(i)) % 2147483647
    end
    if seed == 0 then seed = 1 end

    return function(max) -- returns a whole number from 1 to max
        seed = (seed * 16807) % 2147483647
        return seed % max + 1
    end
end

local RatingByKey = {}
for _, rating in ipairs(Config.Market.ratings) do RatingByKey[rating.key] = rating end

local market = { day = nil, ratings = {} } -- ratings[materialIndex] = a Config.Market.ratings entry

-- Today's rating for every material. Worked out once per day.
local function getMarket()
    local today = dayKey()
    if market.day == today then return market.ratings end

    local random = seededRandom(today .. RESOURCE)

    -- Shuffle the materials so the guaranteed ratings land on a different material each day.
    local order = {}
    for i = 1, #Config.Materials do order[i] = i end
    for i = #order, 2, -1 do
        local j = random(i)
        order[i], order[j] = order[j], order[i]
    end

    local ratings = {}
    for position, materialIndex in ipairs(order) do
        local key = Config.Market.guaranteed[position]
            or Config.Market.randomPool[random(#Config.Market.randomPool)]
        ratings[materialIndex] = RatingByKey[key] or Config.Market.ratings[1]
    end

    market.day, market.ratings = today, ratings
    return ratings
end

-- How many items ONE trade of a material gives right now: base amount x daily rating x level bonus.
local function amountPerTrade(materialIndex, perks)
    local material = Config.Materials[materialIndex]
    local rating = getMarket()[materialIndex]
    local amount = material.amount * rating.multiplier * (1 + perks.tradeBonus / 100)
    return math.max(1, math.floor(amount + 0.5))
end

------------------------------------------------------------------------------------------------
-- Database profile
------------------------------------------------------------------------------------------------

local CREATE_TABLE = [[
CREATE TABLE IF NOT EXISTS `recycling_warehouse_players` (
    `identifier` VARCHAR(64) NOT NULL,
    `xp` INT UNSIGNED NOT NULL DEFAULT 0,
    `boxes_delivered` INT UNSIGNED NOT NULL DEFAULT 0,
    `skill_hits` INT UNSIGNED NOT NULL DEFAULT 0,
    `trades` INT UNSIGNED NOT NULL DEFAULT 0,
    `rare_finds` INT UNSIGNED NOT NULL DEFAULT 0,
    `goals_completed` INT UNSIGNED NOT NULL DEFAULT 0,
    `shifts` INT UNSIGNED NOT NULL DEFAULT 0,
    `goals_day` VARCHAR(10) NULL DEFAULT NULL,
    `goals` LONGTEXT NULL DEFAULT NULL,
    PRIMARY KEY (`identifier`)
)]]

if Config.AutoCreateTable then
    MySQL.ready(function()
        MySQL.query(CREATE_TABLE)
    end)
end

-- Loads (once) and returns the player's profile, or nil if they have no ESX character yet.
local function getProfile(src)
    if Profiles[src] then return Profiles[src] end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end

    local row = MySQL.single.await('SELECT * FROM `recycling_warehouse_players` WHERE `identifier` = ?', { xPlayer.identifier })

    -- Another request may have loaded it while we waited for the database.
    if Profiles[src] then return Profiles[src] end

    row = row or {}
    Profiles[src] = {
        identifier = xPlayer.identifier,
        xp = row.xp or 0,
        boxes = row.boxes_delivered or 0,
        skillHits = row.skill_hits or 0,
        trades = row.trades or 0,
        rareFinds = row.rare_finds or 0,
        goalsCompleted = row.goals_completed or 0,
        shifts = row.shifts or 0,
        goalsDay = row.goals_day,
        goals = row.goals and json.decode(row.goals) or {},
    }
    return Profiles[src]
end

-- Writes the profile to the database. "Insert, or update if it already exists" in one query.
local function saveProfile(profile)
    MySQL.update([[
        INSERT INTO `recycling_warehouse_players`
            (`identifier`, `xp`, `boxes_delivered`, `skill_hits`, `trades`, `rare_finds`, `goals_completed`, `shifts`, `goals_day`, `goals`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `xp` = VALUES(`xp`), `boxes_delivered` = VALUES(`boxes_delivered`), `skill_hits` = VALUES(`skill_hits`),
            `trades` = VALUES(`trades`), `rare_finds` = VALUES(`rare_finds`), `goals_completed` = VALUES(`goals_completed`),
            `shifts` = VALUES(`shifts`), `goals_day` = VALUES(`goals_day`), `goals` = VALUES(`goals`)
    ]], {
        profile.identifier, profile.xp, profile.boxes, profile.skillHits, profile.trades, profile.rareFinds,
        profile.goalsCompleted, profile.shifts, profile.goalsDay, json.encode(profile.goals),
    })
end

-- Adds XP and tells the player if they reached a new level.
local function addXp(src, profile, amount)
    if amount <= 0 then return end

    local before = levelFromXp(profile.xp)
    profile.xp = profile.xp + amount
    local after = levelFromXp(profile.xp)

    if after > before then notify(src, 'levelUp', 'success', after) end
end

------------------------------------------------------------------------------------------------
-- Goals
------------------------------------------------------------------------------------------------

local GoalById = {}
for _, goal in ipairs(Config.Goals.pool) do GoalById[goal.id] = goal end

local function goalText(definition)
    return definition.label:format(definition.target)
end

-- "6x Plastic, 40 XP"
local function rewardText(reward)
    local parts = {}
    for _, entry in ipairs(reward.items or {}) do
        parts[#parts + 1] = ('%dx %s'):format(entry.count, itemLabel(entry.item))
    end
    if reward.xp and reward.xp > 0 then parts[#parts + 1] = ('%d XP'):format(reward.xp) end
    return table.concat(parts, ', ')
end

-- Gives today's goals if the player doesn't have them yet.
local function ensureGoals(profile)
    if not Config.Goals.enabled then return end

    local today = dayKey()
    if profile.goalsDay == today then return end

    -- Pick `perDay` different goals at random.
    local pool = {}
    for i, goal in ipairs(Config.Goals.pool) do pool[i] = goal end

    local goals = {}
    for _ = 1, math.min(Config.Goals.perDay, #pool) do
        local goal = table.remove(pool, math.random(#pool))
        goals[#goals + 1] = { id = goal.id, progress = 0, done = false, claimed = false }
    end

    profile.goalsDay = today
    profile.goals = goals
end

-- Today's goals, or an empty list if they are from an earlier day.
local function todaysGoals(profile)
    if profile.goalsDay ~= dayKey() then return {} end
    return profile.goals
end

-- Gives a goal's reward. Returns false (and gives nothing) if the items don't fit.
local function giveReward(src, profile, reward)
    for _, entry in ipairs(reward.items or {}) do
        if not inventory:CanCarryItem(src, entry.item, entry.count) then return false end
    end

    for _, entry in ipairs(reward.items or {}) do
        inventory:AddItem(src, entry.item, entry.count)
    end

    addXp(src, profile, reward.xp or 0)
    return true
end

-- Moves every goal of `goalType` forward by `amount` and rewards any that are now finished.
local function addGoalProgress(src, profile, goalType, amount)
    if not Config.Goals.enabled or amount <= 0 then return end

    -- A shift that runs past the daily reset picks up the new day's goals.
    if Players[src] then ensureGoals(profile) end

    for _, goal in ipairs(todaysGoals(profile)) do
        local definition = GoalById[goal.id]

        if definition and definition.type == goalType and not goal.done then
            goal.progress = math.min(definition.target, goal.progress + amount)

            if goal.progress >= definition.target then
                goal.done = true
                profile.goalsCompleted = profile.goalsCompleted + 1

                if giveReward(src, profile, definition.reward or {}) then
                    goal.claimed = true
                    notify(src, 'goalDone', 'success', goalText(definition))
                else
                    notify(src, 'goalClaimLater', 'inform', goalText(definition))
                end
            end
        end
    end
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
    state.delivery = nil
    deleteCarryProp(state)
end

-- Ends the shift and forgets the cached profile (used on disconnect / logout).
local function clearPlayer(src, forgetProfile)
    local state = Players[src]
    if state then
        clearCarry(state)
        Players[src] = nil
        debugLog(src, 'shift state cleared')
    end

    if forgetProfile then Profiles[src] = nil end
end

-- Picks the pickup prop the player must use next: a random one, never the same one twice in a row.
local function pickNextSpot(state)
    local total = #Config.Pickups
    local spot = math.random(total)

    if total > 1 then
        while spot == state.activeSpot do spot = math.random(total) end
    end

    state.activeSpot = spot
    return spot
end

------------------------------------------------------------------------------------------------
-- Shift
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:startShift', function(source)
    if Players[source] then return false, 'alreadyOnShift' end
    if not isNear(source, Config.Laptop.coords, Config.Distance.laptop) then return false, 'tooFar' end

    local profile = getProfile(source)
    if not profile then return false, 'noProfile' end

    local state = { carrying = false, pickedUpAt = 0, propNetId = nil, activeSpot = nil, delivery = nil }
    Players[source] = state

    profile.shifts = profile.shifts + 1
    ensureGoals(profile)
    saveProfile(profile)

    debugLog(source, 'started shift')
    -- Also tell the client which prop to highlight.
    return true, 'shiftStarted', pickNextSpot(state)
end)

-- No distance check: ending a shift only takes things away from the player, so it is always allowed.
lib.callback.register('recycling_warehouse:endShift', function(source)
    if not Players[source] then return false, 'notOnShift' end

    clearPlayer(source, false)
    return true, 'shiftEnded'
end)

------------------------------------------------------------------------------------------------
-- Boxes
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:pickupBox', function(source, spotIndex)
    local state = Players[source]
    if not state then return false, 'notOnShift' end
    if state.carrying then return false, 'alreadyCarrying' end

    -- Only the spot the server assigned counts. The position comes from OUR config.
    if spotIndex ~= state.activeSpot then return false, 'wrongSpot' end
    local spot = Config.Pickups[spotIndex]
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

-- Step 1 of a delivery. The SERVER decides whether this delivery gets a skill check.
-- Returns: ok, messageKey, skillCheck (false or { difficulty, keys })
lib.callback.register('recycling_warehouse:startDeliver', function(source)
    local state = Players[source]
    if not state then return false, 'notOnShift' end
    if not state.carrying then return false, 'notCarrying' end
    if not isNear(source, Config.Skip.coords, Config.Distance.skip) then return false, 'tooFar' end

    local skill = Config.SkillCheck.enabled and chance(Config.SkillCheck.chance)
    state.delivery = { startedAt = GetGameTimer(), skill = skill }

    return true, 'ok', skill and { difficulty = Config.SkillCheck.difficulty, keys = Config.SkillCheck.keys } or false
end)

-- Step 2 of a delivery. `hit` only counts if step 1 actually asked for a skill check.
-- Returns: ok, messageKey, result { boxes, skill, hit, nextSpot }
lib.callback.register('recycling_warehouse:finishDeliver', function(source, hit)
    local state = Players[source]
    if not state then return false, 'notOnShift' end
    if not state.carrying then return false, 'notCarrying' end
    if not state.delivery then return false, 'failed' end
    if not isNear(source, Config.Skip.coords, Config.Distance.skip) then return false, 'tooFar' end

    -- The progress bar must really have run (small allowance for network delay).
    if GetGameTimer() - state.delivery.startedAt < Config.Skip.progressDuration - 300 then
        return false, 'tooFast'
    end

    local profile = getProfile(source)
    if not profile then return false, 'noProfile' end

    local perks = perksFor(levelFromXp(profile.xp))
    local skill = state.delivery.skill
    hit = skill and hit == true

    local boxes = Config.RecycleAmount + perks.bonusBoxes + (hit and Config.SkillCheck.bonusBoxes or 0)

    if not inventory:CanCarryItem(source, Config.RecycleItem, boxes) then
        state.delivery = nil
        return false, 'inventoryFull' -- they keep the box and can try again after making space
    end

    if not inventory:AddItem(source, Config.RecycleItem, boxes) then
        state.delivery = nil
        return false, 'failed'
    end

    clearCarry(state)

    -- Stats, XP and goals.
    profile.boxes = profile.boxes + 1
    addXp(source, profile, Config.Xp.perBox + (hit and Config.SkillCheck.bonusXp or 0))
    addGoalProgress(source, profile, 'deliver', 1)

    if hit then
        profile.skillHits = profile.skillHits + 1
        addGoalProgress(source, profile, 'skill', 1)
    end

    -- Rare find: a small chance the box had something unusual inside.
    local rare = Config.RareFinds
    if rare.enabled and #rare.items > 0 and chance(rare.chance + perks.rareChance) then
        local total = 0
        for _, entry in ipairs(rare.items) do total = total + entry.weight end

        local roll = math.random() * total
        for _, entry in ipairs(rare.items) do
            roll = roll - entry.weight
            if roll <= 0 then
                local amount = math.random(entry.min or 1, entry.max or 1)

                if inventory:CanCarryItem(source, entry.item, amount) and inventory:AddItem(source, entry.item, amount) then
                    profile.rareFinds = profile.rareFinds + 1
                    notify(source, 'rareFind', 'success', amount, itemLabel(entry.item))
                else
                    notify(source, 'rareNoRoom', 'error', itemLabel(entry.item))
                end
                break
            end
        end
    end

    saveProfile(profile)
    debugLog(source, ('delivered a box: %d recycle boxes, skill %s, hit %s'):format(boxes, tostring(skill), tostring(hit)))

    return true, 'delivered', { boxes = boxes, skill = skill, hit = hit, nextSpot = pickNextSpot(state) }
end)

-- The client says it lost the box (death, getting in a vehicle, leaving the area).
-- Trusting this is safe: it can only take the box away, never give anything.
RegisterNetEvent('recycling_warehouse:boxDropped', function()
    local state = Players[source]
    if state then clearCarry(state) end
end)

------------------------------------------------------------------------------------------------
-- Laptop screen
------------------------------------------------------------------------------------------------

-- Today's market as a list for the screens.
local function marketList(perks)
    local list = {}
    local ratings = getMarket()

    for index, material in ipairs(Config.Materials) do
        list[#list + 1] = {
            index = index,
            label = material.label,
            cost = material.cost,
            amount = amountPerTrade(index, perks),
            rating = ratings[index].key,
            ratingLabel = ratings[index].label,
        }
    end
    return list
end

local function laptopData(src)
    local profile = getProfile(src)
    if not profile then return nil end

    local level = levelFromXp(profile.xp)
    local current = Config.Levels[level]
    local nextLevel = Config.Levels[level + 1]

    local goals = {}
    for index, goal in ipairs(todaysGoals(profile)) do
        local definition = GoalById[goal.id]
        if definition then
            goals[#goals + 1] = {
                index = index,
                text = goalText(definition),
                progress = goal.progress,
                target = definition.target,
                done = goal.done,
                claimed = goal.claimed,
                reward = rewardText(definition.reward or {}),
            }
        end
    end

    local perks = perksFor(level)

    return {
        onShift = Players[src] ~= nil,
        goalsEnabled = Config.Goals.enabled,
        level = level,
        xp = profile.xp,
        levelXp = current.xp,                       -- XP where this level started
        nextXp = nextLevel and nextLevel.xp or nil, -- XP for the next level (nil = max level)
        perks = perks,
        nextPerks = nextLevel and perksFor(level + 1) or nil,
        stats = {
            boxes = profile.boxes,
            skillHits = profile.skillHits,
            trades = profile.trades,
            rareFinds = profile.rareFinds,
            goalsCompleted = profile.goalsCompleted,
            shifts = profile.shifts,
        },
        goals = goals,
        market = marketList(perks),
        resetIn = secondsUntilReset(),
    }
end

lib.callback.register('recycling_warehouse:getLaptopData', function(source)
    return laptopData(source)
end)

-- Claims a finished goal whose reward didn't fit in the inventory at the time.
lib.callback.register('recycling_warehouse:claimGoal', function(source, goalIndex)
    if not isNear(source, Config.Laptop.coords, Config.Distance.laptop) then return false, 'tooFar' end

    local profile = getProfile(source)
    if not profile then return false, 'noProfile' end

    local goal = type(goalIndex) == 'number' and todaysGoals(profile)[goalIndex]
    local definition = goal and GoalById[goal.id]
    if not definition or not goal.done or goal.claimed then return false, 'notClaimable' end

    if not giveReward(source, profile, definition.reward or {}) then return false, 'inventoryFull' end

    goal.claimed = true
    saveProfile(profile)
    return true, 'goalClaimed'
end)

------------------------------------------------------------------------------------------------
-- Trader
------------------------------------------------------------------------------------------------

lib.callback.register('recycling_warehouse:getTraderData', function(source)
    local profile = getProfile(source)
    if not profile then return nil end

    local perks = perksFor(levelFromXp(profile.xp))

    return {
        count = inventory:GetItemCount(source, Config.RecycleItem) or 0,
        tradeBonus = perks.tradeBonus,
        maxTimes = Config.Market.maxTradesAtOnce,
        materials = marketList(perks),
        resetIn = secondsUntilReset(),
    }
end)

-- Trades `times` x one material. Returns: ok, messageKey, { cost, amount, label }
lib.callback.register('recycling_warehouse:trade', function(source, materialIndex, times)
    if Config.Trader.requireShift and not Players[source] then return false, 'notOnShift' end
    if not isNear(source, Config.Trader.coords, Config.Distance.trader) then return false, 'tooFar' end

    -- The client only sends two numbers; the item, cost and amount all come from our config.
    local material = type(materialIndex) == 'number' and Config.Materials[materialIndex]
    if not material then return false, 'failed' end

    if type(times) ~= 'number' or times ~= math.floor(times) or times < 1 or times > Config.Market.maxTradesAtOnce then
        return false, 'invalidAmount'
    end

    local profile = getProfile(source)
    if not profile then return false, 'noProfile' end

    local perks = perksFor(levelFromXp(profile.xp))
    local cost = material.cost * times
    local amount = amountPerTrade(materialIndex, perks) * times

    local count = inventory:GetItemCount(source, Config.RecycleItem) or 0
    if count < cost then return false, 'cannotAfford' end

    -- Weight check that accounts for the recycle boxes being removed first.
    if not inventory:CanSwapItem(source, Config.RecycleItem, cost, material.item, amount) then
        return false, 'inventoryFull'
    end

    -- 1) Take the cost.
    if not inventory:RemoveItem(source, Config.RecycleItem, cost) then return false, 'failed' end

    -- 2) Give the materials. If that fails (e.g. no free slot), refund the cost.
    if not inventory:AddItem(source, material.item, amount) then
        inventory:AddItem(source, Config.RecycleItem, cost)
        return false, 'inventoryFull'
    end

    profile.trades = profile.trades + times
    addGoalProgress(source, profile, 'trade', times)
    addGoalProgress(source, profile, 'spend', cost)
    saveProfile(profile)

    debugLog(source, ('traded %d %s for %dx %s'):format(cost, Config.RecycleItem, amount, material.item))
    return true, 'traded', { cost = cost, amount = amount, label = material.label }
end)

------------------------------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------------------------------

-- Disconnect. The profile is saved after every change, so nothing needs writing here.
AddEventHandler('playerDropped', function()
    clearPlayer(source, true)
end)

-- ESX character logout / switch (esx_multicharacter). The client also resets itself.
AddEventHandler('esx:playerLogout', function(playerId)
    clearPlayer(playerId, true)
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
