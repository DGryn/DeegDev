--[[
    gryn_gruppe - server/jobs.lua

    The job engine. The server holds each job's whole state (group, task, phase, van, sites,
    every bag or crate and who carries it, timer). Clients get a copy to draw blips, targets and
    props, and ask for each step through a callback that is checked here (member of the job,
    right phase, distance, what they carry) before the state changes.

    Item states:  site -> carried -> van -> carried -> done
    Phases:
      atm        collect (one bank)      -> deliver (one ATM per bag)  -> return
      multibank  collect (banks, in any order; bags from the van go to the HQ hand-in) -> return
      crate      collect (pickups)       -> deliver (drop-off NPC)     -> return (timer runs from start)

    Server natives: https://docs.fivem.net/natives/?_0x6AE51D4B (CreateVehicleServerSetter),
    SetEntityOrphanMode, SetVehicleNumberPlateText, GetVehicleEngineHealth, Entity state bags
    https://docs.fivem.net/docs/scripting-manual/networking/state-bags/
]]

local Jobs = {}   -- [group id] = job
local VanJob = {} -- [van net id] = job
local nextJobId = 0

function G6.JobOf(group) return group and Jobs[group.id] or nil end
function G6.JobByVan(netId) return VanJob[netId] end

local function jobFor(src)
    local group = G6.GroupOf(src)
    return group and Jobs[group.id] or nil, group
end

