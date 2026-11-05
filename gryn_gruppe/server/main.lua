--[[
    gryn_gruppe - server/main.lua

    Shared server helpers (the G6 table is global, so every server file in this resource can use
    it), the database table and the per-player progress cache.

    The server is the authority: clients only report what they did, and every reward, item,
    deposit and payout is worked out and given here.

    API references:
      ESX xPlayer        https://docs.esx-framework.org/legacy/Server/Classes/xPlayer
      ESX functions      https://docs.esx-framework.org/legacy/Server/Functions
      oxmysql            https://coxdocs.dev/oxmysql
      ox_inventory       https://coxdocs.dev/ox_inventory/Functions/Server
      ox_lib callbacks   https://coxdocs.dev/ox_lib/Modules/Callback/Server
]]

ESX = exports['es_extended']:getSharedObject()

G6 = {}

local RESOURCE = GetCurrentResourceName()

------------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------------

function G6.Debug(...)
    if Config.Debug then print(('[%s]'):format(RESOURCE), ...) end
end

function G6.Notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Gruppe 6', description = msg, type = kind or 'inform' })
end

function G6.Identifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier
end

function G6.Name(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getName() or GetPlayerName(src) or ('#' .. src)
end

function G6.Coords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

function G6.Near(src, coords, range)
    return #(G6.Coords(src) - vector3(coords.x, coords.y, coords.z)) <= (range or Config.ServerDistance)
end

-- One action per `ms` per player and key. Returns true when the call should be dropped.
local Limits = {}
function G6.RateLimited(src, key, ms)
    local now = GetGameTimer()
    local list = Limits[src]
    if not list then list = {}; Limits[src] = list end
    if list[key] and list[key] > now then return true end
    list[key] = now + (ms or 500)
    return false
end

function G6.PoliceCount()
    local total = 0
    for _, job in ipairs(Config.PoliceJobs) do
        total = total + #ESX.GetExtendedPlayers('job', job)
    end
    return total
end

function G6.GetMoney(src, account)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return 0 end
    local acc = xPlayer.getAccount(account)
    return acc and acc.money or 0
end

function G6.RemoveMoney(src, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or G6.GetMoney(src, account) < amount then return false end
    xPlayer.removeAccountMoney(account, amount, reason)
    return true
end

function G6.AddMoney(src, account, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or amount <= 0 then return false end
    xPlayer.addAccountMoney(account, amount, reason)
    return true
end

-- Valid net id that points at an existing entity.
function G6.EntityFromNet(netId)
    if type(netId) ~= 'number' then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    return nil
end

function G6.Log(title, msg)
    if Config.Logging.console then
        print(('[%s] %s: %s'):format(RESOURCE, title, msg))
    end
    if Config.Logging.webhook and Config.Logging.webhook ~= '' then
        PerformHttpRequest(Config.Logging.webhook, function() end, 'POST', json.encode({
            username = 'Gruppe 6',
            embeds = { { title = title, description = msg, color = 9133302 } },
        }), { ['Content-Type'] = 'application/json' })
    end
end

------------------------------------------------------------------------------------------------
-- Database and progress cache
------------------------------------------------------------------------------------------------

local Data = {} -- [identifier] = row (numbers), saved on every change

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gryn_gruppe_players` (
            `identifier`       VARCHAR(60) NOT NULL,
            `xp`               INT NOT NULL DEFAULT 0,
            `level`            INT NOT NULL DEFAULT 1,
            `reputation`       INT NOT NULL DEFAULT 0,
            `jobs_completed`   INT NOT NULL DEFAULT 0,
            `xp_today`         INT NOT NULL DEFAULT 0,
            `money_today`      INT NOT NULL DEFAULT 0,
            `daily_reset`      INT NOT NULL DEFAULT 0,
            `last_daily_claim` INT NOT NULL DEFAULT 0,
            `last_job_end`     INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`)
        )
    ]])
end)

local FIELDS = { 'xp', 'level', 'reputation', 'jobs_completed', 'xp_today', 'money_today', 'daily_reset', 'last_daily_claim', 'last_job_end' }

-- Returns the cached row for a player (loading or creating it first). nil if the player is not loaded.
function G6.GetData(src)
    local id = G6.Identifier(src)
    if not id then return nil end
    local row = Data[id]
    if row then return G6.CheckDailyReset(row) end

    row = MySQL.single.await('SELECT * FROM gryn_gruppe_players WHERE identifier = ?', { id })
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO gryn_gruppe_players (identifier, daily_reset) VALUES (?, ?)', { id, os.time() })
        row = { identifier = id, xp = 0, level = 1, reputation = 0, jobs_completed = 0, xp_today = 0,
                money_today = 0, daily_reset = os.time(), last_daily_claim = 0, last_job_end = 0 }
    end
    Data[id] = row
    return G6.CheckDailyReset(row)
end

-- "Today" stats (xp_today, money_today) run on a 24-hour cycle.
function G6.CheckDailyReset(row)
    if os.time() - row.daily_reset >= 86400 then
        row.xp_today, row.money_today, row.daily_reset = 0, 0, os.time()
        G6.SaveData(row)
    end
    return row
end

function G6.SaveData(row)
    local values = {}
    for i, field in ipairs(FIELDS) do values[i] = row[field] end
    values[#values + 1] = row.identifier
    MySQL.update('UPDATE gryn_gruppe_players SET xp = ?, level = ?, reputation = ?, jobs_completed = ?, xp_today = ?, money_today = ?, daily_reset = ?, last_daily_claim = ?, last_job_end = ? WHERE identifier = ?', values)
end

-- Starts the job cooldown by identifier (works while the player is disconnecting, too).
function G6.SetLastJobEnd(identifier)
    if not identifier then return end
    local row = Data[identifier]
    if row then
        row.last_job_end = os.time()
        G6.SaveData(row)
    else
        MySQL.update('UPDATE gryn_gruppe_players SET last_job_end = ? WHERE identifier = ?', { os.time(), identifier })
    end
end

AddEventHandler('esx:playerDropped', function(src)
    local id = G6.Identifier(src)
    if id then Data[id] = nil end
end)

AddEventHandler('playerDropped', function()
    Limits[source] = nil
end)
