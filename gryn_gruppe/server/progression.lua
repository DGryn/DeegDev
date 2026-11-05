--[[
    gryn_gruppe - server/progression.lua

    Levels, XP, the unlock table, reputation, cooldowns, the daily reward and the data the
    tablet shows. Config.Unlocks is the only place that says what a level gives.
]]

local MAX = Config.Levels.max

-- XP needed to go from level n to n + 1.
function G6.XPForLevel(n)
    return math.floor(Config.Levels.base * Config.Levels.growth ^ (n - 1))
end

-- Total XP needed to reach level n from zero.
local TotalFor = { [1] = 0 }
for n = 2, MAX do TotalFor[n] = TotalFor[n - 1] + G6.XPForLevel(n - 1) end

function G6.LevelFromXP(xp)
    local level = 1
    for n = 2, MAX do
        if xp >= TotalFor[n] then level = n else break end
    end
    return level
end

-- Everything a level gives, resolved from the unlock table. Tasks, vehicles and items add up;
-- money bonus, XP bonus and cooldown reduction come from the highest level that sets them.
function G6.Perks(level)
    local perks = { tasks = {}, vehicles = {}, items = {}, moneyBonus = 0, xpBonus = 0, cooldownReduction = 0 }
    for n = 1, level do
        local u = Config.Unlocks[n]
        if u then
            for _, k in ipairs(u.tasks or {}) do perks.tasks[k] = true end
            for _, k in ipairs(u.vehicles or {}) do perks.vehicles[k] = true end
            for _, k in ipairs(u.items or {}) do perks.items[k] = true end
            if u.moneyBonus then perks.moneyBonus = u.moneyBonus end
            if u.xpBonus then perks.xpBonus = u.xpBonus end
            if u.cooldownReduction then perks.cooldownReduction = u.cooldownReduction end
        end
    end
    return perks
end

-- Level a task, vehicle or black market item is unlocked at (nil = not in the unlock table).
function G6.UnlockLevel(kind, key)
    for n = 1, MAX do
        local u = Config.Unlocks[n]
        if u and u[kind] then
            for _, k in ipairs(u[kind]) do
                if k == key then return n end
            end
        end
    end
    return nil
end

function G6.RepBonus(rep)
    return math.floor(rep / Config.Reputation.tierSize) * Config.Reputation.bonusPerTier
end

-- Seconds of job cooldown left for a player.
function G6.CooldownLeft(src)
    local row = G6.GetData(src)
    if not row or row.last_job_end == 0 then return 0 end
    local minutes = math.max(0, Config.Cooldown - G6.Perks(row.level).cooldownReduction)
    return math.max(0, row.last_job_end + minutes * 60 - os.time())
end

-- Adds XP (and optionally money / reputation / a completed job) to a player and saves.
-- `money` is only counted for the "today" stat here; paying it is the caller's job.
function G6.AddProgress(src, xp, money, rep, completedJob)
    local row = G6.GetData(src)
    if not row then return end

    local before = row.level
    row.xp = row.xp + (xp or 0)
    row.level = G6.LevelFromXP(row.xp)
    row.xp_today = row.xp_today + (xp or 0)
    row.money_today = row.money_today + (money or 0)
    row.reputation = row.reputation + (rep or 0)
    if completedJob then row.jobs_completed = row.jobs_completed + 1 end
    G6.SaveData(row)

    if row.level > before then
        G6.Notify(src, ('Level up! You are now level %d.'):format(row.level), 'success')
    end
end

------------------------------------------------------------------------------------------------
-- Tablet data
------------------------------------------------------------------------------------------------

local function dailyLeft(row)
    return math.max(0, row.last_daily_claim + 86400 - os.time())
end

local function payRange(task)
    local t = Config.Tasks[task]
    local mult = Config.Difficulty[t.difficulty].multiplier
    local min, max
    if task == 'atm' then
        min, max = t.bags.base, t.bags.max
    elseif task == 'multibank' then
        min, max = t.banks.min * t.bagsPerBank, t.banks.max * t.bagsPerBank
    else
        min, max = t.pickups.min, t.pickups.max
    end
    return math.floor(min * t.ratePerItem * mult), math.floor(max * t.ratePerItem * mult)
end

