local _, ns = ...

-- TurboFace Plus: social filtering and invite conveniences.
-- Implemented directly against Blizzard friend/group/chat APIs.

local M = {}
ns.PlusSocial = M

local function Settings()
    return ns.PlusSettings()
end

local frames = {}
local function SetEvents(key, enabled, handler, ...)
    local frame = frames[key]
    if enabled then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", handler)
            frames[key] = frame
        end
        frame:UnregisterAllEvents()
        for i = 1, select("#", ...) do
            local event = select(i, ...)
            if event then ns.API.RegisterEvent(frame, event) end
        end
    elseif frame then
        frame:UnregisterAllEvents()
    end
end

local function ShortName(name)
    if type(name) ~= "string" then return name end
    return strsplit("-", name, 2)
end

local function SameName(a, b)
    a, b = ShortName(a), ShortName(b)
    if not a or not b then return false end
    return strlower(a) == strlower(b)
end

local function QueueActive()
    if not GetMaxBattlefieldID or not GetBattlefieldStatus then return false end
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status and status ~= "none" then return true end
    end
    return false
end

local function CharacterFriend(name, guid)
    if not C_FriendList then return false end
    if C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
    local count = C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, count do
        local info = C_FriendList.GetFriendInfoByIndex and C_FriendList.GetFriendInfoByIndex(i)
        if info and SameName(name, info.name) and (not guid or not info.guid or guid == info.guid) then
            return true
        end
    end
    return false
end

local function BattleNetFriend(name)
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts
        and C_BattleNet.GetFriendGameAccountInfo) then
        return false
    end
    for friendIndex = 1, BNGetNumFriends() do
        local accounts = C_BattleNet.GetFriendNumGameAccounts(friendIndex) or 0
        for accountIndex = 1, accounts do
            local info = C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)
            local characterName = info and (info.characterName or info.playerName)
            if SameName(name, characterName) then return true end
        end
    end
    return false
end

local function GuildFriend(name)
    if not Settings().friendlyGuild or not IsInGuild() or not GetNumGuildMembers then return false end
    GuildRoster()
    for i = 1, GetNumGuildMembers() do
        local memberName = GetGuildRosterInfo(i)
        if SameName(name, memberName) then return true end
    end
    return false
end

function M.FriendCheck(name, guid)
    if not name then return false end
    return CharacterFriend(name, guid) or BattleNetFriend(name) or GuildFriend(name)
end

-- ---------------------------------------------------------------------------
-- Duels
-- ---------------------------------------------------------------------------

local function OnDuelRequest(_, _, challenger)
    if M.FriendCheck(challenger) then return end
    if CancelDuel then CancelDuel() end
    if StaticPopup_Hide then StaticPopup_Hide("DUEL_REQUESTED") end
end

function M:RefreshDuels()
    SetEvents("duels", Settings().blockDuels == true, OnDuelRequest, "DUEL_REQUESTED")
end

-- ---------------------------------------------------------------------------
-- Party invitations
-- ---------------------------------------------------------------------------

local function HideInviteDialogs()
    if StaticPopup_ForEachShownDialog then
        StaticPopup_ForEachShownDialog(function(dialog)
            if dialog and (dialog.which == "PARTY_INVITE" or dialog.which == "PARTY_INVITE_XREALM") then
                dialog.inviteAccepted = 1
                StaticPopup_Hide(dialog.which)
            end
        end)
    elseif StaticPopup_Hide then
        StaticPopup_Hide("PARTY_INVITE")
        StaticPopup_Hide("PARTY_INVITE_XREALM")
    end
end

local function OnPartyInvite(_, _, inviter, ...)
    local p = Settings()
    local guid = select(1, ...)
    -- Different Classic builds have moved the inviter GUID within the payload.
    -- Prefer a value that actually looks like a GUID when one is present.
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and value:find("Player%-", 1) then
            guid = value
            break
        end
    end

    local trusted = M.FriendCheck(inviter, guid)
    if p.acceptPartyFriends and trusted and not QueueActive() then
        if AcceptGroup then AcceptGroup() end
        HideInviteDialogs()
        return
    end

    if p.blockPartyInvites and not trusted then
        if DeclineGroup then DeclineGroup() end
        HideInviteDialogs()
    end
end

