-- ElvUI_Banbi — stat text content for Info Bar (right side).

local ADDON_NAME, addon = ...
local L = addon.L

local CFG_KEY = "infoBar"
local DYNAMIC_CORRUPTION_SPELL = 94005
local CORRUPTION_PATTERN = "%+(%d+)%s*腐蚀"
local RESIST_PATTERN = "%+(%d+)%s*腐蚀抗性"
local UPDATE_INTERVAL = 0.2
local TEXT_PAD = 8

local format = string.format
local match = string.match
local gsub = string.gsub
local tonumber = tonumber
local floor = math.floor

local active = false
local host
local textFS
local eventFrame
local scanTip
local gearCorruption, resistCorruption, dynamicCorruption = 0, 0, 0
local powerKind = "melee"
local updateElapsed = 0
local lastText
local contentWidth = 0

local INV_SLOTS = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
}

local CLASS_FALLBACK = {
    MAGE = "spell",
    WARLOCK = "spell",
    PRIEST = "spell",
    HUNTER = "ranged",
    WARRIOR = "melee",
    ROGUE = "melee",
    DEATHKNIGHT = "melee",
    PALADIN = "melee",
    SHAMAN = "melee",
    DRUID = "melee",
}

local CLASS_TAB_KIND = {
    DRUID = { "spell", "melee", "spell" },
    SHAMAN = { "spell", "melee", "spell" },
    PALADIN = { "spell", "melee", "melee" },
}

local function Cfg()
    return addon:GetFeatureConfig(CFG_KEY)
end

local function NotifyRelayout()
    if addon.InfoBar and addon.InfoBar.Relayout then
        addon.InfoBar.Relayout()
    end
end

local function StripColors(text)
    if not text then
        return ""
    end
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    return text
end

local function ComputeNetCorruption(gear, resist, dynamic)
    return (gear or 0) - (resist or 0) + (dynamic or 0)
end

local function GetTalentTabPoints()
    local t1, t2, t3 = 0, 0, 0
    if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
        return t1, t2, t3
    end
    local tabs = GetNumTalentTabs() or 0
    for tab = 1, tabs do
        local points = 0
        local num = GetNumTalents(tab) or 0
        for i = 1, num do
            local _, _, _, _, rank = GetTalentInfo(tab, i)
            points = points + (rank or 0)
        end
        if tab == 1 then
            t1 = points
        elseif tab == 2 then
            t2 = points
        elseif tab == 3 then
            t3 = points
        end
    end
    return t1, t2, t3
end

local function ClassToken()
    local _, class = UnitClass("player")
    return class or "WARRIOR"
end

