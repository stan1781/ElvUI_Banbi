-- ElvUI_Banbi — MotionSpeed (ported from MotionSpeed / DragonUI_Enhanced).

local ADDON_NAME, addon = ...
local L = addon.L

local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetUnitSpeed = GetUnitSpeed
local format = format
local TOOLTIP_UPDATE_TIME = TOOLTIP_UPDATE_TIME

local FORMAT_PERCENT_PLAYER = format("%s %%d%%%%", PLAYER)
local FORMAT_PERCENT_PLAYERTARGET = format("%s %%d%%%%, %s %%d%%%%", PLAYER, TARGET)

local KEY = "motionSpeed"
local frame
local lastPlayerSpeed, lastTargetSpeed, hasTarget
local playerUnit = "player"
local updateElapsed = 0
local moverRegistered = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function NormalizeSpeed(speed)
    return speed * 100 / 7 + 0.5
end

local function PersistPosition()
    if not frame then return end
    local cfg = Cfg()
    if not cfg then return end
    local point, _, _, x, y = frame:GetPoint(1)
    cfg.anchor = point or "CENTER"
    cfg.posX = x or 0
    cfg.posY = y or 0
end

local function ApplyPosition()
    if not frame then return end
    local cfg = Cfg()
    frame:ClearAllPoints()
    frame:SetPoint(
        cfg.anchor or "CENTER",
        UIParent,
        cfg.anchor or "CENTER",
        cfg.posX or 0,
        cfg.posY or 120
    )
end

local function ApplyStyle()
    if not frame then return end
    local cfg = Cfg()
    local size = cfg.fontSize or 11
    if size < 8 then size = 8 end
    if size > 24 then size = 24 end
    local E = addon:GetE()
    local font = (E and E.media and E.media.normFont) or STANDARD_TEXT_FONT
    frame.text:SetFont(font, size, "OUTLINE")
end

local function EnsureFrame()
    if frame then
        return frame
    end

    frame = CreateFrame("Button", "ElvUI_Banbi_MotionSpeed", UIParent)
    frame:SetWidth(16)
    frame:SetHeight(16)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PersistPosition()
    end)

    frame.icon = frame:CreateTexture("$parentIcon", "ARTWORK")
    frame.icon:SetAllPoints(frame)
    frame.icon:SetTexture(addon.media.icons.dash)

    frame.text = frame:CreateFontString("$parentText", "ARTWORK", "GameFontHighlightLeft")
    frame.text:SetPoint("LEFT", frame, "RIGHT", 2, 0)

    frame:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    frame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    frame:RegisterEvent("UNIT_EXITED_VEHICLE")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            hasTarget = UnitExists("target")
                and not UnitIsUnit("player", "target")
                and not UnitIsUnit("vehicle", "target")
        elseif unit == "player" then
            if event == "UNIT_ENTERED_VEHICLE" then
                playerUnit = "vehicle"
            elseif event == "UNIT_EXITED_VEHICLE" then
                playerUnit = "player"
            end
        end
    end)

    ApplyPosition()
    ApplyStyle()
    return frame
end

local function OnUpdate(self, elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed <= TOOLTIP_UPDATE_TIME then
        return
    end
    updateElapsed = 0
    local playerSpeed = GetUnitSpeed(playerUnit)
    local targetSpeed = hasTarget and GetUnitSpeed("target") or nil
    if lastPlayerSpeed == playerSpeed and lastTargetSpeed == targetSpeed then
        return
    end
    lastPlayerSpeed, lastTargetSpeed = playerSpeed, targetSpeed
    if targetSpeed then
        self.text:SetText(format(FORMAT_PERCENT_PLAYERTARGET, NormalizeSpeed(playerSpeed), NormalizeSpeed(targetSpeed)))
    else
        self.text:SetText(format(FORMAT_PERCENT_PLAYER, NormalizeSpeed(playerSpeed)))
    end
end

local function RegisterMover()
    if moverRegistered then return end
    local E = addon:GetE()
    if not (E and E.CreateMover) then return end
    E:CreateMover(frame, "BanbiMotionSpeedMover", L["Motion Speed"] or "Motion Speed", nil, nil, function()
        PersistPosition()
    end)
    moverRegistered = true
end

local function OnEnable()
    EnsureFrame()
    RegisterMover()
    ApplyPosition()
    ApplyStyle()
    hasTarget = UnitExists("target")
        and not UnitIsUnit("player", "target")
        and not UnitIsUnit("vehicle", "target")
    lastPlayerSpeed, lastTargetSpeed = nil, nil
    updateElapsed = 0
    frame:Show()
    frame:SetScript("OnUpdate", OnUpdate)
end

local function OnDisable()
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function() return L["Motion Speed"] end,
    desc = function() return L["Show player (and target) movement speed as a percentage."] end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Drag the text to move it."] or "Drag the text to move it.")
        C:AddSlider(section, {
            label = L["Font Size"],
            min = 8,
            max = 24,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and cfg.fontSize) or 11
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then cfg.fontSize = val end
                if addon:IsFeatureEnabled(KEY) then
                    ApplyStyle()
                end
            end,
        })
    end,
    Refresh = function()
        if addon:IsFeatureEnabled(KEY) then
            ApplyPosition()
            ApplyStyle()
        end
    end,
})
