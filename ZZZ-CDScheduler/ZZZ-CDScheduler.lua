local ADDON, ns = ...
local HL = HeroLibEx
local Player = HL and HL.Unit and HL.Unit.Player
local MainAddon = _G.MainAddon 
local JSON = LibStub and LibStub('LibJSON-1.0', true)
CDSchedulerDB = CDSchedulerDB or {}
CDSchedulerCharDB = CDSchedulerCharDB or {}
local ENABLE = 'enable'
local ALLOW_NONRAID = 'allow_nonraid'
local WINDOW = 'window'
local LISTS = 'lists'
local SELECTED = 'selected'
local SHOW_TRACKER = 'show_tracker'
local ENCOUNTER_MAP = 'encounter_map'
local CHAR_LISTS = 'char_lists'
local function GetCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end
local function GetOpt(key, default) return CDSchedulerDB[key] ~= nil and CDSchedulerDB[key] or default end
local function SetOpt(key, val) CDSchedulerDB[key] = val end
local function GetCharOpt(key, default)
    local charKey = GetCharKey()
    CDSchedulerCharDB[charKey] = CDSchedulerCharDB[charKey] or {}
    return CDSchedulerCharDB[charKey][key] ~= nil and CDSchedulerCharDB[charKey][key] or default
end
local function SetCharOpt(key, val)
    local charKey = GetCharKey()
    CDSchedulerCharDB[charKey] = CDSchedulerCharDB[charKey] or {}
    CDSchedulerCharDB[charKey][key] = val
end
local function IsRaidArea()
    if Player and Player.IsInRaidArea then return Player:IsInRaidArea() end
    local _, itype = GetInstanceInfo()
    return itype == 'raid'
end
local encounterAllowed = true
local function IsCustomSelected()
    local sel = GetCharOpt(SELECTED, 'Default')
    return type(sel) == 'string' and sel:gsub('%s+$',''):lower() == 'custom'
end
local function IsActive()
    return GetOpt(ENABLE, false) and (IsCustomSelected() or ((IsRaidArea() or GetOpt(ALLOW_NONRAID, false)) and encounterAllowed))
end
local function GetWindow() return math.max(0, tonumber(GetOpt(WINDOW, '5')) or 5) end
local function IsAutoCastEnabled() return IsActive() end
local function SpellTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then return tex end
    end
    if GetSpellTexture then
        local tex = GetSpellTexture(spellId)
        if tex then return tex end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local _, _, icon = C_Spell.GetSpellInfo(spellId)
        if icon then return icon end
    end
    return 136243
