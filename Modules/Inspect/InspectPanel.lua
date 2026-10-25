-- ElvUI_Banbi — Character / Inspect equipment list (from TinyInspect Core).
-- Gem/enchant icons via inspect_gem*.lua on the shared addon table.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "inspectPanel"
local WIN = _G.ElvUI_Banbi_InfoWindow
local PORTRAIT = "Interface\\AddOns\\ElvUI_Banbi\\Textures\\InspectPortrait"

local slots = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

local active = false
local hookedInspectChanged = false
local autoHidden = false
local origInspectUnit
local cached = false
local cacheItems
local curUnit, curUnitName, curUser
local pendingInspectUnit
local inspectTimer
local eventFrame

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function After(delay, fn)
    if addon.core and addon.core.ScheduleTimer then
        return addon.core:ScheduleTimer(fn, delay)
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
    return f
end

local function CancelTimer(handle)
    if not handle then return end
    if type(handle) == "table" and handle.SetScript then
        handle:SetScript("OnUpdate", nil)
    elseif addon.core and addon.core.CancelTimer then
        addon.core:CancelTimer(handle, true)
    end
end

-- 与 Defaults.lua inspectPanel 调试默认值保持一致。
local DEFAULT_CHAR_OFFSET_X = 0
local DEFAULT_INSPECT_OFFSET_X = -30
local DEFAULT_OFFSET_Y = 0

local function GetOffsets(parent)
    local cfg = Cfg()
    local y = (cfg and cfg.offsetY)
    if type(y) ~= "number" then y = DEFAULT_OFFSET_Y end

    local isChar = parent == CharacterFrame
        or (parent and parent.GetName and parent:GetName() == "CharacterFrame")
    local x
    if isChar then
        x = cfg and cfg.charOffsetX
        if type(x) ~= "number" then
            -- 兼容旧单一 offsetX：角色窗不再用负值（会叠在属性上）
            x = (cfg and type(cfg.offsetX) == "number" and cfg.offsetX >= 0) and cfg.offsetX or DEFAULT_CHAR_OFFSET_X
        end
    else
        x = cfg and cfg.inspectOffsetX
        if type(x) ~= "number" then
            x = (cfg and type(cfg.offsetX) == "number") and cfg.offsetX or DEFAULT_INSPECT_OFFSET_X
        end
    end
    return x, y
end

local function SetPanelParent(frame)
    if not WIN or not frame then return end
    local ox, oy = GetOffsets(frame)
    WIN:SetParent(frame)
    WIN:ClearAllPoints()
    WIN:SetPoint("TOPLEFT", frame, "TOPRIGHT", ox, oy)
end

local function ReanchorIfShown()
    if not WIN or not WIN:IsShown() then return end
    local parent = WIN:GetParent()
    if parent and parent ~= UIParent then
        SetPanelParent(parent)
    end
end

local function FullUnitName(name, realm)
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function GetTalentString(isInspecting, id)
    local talentString, talentIcon, maxPts = "", nil, 0
    for v = 1, 3 do
        local _, icon, num = GetTalentTabInfo(v, isInspecting, false, id)
        if num > maxPts then
            maxPts = num
            talentIcon = icon
        end
        if #talentString > 0 then talentString = talentString .. "/" end
        talentString = talentString .. num
    end
    return talentIcon, talentString
end

-- DragonUI palette on TinyInspect layout (no ForeverUI Content padding).
local GOLD = { 1, 0.82, 0 }
local PANEL = { 0.1216, 0.1176, 0.1294, 0.93 }
local CYAN = { 0, 0.9, 0.9 } -- TinyInspect default label tint (overridden by quality)
local MIN_WIDTH = 350
local FRAME_H = 450

local function ApplyChrome(frame)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], PANEL[4] or 0.93)
    frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.85)
    return frame
end

local function Line_OnEnter(row)
    if not row.link then return end
    GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT")
    if (not cached) and curUnit and UnitName(curUnit) == curUnitName then
        local slotName = slots[row.index]
        if slotName then
            row.link = GetInventoryItemLink(curUnit, GetInventorySlotInfo(slotName)) or row.link
        end
    end
    GameTooltip:SetHyperlink(row.link)
    GameTooltip:Show()
end

local function Line_OnLeave()
    GameTooltip:Hide()
end

