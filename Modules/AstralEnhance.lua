-- ElvUI_Banbi — Astral Forger/Caster auto enhance (gossip) to N/10 without luck charms.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "astralEnhance"

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitName = UnitName
local UnitExists = UnitExists
local GetGossipOptions = GetGossipOptions
local SelectGossipOption = SelectGossipOption
local CloseGossip = CloseGossip
local TargetByName = TargetByName
local InteractUnit = InteractUnit
local InCombatLockdown = InCombatLockdown
local format = string.format
local find = string.find
local match = string.match
local lower = string.lower
local gsub = string.gsub
local wipe = wipe

local ProcessGossip -- forward decl for GoBackOrReopen

local NPC_NAMES = {
    "星界铸造者",
    "星界锻造者",
}

local ATTR_PATTERN = "^(.-)%s*%((%d+)%s*/%s*(%d+)%)%s*$"
local UPGRADE_PLAIN = "提升一级强化等级"
local LUCK_TOKEN = "好运符"
-- Gossip UI often pads with CJK ideographic space (U+3000). Lua 5.1 patterns are
-- byte-based, so never put　inside []; normalize to ASCII space first.
local IDEOGRAPHIC_SPACE = "　"

local running = false
local busy = false
local statusText = ""
local panel
local eventFrame
local pendingTimer
local attempts = 0
local lastActionAt = 0
-- Multi-item pass: walk gossip equipment list without unequipping.
local currentItemKey = nil -- canonical item name currently being enhanced
local completedItems = {} -- [itemKey] = true
local knownItemOrder = {} -- names discovered on item page, stable order

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function Print(msg)
    print("|cff1784d1Banbi|r " .. tostring(msg))
end

local function SetStatus(msg)
    statusText = msg or ""
    if panel and panel.status then
        panel.status:SetText(statusText)
    end
end

local function After(delay, fn)
    if pendingTimer then
        if addon.core and addon.core.CancelTimer then
            addon.core:CancelTimer(pendingTimer, true)
        end
        pendingTimer = nil
    end
    if addon.core and addon.core.ScheduleTimer then
        pendingTimer = addon.core:ScheduleTimer(function()
            pendingTimer = nil
            fn()
        end, delay)
        return
    end
    local f = CreateFrame("Frame")
    local t = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t >= delay then
            f:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

local function GetDelay()
    local cfg = Cfg()
    local d = cfg and cfg.clickDelay
    if type(d) ~= "number" or d < 0.2 then
        return 0.45
    end
    if d > 2 then
        return 2
    end
    return d
end

local function GetTargetLevel()
    local cfg = Cfg()
    local n = cfg and cfg.targetLevel
    if type(n) ~= "number" then
        return 9
    end
    if n < 1 then
        return 1
    end
    if n > 10 then
        return 10
    end
    return math.floor(n)
end

local function NormalizeSpaces(s)
    if not s then
        return ""
    end
    return (gsub(s, IDEOGRAPHIC_SPACE, " "))
end