local function pick(list, count)
    local pool = {}
    for i = 1, #list do pool[i] = list[i] end
    local out = {}
    for _ = 1, math.min(count, #pool) do
        out[#out + 1] = table.remove(pool, math.random(#pool))
    end
    return out
end

------------------------------------------------------------------------------------------------
-- Sync
------------------------------------------------------------------------------------------------

local function counts(job)
    local c = { site = 0, van = 0, carried = 0, done = 0, total = #job.items }
    for _, item in ipairs(job.items) do c[item.state] = c[item.state] + 1 end
    return c
end

-- What members see: enough to draw blips, targets and props. Same table for every member.
local function clientJob(job)
    local sites = {}
    for _, s in ipairs(job.sites) do
        sites[#sites + 1] = { id = s.id, type = s.type, label = s.label, coords = s.coords, remaining = s.remaining, done = s.done, model = s.model }
    end
    local carriers = {}
    for _, item in ipairs(job.items) do
        if item.state == 'carried' then carriers[tostring(item.carrier)] = item.kind end
    end
    local t = Config.Tasks[job.task]
    return {
        id = job.id, task = job.task, label = t.label, phase = job.phase,
        vanNet = job.vanNet, kind = job.kind, sites = sites, counts = counts(job), carriers = carriers,
        timeLeft = job.deadline and math.max(0, job.deadline - os.time()) or nil,
        payEstimate = math.floor(#job.items * t.ratePerItem * job.mult),
        members = #job.group.members,
    }
end

function G6.SyncJob(group)
    local job = Jobs[group.id]
    if not job then return end
    local data = clientJob(job)
    for _, m in ipairs(group.members) do
        TriggerClientEvent('gryn_gruppe:jobState', m, data)
    end
end

-- For the tablet's Jobs page.
function G6.JobInfo(src)
    local job = jobFor(src)
    if not job then return nil end
    local data = clientJob(job)
    for _, s in ipairs(data.sites) do s.coords = nil end -- the NUI needs no vectors (keeps json.encode simple)
    return data
end

------------------------------------------------------------------------------------------------
-- Ending a job
------------------------------------------------------------------------------------------------

local function cleanup(job, keepVan)
    job.ended = true
    Jobs[job.group.id] = nil
    VanJob[job.vanNet] = nil
    if DoesEntityExist(job.van) then
        Entity(job.van).state:set('g6Job', nil, true)
        if not keepVan then DeleteEntity(job.van) end
    end
    for _, m in ipairs(job.group.members) do
        TriggerClientEvent('gryn_gruppe:jobEnded', m)
        G6.SetLastJobEnd(job.identifiers[m])
    end
    G6.SyncGroup(job.group)
end

function G6.FailJob(job, reason, keepVan)
    if job.ended then return end
    for _, m in ipairs(job.group.members) do
        G6.Notify(m, ('Job failed: %s. The deposit is lost.'):format(reason), 'error')
    end
    G6.Log('Job failed', ('Job #%d (%s, group of %d): %s'):format(job.id, job.task, #job.group.members, reason))
    cleanup(job, keepVan)
end

local function completeJob(job)
    local t = Config.Tasks[job.task]
    local members = job.group.members
    local n = #members
    local groupMult = 1 + (Config.GroupBonus * (n - 1)) / 100

    -- Group bonus on the total, split equally, then each member's own level and rep bonus.
    local payShare = #job.items * t.ratePerItem * job.mult * groupMult / n
    local xpShare  = #job.items * t.xpPerItem  * job.mult * groupMult / n
    local lines = {}

    for _, m in ipairs(members) do
        local row = G6.GetData(m)
        if row then
            local perks = G6.Perks(row.level)
            local pay = math.floor(payShare * (1 + (perks.moneyBonus + G6.RepBonus(row.reputation)) / 100))
            local xp  = math.floor(xpShare * (1 + perks.xpBonus / 100))
            G6.AddMoney(m, Config.PayAccount, pay, 'Gruppe 6 job')
            G6.AddProgress(m, xp, pay, t.rep, true)

            local msg = ('Job complete: $%s and %d XP.'):format(pay, xp)
            if m == job.depositor then
                G6.AddMoney(m, Config.DepositAccount, job.deposit, 'Gruppe 6 deposit refund')
                msg = msg .. (' Deposit of $%s refunded.'):format(job.deposit)
            end
            G6.Notify(m, msg, 'success')
            lines[#lines + 1] = ('%s: $%d, %d XP'):format(G6.Name(m), pay, xp)
        end
    end

    G6.Log('Job complete', ('Job #%d (%s, %d items)\n%s'):format(job.id, job.task, #job.items, table.concat(lines, '\n')))
    cleanup(job, false)
end

-- Called by groups.lua after a player is removed from a group.
function G6.OnMemberLeft(group, src)
    local job = Jobs[group.id]
    if not job then return end

    for _, item in ipairs(job.items) do
        if item.state == 'carried' and item.carrier == src then
            item.state, item.carrier = item.from, nil
            if item.from == 'site' then
                local site = job.sites[item.site]
                site.remaining, site.done = site.remaining + 1, false
            end
        end
    end
    TriggerClientEvent('gryn_gruppe:jobEnded', src)
    G6.SetLastJobEnd(job.identifiers[src])

    if #group.members == 0 then
        G6.Notify(src, 'Job failed: everyone left. The deposit is lost.', 'error')
        G6.FailJob(job, 'everyone left')
    end
end

------------------------------------------------------------------------------------------------
-- Starting a job
------------------------------------------------------------------------------------------------

local function spawnVan(vehicleKey, jobId)
    local v = Config.Vehicles[vehicleKey]
    local spawn = Config.HQ.vehicleSpawn

    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - spawn.xyz) < 3.0 then return nil, 'The Stockade spawn is blocked.' end
    end

    local van = CreateVehicleServerSetter(v.model, 'automobile', spawn.x, spawn.y, spawn.z, spawn.w)
    local timeout = GetGameTimer() + 3000
    while not DoesEntityExist(van) and GetGameTimer() < timeout do Wait(50) end
    if not DoesEntityExist(van) then return nil, 'The Stockade could not be spawned.' end

    SetEntityOrphanMode(van, 2) -- keep the van when its owner drops or moves away
    SetVehicleNumberPlateText(van, ('%s%05d'):format(v.platePrefix, jobId % 100000))
    Entity(van).state:set('g6Job', jobId, true)
    return van
end

-- Builds the sites and items for a task. Returns sites, items, item kind.
local function buildTask(task, groupSize)
    local t = Config.Tasks[task]
    local sites, items = {}, {}

    local function addSite(type, label, coords, remaining, model)
        sites[#sites + 1] = { id = #sites + 1, type = type, label = label, coords = coords, remaining = remaining or 0, done = false, model = model }
        return sites[#sites]
    end
    local function addItems(kind, site, n)
        for _ = 1, n do
            items[#items + 1] = { id = #items + 1, kind = kind, state = 'site', site = site.id, from = 'site' }
        end
    end

    if task == 'atm' then
        local bags = math.min(t.bags.max, t.bags.base + t.bags.perExtraMember * (groupSize - 1))
        local bank = pick(Config.Banks, 1)[1]
        addItems('bag', addSite('bank', bank.label, bank.coords, bags), bags)
        return sites, items, 'bag'
    elseif task == 'multibank' then
        for _, bank in ipairs(pick(Config.Banks, math.random(t.banks.min, t.banks.max))) do
            addItems('bag', addSite('bank', bank.label, bank.coords, t.bagsPerBank), t.bagsPerBank)
        end
        addSite('hq', 'Gruppe 6 HQ', Config.HQ.handIn)
        return sites, items, 'bag'
    else
        for _, p in ipairs(pick(Config.CratePickups, math.random(t.pickups.min, t.pickups.max))) do
            addItems('crate', addSite('pickup', p.label, p.coords, 1), 1)
        end
        return sites, items, 'crate'
    end
end

lib.callback.register('gryn_gruppe:startJob', function(src, task)
    if G6.RateLimited(src, 'start', 3000) then return false end
    local t = Config.Tasks[task]
    if not t then return false end
    if not G6.Near(src, Config.HQ.npc.coords, Config.ServerDistance + 2.0) then return false, 'You are too far from the dispatcher.' end

    local group = G6.EnsureGroup(src)
    if group.leader ~= src then return false, 'Only the leader can start a job.' end
    if Jobs[group.id] then return false, 'Your group is already on a job.' end

    local row = G6.GetData(src)
    if not row then return false end
    local perks = G6.Perks(row.level)
    if not perks.tasks[task] then return false, ('This task unlocks at level %d.'):format(G6.UnlockLevel('tasks', task) or 0) end
    if not perks.vehicles[Config.DefaultVehicle] then return false, 'You have not unlocked the Stockade yet.' end

    for _, m in ipairs(group.members) do
        local left = G6.CooldownLeft(m)
        if left > 0 then
            local who = m == src and 'You are' or (G6.Name(m) .. ' is')
            return false, ('%s on cooldown for %d more min.'):format(who, math.ceil(left / 60))
        end
    end

    local diff = Config.Difficulty[t.difficulty]
    if not G6.RemoveMoney(src, Config.DepositAccount, diff.deposit, 'Gruppe 6 deposit') then
        return false, ('You need $%s in the bank for the deposit.'):format(diff.deposit)
    end

    nextJobId = nextJobId + 1
    local van, err = spawnVan(Config.DefaultVehicle, nextJobId)
    if not van then
        G6.AddMoney(src, Config.DepositAccount, diff.deposit, 'Gruppe 6 deposit refund')
        return false, err
    end

    local sites, items, kind = buildTask(task, #group.members)
    local identifiers = {}
    for _, m in ipairs(group.members) do identifiers[m] = G6.Identifier(m) end

    local job = {
        id = nextJobId, group = group, task = task, kind = kind,
        mult = diff.multiplier, deposit = diff.deposit, depositor = src,
        van = van, vanNet = NetworkGetNetworkIdFromEntity(van),
        phase = 'collect', sites = sites, items = items,
        identifiers = identifiers, startedAt = os.time(),
        deadline = t.timeLimit and (os.time() + t.timeLimit * 60) or nil,
    }
    Jobs[group.id] = job
    VanJob[job.vanNet] = job

    for _, m in ipairs(group.members) do
        G6.Notify(m, ('Job started: %s. The Stockade is waiting at HQ.'):format(t.label), 'success')
    end
    G6.Log('Job started', ('Job #%d (%s) by %s, group of %d, deposit $%d'):format(job.id, task, G6.Name(src), #group.members, diff.deposit))
    G6.SyncJob(group)
    G6.SyncGroup(group)
    return true
end)

------------------------------------------------------------------------------------------------
-- Steps
------------------------------------------------------------------------------------------------

local function carriedBy(job, src)
    for _, item in ipairs(job.items) do
        if item.state == 'carried' and item.carrier == src then return item end
    end
end

local function nearVan(job, src)
    return DoesEntityExist(job.van) and G6.Near(src, GetEntityCoords(job.van), Config.ServerDistance + 2.0)
end

local function allIn(job, state)
    for _, item in ipairs(job.items) do
        if item.state ~= state then return false end
    end
    return true
end

-- Moves the job to the next phase when everything needed for it is done.
local function advance(job)
    if job.phase == 'collect' and job.task ~= 'multibank' and allIn(job, 'van') then
        job.phase = 'deliver'
        if job.task == 'atm' then
            for _, coords in ipairs(pick(Config.ATMs, #job.items)) do
                job.sites[#job.sites + 1] = { id = #job.sites + 1, type = 'atm', label = 'ATM', coords = coords, remaining = 0, done = false }
            end
        else
            local d = pick(Config.CrateDropoffs, 1)[1]
            job.sites[#job.sites + 1] = { id = #job.sites + 1, type = 'dropoff', label = d.label, coords = d.coords, remaining = 0, done = false, model = d.model }
        end
        for _, m in ipairs(job.group.members) do
            G6.Notify(m, job.task == 'atm' and 'All bags loaded. Refill the marked ATMs.' or 'All crates secured. The client is waiting at the drop-off.', 'inform')
        end
    elseif job.phase ~= 'return' and allIn(job, 'done') then
        job.phase = 'return'
        for _, m in ipairs(job.group.members) do
            G6.Notify(m, 'All delivered. Bring the Stockade back to HQ.', 'inform')
        end
    end
end

-- Every step: rate limit, job membership, then the step's own checks.
local function step(name, ms, fn)
    lib.callback.register('gryn_gruppe:' .. name, function(src, ...)
        if G6.RateLimited(src, 'step', math.floor(ms * 0.8)) then return false end
        local job, group = jobFor(src)
        if not job or job.ended then return false, 'You are not on a job.' end
        local ok, msg = fn(src, job, ...)
        if ok then
            advance(job)
            G6.SyncJob(group)
        end
        return ok, msg
    end)
end

step('takeFromSite', Config.Progress.takeAtSite, function(src, job, siteId)
    local site = job.sites[siteId]
    if not site or (site.type ~= 'bank' and site.type ~= 'pickup') or site.remaining < 1 then return false end
    if job.phase ~= 'collect' then return false end
    if carriedBy(job, src) then return false, 'Your hands are full.' end
    if not G6.Near(src, site.coords) then return false, 'Too far away.' end

    for _, item in ipairs(job.items) do
        if item.state == 'site' and item.site == site.id then
            item.state, item.carrier, item.from = 'carried', src, 'site'
            site.remaining = site.remaining - 1
            site.done = site.remaining == 0
            return true
        end
    end
    return false
end)

step('loadVan', Config.Progress.loadVan, function(src, job)
    local item = carriedBy(job, src)
    if not item then return false, 'You are not carrying anything.' end
    if not nearVan(job, src) then return false, 'Too far from the Stockade.' end
    item.state, item.carrier = 'van', nil
    return true
end)

step('takeFromVan', Config.Progress.takeFromVan, function(src, job)
    if job.phase ~= 'deliver' and job.task ~= 'multibank' then return false, 'Load everything first.' end
    if carriedBy(job, src) then return false, 'Your hands are full.' end
    if not nearVan(job, src) then return false, 'Too far from the Stockade.' end
    for _, item in ipairs(job.items) do
        if item.state == 'van' then
            item.state, item.carrier, item.from = 'carried', src, 'van'
            return true
        end
    end
    return false, 'The Stockade is empty.'
end)

step('deliver', Config.Progress.deliver, function(src, job, siteId)
    local site = job.sites[siteId]
    if not site or site.done then return false end
    local item = carriedBy(job, src)
    if not item or item.from ~= 'van' then return false, 'Bring it from the Stockade.' end

    if site.type == 'atm' then
        if job.phase ~= 'deliver' then return false end
        site.done = true
    elseif site.type == 'dropoff' then
        if job.phase ~= 'deliver' then return false end
    elseif site.type ~= 'hq' then
        return false
    end

    local coords = site.coords
    if not G6.Near(src, vector3(coords.x, coords.y, coords.z)) then return false, 'Too far away.' end
    item.state, item.carrier = 'done', nil
    if site.type == 'dropoff' and allIn(job, 'done') then site.done = true end
    return true
end)

lib.callback.register('gryn_gruppe:returnVan', function(src)
    if G6.RateLimited(src, 'return', 2000) then return false end
    local job = jobFor(src)
    if not job or job.ended or job.phase ~= 'return' then return false end
    if not nearVan(job, src) then return false, 'Too far from the Stockade.' end
    if #(GetEntityCoords(job.van) - Config.HQ.returnPoint) > Config.HQ.returnRadius then
        return false, 'Park the Stockade at the HQ return point.'
    end
    completeJob(job)
    return true
end)

------------------------------------------------------------------------------------------------
-- Robbery hook (robbery.lua)
------------------------------------------------------------------------------------------------

-- Fails the job as robbed and returns the kinds of every item still in the van (the loot).
function G6.RobJob(job)
    local loot = {}
    for _, item in ipairs(job.items) do
        if item.state == 'van' then loot[#loot + 1] = item.kind end
    end
    G6.FailJob(job, 'the Stockade was robbed', true)
    return loot
end

------------------------------------------------------------------------------------------------
-- Watchdog: van destroyed, timer
------------------------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.VanCheckInterval)
        local now = os.time()
        for _, job in pairs(Jobs) do
            if not DoesEntityExist(job.van) or GetEntityHealth(job.van) <= 0
                or GetVehicleEngineHealth(job.van) <= Config.VanDestroyedEngine then
                G6.FailJob(job, 'the Stockade was destroyed')
            elseif job.deadline and now > job.deadline then
                G6.FailJob(job, 'you ran out of time')
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, job in pairs(Jobs) do
        if DoesEntityExist(job.van) then DeleteEntity(job.van) end
    end
end)
