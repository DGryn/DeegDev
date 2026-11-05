--[[
    gryn_gruppe - server/groups.lua

    Groups of up to Config.MaxGroupSize players (leader + members). A solo player gets a group of
    one when they start a job. Only the leader invites, kicks, picks the task and starts it.
    When anyone leaves (button, kick, disconnect, death during a job) the job carries on with
    whoever is left; the next member becomes leader; an empty group fails its job.
]]

local Groups = {}      -- [id] = { id, leader = src, members = { src, ... } }
local PlayerGroup = {} -- [src] = group id
local Invites = {}     -- [target src] = { group = id, from = src, expires = os.time() }
local nextId = 0

function G6.GetGroup(id) return Groups[id] end

function G6.GroupOf(src)
    local id = PlayerGroup[src]
    return id and Groups[id] or nil
end

function G6.IsMember(group, src)
    for _, m in ipairs(group.members) do
        if m == src then return true end
    end
    return false
end

function G6.GroupInfo(src)
    local group = G6.GroupOf(src)
    if not group then return nil end
    local members = {}
    for _, m in ipairs(group.members) do
        members[#members + 1] = { id = m, name = G6.Name(m), leader = m == group.leader, me = m == src }
    end
    return { id = group.id, isLeader = group.leader == src, members = members, max = Config.MaxGroupSize }
end

-- Tells every member to refresh their tablet (if it is open).
function G6.SyncGroup(group)
    for _, m in ipairs(group.members) do
        TriggerClientEvent('gryn_gruppe:refresh', m)
    end
end

function G6.EnsureGroup(src)
    local group = G6.GroupOf(src)
    if group then return group end
    nextId = nextId + 1
    group = { id = nextId, leader = src, members = { src } }
    Groups[group.id] = group
    PlayerGroup[src] = group.id
    return group
end

-- Removes a player from their group. `reason` is shown to the rest of the group.
function G6.RemoveFromGroup(src, reason)
    local group = G6.GroupOf(src)
    if not group then return end

    for i, m in ipairs(group.members) do
        if m == src then table.remove(group.members, i) break end
    end
    PlayerGroup[src] = nil
    TriggerClientEvent('gryn_gruppe:refresh', src)

    -- jobs.lua: drops what they carried, starts their cooldown, fails the job if nobody is left
    G6.OnMemberLeft(group, src)

    if #group.members == 0 then
        Groups[group.id] = nil
        return
    end

    if group.leader == src then
        group.leader = group.members[1]
        G6.Notify(group.leader, 'You are now the group leader.', 'inform')
    end

    for _, m in ipairs(group.members) do
        G6.Notify(m, ('%s %s.'):format(G6.Name(src), reason or 'left the group'), 'inform')
    end

    G6.SyncJob(group)
    G6.SyncGroup(group)
end

------------------------------------------------------------------------------------------------
-- Tablet actions
------------------------------------------------------------------------------------------------

lib.callback.register('gryn_gruppe:nearbyPlayers', function(src)
    if G6.RateLimited(src, 'nearby', 1000) then return {} end
    local group = G6.GroupOf(src)
    if group and group.leader ~= src then return {} end

    local mine = G6.Coords(src)
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        if p ~= src and not PlayerGroup[p] and ESX.GetPlayerFromId(p)
            and #(G6.Coords(p) - mine) <= Config.InviteDistance then
            list[#list + 1] = { id = p, name = G6.Name(p) }
        end
    end
    return list
end)

lib.callback.register('gryn_gruppe:invite', function(src, target)
    if G6.RateLimited(src, 'invite', 1000) then return false end
    target = tonumber(target)
    if not target or target == src or not ESX.GetPlayerFromId(target) then return false, 'Player not found.' end

    local group = G6.EnsureGroup(src)
    if group.leader ~= src then return false, 'Only the leader can invite.' end
    if G6.JobOf(group) then return false, 'You cannot invite during a job.' end
    if #group.members >= Config.MaxGroupSize then return false, 'Your group is full.' end
    if PlayerGroup[target] then return false, 'That player is already in a group.' end
    if #(G6.Coords(target) - G6.Coords(src)) > Config.InviteDistance then return false, 'That player is too far away.' end

    Invites[target] = { group = group.id, from = src, expires = os.time() + Config.InviteTimeout }
    TriggerClientEvent('gryn_gruppe:invited', target, { from = G6.Name(src), timeout = Config.InviteTimeout })
    G6.SyncGroup(group)
    return true, ('Invite sent to %s.'):format(G6.Name(target))
end)

lib.callback.register('gryn_gruppe:respondInvite', function(src, accept)
    local invite = Invites[src]
    Invites[src] = nil
    if not invite then return false end
    if not accept then
        G6.Notify(invite.from, ('%s declined your invite.'):format(G6.Name(src)), 'inform')
        return true
    end

    local group = Groups[invite.group]
    if invite.expires < os.time() or not group then return false, 'That invite has expired.' end
    if PlayerGroup[src] then return false, 'You are already in a group.' end
    if G6.JobOf(group) then return false, 'That group has already started a job.' end
    if #group.members >= Config.MaxGroupSize then return false, 'That group is full.' end

    group.members[#group.members + 1] = src
    PlayerGroup[src] = group.id
    for _, m in ipairs(group.members) do
        if m ~= src then G6.Notify(m, ('%s joined the group.'):format(G6.Name(src)), 'success') end
    end
    G6.SyncGroup(group)
    return true, 'You joined the group.'
end)

lib.callback.register('gryn_gruppe:kick', function(src, target)
    if G6.RateLimited(src, 'kick', 1000) then return false end
    target = tonumber(target)
    local group = G6.GroupOf(src)
    if not group or group.leader ~= src then return false, 'Only the leader can kick.' end
    if target == src or not G6.IsMember(group, target) then return false end

    G6.Notify(target, 'You were removed from the group.', 'error')
    G6.RemoveFromGroup(target, 'was removed from the group')
    return true
end)

lib.callback.register('gryn_gruppe:leaveGroup', function(src)
    if G6.RateLimited(src, 'leave', 1000) then return false end
    if not G6.GroupOf(src) then return false end
    G6.RemoveFromGroup(src, 'left the group')
    return true, 'You left the group.'
end)

------------------------------------------------------------------------------------------------
-- Disconnect / death
------------------------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    Invites[src] = nil
    G6.RemoveFromGroup(src, 'disconnected')
end)

-- es_extended's client sends this when the player dies (client/modules/death.lua).
-- Dying only removes a player while their group is on a job.
RegisterNetEvent('esx:onPlayerDeath', function()
    local src = source
    local group = G6.GroupOf(src)
    if group and G6.JobOf(group) then
        G6.Notify(src, 'You went down and are out of the job.', 'error')
        G6.RemoveFromGroup(src, 'went down and is out of the job')
    end
end)
