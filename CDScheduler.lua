-- CDScheduler - Standalone cooldown scheduler

local ADDON, ns = ...
local HL = HeroLibEx
local Player = HL and HL.Unit and HL.Unit.Player
local MainAddon = _G.MainAddon 
local JSON = LibStub and LibStub('LibJSON-1.0', true)

CDSchedulerDB = CDSchedulerDB or {}

local ENABLE = 'enable'
local ALLOW_NONRAID = 'allow_nonraid'
local WINDOW = 'window'
local LISTS = 'lists'
local SELECTED = 'selected'
local SHOW_TRACKER = 'show_tracker'
local ENCOUNTER_MAP = 'encounter_map'

local function GetOpt(key, default)
    local v = CDSchedulerDB[key]
    if v == nil then return default end
    return v
end
local function SetOpt(key, val) CDSchedulerDB[key] = val end

local function IsRaidArea()
    if Player and Player.IsInRaidArea then return Player:IsInRaidArea() end
    local _, itype = GetInstanceInfo()
    return itype == 'raid'
end

local encounterAllowed = true
local function IsActive()
    if not GetOpt(ENABLE, false) then return false end
    if not (IsRaidArea() or GetOpt(ALLOW_NONRAID, false)) then return false end
    if not encounterAllowed then
        return GetOpt(SELECTED, 'Default') == 'Custom'
    end
    return true
end

local function GetWindow()
    local w = tonumber(GetOpt(WINDOW, '5')) or 5
    if w < 0 then w = 0 end
    return w
end

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
local schedMap = {} -- [spellId] = { times }
local consumed = {}  -- [spellId] = { [idx]=true }