-- Layout mirrors ElvUI_TinyInspect Core.lua InspectFrameInitialize.
local function EnsureFrameReady(frame)
    if frame.ready then
        frame.talentIcon:SetTexture()
        frame.talentString:SetText("")
        return frame
    end

    ApplyChrome(frame)
    frame:SetHeight(FRAME_H)

    local font = STANDARD_TEXT_FONT
    local fontsize = 13

    frame.unitFrame = frame:CreateTexture(nil, "BORDER")
    frame.unitFrame:SetSize(64, 64)
    frame.unitFrame:SetPoint("TOPLEFT", 15, -15)
    frame.unitFrame:SetTexture(PORTRAIT)

    frame.unitPortrait = frame:CreateTexture(nil, "ARTWORK")
    frame.unitPortrait:SetSize(40, 35)
    frame.unitPortrait:SetPoint("TOP", frame.unitFrame, "TOP", -1, -7)
    frame.unitPortrait:SetTexCoord(0, 1, 0, 0.875)

    frame.unitLevel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.unitLevel:SetPoint("BOTTOM", frame.unitFrame, "BOTTOM", 0, 7)
    frame.unitLevel:SetJustifyH("CENTER")
    frame.unitLevel:SetFont(font, 12, "OUTLINE")
    frame.unitLevel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    frame.title = frame:CreateFontString(nil, "ARTWORK")
    frame.title:SetPoint("LEFT", frame.unitFrame, "RIGHT", 0, 10)
    frame.title:SetFont(font, 20, "OUTLINE")

    frame.avglevel = frame:CreateFontString(nil, "ARTWORK")
    frame.avglevel:SetPoint("LEFT", frame.unitFrame, "RIGHT", 0, -15)
    frame.avglevel:SetFont(font, 12, "OUTLINE")
    frame.avglevel:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    frame.talentIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.talentIcon:SetSize(50, 50)
    frame.talentIcon:SetPoint("RIGHT", frame, "TOPRIGHT", -40, -40)
    frame.talentIcon:SetAlpha(0.9)
    frame.talentString = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.talentString:SetSize(50, 15)
    frame.talentString:SetPoint("TOP", frame.talentIcon, "BOTTOM")
    frame.talentString:SetFont(font, 10, "OUTLINE")
    frame.talentString:SetJustifyH("CENTER")
    frame.talentString:SetTextColor(1, 1, 1)

    local labelBackdrop = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    }
    local rowH = (440 - 85) / #slots
    for i, slotName in ipairs(slots) do
        local itemframe = CreateFrame("Button", nil, frame)
        itemframe:SetSize(120, rowH)
        itemframe.index = i
        if i == 1 then
            itemframe:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -85)
        else
            itemframe:SetPoint("TOPLEFT", frame["item" .. (i - 1)], "BOTTOMLEFT")
        end
        itemframe.label = CreateFrame("Frame", nil, itemframe)
        itemframe.label:SetSize(38, 18)
        itemframe.label:SetPoint("LEFT")
        if itemframe.label.SetBackdrop then
            itemframe.label:SetBackdrop(labelBackdrop)
            itemframe.label:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], 0.85)
            itemframe.label:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.45)
        end
        itemframe.label.text = itemframe.label:CreateFontString(nil, "ARTWORK")
        itemframe.label.text:SetFont(UNIT_NAME_FONT or font, fontsize, "THINOUTLINE")
        itemframe.label.text:SetSize(36, 14)
        itemframe.label.text:SetPoint("CENTER", 1, 0)
        itemframe.label.text:SetText(L[slotName] or slotName)
        itemframe.label.text:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        itemframe.levelString = itemframe:CreateFontString(nil, "ARTWORK")
        itemframe.levelString:SetPoint("LEFT", itemframe.label, "RIGHT", 4, 0)
        itemframe.levelString:SetJustifyH("RIGHT")
        itemframe.levelString:SetFont(NAMEPLATE_FONT or font, fontsize, "NONE")
        itemframe.levelString:SetWidth(26)
        itemframe.itemString = itemframe:CreateFontString(nil, "ARTWORK")
        itemframe.itemString:SetFont(NAMEPLATE_FONT or font, fontsize, "NONE")
        itemframe.itemString:SetHeight(16)
        itemframe.itemString:SetPoint("LEFT", itemframe.levelString, "RIGHT", 2, 0)
        itemframe:SetScript("OnEnter", Line_OnEnter)
        itemframe:SetScript("OnLeave", Line_OnLeave)
        frame["item" .. i] = itemframe
    end
    frame.ready = true
    return frame
end