function M:RefreshPartyInvites()
    local p = Settings()
    SetEvents("party", p.blockPartyInvites == true or p.acceptPartyFriends == true,
        OnPartyInvite, "PARTY_INVITE_REQUEST")
end

-- ---------------------------------------------------------------------------
-- Battle.net friend requests
-- ---------------------------------------------------------------------------

local function DeclinePendingFriendRequests()
    if not Settings().blockFriendRequests or not BNGetNumFriendInvites then return end
    for i = BNGetNumFriendInvites(), 1, -1 do
        local invite = ns.API.GetBattleNetFriendInviteInfo(i)
        local inviteID = invite and invite.inviteID
        if inviteID and BNDeclineFriendInvite then
            BNDeclineFriendInvite(inviteID)
        end
    end
end

function M:RefreshFriendRequests()
    local active = Settings().blockFriendRequests == true and BNGetNumFriendInvites ~= nil
    SetEvents("friendRequests", active, DeclinePendingFriendRequests, "BN_FRIEND_INVITE_ADDED")
    if active then DeclinePendingFriendRequests() end
end

-- ---------------------------------------------------------------------------
-- Shared quests
-- ---------------------------------------------------------------------------

function M:DeclineSharedQuestIfNeeded()
    if not Settings().blockSharedQuests then return false end
    if not UnitExists("questnpc") or not UnitIsPlayer("questnpc") then return false end
    if not (UnitInParty("questnpc") or UnitInRaid("questnpc")) then return false end

    local name = UnitName("questnpc")
    local guid = UnitGUID and UnitGUID("questnpc")
    if M.FriendCheck(name, guid) then return false end
    if DeclineQuest then DeclineQuest() end
    return true
end

local function OnQuestDetail()
    M:DeclineSharedQuestIfNeeded()
end

function M:RefreshSharedQuests()
    SetEvents("sharedQuests", Settings().blockSharedQuests == true, OnQuestDetail, "QUEST_DETAIL")
end

-- ---------------------------------------------------------------------------
-- Whisper keyword invitations
-- ---------------------------------------------------------------------------

local function CanInvitePeople()
    if QueueActive() then return false end
    return ns.API.CanInviteParty()
end

local function InviteCharacter(name)
    if not name then return end
    local short, realm = strsplit("-", name, 2)
    if realm then
        local _, myRealm = UnitFullName("player")
        if myRealm and realm == myRealm then name = short end
    end
    ns.API.InviteUnit(name)
end

local function OnWhisper(_, event, message, sender, ...)
    local p = Settings()
    local keyword = strlower(strtrim(tostring(p.inviteKeyword or "inv")))
    if keyword == "" then keyword = "inv" end
    if strlower(strtrim(tostring(message or ""))) ~= keyword or not CanInvitePeople() then return end

    if event == "CHAT_MSG_WHISPER" then
        local guid
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if type(value) == "string" and value:find("Player%-", 1) then guid = value break end
        end
        if not p.inviteFriendsOnly or M.FriendCheck(sender, guid) then
            InviteCharacter(sender)
        end
        return
    end

    if event == "CHAT_MSG_BN_WHISPER" then
        local presenceID
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if type(value) == "number" and BNIsFriend and BNIsFriend(value) then
                presenceID = value
                break
            end
        end
        if not presenceID then return end
        if p.inviteFriendsOnly and not BNIsFriend(presenceID) then return end

        local index = BNGetFriendIndex and BNGetFriendIndex(presenceID)
        local account = index and C_BattleNet and C_BattleNet.GetFriendAccountInfo
            and C_BattleNet.GetFriendAccountInfo(index)
        local gameAccountID = account and account.gameAccountInfo and account.gameAccountInfo.gameAccountID
        if gameAccountID then ns.API.InviteBattleNetFriend(gameAccountID) end
    end
end

function M:RefreshWhisperInvites()
    local active = Settings().inviteFromWhisper == true
    if active and BNGetNumFriends then
        SetEvents("whispers", true, OnWhisper, "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER")
    else
        SetEvents("whispers", active, OnWhisper, "CHAT_MSG_WHISPER")
    end
end

function M:Refresh()
    self:RefreshDuels()
    self:RefreshPartyInvites()
    self:RefreshFriendRequests()
    self:RefreshSharedQuests()
    self:RefreshWhisperInvites()
end

function M:Init()
    self:Refresh()
end
