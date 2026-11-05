-- ElvUI_Banbi — movable stat bar (corruption overflow, AP/SP, crit, haste).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "statBar"
local DYNAMIC_CORRUPTION_SPELL = 94005
local CORRUPTION_PATTERN = "%+(%d+)%s*腐蚀"
local RESIST_PATTERN = "%+(%d+)%s*腐蚀抗性"
local UPDATE_INTERVAL = 0.2

local format = string.format
local match = string.match
local gsub = string.gsub
local tonumber = tonumber
local floor = math.floor

local active = false
local frame
local scanTip
local gearCorruption, resistCorruption, dynamicCorruption = 0, 0, 0
local powerKind = "melee" -- melee | ranged | spell
local updateElapsed = 0
local lastText

local INV_SLOTS = {
    -- include shirt(4) and tabard(19): private-server resist/corruption often live there
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

-- Dual-spec classes: tab index → kind (1/2/3).
local CLASS_TAB_KIND = {
    DRUID = { "spell", "melee", "spell" }, -- Balance, Feral, Resto
    SHAMAN = { "spell", "melee", "spell" }, -- Elemental, Enhance, Resto
    PALADIN = { "spell", "melee", "melee" }, -- Holy, Prot, Ret
}

local function Cfg()
    return addon:GetFeatureConfig(KEY)
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

local function NormTex()
    local E = addon:GetE()
    if E and E.media and E.media.normTex then
        return E.media.normTex
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function PersistPosition()
    if not frame then
        return
    end
    local cfg = Cfg()
    if not cfg then
        return
    end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then
        return
    end
    local pLeft, pTop = UIParent:GetLeft() or 0, UIParent:GetTop() or 0
    cfg.anchor = "TOPLEFT"
    cfg.posX = left - pLeft
    cfg.posY = top - pTop
end

local function ApplyPosition()
    if not frame then
        return
    end
    local cfg = Cfg()
    frame:ClearAllPoints()
    frame:SetPoint(
        "TOPLEFT",
        UIParent,
        "TOPLEFT",
        (cfg and cfg.posX) or 20,
        (cfg and cfg.posY) or -40
    )
end

local function ApplyChrome()
    if not frame then
        return
    end
    local tex = NormTex()
    frame:SetBackdrop({
        bgFile = tex,
        edgeFile = tex,
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.55)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
end

local function ApplyFont()
    if not frame or not frame.text then
        return
    end
    local cfg = Cfg()
    local size = (cfg and cfg.fontSize) or 12
    if size < 8 then
        size = 8
    end
    if size > 24 then
        size = 24
    end
    local E = addon:GetE()
    local font = (E and E.media and E.media.normFont) or STANDARD_TEXT_FONT
    frame.text:SetFont(font, size, "OUTLINE")
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
    if not frame or not active then
        if frame then
            frame:Hide()
        end
        return
    end
    local text = BuildText()
    if not force and text == lastText then
        return
    end
    lastText = text
    frame.text:SetText(text)
    local w = (frame.text:GetStringWidth() or 40) + 16
    frame:SetWidth(math.max(w, 40))
    frame:Show()
end

local function FullCorruptionRefresh()
    RescanGearCorruption()
    ReadDynamicCorruption()
    RefreshText(true)
end

local function EnsureFrame()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "ElvUI_Banbi_StatBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetHeight(24)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PersistPosition()
    end)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("LEFT", frame, "LEFT", 8, 0)
    frame.text:SetJustifyH("LEFT")
    ApplyChrome()
    ApplyPosition()
    ApplyFont()
    frame:SetScript("OnUpdate", function(self, elapsed)
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
    frame:SetScript("OnEvent", function(self, event, unit)
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
    end)
    return frame
end

local function OnEnable()
    active = true
    EnsureFrame()
    ApplyChrome()
    ApplyPosition()
    ApplyFont()
    RefreshPowerKind()
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("COMBAT_RATING_UPDATE")
    frame:RegisterEvent("UNIT_STATS")
    frame:RegisterEvent("UNIT_ATTACK_POWER")
    frame:RegisterEvent("UNIT_RANGED_ATTACK_POWER")
    FullCorruptionRefresh()
end

local function OnDisable()
    active = false
    lastText = nil
    if frame then
        frame:UnregisterAllEvents()
        frame:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function()
        return L["Stat Bar"]
    end,
    desc = function()
        return L["Show corruption overflow, attack/spell power, crit, and haste on a movable bar."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = function()
        if not active then
            return
        end
        ApplyChrome()
        ApplyPosition()
        ApplyFont()
        RefreshPowerKind()
        FullCorruptionRefresh()
    end,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Drag the bar to move it."] or "Drag the bar to move it.")
        C:AddSlider(section, {
            label = L["Font Size"],
            min = 8,
            max = 24,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and cfg.fontSize) or 12
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.fontSize = val
                end
                if active then
                    ApplyFont()
                    RefreshText(true)
                end
            end,
        })
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
    end,
})