local function InspectItem(frame, unit, index)
    local level
    local width = MIN_WIDTH
    local getItem
    if cached then
        getItem = function(slot)
            local istr = cacheItems and cacheItems[slot]
            if istr then
                local itemId = tonumber(istr:match("item:(%d+)"))
                return select(2, GetItemInfo(istr)) or ("[" .. tostring(itemId) .. "]")
            end
            return nil
        end
    else
        getItem = function(slot)
            return GetInventoryItemLink(unit, GetInventorySlotInfo(slot))
        end
    end

    local slotName = slots[index]
    local itemLink = getItem and getItem(slotName)
    local itemFrame = frame["item" .. index]
    if not itemFrame then return nil, width end

    if itemLink then
        local itemName, infoLink, itemQuality, itemLevelValue = GetItemInfo(itemLink)
        if infoLink and infoLink ~= "" then itemLink = infoLink end
        itemFrame.link = itemLink
        local r, g, b = CYAN[1], CYAN[2], CYAN[3]
        if itemQuality then
            r, g, b = GetItemQualityColor(itemQuality)
        end
        itemFrame.label.text:SetTextColor(r, g, b)
        if itemFrame.label.SetBackdropBorderColor then
            itemFrame.label:SetBackdropBorderColor(r, g, b, 0.55)
        end
        if itemLevelValue and itemLevelValue > 0 then
            level = itemLevelValue
            itemFrame.levelString:SetText(format("%s", itemLevelValue))
            itemFrame.levelString:SetTextColor(r, g, b)
        else
            itemFrame.levelString:SetText("")
        end
        itemFrame.itemString:SetText(itemLink or (itemName or ""))
        width = 110 + itemFrame.itemString:GetWidth()

        -- gems/enchants only — no 出处 / lootString
        if addon.ShowGemAndEnchant then
            local gaeWidth = addon:ShowGemAndEnchant(frame, itemLink, itemFrame.itemString, index) or 0
            if gaeWidth > 0 then
                width = width + gaeWidth
            end
        end
        itemFrame:SetAlpha(1)
    else
        itemFrame.link = nil
        itemFrame.label.text:SetTextColor(CYAN[1], CYAN[2], CYAN[3])
        if itemFrame.label.SetBackdropBorderColor then
            itemFrame.label:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
        end
        itemFrame.levelString:SetText("")
        itemFrame.itemString:SetText("")
        itemFrame:SetAlpha(0.5)
    end
    return level, width
end

local function Inspect(unit, entry)
    if not WIN or not active then return end
    cached = (unit == "cache")
    if cached and not entry then
        WIN:Hide()
        return
    end

    cacheItems = cached and entry.Items or nil
    local unitName, unitRealm
    if cached then
        unitName, unitRealm = entry.name, entry.realm
    else
        if not unit or not UnitExists(unit) then
            unit = "player"
        end
        unitName, unitRealm = UnitName(unit)
        if not CanInspect(unit) and _G.Examiner_Cache then
            entry = _G.Examiner_Cache[FullUnitName(unitName, unitRealm)]
            if entry then
                cached = true
                cacheItems = entry.Items
            end
        end
    end
    if unitRealm == "" then unitRealm = nil end
    curUnit = unit
    curUnitName = unitName
    curUser = FullUnitName(unitName, unitRealm)

    local frame = EnsureFrameReady(WIN)
    local class = select(2, UnitClass(unit))
    local color = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
    SetPortraitTexture(frame.unitPortrait, unit)
    frame.unitLevel:SetText(UnitLevel(unit) or "")
    if frame.title then
        frame.title:SetText(curUser or "")
        frame.title:SetTextColor(color.r, color.g, color.b)
    end

    local isInspecting = (unit ~= "player")
    local activeTalent = GetActiveTalentGroup(isInspecting, false)
    if activeTalent and activeTalent > 0 then
        local talentIcon, talentString = GetTalentString(isInspecting, activeTalent)
        if talentIcon then
            frame.talentIcon:SetTexture(talentIcon)
            frame.talentIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            frame.talentIcon:SetTexture([[Interface\Icons\Ability_Marksmanship]])
            frame.talentIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if talentString then
            frame.talentString:SetText(talentString)
        end
    end

    local lvlSum, itemNum, maxWidth = 0, 0, 0
    if addon.HideAllIconFrame then
        addon:HideAllIconFrame(frame)
    end
    for i = 1, #slots do
        local lvl, width = InspectItem(frame, unit, i)
        if lvl then
            lvlSum = lvlSum + lvl
            itemNum = itemNum + 1
        end
        if width > maxWidth then maxWidth = width end
    end
    if itemNum > 0 then
        frame.avglevel:SetText((L["Avg. Item Level"] or "平均装等") .. " " .. string.format("%.2f", lvlSum / itemNum))
    else
        frame.avglevel:SetText("")
    end
    frame:SetWidth(math.max(maxWidth, MIN_WIDTH))

    if WIN:GetParent() == CharacterFrame
        and ((GearManagerDialog and GearManagerDialog:IsVisible())
            or (OutfitterFrame and OutfitterFrame:IsVisible())) then
        autoHidden = true
    else
        WIN:Show()
    end