local function levelCards()
    local cards = {}
    for n = 1, MAX do
        local u = Config.Unlocks[n]
        if u then
            local lines = {}
            for _, k in ipairs(u.tasks or {}) do lines[#lines + 1] = { kind = 'task', label = Config.Tasks[k] and Config.Tasks[k].label or k } end
            for _, k in ipairs(u.vehicles or {}) do lines[#lines + 1] = { kind = 'vehicle', label = Config.Vehicles[k] and Config.Vehicles[k].label or k } end
            for _, k in ipairs(u.items or {}) do lines[#lines + 1] = { kind = 'item', label = k } end
            if u.moneyBonus and u.moneyBonus > 0 then lines[#lines + 1] = { kind = 'money', label = ('+%d%% money'):format(u.moneyBonus) } end
            if u.xpBonus and u.xpBonus > 0 then lines[#lines + 1] = { kind = 'xp', label = ('+%d%% XP'):format(u.xpBonus) } end
            if u.cooldownReduction and u.cooldownReduction > 0 then lines[#lines + 1] = { kind = 'cooldown', label = ('-%d min cooldown'):format(u.cooldownReduction) } end
            cards[#cards + 1] = { level = n, xp = TotalFor[n], unlocks = lines }
        end
    end
    return cards
end

function G6.TabletData(src)
    local row = G6.GetData(src)
    if not row then return nil end
    local perks = G6.Perks(row.level)

    local tasks = {}
    for _, key in ipairs(Config.TaskOrder) do
        local t = Config.Tasks[key]
        local diff = Config.Difficulty[t.difficulty]
        local min, max = payRange(key)
        tasks[#tasks + 1] = {
            key = key, label = t.label, description = t.description,
            difficulty = diff.label, difficultyKey = t.difficulty, deposit = diff.deposit,
            payMin = min, payMax = max,
            level = G6.UnlockLevel('tasks', key) or 1,
            locked = not perks.tasks[key],
            timeLimit = t.timeLimit,
        }
    end

    local isMax = row.level >= MAX
    return {
        player = {
            name = G6.Name(src),
            level = row.level,
            maxLevel = MAX,
            xp = row.xp,
            xpInto = row.xp - TotalFor[row.level],
            xpNeeded = isMax and 0 or G6.XPForLevel(row.level),
            moneyBonus = perks.moneyBonus,
            xpBonus = perks.xpBonus,
            reputation = row.reputation,
            repBonus = G6.RepBonus(row.reputation),
            jobsCompleted = row.jobs_completed,
            xpToday = row.xp_today,
            moneyToday = row.money_today,
            todayResetIn = math.max(0, row.daily_reset + 86400 - os.time()),
            cooldown = G6.CooldownLeft(src),
            dailyLeft = dailyLeft(row),
            daily = Config.Daily,
            groupBonus = Config.GroupBonus,
            maxGroup = Config.MaxGroupSize,
            inviteDistance = Config.InviteDistance,
        },
        levels = levelCards(),
        tasks = tasks,
        group = G6.GroupInfo(src),
        job = G6.JobInfo(src),
    }
end

lib.callback.register('gryn_gruppe:tablet', function(src)
    if not G6.Near(src, Config.HQ.npc.coords, Config.ServerDistance + 2.0) then return nil end
    return G6.TabletData(src)
end)

lib.callback.register('gryn_gruppe:claimDaily', function(src)
    if G6.RateLimited(src, 'daily', 2000) then return false end
    if not G6.Near(src, Config.HQ.npc.coords, Config.ServerDistance + 2.0) then return false end
    local row = G6.GetData(src)
    if not row then return false end
    if dailyLeft(row) > 0 then return false, 'Your daily reward is not ready yet.' end

    row.last_daily_claim = os.time()
    G6.SaveData(row)
    G6.AddMoney(src, Config.PayAccount, Config.Daily.money, 'Gruppe 6 daily reward')
    G6.AddProgress(src, Config.Daily.xp, Config.Daily.money)
    G6.Log('Daily reward', ('%s (%s) claimed $%d and %d XP'):format(G6.Name(src), row.identifier, Config.Daily.money, Config.Daily.xp))
    return true, ('Daily reward: $%s and %d XP.'):format(Config.Daily.money, Config.Daily.xp), G6.TabletData(src)
end)