end
local combatStart = 0
local schedMap = {}
local consumed = {}
local function TimeToSeconds(s)
    local h, m, sec = 0, 0, 0
    local p = {}
    for tok in string.gmatch(s or '', '[^:]+') do p[#p+1] = tok end
    if #p == 2 then m = tonumber(p[1]) or 0; sec = tonumber(p[2]) or 0
    elseif #p == 3 then h = tonumber(p[1]) or 0; m = tonumber(p[2]) or 0; sec = tonumber(p[3]) or 0
    else sec = tonumber(s) or 0 end
    return h*3600 + m*60 + sec
end
local IGNORED_SPELLS = {
    [431932] = true,
}
local function ParseScheduleText(txt)
    local map = {}
    if not txt or txt == '' then return map end
    for t, id in string.gmatch(txt, "{%s*[Tt][Ii][Mm][Ee]%s*:%s*([%d:]+)%s*}%s*%-%s*{%s*[Ss][Pp][Ee][Ll][Ll]%s*:%s*(%d+)%s*}") do
        local sid = tonumber(id)
        local secs = TimeToSeconds(t)
        if sid and secs and not IGNORED_SPELLS[sid] then
            local spellInfo = C_Spell.GetSpellInfo(sid)
            if spellInfo and spellInfo.name and IsSpellKnown(sid) then
                map[sid] = map[sid] or {}
                table.insert(map[sid], secs)
            end
        end
    end
    for _, list in pairs(map) do table.sort(list) end
    return map
end
local function LoadLists()
    for _, raw in ipairs({GetCharOpt(CHAR_LISTS, nil), CDSchedulerDB[LISTS]}) do
        if type(raw) == 'string' and raw ~= '' and JSON then
            local ok, obj = pcall(JSON.Deserialize, raw)
            if ok and type(obj) == 'table' then return obj end
        end
    end
    return {}
end
local function SaveLists(tbl)
    if JSON then
        local ok, str = pcall(JSON.Serialize, tbl)
        if ok then SetCharOpt(CHAR_LISTS, str) end
    end
end
local function DecorateDifficultyLabel(nm)
    if type(nm) ~= 'string' then return nm end
    return nm:gsub(' %- Heroic$', ' - |cffff8000Heroic|r'):gsub(' %- Mythic$', ' - |cffa335eeMythic|r')
end
local function GetEncounterMap()
    if type(CDSchedulerDB[ENCOUNTER_MAP]) ~= 'table' then CDSchedulerDB[ENCOUNTER_MAP] = {} end
    return CDSchedulerDB[ENCOUNTER_MAP]
end
local function MapKey(encounterID, difficultyID) return encounterID .. ':' .. difficultyID end
local function AssignEncounterList(encounterID, difficultyID, listName)
    if listName and listName ~= '' then GetEncounterMap()[MapKey(encounterID, difficultyID)] = listName end
end
local function LookupEncounterList(encounterID, difficultyID) return GetEncounterMap()[MapKey(encounterID, difficultyID)] end
local function IsProtectedListName(name)
    if not name or name == '' then return false end
    local m = GetEncounterMap()
    for _, v in pairs(m) do if v == name then return true end end
    return false
end
local BOSS_ENCOUNTERS = {
    [3129] = 'Plexus Sentinel',
    [3131] = 'Loomithar',
    [3130] = 'Soulbinder Naazindhri',
    [3132] = 'Forgeweaver Araz',
    [3122] = 'The Soul Hunters',
    [3133] = 'Fractillus',
    [3134] = 'Nexus-King Salhadaar',
    [3135] = 'Dimensius the All-Devouring',
}
local function SeedEncounters()
    local lists = LoadLists()
    local m = GetEncounterMap()
    local changed = false
    for eid, base in pairs(BOSS_ENCOUNTERS) do
        local heroicName = base .. ' - Heroic'
        local mythicName = base .. ' - Mythic'
        local legacy = lists[base]
        if not lists[heroicName] then lists[heroicName] = legacy or ''; changed = true end
        if not lists[mythicName] then lists[mythicName] = legacy or ''; changed = true end
        m[MapKey(eid, 15)] = heroicName
        m[MapKey(eid, 16)] = mythicName
    end
    if not lists['Custom'] then lists['Custom'] = ''; changed = true end
    if changed then SaveLists(lists) end
end
local function CleanupNonDifficultyLists()
    local lists = LoadLists()
    local changed = false
    for name in pairs(lists) do
        if name ~= 'Custom' and not name:find(' %- Heroic$') and not name:find(' %- Mythic$') then
            lists[name] = nil
            changed = true
        end
    end
    if changed then SaveLists(lists) end
end
local function ParseSelected()
    if not IsActive() and not IsCustomSelected() then schedMap = {}; consumed = {}; return end
    local lists = LoadLists()
    local selected = GetCharOpt(SELECTED, 'Default')
    schedMap = ParseScheduleText(lists[selected] or '')
    consumed = {}
end
local function IsAllowedNow(spellId)
    if not IsActive() then return true end
    local list = schedMap[spellId]
    if not list or #list == 0 then return true end
    local elapsed = (combatStart > 0) and (GetTime() - combatStart) or 0
    local w = GetWindow()
    local lastTime = list[#list]
    if lastTime and elapsed > (lastTime + w) then return true end
    for i = 1, #list do local t = list[i]; if elapsed >= t and elapsed <= t + w then return true end end
    return false
end
local function MarkConsumedNearest(spellId)
    local list = schedMap[spellId]; if not list then return end
    local elapsed = (combatStart > 0) and (GetTime() - combatStart) or 0
    local bestIdx, bestDiff
    for i = 1, #list do local d = math.abs(list[i] - elapsed); if not bestDiff or d < bestDiff then bestDiff = d; bestIdx = i end end
    consumed[spellId] = consumed[spellId] or {}; consumed[spellId][bestIdx] = true
end
local function IsInWindow(spellId)
    local list = schedMap[spellId]
    if not list or #list == 0 then return false end
    local elapsed = (combatStart > 0) and (GetTime() - combatStart) or 0
    local w = GetWindow()
    for i = 1, #list do
        local t = list[i]
        if elapsed >= t and elapsed <= t + w then return true end
    end
    return false
end
local function HasScheduledSpell()
    return scheduledSpell ~= nil
end
ns.IsAllowedNow = IsAllowedNow
ns.ParseSelected = ParseSelected
ns.MarkConsumedNearest = MarkConsumedNearest
local tracker, rows, last = nil, {}, 0
local badge
local injected = {}
local scheduledSpell = nil
local scheduledObject = nil
local autoCastTimer
local function GetScheduledCooldown(schedId)
    if not (HL and Player) then return 999 end
    local function recCooldown(rec)
        if not rec then return nil end
        local obj = rec.Object
        local itemId = rec.ID or (obj and obj.ID and obj:ID())
        local spellId = nil
        if rec.Spell then
            if type(rec.Spell) == 'table' and rec.Spell.ID then
                local ok, sid = pcall(function() return rec.Spell:ID() end)
                if ok then spellId = sid end
            elseif type(rec.Spell) == 'number' then
                spellId = rec.Spell
            end
        end
        if (itemId and itemId == schedId) or (spellId and spellId == schedId) then
            if obj and obj.CooldownRemains then
                local cd = obj:CooldownRemains()
                return cd or 0
            end
        end
        return nil
    end
    if Player.GetTrinketData then
        local r1, r2 = Player:GetTrinketData()
        local cd = recCooldown(r1)
        if cd then return cd end
        cd = recCooldown(r2)
        if cd then return cd end
    end
    if Player.GetOnUseItems then
        local list = Player:GetOnUseItems()
        if type(list) == 'table' then
            for _, rec in pairs(list) do
                local cd = recCooldown(rec)
                if cd then return cd end
            end
        end
    end
    if HL.Spell then
        local sp = HL.Spell(schedId)
        if sp and sp.CooldownRemains then
            return sp:CooldownRemains() or 0
        end
    end
    return 0
end
local function IsScheduledReady(schedId)
    if not (HL and Player) then return false end
    local function recReady(rec)
        if not rec then return false end
        local obj = rec.Object
        local itemId = rec.ID or (obj and obj.ID and obj:ID())
        local spellId = nil
        if rec.Spell then
            if type(rec.Spell) == 'table' and rec.Spell.ID then
                local ok, sid = pcall(function() return rec.Spell:ID() end)
                if ok then spellId = sid end
            elseif type(rec.Spell) == 'number' then
                spellId = rec.Spell
            end
        end
        if (itemId and itemId == schedId) or (spellId and spellId == schedId) then
            if obj and obj.IsReady and obj:IsReady() then return true end
        end
        return false
    end
    if Player.GetTrinketData then
        local r1, r2 = Player:GetTrinketData()
        if recReady(r1) or recReady(r2) then return true end
    end
    if Player.GetOnUseItems then
        local list = Player:GetOnUseItems()
        if type(list) == 'table' then
            for _, rec in pairs(list) do if recReady(rec) then return true end end
        end
    end
    if HL.Spell then
        local sp = HL.Spell(schedId)
        if sp and sp.IsReady and sp:IsReady() then return true end
    end
    return false
end
local castAttempts = {}
local function TryCastScheduled(schedId, maxRetries)
    if not (MainAddon and MainAddon.Cast and HL and Player) then return false end
    maxRetries = maxRetries or 3
    local function recMatches(rec)
        if not rec then return false end
        local obj = rec.Object
        local itemId = rec.ID or (obj and obj.ID and obj:ID())
        local spellId = nil
        if rec.Spell then
            if type(rec.Spell) == 'table' and rec.Spell.ID then
                local ok, sid = pcall(function() return rec.Spell:ID() end)
                if ok then spellId = sid end
            elseif type(rec.Spell) == 'number' then
                spellId = rec.Spell
            end
        end
        if (itemId and itemId == schedId) or (spellId and spellId == schedId) then
            if obj and obj.IsReady and obj:IsReady() then
                local ok, reason = MainAddon.Cast(obj)
                return ok and true or false, reason
            end
        end
        return false
    end
    if Player.GetTrinketData then
        local r1, r2 = Player:GetTrinketData()
        local success, reason = recMatches(r1)
        if success then return true, "trinket1" end
        success, reason = recMatches(r2)
        if success then return true, "trinket2" end
    end
    if Player.GetOnUseItems then
        local list = Player:GetOnUseItems()
        if type(list) == 'table' then
            for _, rec in pairs(list) do
                local success, reason = recMatches(rec)
                if success then return true, "onuse" end
            end
        end
    end
    if HL.Spell then
        local sp = HL.Spell(schedId)
        if sp and sp.IsReady and sp:IsReady() then
            local ok, reason = MainAddon.Cast(sp)
            if ok then return true, "spell" end
        end
    end
    return false, "not_ready"
end
local function ResolveObjectForId(schedId)
    if not (HL and Player) then return nil end
    local function fromRec(rec)
        if not rec then return nil end
        local obj = rec.Object
        local itemId = rec.ID or (obj and obj.ID and obj:ID())
        local spellId = nil
        if rec.Spell then
            if type(rec.Spell) == 'table' and rec.Spell.ID then
                local ok, sid = pcall(function() return rec.Spell:ID() end)
                if ok then spellId = sid end
            elseif type(rec.Spell) == 'number' then
                spellId = rec.Spell
            end
        end
        if (itemId and itemId == schedId) or (spellId and spellId == schedId) then
            return obj
        end
        return nil
    end
    if Player.GetTrinketData then
        local r1, r2 = Player:GetTrinketData()
        local o = fromRec(r1); if o then return o end
        o = fromRec(r2); if o then return o end
    end
    if Player.GetOnUseItems then
        local list = Player:GetOnUseItems()
        if type(list) == 'table' then
            for _, rec in pairs(list) do
                local o = fromRec(rec)
                if o then return o end
            end
        end
    end
    if HL.Spell then
        local sp = HL.Spell(schedId)
        if sp then return sp end
    end
    return nil
end
local function StartAutoCastTimer()
    if autoCastTimer and autoCastTimer.Cancel then autoCastTimer:Cancel() end
    autoCastTimer = C_Timer.NewTicker(0.1, function()
        if not IsAutoCastEnabled() then return end
        local elapsed = (combatStart > 0) and (GetTime() - combatStart) or 0
        local window = GetWindow()
        if scheduledSpell then
            if elapsed > scheduledSpell.windowEnd then
                scheduledSpell = nil
                scheduledObject = nil
            else
                local cd = GetScheduledCooldown(scheduledSpell.id)
                if cd > 5 then
                    MarkConsumedNearest(scheduledSpell.id)
                    scheduledSpell = nil
                    scheduledObject = nil
                    if not tracker then BuildTracker() end
                    if tracker then tracker:Show() end
                end
            end
        elseif not scheduledSpell then
            for spellId, times in pairs(schedMap) do
                if type(times) == 'table' then
                    for i = 1, #times do
                        local t = times[i]
                        local isConsumed = consumed[spellId] and consumed[spellId][i]
                        if not isConsumed and elapsed >= t and elapsed <= t + window then
                            scheduledSpell = {
                                id = spellId,
                                time = t,
                                windowEnd = t + window,
                                timeIndex = i
                            }
                            scheduledObject = ResolveObjectForId(spellId)
                            if not scheduledObject then
                                scheduledSpell = nil
                            end
                            break
                        end
                    end
                    if scheduledSpell then break end
                end
            end
        end
    end)
end
local function StopAutoCastTimer()
    if autoCastTimer and autoCastTimer.Cancel then
        autoCastTimer:Cancel()
        autoCastTimer = nil
    end
end
local function UpdateBadgeVisibility()
    if not badge then return end
    if IsActive() then
        badge:Show()
        badge.fs:SetText('|cffff5555Scheduler ON|r')
    else
        badge:Hide()
    end
end
local function BuildBadge()
    if badge then return end
    badge = CreateFrame('Frame', 'CDSched_Badge', UIParent)
    badge:SetSize(130, 18)
    badge:SetFrameStrata('TOOLTIP')
    badge.fs = badge:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    badge.fs:SetAllPoints(true)
    badge.fs:SetJustifyH('LEFT')
    badge.fs:SetText('|cffff5555Scheduler ON|r')
    badge:ClearAllPoints()
    badge:SetPoint('TOP', UIParent, 'TOP', 0, -60)
    badge:Hide()
end
local function ResolveAnchorFrame()
    if _G.IconRotationFrame and _G.IconRotationFrame.GetObjectType then return _G.IconRotationFrame end
    local tp = _G.TopPanelAlternative or _G.TopPanel
    if tp then
        if type(tp) == 'table' and tp.GetObjectType then return tp end
        if tp.topIcons and tp.topIcons.GetObjectType then return tp.topIcons end
        if tp.background and tp.background.GetObjectType then return tp.background end
    end
    return UIParent
end
local function TryReanchorBadge()
    if not badge then return end
    local anchor = ResolveAnchorFrame()
    badge:ClearAllPoints()
    badge:SetPoint('LEFT', anchor, 'RIGHT', 8, 0)
end
local anchorTicker
local function StartAnchorTicker()
    if not badge then BuildBadge() end
    if anchorTicker and anchorTicker.Cancel then anchorTicker:Cancel() end
    anchorTicker = C_Timer.NewTicker(1.0, function()
        TryReanchorBadge(); UpdateBadgeVisibility()
        if ResolveAnchorFrame() ~= UIParent then
            if anchorTicker and anchorTicker.Cancel then anchorTicker:Cancel() end
            anchorTicker = nil
        end
    end, 12)
end
local function TimeToMMSS(sec) local m = math.floor(sec/60); local s = math.floor(sec%60); return string.format('%02d:%02d', m, s) end
local function FlattenEntries()
    local out = {}; if not IsActive() then return out end
    local elapsed = (combatStart > 0) and (GetTime() - combatStart) or 0; local w = GetWindow()
    for id, list in pairs(schedMap) do local used = consumed[id]; for i = 1, #list do local t = list[i];
        if not (used and used[i]) then
            local inWindow = (elapsed >= t and elapsed <= t + w)
            local windowPassed = (elapsed > t + w)
            local isUpcoming = (t > elapsed)
            local isReady = IsScheduledReady(id)
            local isScheduled = (scheduledSpell ~= nil and scheduledSpell.id == id)
            if not windowPassed and (isScheduled or inWindow or isUpcoming) then
                local tex = SpellTexture(id)
                table.insert(out, { id = id, tex = tex, time = t, inWindow = inWindow, isReady = isReady, isScheduled = isScheduled, isUpcoming = isUpcoming })
            end
        end
    end end
    table.sort(out, function(a,b)
        if a.isScheduled ~= b.isScheduled then return a.isScheduled end
        return a.time < b.time
    end); return out
end
local function BuildTracker()
    if tracker then return end
    tracker = CreateFrame('Frame', 'CDSched_Tracker', UIParent)
    tracker:SetSize(180, 120); tracker:SetPoint('CENTER', UIParent, 'CENTER', 280, 120)
    tracker:EnableMouse(true); tracker:SetMovable(true); tracker:RegisterForDrag('LeftButton'); tracker:SetScript('OnDragStart', tracker.StartMoving); tracker:SetScript('OnDragStop', tracker.StopMovingOrSizing)
    tracker:SetClampedToScreen(true)
    local bg = tracker:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(true); bg:SetColorTexture(0,0,0,0.12)
    tracker.header = tracker:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    tracker.header:SetPoint('TOPLEFT', tracker, 'TOPLEFT', 8, -8)
    tracker.header:SetPoint('RIGHT', tracker, 'RIGHT', -8, 0)
    tracker.header:SetJustifyH('LEFT')
    local topY = -22
    for i = 1, 6 do local row = CreateFrame('Frame', nil, tracker); row:SetSize(160, 22); if i == 1 then row:SetPoint('TOPLEFT', tracker, 'TOPLEFT', 8, topY) else row:SetPoint('TOPLEFT', rows[i-1], 'BOTTOMLEFT', 0, -4) end; row.icon = row:CreateTexture(nil, 'ARTWORK'); row.icon:SetSize(20,20); row.icon:SetPoint('LEFT', row, 'LEFT', 0, 0); row.text = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); row.text:SetPoint('LEFT', row.icon, 'RIGHT', 8, 0); row.text:SetPoint('RIGHT', row, 'RIGHT', -2, 0); row.text:SetJustifyH('LEFT'); row:Hide(); rows[i] = row end
    tracker:SetScript('OnUpdate', function() local now = GetTime(); if now - last > 0.25 then local entries = FlattenEntries(); local shown = 0; local elapsed = (combatStart > 0) and (now - combatStart) or 0; local w = GetWindow();
        tracker.header:SetText('List: ' .. DecorateDifficultyLabel(GetCharOpt(SELECTED, 'Default') or 'Default'))
        for i = 1, #rows do local row = rows[i]; local e = entries[i]; if e then row.icon:SetTexture(e.tex or 136243); local rem = e.time - elapsed; if rem < 0 then rem = 0 end; row.text:SetText(TimeToMMSS(rem));
            if e.isScheduled then
                row.text:SetTextColor(1,0.2,0.2)
            elseif e.inWindow and e.isReady then
                row.text:SetTextColor(0.2,1,0.2)
            elseif e.inWindow then
                row.text:SetTextColor(1,0.8,0.2)
            elseif e.isReady then
                row.text:SetTextColor(0.8,0.8,1)
            else
                row.text:SetTextColor(1,1,1)
            end
            row:Show(); shown = shown + 1
        else row:Hide() end end;
        local hasReadySpells = false
        for _, e in ipairs(entries) do if e.isReady then hasReadySpells = true break end end
        if GetOpt(SHOW_TRACKER, true) and (shown > 0 or IsCustomSelected() or IsActive() or (hasReadySpells and IsAutoCastEnabled()) or HasScheduledSpell()) then tracker:Show() else tracker:Hide() end; last = now end end)
end
local editor
SLASH_CDS1 = '/cdscheduler'
SLASH_CDS2 = '/cds'
SlashCmdList['CDS'] = function()
    if not editor then
        editor = CreateFrame('Frame', 'CDSched_Editor', UIParent, 'BasicFrameTemplateWithInset')
        editor:SetSize(720, 420); editor:SetPoint('CENTER')
        editor:EnableMouse(true); editor:SetMovable(true); editor:RegisterForDrag('LeftButton'); editor:SetScript('OnDragStart', editor.StartMoving); editor:SetScript('OnDragStop', editor.StopMovingOrSizing); editor:SetClampedToScreen(true)
        local lbl = editor:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'); lbl:SetPoint('TOPLEFT', 16, -36); lbl:SetText('List name:')
        local name = CreateFrame('EditBox', 'CDSched_Name', editor, 'InputBoxTemplate'); name:SetSize(240, 24); name:SetPoint('LEFT', lbl, 'RIGHT', 6, 0); name:SetAutoFocus(false)
        local listDropdown = CreateFrame('Frame', 'CDSched_ListDropdown', editor, 'UIDropDownMenuTemplate')
        listDropdown:SetPoint('TOPRIGHT', editor, 'TOPRIGHT', -40, -36)
        UIDropDownMenu_SetWidth(listDropdown, 160)
        UIDropDownMenu_SetText(listDropdown, 'Select list')
        local function DecorateListLabel(nm)
            if type(nm) ~= 'string' then return nm end
            return DecorateDifficultyLabel(nm)
        end
        local function RebuildListDropdown()
            local lists = LoadLists()
            local function OnSelect(self, arg1)
                CDSched_Name:SetText(arg1)
                local l = LoadLists()
                CDSched_Edit:SetText(l[arg1] or '')
                SetCharOpt(SELECTED, arg1)
                ParseSelected()
                UIDropDownMenu_SetText(listDropdown, DecorateListLabel(arg1))
            end
            UIDropDownMenu_Initialize(listDropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                local ordered = {}
                for _, base in pairs(BOSS_ENCOUNTERS) do
                    local h = base .. ' - Heroic'
                    local m = base .. ' - Mythic'
                    if lists[h] then table.insert(ordered, h) end
                    if lists[m] then table.insert(ordered, m) end
                end
                if lists['Custom'] then table.insert(ordered, 'Custom') end
                for i = 1, #ordered do
                    local nm = ordered[i]
                    info.text = DecorateListLabel(nm); info.arg1 = nm; info.func = OnSelect; info.checked = (nm == (GetCharOpt(SELECTED, 'Default')))
                    UIDropDownMenu_AddButton(info, level)
                end
                if #ordered == 0 then
                    info = UIDropDownMenu_CreateInfo(); info.text = 'No lists saved'; info.notCheckable = true; info.disabled = true
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
        end
        local left = CreateFrame('ScrollFrame', nil, editor, 'UIPanelScrollFrameTemplate'); left:SetPoint('TOPLEFT', 16, -70); left:SetPoint('BOTTOMLEFT', 16, 120); left:SetWidth(340)
        local leftBg = left:CreateTexture(nil, 'BACKGROUND')
        leftBg:SetAllPoints(left)
        leftBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        local edit = CreateFrame('EditBox', 'CDSched_Edit', left); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject('ChatFontNormal'); edit:SetWidth(340); left:SetScrollChild(edit)
        edit:SetScript('OnEnter', function(self) leftBg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end)
        edit:SetScript('OnLeave', function(self) leftBg:SetColorTexture(0.1, 0.1, 0.1, 0.8) end)
        local right = CreateFrame('ScrollFrame', nil, editor, 'UIPanelScrollFrameTemplate'); right:SetPoint('TOPLEFT', left, 'TOPRIGHT', 10, 0); right:SetPoint('BOTTOMRIGHT', -28, 120)
        local rchild = CreateFrame('Frame', nil, right); rchild:SetSize(300, 10); right:SetScrollChild(rchild)
        local rows = {}
        local function UpdatePreview()
            for _, r in ipairs(rows) do r:Hide() end; wipe(rows)
            local txt = edit:GetText() or ''; local entries = {}
            for t, id in string.gmatch(txt, "{%s*[Tt][Ii][Mm][Ee]%s*:%s*([%d:]+)%s*}%s*%-%s*{%s*[Ss][Pp][Ee][Ll][Ll]%s*:%s*(%d+)%s*}") do local tex = SpellTexture(tonumber(id)); table.insert(entries, { time = t, tex = tex }) end
            local y = -2
            for i = 1, #entries do local e = entries[i]; local row = CreateFrame('Frame', nil, rchild); row:SetSize(280, 20); row:SetPoint('TOPLEFT', rchild, 'TOPLEFT', 22, y); local ic = row:CreateTexture(nil, 'ARTWORK'); ic:SetSize(18, 18); ic:SetPoint('LEFT', row, 'LEFT', 0, 0); ic:SetTexture(e.tex or 136243); local fs = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); fs:SetPoint('LEFT', ic, 'RIGHT', 6, 0); fs:SetText(e.time or '??:??'); table.insert(rows, row); y = y - 22 end
            rchild:SetHeight(math.max(10, -y))
        end
        edit:HookScript('OnTextChanged', UpdatePreview)
        local save = CreateFrame('Button', nil, editor, 'UIPanelButtonTemplate'); save:SetSize(100, 22); save:SetPoint('BOTTOMRIGHT', -10, 12); save:SetText('Save'); save:SetScript('OnClick', function()
            local txt = edit:GetText() or ''; local nm = CDSched_Name:GetText() or 'Default'
            local lists = LoadLists(); lists[nm] = txt; SaveLists(lists); SetCharOpt(SELECTED, nm); ParseSelected(); UpdatePreview(); UIDropDownMenu_SetText(listDropdown, DecorateListLabel(nm)); RebuildListDropdown()
        end)
        local del = CreateFrame('Button', nil, editor, 'UIPanelButtonTemplate'); del:SetSize(100, 22); del:SetPoint('RIGHT', save, 'LEFT', -10, 0); del:SetText('Delete'); del:SetScript('OnClick', function()
            local nm = CDSched_Name:GetText() or ''
            if nm == '' then return end
            if IsProtectedListName(nm) then print('[ZZZ-CDScheduler] Boss lists cannot be deleted.'); return end
            local lists = LoadLists(); lists[nm] = nil; SaveLists(lists); if GetCharOpt(SELECTED, 'Default') == nm then SetCharOpt(SELECTED, 'Default') end; edit:SetText(''); CDSched_Name:SetText(''); ParseSelected(); UIDropDownMenu_SetText(listDropdown, 'Select list'); RebuildListDropdown()
        end)
        local enable = CreateFrame('CheckButton', nil, editor, 'SettingsCheckBoxTemplate'); enable:SetPoint('BOTTOMLEFT', editor, 'BOTTOMLEFT', 16, 16); enable:SetChecked(GetOpt(ENABLE, false)); enable:SetScript('OnClick', function(self)
            SetOpt(ENABLE, self:GetChecked())
            if self:GetChecked() then
                if not tracker then BuildTracker() end
                ParseSelected()
                BuildBadge()
                TryReanchorBadge()
                UpdateBadgeVisibility()
                if IsAutoCastEnabled() then StartAutoCastTimer() end
            else
                StopAutoCastTimer()
                UpdateBadgeVisibility()
            end
        end); enable:SetFrameStrata('HIGH')
        local enableText = editor:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); enableText:SetPoint('LEFT', enable, 'RIGHT', 6, 0); enableText:SetText('Enable scheduled cooldowns')
        local allow = CreateFrame('CheckButton', nil, editor, 'SettingsCheckBoxTemplate'); allow:SetPoint('BOTTOMLEFT', enable, 'TOPLEFT', 0, 8); allow:SetChecked(GetOpt(ALLOW_NONRAID, false)); allow:SetScript('OnClick', function(self) SetOpt(ALLOW_NONRAID, self:GetChecked()); UpdateBadgeVisibility() end); allow:SetFrameStrata('HIGH')
        local allowText = editor:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); allowText:SetPoint('LEFT', allow, 'RIGHT', 6, 0); allowText:SetText('Allow outside raid (testing)')
        local show = CreateFrame('CheckButton', nil, editor, 'SettingsCheckBoxTemplate'); show:SetPoint('BOTTOMLEFT', allow, 'TOPLEFT', 0, 8); show:SetChecked(GetOpt(SHOW_TRACKER, true)); show:SetScript('OnClick', function(self) SetOpt(SHOW_TRACKER, self:GetChecked()) end); show:SetFrameStrata('HIGH')
        local showText = editor:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight'); showText:SetPoint('LEFT', show, 'RIGHT', 6, 0); showText:SetText('Show on-screen tracker')
        local windowLabel = editor:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
        windowLabel:SetPoint('TOPLEFT', right, 'BOTTOMLEFT', 0, -8)
        windowLabel:SetText('Window (seconds):')
        local wl = CreateFrame('EditBox', nil, editor, 'InputBoxTemplate'); wl:SetSize(60, 24); wl:SetPoint('LEFT', windowLabel, 'RIGHT', 8, 0); wl:SetAutoFocus(false); wl:SetText(tostring(GetOpt(WINDOW, '5'))); wl:SetScript('OnEditFocusLost', function(self) SetOpt(WINDOW, self:GetText()) end)
        editor.enable = enable; editor.allow = allow; editor.window = wl; editor.listDropdown = listDropdown
        RebuildListDropdown()
    end
    local lists = LoadLists(); local cur = GetCharOpt(SELECTED, 'Default'); CDSched_Name:SetText(cur); CDSched_Edit:SetText(lists[cur] or ''); UIDropDownMenu_SetText(CDSched_ListDropdown, (function(n) if n:find('%- Heroic$') then return (n:gsub('%- Heroic$', '') .. '|cffff8000 - Heroic|r') elseif n:find('%- Mythic$') then return (n:gsub('%- Mythic$', '') .. '|cffa335ee - Mythic|r') else return n end end)(cur))
    editor:Show()