end

local function TryInspectUnit(unit)
    local cfg = Cfg()
    if not cfg.inspectWindow then return end
    SetPanelParent(_G.Examiner or InspectFrame)
    WIN:Hide()
    CancelTimer(inspectTimer)
    inspectTimer = nil
    pendingInspectUnit = unit
    inspectTimer = After(0.1, function()
        inspectTimer = nil
        if not pendingInspectUnit or not UnitExists(pendingInspectUnit) then
            pendingInspectUnit = nil
            return
        end
        local hasData = false
        for i = 1, #slots do
            local slotId = GetInventorySlotInfo(slots[i])
            if slotId and GetInventoryItemLink(pendingInspectUnit, slotId) then
                hasData = true
                break
            end
        end
        if hasData or not CanInspect(pendingInspectUnit) then
            Inspect(pendingInspectUnit)
            pendingInspectUnit = nil
        else
            inspectTimer = After(0.2, function()
                inspectTimer = nil
                if pendingInspectUnit and UnitExists(pendingInspectUnit) then
                    Inspect(pendingInspectUnit)
                end
                pendingInspectUnit = nil
            end)
        end
    end)
end

local function WrappedInspectUnit(unit, ...)
    if origInspectUnit then
        origInspectUnit(unit, ...)
    end
    if active then
        TryInspectUnit(unit)
    end
end

local function OnInspectFrameUnitChanged()
    if not active then return end
    if InspectFrame and InspectFrame.unit and Cfg().inspectWindow then
        TryInspectUnit(InspectFrame.unit)
    elseif WIN then
        WIN:Hide()
    end
end

local function PaperDoll_OnShow()
    if not active or not Cfg().charWindow then return end
    SetPanelParent(CharacterFrame)
    Inspect("player")
end

local function PaperDoll_OnHide()
    if WIN and WIN:GetParent() == CharacterFrame then
        WIN:Hide()
        autoHidden = false
    end
end

local function GearManager_OnShow()
    if WIN and WIN:GetParent() == CharacterFrame and WIN:IsShown() then
        autoHidden = true
        WIN:Hide()
    end
end

local function GearManager_OnHide()
    if autoHidden and WIN and WIN:GetParent() == CharacterFrame and PaperDollFrame:IsVisible() then
        autoHidden = false
        if Cfg().charWindow then
            Inspect("player")
        end
    end
end

local function OnInventoryChanged(_, unit)
    if not active or not WIN then return end
    if unit == "player" and (WIN:IsVisible() or autoHidden) and WIN:GetParent() == CharacterFrame then
        Inspect("player")
    elseif pendingInspectUnit and unit == pendingInspectUnit and WIN:GetParent() ~= CharacterFrame then
        CancelTimer(inspectTimer)
        inspectTimer = nil
        Inspect(pendingInspectUnit)
        pendingInspectUnit = nil
    elseif InspectFrame and InspectFrame.unit and unit == InspectFrame.unit and Cfg().inspectWindow then
        if WIN:IsVisible() and WIN:GetParent() ~= CharacterFrame then
            Inspect(unit)
        end
    end
end

local function Migrate()
    if not addon.db or not addon.db.global then return end
    local g = addon.db.global
    g.migrated = g.migrated or {}
    if g.migrated.tinyInspectPanel then return end
    g.migrated.tinyInspectPanel = true
    local old = _G.TinyInspectConfig
    local cfg = Cfg()
    if type(old) ~= "table" or not cfg then return end
    if old.inspectWindow ~= nil then cfg.inspectWindow = old.inspectWindow and true or false end
    if old.charWindow ~= nil then cfg.charWindow = old.charWindow and true or false end
end