local function ResolvePowerKind(powerMode)
    if powerMode == "melee" or powerMode == "ranged" or powerMode == "spell" then
        return powerMode
    end
    local class = ClassToken()
    local map = CLASS_TAB_KIND[class]
    local fallback = CLASS_FALLBACK[class] or "melee"
    if not map then
        return fallback
    end
    local t1, t2, t3 = GetTalentTabPoints()
    local maxp = t1
    if t2 > maxp then
        maxp = t2
    end
    if t3 > maxp then
        maxp = t3
    end
    if maxp == 0 then
        return fallback
    end
    local winners = {}
    if t1 == maxp then
        winners[#winners + 1] = 1
    end
    if t2 == maxp then
        winners[#winners + 1] = 2
    end
    if t3 == maxp then
        winners[#winners + 1] = 3
    end
    if #winners ~= 1 then
        return fallback
    end
    return map[winners[1]] or fallback
end

local function GetSpellPower()
    local schools = { 2, 3, 4, 5, 6, 7 }
    local best = 0
    if GetSpellBonusDamage then
        for i = 1, #schools do
            local v = GetSpellBonusDamage(schools[i]) or 0
            if v > best then
                best = v
            end
        end
    end
    local heal = GetSpellBonusHealing and (GetSpellBonusHealing() or 0) or 0
    if heal > best then
        best = heal
    end
    return best
end

local function GetMeleeAP()
    local base, pos, neg = UnitAttackPower("player")
    return (base or 0) + (pos or 0) + (neg or 0)
end

local function GetRangedAP()
    local base, pos, neg = UnitRangedAttackPower("player")
    return (base or 0) + (pos or 0) + (neg or 0)
end

local function GetPowerValue(kind)
    if kind == "spell" then
        return GetSpellPower()
    end
    if kind == "ranged" then
        return GetRangedAP()
    end
    return GetMeleeAP()
end

local function GetPowerLabel(kind)
    if kind == "spell" then
        return L["Spell Power"] or "法强"
    end
    if kind == "ranged" then
        return L["Ranged Attack Power"] or "远程攻强"
    end
    return L["Attack Power"] or "攻强"
end

local function GetCritPercent(kind)
    if kind == "spell" then
        local best = 0
        for school = 2, 7 do
            local v = GetSpellCritChance and (GetSpellCritChance(school) or 0) or 0
            if v > best then
                best = v
            end
        end
        return best
    end
    if kind == "ranged" then
        return GetRangedCritChance and (GetRangedCritChance() or 0) or 0
    end
    return GetCritChance and (GetCritChance() or 0) or 0
end

local function GetHastePercent(kind)
    if not GetCombatRatingBonus then
        return 0
    end
    if kind == "spell" then
        return GetCombatRatingBonus(CR_HASTE_SPELL) or 0
    end
    if kind == "ranged" then
        return GetCombatRatingBonus(CR_HASTE_RANGED) or 0
    end
    return GetCombatRatingBonus(CR_HASTE_MELEE) or 0
end

local function FormatPercent(v)
    return format("%.1f%%", v or 0)
end

local function EnsureScanTip()
    if scanTip then
        return scanTip
    end
    scanTip = CreateFrame("GameTooltip", "ElvUI_Banbi_StatBarTip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

local function ScanSlotCorruption(slot)
    local tip = EnsureScanTip()
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetInventoryItem("player", slot)
    local gear, resist = 0, 0
    local num = tip:NumLines() or 0
    for i = 2, num do
        local line = _G["ElvUI_Banbi_StatBarTipTextLeft" .. i]
        local text = line and StripColors(line:GetText() or "") or ""
        if text ~= "" then
            local r = match(text, RESIST_PATTERN)
            if r then
                resist = resist + (tonumber(r) or 0)
            else
                local c = match(text, CORRUPTION_PATTERN)
                if c and not match(text, "腐蚀抗性") then
                    gear = gear + (tonumber(c) or 0)
                end
            end
        end
    end
    tip:Hide()
    return gear, resist
end

local function RescanGearCorruption()
    local g, r = 0, 0
    for i = 1, #INV_SLOTS do
        local sg, sr = ScanSlotCorruption(INV_SLOTS[i])
        g = g + sg
        r = r + sr
    end
    gearCorruption, resistCorruption = g, r
end

local function DynamicSpellName()
    if GetSpellInfo then
        return GetSpellInfo(DYNAMIC_CORRUPTION_SPELL)
    end
    return nil
end

local function ReadDynamicCorruption()
    dynamicCorruption = 0
    local wantName = DynamicSpellName()
    local i = 1
    while true do
        local name, _, _, count = UnitAura("player", i, "HELPFUL")
        if not name then
            break
        end
        local isTarget = wantName and name == wantName
        if isTarget then
            local amount = tonumber(count) or 0
            if amount == 0 then
                local tip = EnsureScanTip()
                tip:ClearLines()
                tip:SetOwner(UIParent, "ANCHOR_NONE")
                tip:SetUnitAura("player", i, "HELPFUL")
                local num = tip:NumLines() or 0
                for li = 2, num do
                    local line = _G["ElvUI_Banbi_StatBarTipTextLeft" .. li]
                    local text = line and StripColors(line:GetText() or "") or ""
                    if match(text, "腐蚀") then
                        local n = match(text, "(%d+)")
                        if n then
                            amount = tonumber(n) or 0
                            break
                        end
                    end
                end
                tip:Hide()
            end
            dynamicCorruption = amount
            break
        end
        i = i + 1
    end
end

local function RefreshPowerKind()
    local cfg = Cfg()
    powerKind = ResolvePowerKind(cfg and cfg.powerMode or "auto")
end

local function BuildText()
    local cfg = Cfg() or {}
    local parts = {}
    if cfg.showCorruption ~= false then
        local net = ComputeNetCorruption(gearCorruption, resistCorruption, dynamicCorruption)
        parts[#parts + 1] = format("|cff9420e6%s %d|r", L["Corruption Overflow"] or "腐蚀溢出", net)
    end
    if cfg.showPower ~= false then
        parts[#parts + 1] = format("%s %d", GetPowerLabel(powerKind), floor(GetPowerValue(powerKind) + 0.5))
    end
    if cfg.showCrit ~= false then
        parts[#parts + 1] = format("%s %s", L["Crit"] or "爆击", FormatPercent(GetCritPercent(powerKind)))
    end
    if cfg.showHaste ~= false then
        parts[#parts + 1] = format("%s %s", L["Haste"] or "急速", FormatPercent(GetHastePercent(powerKind)))
    end
    if #parts == 0 then
        return ""
    end
    return table.concat(parts, "  |  ")
end

local function RefreshText(force)
    if not textFS or not active then
        contentWidth = 0
        if host then
            host:Hide()
        end
        NotifyRelayout()
        return
    end
    local text = BuildText()
    if not force and text == lastText then
        return
    end
    lastText = text
    textFS:SetText(text)
    if text == "" then
        contentWidth = 0
        host:Hide()
    else
        contentWidth = (textFS:GetStringWidth() or 0) + TEXT_PAD
        host:SetWidth(math.max(contentWidth, 1))
        host:Show()
    end
    NotifyRelayout()
end

local function FullCorruptionRefresh()
    RescanGearCorruption()
    ReadDynamicCorruption()
    RefreshText(true)
end

local function OnEvent(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end
    if event == "UNIT_INVENTORY_CHANGED" and unit and unit ~= "player" then
        return
    end
    if event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        RefreshPowerKind()
    end
    if event == "UNIT_AURA"
        or event == "UNIT_INVENTORY_CHANGED"
        or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_LOGIN"
    then
        FullCorruptionRefresh()
    else
        RefreshText(true)
    end
end

local function Attach(parent)
    if host then
        host:SetParent(parent)
        return host
    end
    host = CreateFrame("Frame", "ElvUI_Banbi_InfoBarStats", parent)
    host:SetHeight(24)
    host:EnableMouse(false)
    textFS = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    textFS:SetPoint("LEFT", host, "LEFT", 0, 0)
    textFS:SetJustifyH("LEFT")
    eventFrame = CreateFrame("Frame", nil, host)
    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:SetScript("OnUpdate", function(_, elapsed)
        if not active then
            return
        end
        updateElapsed = updateElapsed + elapsed
        if updateElapsed < UPDATE_INTERVAL then
            return
        end
        updateElapsed = 0
        RefreshText(false)
    end)
    return host
end

local function ApplyFont(font, size)
    if textFS then
        textFS:SetFont(font, size, "OUTLINE")
    end
    if active then
        RefreshText(true)
    end
end

local function Enable()
    active = true
    if not eventFrame then
        return
    end
    RefreshPowerKind()
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    eventFrame:RegisterEvent("UNIT_STATS")
    eventFrame:RegisterEvent("UNIT_ATTACK_POWER")
    eventFrame:RegisterEvent("UNIT_RANGED_ATTACK_POWER")
    FullCorruptionRefresh()
end

local function Disable()
    active = false
    lastText = nil
    contentWidth = 0
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if host then
        host:Hide()
    end
    NotifyRelayout()
end

local function BuildOptions(section, C)
    C:AddToggle(section, {
        label = L["Show Corruption Overflow"],
        getFunc = function()
            local cfg = Cfg()
            return not cfg or cfg.showCorruption ~= false
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then
                cfg.showCorruption = val and true or false
            end
            if active then
                RefreshText(true)
            end
        end,
    })
    C:AddToggle(section, {
        label = L["Show Power"],
        getFunc = function()
            local cfg = Cfg()
            return not cfg or cfg.showPower ~= false
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then
                cfg.showPower = val and true or false
            end
            if active then
                RefreshText(true)
            end
        end,
    })
    C:AddToggle(section, {
        label = L["Show Crit"],
        getFunc = function()
            local cfg = Cfg()
            return not cfg or cfg.showCrit ~= false
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then
                cfg.showCrit = val and true or false
            end
            if active then
                RefreshText(true)
            end
        end,
    })
    C:AddToggle(section, {
        label = L["Show Haste"],
        getFunc = function()
            local cfg = Cfg()
            return not cfg or cfg.showHaste ~= false
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then
                cfg.showHaste = val and true or false
            end
            if active then
                RefreshText(true)
            end
        end,
    })
    C:AddSelect(section, {
        label = L["Power Display"],
        values = {
            auto = L["Auto (talents)"] or "Auto",
            melee = L["Melee AP"] or "Melee AP",
            ranged = L["Ranged AP"] or "Ranged AP",
            spell = L["Spell Power"] or "Spell Power",
        },
        getFunc = function()
            local cfg = Cfg()
            return (cfg and cfg.powerMode) or "auto"
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then
                cfg.powerMode = val
            end
            if active then
                RefreshPowerKind()
                RefreshText(true)
            end
        end,
    })
end

addon.InfoBarStats = {
    Attach = Attach,
    Enable = Enable,
    Disable = Disable,
    Refresh = function()
        if active then
            RefreshPowerKind()
            FullCorruptionRefresh()
        end
    end,
    ApplyFont = ApplyFont,
    BuildOptions = BuildOptions,
    GetContentWidth = function()
        return contentWidth or 0
    end,
    HasContent = function()
        return (contentWidth or 0) > 0
    end,
    GetHost = function()
        return host
    end,
}