end
if MainAddon and MainAddon.Cast then
    local CastOriginal = MainAddon.Cast
    local lastDebugTime = 0
    if HL and HL.RegisterForSelfCombatEvent then
        HL:RegisterForSelfCombatEvent(function(event, _, _, _, _, _, _, _, _, _, _, spellId)
            if scheduledSpell then
                local matches = (scheduledSpell.id == spellId)
                if not matches and scheduledObject and scheduledObject.ItemID then
                    matches = false
                end
                if matches then
                    MarkConsumedNearest(scheduledSpell.id)
                    scheduledSpell = nil
                    scheduledObject = nil
                    if not tracker then BuildTracker() end
                    if tracker then tracker:Show() end
                end
            end
        end, "SPELL_CAST_SUCCESS")
    end
    MainAddon.Cast = function(spell, ...)
        if scheduledSpell and scheduledObject then
            local currentSpell = scheduledSpell
            local currentObject = scheduledObject
            local cdRemaining = GetScheduledCooldown(currentSpell.id)
            if cdRemaining > 0 then
                return false, 'scheduled spell on cooldown (' .. string.format("%.1f", cdRemaining) .. 's)'
            end
            local now = GetTime()
            local isItem = currentObject.ItemID ~= nil
            if now - lastDebugTime > 1 then
                local ready = currentObject.IsReady and currentObject:IsReady() or false
                print("[CDSched Hook] Injecting " .. (isItem and "item" or "spell") .. " " .. currentSpell.id .. ", ready=" .. tostring(ready))
                lastDebugTime = now
            end
            if not isItem then
                if currentObject.IsReady and not currentObject:IsReady() then
                    return true, 'scheduled spell not ready, waiting'
                end
            end
            local ok, reason = CastOriginal(currentObject, ...)
            if not ok and now - lastDebugTime > 1 then
                print("[CDSched Hook] Cast failed: " .. tostring(reason))
            end
            return true, 'scheduled spell injected'
        end
        if IsActive() and spell and spell.ID and schedMap and schedMap[spell:ID()] then
            if not IsAllowedNow(spell:ID()) then return false, 'cdsched: before time' end
            local ok, reason = CastOriginal(spell, ...)
            if ok then MarkConsumedNearest(spell:ID()); if not tracker then BuildTracker() end; tracker:Show() end
            return ok, reason
        end
        return CastOriginal(spell, ...)
    end