local function OnEnable()
    if not WIN then
        WIN = _G.ElvUI_Banbi_InfoWindow
    end
    if not WIN then return end
    Migrate()
    active = true
    WIN:Hide()
    ApplyChrome(WIN)

    if not origInspectUnit then
        origInspectUnit = _G.InspectUnit
        _G.InspectUnit = WrappedInspectUnit
    end

    if PaperDollFrame and not PaperDollFrame._banbiInspectHooked then
        PaperDollFrame:HookScript("OnShow", PaperDoll_OnShow)
        PaperDollFrame:HookScript("OnHide", PaperDoll_OnHide)
        PaperDollFrame._banbiInspectHooked = true
    end
    if GearManagerDialog and not GearManagerDialog._banbiInspectHooked then
        GearManagerDialog:HookScript("OnShow", GearManager_OnShow)
        GearManagerDialog:HookScript("OnHide", GearManager_OnHide)
        GearManagerDialog._banbiInspectHooked = true
    end
    if not hookedInspectChanged and _G.InspectFrame_UnitChanged then
        hooksecurefunc("InspectFrame_UnitChanged", OnInspectFrameUnitChanged)
        hookedInspectChanged = true
    end

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_INVENTORY_CHANGED" then
                OnInventoryChanged(_, ...)
            elseif event == "ADDON_LOADED" then
                local name = ...
                if name == "Blizzard_InspectUI" and not hookedInspectChanged and _G.InspectFrame_UnitChanged then
                    hooksecurefunc("InspectFrame_UnitChanged", OnInspectFrameUnitChanged)
                    hookedInspectChanged = true
                end
            end
        end)
    end
    eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    eventFrame:RegisterEvent("ADDON_LOADED")

    if PaperDollFrame and PaperDollFrame:IsVisible() and Cfg().charWindow then
        PaperDoll_OnShow()
    end
end

local function OnDisable()
    active = false
    CancelTimer(inspectTimer)
    inspectTimer = nil
    pendingInspectUnit = nil
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if origInspectUnit and _G.InspectUnit == WrappedInspectUnit then
        _G.InspectUnit = origInspectUnit
        origInspectUnit = nil
    end
    if WIN then
        WIN:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "equipment",
    default = true,
    requiresReload = true,
    label = function() return L["Equipment List Panel"] end,
    desc = function()
        return L["Gear list beside Character and Inspect windows, with gems/enchants."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Panel attaches to the right of Character/Inspect. Disable the old standalone equipment-list addon to avoid two panels."])
        C:AddToggle(section, {
            label = L["Character equipment list"],
            desc = L["Show the list when opening the character window."],
            getFunc = function() return Cfg().charWindow ~= false end,
            setFunc = function(val)
                Cfg().charWindow = val and true or false
                if val and PaperDollFrame and PaperDollFrame:IsVisible() then
                    PaperDoll_OnShow()
                elseif not val and WIN and WIN:GetParent() == CharacterFrame then
                    WIN:Hide()
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Inspect equipment list"],
            desc = L["Show the list when inspecting other players."],
            getFunc = function() return Cfg().inspectWindow ~= false end,
            setFunc = function(val)
                Cfg().inspectWindow = val and true or false
            end,
        })
        C:AddSlider(section, {
            label = L["Character horizontal offset"],
            desc = L["Horizontal offset for the character window list. Positive moves it away."],
            min = -80,
            max = 80,
            step = 1,
            getFunc = function()
                local v = Cfg().charOffsetX
                return type(v) == "number" and v or DEFAULT_CHAR_OFFSET_X
            end,
            setFunc = function(val)
                Cfg().charOffsetX = val
                ReanchorIfShown()
            end,
        })
        C:AddSlider(section, {
            label = L["Inspect horizontal offset"],
            desc = L["Horizontal offset for the inspect window list. Negative moves it closer."],
            min = -80,
            max = 80,
            step = 1,
            getFunc = function()
                local v = Cfg().inspectOffsetX
                return type(v) == "number" and v or DEFAULT_INSPECT_OFFSET_X
            end,
            setFunc = function(val)
                Cfg().inspectOffsetX = val
                ReanchorIfShown()
            end,
        })
        C:AddSlider(section, {
            label = L["Vertical offset"],
            desc = L["Positive moves the list up relative to the Character/Inspect top edge."],
            min = -80,
            max = 80,
            step = 1,
            getFunc = function()
                local v = Cfg().offsetY
                return type(v) == "number" and v or DEFAULT_OFFSET_Y
            end,
            setFunc = function(val)
                Cfg().offsetY = val
                ReanchorIfShown()
            end,
        })
    end,
})

addon.InspectPanel = {
    Inspect = Inspect,
    Refresh = function()
        if active and WIN and WIN:IsVisible() and curUnit then
            Inspect(curUnit)
        end
    end,
}