local function Trim(s)
    if not s then
        return ""
    end
    s = NormalizeSpaces(s)
    return (gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Canonical attr key for exclude matching (strip all whitespace).
local function AttrKey(s)
    s = Trim(s)
    if s == "" then
        return ""
    end
    return (gsub(s, "%s+", ""))
end

-- Build { [attrKey]=true } from cfg.attrExclude ("力量,敏捷" / "力量、敏捷" / "力量，敏捷").
local function GetAttrExcludeSet()
    local cfg = Cfg()
    local raw = cfg and cfg.attrExclude
    local set = {}
    if type(raw) ~= "string" or raw == "" then
        return set
    end
    raw = NormalizeSpaces(raw)
    -- Normalize common Chinese / ASCII separators to ","
    raw = gsub(raw, "、", ",")
    raw = gsub(raw, "，", ",")
    raw = gsub(raw, "；", ",")
    raw = gsub(raw, ";", ",")
    raw = gsub(raw, "%s+", ",")
    for part in string.gmatch(raw, "[^,]+") do
        local name = AttrKey(part)
        if name ~= "" then
            set[name] = true
        end
    end
    return set
end

local function FormatExcludeList(set)
    local names = {}
    for name in pairs(set) do
        names[#names + 1] = name
    end
    if #names == 0 then
        return ""
    end
    table.sort(names)
    return table.concat(names, ",")
end

-- Upgrade page status:「已选择强化属性：攻击强度 (3/10)」
local function ExtractSelectedAttr(options)
    for i = 1, #options do
        local text = NormalizeSpaces(options[i].text)
        local name, cur, maxv = match(text, "已选择强化属性%s*[：:]%s*(.-)%s*%((%d+)%s*/%s*(%d+)%)")
        if name then
            name = Trim(name)
            if name ~= "" then
                return name, tonumber(cur), tonumber(maxv)
            end
        end
    end
    return nil
end

local function GossipOpen()
    return GossipFrame and GossipFrame:IsShown()
end

-- Strip |cAARRGGBB / |r so matching works on colored gossip text.
local function StripColors(text)
    if not text then
        return ""
    end
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    text = gsub(text, "|T.-|t", "")
    text = NormalizeSpaces(text)
    return text
end

-- Prefer GossipTitleButtonN (same as /click macro). SelectGossipOption index
-- often disagrees with button id on custom gossip UIs that pad header rows.
local function CollectGossipOptions()
    local list = {}
    for i = 1, 32 do
        local btn = _G["GossipTitleButton" .. i]
        if not btn then
            break
        end
        if btn:IsShown() then
            local text = StripColors(btn:GetText() or "")
            if text ~= "" then
                list[#list + 1] = {
                    index = i,
                    text = text,
                    button = btn,
                }
            end
        end
    end
    if #list > 0 then
        return list
    end
    -- Last resort: API options (index may not match TitleButton)
    if GetGossipOptions then
        local raw = { GetGossipOptions() }
        local idx = 0
        for i = 1, #raw, 2 do
            idx = idx + 1
            local text = StripColors(raw[i] or "")
            if text ~= "" then
                list[#list + 1] = { index = idx, text = text }
            end
        end
    end
    return list
end

local function ParseAttr(text)
    if not text then
        return nil
    end
    local name, cur, maxv = match(text, ATTR_PATTERN)
    if not name then
        return nil
    end
    -- Skip header-like lines that somehow match
    if find(name, "已选择", 1, true) or find(name, "请选择", 1, true) then
        return nil
    end
    return {
        name = Trim(name),
        cur = tonumber(cur),
        max = tonumber(maxv),
    }
end

local function IsPlainUpgradeText(text)
    if not text then
        return false
    end
    -- Status/header lines also contain「提升一级强化等级」— must not treat as the click option
    if find(text, "每提升", 1, true) or find(text, "将获得", 1, true) then
        return false
    end
    if find(text, "已选择", 1, true) or find(text, "可以强化", 1, true) then
        return false
    end
    -- Distinguishes luck charm via token only — plain upgrade is also 100% at 0/10
    if find(text, LUCK_TOKEN, 1, true) then
        return false
    end
    -- Real option:「提升一级强化等级 (成功几率: N%)」(N can be 100% at low levels)
    if find(text, "提升一级", 1, true) and find(text, "成功几率", 1, true) then
        return true
    end
    return false
end

local function DetectPage(options)
    local hasUpgrade, hasLuck, hasAttr, hasSelectHint = false, false, false, false
    local attrs = {}
    for i = 1, #options do
        local text = options[i].text
        if find(text, LUCK_TOKEN, 1, true) and find(text, "提升一级", 1, true) then
            hasLuck = true
        elseif IsPlainUpgradeText(text) then
            hasUpgrade = true
        end
        local attr = ParseAttr(text)
        -- Only count real selectable attrs, not「已选择强化属性：命中 (8/10)」status lines
        if attr and attr.max == 10 and not find(text, "已选择强化属性", 1, true) then
            hasAttr = true
            attrs[#attrs + 1] = {
                index = options[i].index,
                name = attr.name,
                cur = attr.cur,
                max = attr.max,
                button = options[i].button,
            }
        end
        if find(text, "请选择强化属性", 1, true) then
            hasSelectHint = true
        end
    end
    -- Upgrade page must win even if status line also shows (x/10)
    if hasUpgrade or hasLuck then
        return "upgrade", attrs
    end
    if hasAttr or hasSelectHint then
        return "attr", attrs
    end
    return "item", attrs
end

local function FindUpgradeOption(options)
    local plain, fallback
    for i = 1, #options do
        local text = options[i].text
        if IsPlainUpgradeText(text) then
            plain = options[i]
            break
        elseif find(text, "成功几率", 1, true)
            and not find(text, LUCK_TOKEN, 1, true)
            and not find(text, "每提升", 1, true)
            and not find(text, "将获得", 1, true) then
            fallback = fallback or options[i]
        end
    end
    return plain or fallback
end

local function FindAttrNeedingUpgrade(attrs, targetLevel)
    local exclude = GetAttrExcludeSet()
    for i = 1, #attrs do
        local a = attrs[i]
        local key = AttrKey(a.name)
        if key ~= "" and not exclude[key] and a.cur and a.cur < targetLevel then
            return a
        end
    end
    return nil
end

local function IsEnhanceNPCName(name)
    if not name then
        return false
    end
    for i = 1, #NPC_NAMES do
        if name == NPC_NAMES[i] then
            return true
        end
    end
    return false
end

local function EnsureNPCTarget()
    local name = UnitName("target")
    if IsEnhanceNPCName(name) then
        return true
    end
    if UnitExists("npc") and IsEnhanceNPCName(UnitName("npc")) then
        return true
    end
    for i = 1, #NPC_NAMES do
        if TargetByName then
            TargetByName(NPC_NAMES[i], true)
        end
        if IsEnhanceNPCName(UnitName("target")) then
            return true
        end
    end
    return false
end

local function OpenGossip()
    if GossipOpen() then
        return true
    end
    if not EnsureNPCTarget() then
        SetStatus(L["Astral: target NPC first"] or "请先选中星界铸造者/锻造者")
        return false
    end
    if InteractUnit then
        InteractUnit("target")
    end
    return GossipOpen()
end

local function ClickOption(indexOrEntry)
    local index, button
    if type(indexOrEntry) == "table" then
        index = indexOrEntry.index
        button = indexOrEntry.button
    else
        index = indexOrEntry
    end
    if not index and not button then
        return false
    end
    lastActionAt = GetTime()
    -- Prefer real button :Click() — matches /click GossipTitleButtonN on this server
    if not button and index then
        button = _G["GossipTitleButton" .. index]
    end
    if button and button.Click and button:IsShown() then
        button:Click()
        return true
    end
    if index and SelectGossipOption then
        SelectGossipOption(index)
        return true
    end
    return false
end

local function NormalizeItemKey(text)
    if not text then
        return nil
    end
    local fromLabel = match(text, "已选择物品.-%[(.-)%]")
    if fromLabel and fromLabel ~= "" then
        return Trim(fromLabel)
    end
    local bracket = match(text, "%[(.-)%]")
    if bracket and bracket ~= "" then
        return Trim(bracket)
    end
    local t = Trim(text)
    return t ~= "" and t or nil
end

local function IsHeaderOrNavText(text)
    if not text or text == "" then
        return true
    end
    if find(text, "返回", 1, true) then
        return true
    end
    if find(text, "※", 1, true) then
        return true
    end
    if find(text, "已选择", 1, true) then
        return true
    end
    if find(text, "请选择", 1, true) then
        return true
    end
    if find(text, "可以强化", 1, true) then
        return true
    end
    if find(text, "每提升", 1, true) then
        return true
    end
    if find(text, UPGRADE_PLAIN, 1, true) then
        return true
    end
    if find(text, LUCK_TOKEN, 1, true) then
        return true
    end
    if ParseAttr(text) then
        return true
    end
    return false
end

local function IsItemOptionText(text)
    if IsHeaderOrNavText(text) then
        return false
    end
    -- Prefer [物品名] lines; also allow plain names on item list page
    if find(text, "%[.+%]") then
        return true
    end
    -- Plain row that is not navigation: treat as candidate item
    if #text >= 2 then
        return true
    end
    return false
end

local function ExtractSelectedItemKey(options)
    for i = 1, #options do
        local text = options[i].text
        local fromLabel = match(text, "已选择物品.-%[(.-)%]")
        if fromLabel then
            return fromLabel
        end
        local onlyBracket = match(text, "^%s*%[(.-)%]%s*$")
        if onlyBracket then
            return onlyBracket
        end
    end
    return currentItemKey
end

local function FindBackOption(options)
    for i = 1, #options do
        if find(options[i].text, "返回", 1, true) then
            return options[i]
        end
    end
    return nil
end

local function PassesItemFilter(itemKey, text)
    local cfg = Cfg()
    local filter = cfg and cfg.itemFilter
    if type(filter) ~= "string" or filter == "" then
        return true
    end
    return find(itemKey or "", filter, 1, true) or find(text or "", filter, 1, true)
end

local function CollectItemOptions(options)
    local items = {}
    for i = 1, #options do
        local text = options[i].text
        if IsItemOptionText(text) then
            local key = NormalizeItemKey(text)
            if key and PassesItemFilter(key, text) then
                items[#items + 1] = {
                    index = options[i].index,
                    text = text,
                    key = key,
                    button = options[i].button,
                }
                -- remember discovery order
                local seen = false
                for j = 1, #knownItemOrder do
                    if knownItemOrder[j] == key then
                        seen = true
                        break
                    end
                end
                if not seen then
                    knownItemOrder[#knownItemOrder + 1] = key
                end
            end
        end
    end
    return items
end

local function FindNextItemOption(options)
    local items = CollectItemOptions(options)
    if #items == 0 then
        return nil, nil
    end

    -- Continue current item until marked completed
    if currentItemKey and not completedItems[currentItemKey] then
        for i = 1, #items do
            if items[i].key == currentItemKey then
                return items[i], items[i].key
            end
        end
    end

    -- Next incomplete item in list order
    for i = 1, #items do
        local key = items[i].key
        if not completedItems[key] then
            return items[i], key
        end
    end

    return nil, nil -- all done
end

local function CountPendingItems(options)
    local items = CollectItemOptions(options)
    local pending = 0
    for i = 1, #items do
        if not completedItems[items[i].key] then
            pending = pending + 1
        end
    end
    return pending, #items
end

local function GoBackOrReopen(options)
    local back = FindBackOption(options)
    if back then
        ClickOption(back)
        After(GetDelay(), function()
            busy = false
            if running and GossipOpen() then
                ProcessGossip()
            elseif running then
                OpenGossip()
            end
        end)
        return
    end
    if CloseGossip then
        CloseGossip()
    end
    After(GetDelay(), function()
        busy = false
        if running then
            OpenGossip()
        end
    end)
end

local function StopRun(reason)
    running = false
    busy = false
    currentItemKey = nil
    wipe(completedItems)
    wipe(knownItemOrder)
    if pendingTimer and addon.core and addon.core.CancelTimer then
        addon.core:CancelTimer(pendingTimer, true)
        pendingTimer = nil
    end
    if reason then
        SetStatus(reason)
        Print(reason)
    else
        SetStatus(L["Astral: stopped"] or "已停止")
    end
    if panel and panel.startBtn then
        panel.startBtn:SetText(L["Astral: Start"] or "开始强化")
    end
end

ProcessGossip = function()
    if not running or busy then
        return
    end
    if not GossipOpen() then
        return
    end

    local targetLevel = GetTargetLevel()
    local options = CollectGossipOptions()
    if #options == 0 then
        return
    end

    local page, attrs = DetectPage(options)
    busy = true

    -- Keep selected item name in sync when UI shows it
    local selected = ExtractSelectedItemKey(options)
    if selected then
        currentItemKey = selected
    end

    if page == "upgrade" then
        -- Blacklist / target only applied on attr pick before; upgrade page must
        -- also refuse to keep clicking when current selection is excluded or done.
        local selName, selCur = ExtractSelectedAttr(options)
        local exclude = GetAttrExcludeSet()
        local selKey = selName and AttrKey(selName) or ""
        if selKey ~= "" and exclude[selKey] then
            SetStatus(format(
                L["Astral: skip excluded attr"] or "[%s] 跳过排除属性：%s",
                currentItemKey or "?",
                selName
            ))
            GoBackOrReopen(options)
            return
        end
        if selName and selCur and selCur >= targetLevel then
            SetStatus(format(
                L["Astral: attr done reselect"] or "[%s] %s 已达目标，重选属性…",
                currentItemKey or "?",
                selName
            ))
            GoBackOrReopen(options)
            return
        end

        local entry = FindUpgradeOption(options)
        if not entry then
            busy = false
            StopRun(L["Astral: no plain upgrade option"] or "未找到非好运符升级选项")
            return
        end
        attempts = attempts + 1
        local label = currentItemKey or "?"
        local attrLabel = selName and (selName .. " ") or ""
        SetStatus(format(
            L["Astral: upgrading item attr"] or "强化 [%s] %s… 第 %d 次",
            label,
            attrLabel,
            attempts
        ))
        if not ClickOption(entry) then
            busy = false
            StopRun(L["Astral: click failed"] or "点击强化选项失败")
            return
        end
        After(GetDelay(), function()
            busy = false
            if not running then
                return
            end
            if GossipOpen() then
                ProcessGossip()
            else
                OpenGossip()
            end
        end)
        return
    end

    if page == "attr" then
        local need = FindAttrNeedingUpgrade(attrs, targetLevel)
        if not need then
            -- This piece is done → mark and go back to equipment list
            if currentItemKey then
                completedItems[currentItemKey] = true
                Print(format(L["Astral: item done %s"] or "已完成：[%s]", currentItemKey))
            end
            local doneKey = currentItemKey
            currentItemKey = nil
            SetStatus(format(L["Astral: item done next"] or "[%s] 已达目标，切换下一件…", doneKey or "?"))
            GoBackOrReopen(options)
            return
        end
        SetStatus(format(
            L["Astral: pick attr on item"] or "[%s] 属性：%s（%d/%d）",
            currentItemKey or "?",
            need.name,
            need.cur,
            need.max
        ))
        ClickOption(need)
        After(GetDelay(), function()
            busy = false
            if running and GossipOpen() then
                ProcessGossip()
            end
        end)
        return
    end

    -- item page: walk list, skip completed
    local itemEntry, itemKey = FindNextItemOption(options)
    if not itemEntry then
        local _, total = CountPendingItems(options)
        busy = false
        if total > 0 or next(completedItems) then
            StopRun(format(L["Astral: all items done %d"] or "列表内装备均已达 %d/10，完成", targetLevel))
        else
            StopRun(L["Astral: no item option"] or "装备列表中未找到可选物品")
        end
        if CloseGossip then
            CloseGossip()
        end
        return
    end

    currentItemKey = itemKey
    local pending, total = CountPendingItems(options)
    SetStatus(format(
        L["Astral: pick item progress"] or "选择装备 [%s]（剩余 %d/%d 件）",
        itemKey,
        pending,
        total
    ))
    ClickOption(itemEntry)
    After(GetDelay(), function()
        busy = false
        if running and GossipOpen() then
            ProcessGossip()
        end
    end)
end

local function StartRun()
    if InCombatLockdown and InCombatLockdown() then
        Print(L["Astral: not in combat"] or "战斗中无法强化")
        return
    end
    if running then
        return
    end
    attempts = 0
    currentItemKey = nil
    wipe(completedItems)
    wipe(knownItemOrder)
    running = true
    busy = false
    local excl = GetAttrExcludeSet()
    local exclText = FormatExcludeList(excl)
    if exclText ~= "" then
        Print(format(L["Astral: exclude active"] or "排除属性已生效：%s", exclText))
        SetStatus(format(L["Astral: starting exclude"] or "开始… 排除 %s", exclText))
    else
        SetStatus(L["Astral: starting"] or "开始… 请靠近 NPC")
    end
    if panel and panel.startBtn then
        panel.startBtn:SetText(L["Astral: Stop"] or "停止")
    end
    if not EnsureNPCTarget() then
        StopRun(L["Astral: target NPC first"] or "请先选中星界铸造者/锻造者")
        return
    end
    if GossipOpen() then
        ProcessGossip()
    else
        OpenGossip()
        After(GetDelay(), function()
            if running then
                if GossipOpen() then
                    ProcessGossip()
                else
                    StopRun(L["Astral: open gossip failed"] or "无法打开对话，请手动右键 NPC 后再点开始")
                end
            end
        end)
    end
end

local function ToggleRun()
    if running then
        StopRun(L["Astral: stopped"] or "已停止")
    else
        StartRun()
    end
end

local function UpdatePanelVisibility()
    if not panel then
        return
    end
    if addon:IsFeatureEnabled(KEY) then
        panel:Show()
    else
        panel:Hide()
        if running then
            StopRun()
        end
    end
end

local function EnsurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "ElvUI_Banbi_AstralEnhance", UIParent)
    panel:SetSize(220, 88)
    panel:SetPoint("CENTER", UIParent, "CENTER", 280, 80)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.8)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown and IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cfg = Cfg()
        if cfg then
            local p, _, rp, x, y = self:GetPoint(1)
            cfg.anchor = p
            cfg.relAnchor = rp
            cfg.posX = x
            cfg.posY = y
        end
    end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText(L["Astral Enhance"] or "星界强化")

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 10, -26)
    panel.status:SetPoint("TOPRIGHT", -10, -26)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetText(L["Astral: idle"] or "待命（Shift+拖动面板）")

    panel.startBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.startBtn:SetSize(90, 22)
    panel.startBtn:SetPoint("BOTTOMLEFT", 10, 10)
    panel.startBtn:SetText(L["Astral: Start"] or "开始强化")
    panel.startBtn:SetScript("OnClick", ToggleRun)

    local stopHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stopHint:SetPoint("BOTTOMRIGHT", -10, 14)
    stopHint:SetText("→" .. GetTargetLevel() .. "/10")

    panel:Hide()
    return panel
end

local function OnEvent(_, event)
    if not addon:IsFeatureEnabled(KEY) then
        return
    end
    if event == "GOSSIP_SHOW" then
        if running and not busy then
            After(0.05, function()
                if running and not busy then
                    ProcessGossip()
                end
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if running then
            StopRun(L["Astral: combat stop"] or "进入战斗，已停止强化")
        end
    elseif event == "GOSSIP_CLOSED" then
        if running and not busy then
            After(GetDelay(), function()
                if running and not GossipOpen() then
                    OpenGossip()
                end
            end)
        end
    end
end

local slashRegistered = false

local function OnEnable()
    EnsurePanel()
    local cfg = Cfg()
    if cfg and cfg.anchor and panel then
        panel:ClearAllPoints()
        panel:SetPoint(cfg.anchor, UIParent, cfg.relAnchor or cfg.anchor, cfg.posX or 280, cfg.posY or 80)
    end
    UpdatePanelVisibility()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("GOSSIP_CLOSED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    if not slashRegistered and addon.core and addon.core.RegisterChatCommand then
        slashRegistered = true
        addon.core:RegisterChatCommand("banbiastral", function(input)
            input = lower(input or "")
            if find(input, "stop", 1, true) then
                StopRun(L["Astral: stopped"] or "已停止")
            else
                StartRun()
            end
        end)
    end
end

local function OnDisable()
    if running then
        StopRun()
    end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if panel then
        panel:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = false,
    label = function()
        return L["Astral Enhance"]
    end,
    desc = function()
        return L["Astral Enhance Desc"]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = UpdatePanelVisibility,
    BuildOptions = function(_, C)
        C:AddDescription(_, L["Astral Enhance Help"])
        C:AddSlider(_, {
            label = L["Astral target level"],
            desc = L["Astral target level desc"],
            min = 1,
            max = 10,
            step = 1,
            getFunc = function()
                return GetTargetLevel()
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.targetLevel = val
                end
            end,
        })
        C:AddSlider(_, {
            label = L["Astral click delay"],
            desc = L["Astral click delay desc"],
            min = 0.2,
            max = 1.5,
            step = 0.05,
            getFunc = function()
                return GetDelay()
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.clickDelay = val
                end
            end,
        })
        C:AddEditBox(_, {
            label = L["Astral item filter"],
            desc = L["Astral item filter desc"],
            getFunc = function()
                local cfg = Cfg()
                return cfg and cfg.itemFilter or ""
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.itemFilter = val or ""
                end
            end,
        })
        C:AddEditBox(_, {
            label = L["Astral attr exclude"],
            desc = L["Astral attr exclude desc"],
            getFunc = function()
                local cfg = Cfg()
                return cfg and cfg.attrExclude or ""
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.attrExclude = val or ""
                end
            end,
        })
        C:AddButton(_, {
            label = L["Astral: Start"],
            desc = L["Astral start button desc"],
            callback = StartRun,
        })
        C:AddButton(_, {
            label = L["Astral: Stop"],
            callback = function()
                StopRun(L["Astral: stopped"] or "已停止")
            end,
        })
    end,
})