local function TimeToSeconds(s)
    local h, m, sec = 0, 0, 0
    local p = {}
    for tok in string.gmatch(s or '', '[^:]+') do p[#p+1] = tok end
    if #p == 2 then m = tonumber(p[1]) or 0; sec = tonumber(p[2]) or 0
    elseif #p == 3 then h = tonumber(p[1]) or 0; m = tonumber(p[2]) or 0; sec = tonumber(p[3]) or 0
    else sec = tonumber(s) or 0 end
    return h*3600 + m*60 + sec
end

local function ParseScheduleText(txt)
    local map = {}
    if not txt or txt == '' then return map end
    for t, id in string.gmatch(txt, "{%s*[Tt][Ii][Mm][Ee]%s*:%s*([%d:]+)%s*}%s*%-%s*{%s*[Ss][Pp][Ee][Ll][Ll]%s*:%s*(%d+)%s*}") do
        local sid = tonumber(id)
        local secs = TimeToSeconds(t)
        if sid and secs then map[sid] = map[sid] or {}; table.insert(map[sid], secs) end
    end
    for _, list in pairs(map) do table.sort(list) end
    return map
end

local function LoadLists()
    local raw = CDSchedulerDB[LISTS]
    if type(raw) == 'string' and raw ~= '' and JSON then
        local ok, obj = pcall(JSON.Deserialize, raw)
        if ok and type(obj) == 'table' then return obj end
    end
    return {}
end

local function SaveLists(tbl)
    if JSON then
        local ok, str = pcall(JSON.Serialize, tbl)
        if ok then CDSchedulerDB[LISTS] = str end
    end
end

local function DecorateDifficultyLabel(nm)
    if type(nm) ~= 'string' then return nm end
    if nm:find('%- Heroic$') then return (nm:gsub('%- Heroic$', '') .. ' - |cffff8000Heroic|r') end
    if nm:find('%- Mythic$') then return (nm:gsub('%- Mythic$', '') .. ' - |cffa335eeMythic|r') end
    return nm
end

local function GetEncounterMap()
    local m = CDSchedulerDB[ENCOUNTER_MAP]
    if type(m) ~= 'table' then m = {}; CDSchedulerDB[ENCOUNTER_MAP] = m end
    return m
end
local function MapKey(encounterID, difficultyID)
    return tostring(encounterID) .. ':' .. tostring(difficultyID)
end
local function AssignEncounterList(encounterID, difficultyID, listName)
    local m = GetEncounterMap()
    local key = MapKey(encounterID, difficultyID)
    if listName and listName ~= '' then m[key] = listName end
end
local function LookupEncounterList(encounterID, difficultyID)
    local m = GetEncounterMap()
    return m[MapKey(encounterID, difficultyID)]
end

local function IsProtectedListName(name)
    if not name or name == '' then return false end
    local m = GetEncounterMap()
    for _, v in pairs(m) do if v == name then return true end end
    return false
end

local function SeedManaforgeOmega()
    local seeds = {
        [3129] = 'Plexus Sentinel',
        [3131] = 'Loomithar',
        [3130] = 'Soulbinder Naazindhri',
        [3132] = 'Forgeweaver Araz',
        [3122] = 'The Soul Hunters',
        [3133] = 'Fractillus',
        [3134] = 'Nexus-King Salhadaar',
        [3135] = 'Dimensius the All-Devouring',
    }
    local lists = LoadLists()
    local m = GetEncounterMap()
    for eid, listName in pairs(seeds) do
        local heroicName = listName .. ' - Heroic'
        local mythicName = listName .. ' - Mythic'
        if not lists[heroicName] then lists[heroicName] = '' end
        if not lists[mythicName] then lists[mythicName] = '' end
        m[MapKey(eid, 15)] = heroicName
        m[MapKey(eid, 16)] = mythicName
    end
    if not lists['Custom'] then lists['Custom'] = '' end
    SaveLists(lists)
end

local function EnsureDifficultySplit()
    local seeds = {
        [3129] = 'Plexus Sentinel',
        [3131] = 'Loomithar',
        [3130] = 'Soulbinder Naazindhri',
        [3132] = 'Forgeweaver Araz',
        [3122] = 'The Soul Hunters',
        [3133] = 'Fractillus',
        [3134] = 'Nexus-King Salhadaar',
        [3135] = 'Dimensius the All-Devouring',
    }
    local lists = LoadLists()
    local m = GetEncounterMap()
    local changed = false
    for eid, base in pairs(seeds) do
        local heroicName = base .. ' - Heroic'
        local mythicName = base .. ' - Mythic'
        local legacy = lists[base]
        if lists[heroicName] == nil then lists[heroicName] = legacy or ''; changed = true end
        if lists[mythicName] == nil then lists[mythicName] = legacy or ''; changed = true end
        m[MapKey(eid, 15)] = heroicName
        m[MapKey(eid, 16)] = mythicName
    end
    if lists['Custom'] == nil then lists['Custom'] = ''; changed = true end
    if changed then SaveLists(lists) end
end

local function CleanupNonDifficultyLists()
    local lists = LoadLists()
    local changed = false
    for name,_ in pairs(lists) do
        local isCustom = (name == 'Custom')
        local isHeroic = type(name) == 'string' and name:find('%- Heroic$') ~= nil
        local isMythic = type(name) == 'string' and name:find('%- Mythic$') ~= nil
        if not isCustom and not isHeroic and not isMythic then
            lists[name] = nil
            changed = true
        end
    end
    if changed then SaveLists(lists) end
end

local function PurgeUnlabeledLists()
    local lists = LoadLists()
    local changed = false
    for name,_ in pairs(lists) do
        if name ~= 'Custom' and not name:find('%- Heroic$') and not name:find('%- Mythic$') then
            lists[name] = nil
            changed = true
        end
    end
    if changed then SaveLists(lists) end
end

local function ParseSelected()
    if not IsActive() then schedMap = {}; consumed = {}; return end
    local lists = LoadLists()
    local selected = GetOpt(SELECTED, 'Default')
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

ns.IsAllowedNow = IsAllowedNow
ns.ParseSelected = ParseSelected
ns.MarkConsumedNearest = MarkConsumedNearest

local tracker, rows, last = nil, {}, 0
local badge
local function UpdateBadgeVisibility()
    if not badge then return end
    if IsActive() then badge:Show() else badge:Hide() end
end
local function BuildBadge()
    if badge then return end
    badge = CreateFrame('Frame', 'CDSched_Badge', UIParent)
    badge:SetSize(110, 18)
    badge:SetFrameStrata('TOOLTIP')
    local fs = badge:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    fs:SetAllPoints(true)
    fs:SetJustifyH('LEFT')
    fs:SetText('|cffff5555Scheduler ON|r')
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
    for id, list in pairs(schedMap) do local used = consumed[id]; for i = 1, #list do local t = list[i]; if not (used and used[i]) and (t + w >= elapsed) then local tex = SpellTexture(id); table.insert(out, { id = id, tex = tex, time = t }) end end end
    table.sort(out, function(a,b) return a.time < b.time end); return out
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
    tracker:SetScript('OnUpdate', function() local now = GetTime(); if now - last > 0.25 then if not GetOpt(SHOW_TRACKER, true) then tracker:Hide(); last = now; return end; local entries = FlattenEntries(); local shown = 0; local elapsed = (combatStart > 0) and (now - combatStart) or 0; local w = GetWindow();
        tracker.header:SetText('List: ' .. DecorateDifficultyLabel(GetOpt(SELECTED, 'Default') or 'Default'))
        for i = 1, #rows do local row = rows[i]; local e = entries[i]; if e then row.icon:SetTexture(e.tex or 136243); local rem = e.time - elapsed; if rem < 0 then rem = 0 end; row.text:SetText(TimeToMMSS(rem)); if (e.time - elapsed) <= w then row.text:SetTextColor(0.2,1,0.2) else row.text:SetTextColor(1,1,1) end; row:Show(); shown = shown + 1 else row:Hide() end end; if shown > 0 then tracker:Show() else tracker:Hide() end; last = now end end)
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
            if nm:find('%- Heroic$') then return (nm:gsub('%- Heroic$', '') .. '|cffff8000 - Heroic|r') end
            if nm:find('%- Mythic$') then return (nm:gsub('%- Mythic$', '') .. '|cffa335ee - Mythic|r') end
            return nm
        end
        local function RebuildListDropdown()
            local lists = LoadLists()
            local function OnSelect(self, arg1)
                CDSched_Name:SetText(arg1)
                local l = LoadLists()
                CDSched_Edit:SetText(l[arg1] or '')
                CDSchedulerDB[SELECTED] = arg1
                ParseSelected()
                UIDropDownMenu_SetText(listDropdown, DecorateListLabel(arg1))
            end
            UIDropDownMenu_Initialize(listDropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                local ordered = {}
                local bases = {
                    'Plexus Sentinel',
                    'Loomithar',
                    'Soulbinder Naazindhri',
                    'Forgeweaver Araz',
                    'The Soul Hunters',
                    'Fractillus',
                    'Nexus-King Salhadaar',
                    'Dimensius the All-Devouring',
                }
                for i = 1, #bases do
                    local base = bases[i]
                    local h = base .. ' - Heroic'
                    local m = base .. ' - Mythic'
                    if lists[h] then table.insert(ordered, h) end
                    if lists[m] then table.insert(ordered, m) end
                end
                if lists['Custom'] then table.insert(ordered, 'Custom') end
                for i = 1, #ordered do
                    local nm = ordered[i]
                    info.text = DecorateListLabel(nm); info.arg1 = nm; info.func = OnSelect; info.checked = (nm == (GetOpt(SELECTED, 'Default')))
                    UIDropDownMenu_AddButton(info, level)
                end
                if #ordered == 0 then
                    info = UIDropDownMenu_CreateInfo(); info.text = 'No lists saved'; info.notCheckable = true; info.disabled = true
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
        end
        local left = CreateFrame('ScrollFrame', nil, editor, 'UIPanelScrollFrameTemplate'); left:SetPoint('TOPLEFT', 16, -70); left:SetPoint('BOTTOMLEFT', 16, 120); left:SetWidth(340)
        local edit = CreateFrame('EditBox', 'CDSched_Edit', left); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject('ChatFontNormal'); edit:SetWidth(340); left:SetScrollChild(edit)
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
            local lists = LoadLists(); lists[nm] = txt; SaveLists(lists); CDSchedulerDB[SELECTED] = nm; ParseSelected(); UpdatePreview(); UIDropDownMenu_SetText(listDropdown, DecorateListLabel(nm)); RebuildListDropdown()
        end)
        local del = CreateFrame('Button', nil, editor, 'UIPanelButtonTemplate'); del:SetSize(100, 22); del:SetPoint('RIGHT', save, 'LEFT', -10, 0); del:SetText('Delete'); del:SetScript('OnClick', function()
            local nm = CDSched_Name:GetText() or ''
            if nm == '' then return end
            if IsProtectedListName(nm) then print('[CDScheduler] Boss lists cannot be deleted.'); return end
            local lists = LoadLists(); lists[nm] = nil; SaveLists(lists); if GetOpt(SELECTED, 'Default') == nm then CDSchedulerDB[SELECTED] = 'Default' end; edit:SetText(''); CDSched_Name:SetText(''); ParseSelected(); UIDropDownMenu_SetText(listDropdown, 'Select list'); RebuildListDropdown()
        end)
        local enable = CreateFrame('CheckButton', nil, editor, 'SettingsCheckBoxTemplate'); enable:SetPoint('BOTTOMLEFT', editor, 'BOTTOMLEFT', 16, 16); enable:SetChecked(GetOpt(ENABLE, false)); enable:SetScript('OnClick', function(self) SetOpt(ENABLE, self:GetChecked()); if self:GetChecked() then if not tracker then BuildTracker() end end; ParseSelected(); BuildBadge(); TryReanchorBadge(); UpdateBadgeVisibility() end); enable:SetFrameStrata('HIGH')
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
    local lists = LoadLists(); local cur = GetOpt(SELECTED, 'Default'); CDSched_Name:SetText(cur); CDSched_Edit:SetText(lists[cur] or ''); UIDropDownMenu_SetText(CDSched_ListDropdown, (function(n) if n:find('%- Heroic$') then return (n:gsub('%- Heroic$', '') .. '|cffff8000 - Heroic|r') elseif n:find('%- Mythic$') then return (n:gsub('%- Mythic$', '') .. '|cffa335ee - Mythic|r') else return n end end)(cur))
    editor:Show()
end

if MainAddon and MainAddon.Cast then
    local CastOriginal = MainAddon.Cast
    MainAddon.Cast = function(spell, ...)
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
    HL:RegisterForEvent(function() combatStart = GetTime(); consumed = {}; encounterAllowed = true; if not tracker then BuildTracker() end end, 'PLAYER_REGEN_DISABLED')
    HL:RegisterForEvent(function() combatStart = 0; consumed = {}; if tracker then tracker:Hide() end end, 'PLAYER_REGEN_ENABLED')
    HL:RegisterForEvent(function()
        local lists = LoadLists()
        if CDSchedulerDB[SELECTED] == nil then
            local first
            for k,_ in pairs(lists) do first = k break end
            CDSchedulerDB[SELECTED] = first or 'Default'
        end
        if not CDSchedulerDB._moSeeded then
            SeedManaforgeOmega(); CDSchedulerDB._moSeeded = true
        end
        EnsureDifficultySplit()
        CleanupNonDifficultyLists()
        lists = LoadLists()
        local cur = GetOpt(SELECTED, 'Default')
        if cur and lists[cur] == nil then
            CDSchedulerDB[SELECTED] = 'Custom'
        end
        ParseSelected()
        BuildBadge(); StartAnchorTicker(); UpdateBadgeVisibility()
    end, 'PLAYER_LOGIN')
    HL:RegisterForEvent(function()
        BuildBadge(); StartAnchorTicker()
    end, 'ADDON_LOADED')

    HL:RegisterForEvent(function(_, encounterID, encounterName, difficultyID)
        local listName = LookupEncounterList(encounterID, difficultyID)
        if listName then
            local lists = LoadLists()
            if lists[listName] then
                CDSchedulerDB[SELECTED] = listName
                ParseSelected()
                if not tracker then BuildTracker() end
            end
            encounterAllowed = true
        else
            encounterAllowed = false
        end
    end, 'ENCOUNTER_START')
end

ParseSelected()