end
if HL and HL.RegisterForEvent then
    HL:RegisterForEvent(function() combatStart = GetTime(); consumed = {}; encounterAllowed = true; if not tracker then BuildTracker() end; ParseSelected(); if tracker and GetOpt(SHOW_TRACKER, true) then tracker:Show() end; if IsAutoCastEnabled() then StartAutoCastTimer() end end, 'PLAYER_REGEN_DISABLED')
    HL:RegisterForEvent(function() combatStart = 0; consumed = {}; if tracker then tracker:Hide() end; StopAutoCastTimer() end, 'PLAYER_REGEN_ENABLED')
    HL:RegisterForEvent(function()
        local lists = LoadLists()
        if GetCharOpt(SELECTED, nil) == nil then
            local first
            for k,_ in pairs(lists) do first = k break end
            SetCharOpt(SELECTED, first or 'Default')
        end
        if not CDSchedulerDB._encountersSeeded then
            SeedEncounters()
            CDSchedulerDB._encountersSeeded = true
        end
        CleanupNonDifficultyLists()
        lists = LoadLists()
        local cur = GetCharOpt(SELECTED, 'Default')
        if cur and lists[cur] == nil then
            SetCharOpt(SELECTED, 'Custom')
        end
        ParseSelected()
        BuildBadge(); StartAnchorTicker(); UpdateBadgeVisibility()
        if IsAutoCastEnabled() then StartAutoCastTimer() end
    end, 'PLAYER_LOGIN')
    HL:RegisterForEvent(function()
        BuildBadge(); StartAnchorTicker()
    end, 'ADDON_LOADED')
    HL:RegisterForEvent(function(_, encounterID, encounterName, difficultyID)
        local listName = LookupEncounterList(encounterID, difficultyID)
        if listName then
            local lists = LoadLists()
            if lists[listName] then
                SetCharOpt(SELECTED, listName)
                ParseSelected()
                if not tracker then BuildTracker() end
                if tracker and GetOpt(SHOW_TRACKER, true) then tracker:Show() end
            end
            encounterAllowed = true
        else
            encounterAllowed = false
        end
    end, 'ENCOUNTER_START')
end
ParseSelected()
