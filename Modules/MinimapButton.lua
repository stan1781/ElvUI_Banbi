-- ElvUI_Banbi — minimap button to open Banbi options.

local ADDON_NAME, addon = ...
local L = addon.L

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local Minimap = Minimap
local GameTooltip = GameTooltip
local cos, sin, abs, max = math.cos, math.sin, math.abs, math.max
local deg, rad, atan2 = math.deg, math.rad, math.atan2

local button
local ICON = "Interface\\AddOns\\ElvUI\\Media\\ChatLogos\\ElvBlue.tga"
local DEFAULT_ANGLE = 225

local function Cfg()
    if not addon.db or not addon.db.global then
        return nil
    end
    local cfg = addon.db.global.minimapButton
    if type(cfg) ~= "table" then
        cfg = { hide = false, angle = DEFAULT_ANGLE }
        addon.db.global.minimapButton = cfg
    end
    if type(cfg.angle) ~= "number" then
        cfg.angle = DEFAULT_ANGLE
    end
    return cfg
end

function addon:IsMinimapButtonShown()
    local cfg = Cfg()
    return not cfg or cfg.hide ~= true
end

local function UpdatePosition()
    if not button or not Minimap then
        return
    end
    local cfg = Cfg()
    local angle = rad((cfg and cfg.angle) or DEFAULT_ANGLE)
    local x, y = cos(angle), sin(angle)
    local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    if shape ~= "ROUND" then
        local d = max(abs(x), abs(y))
        if d > 0 then
            x, y = x / d, y / d
        end
    end
    -- Sit just outside the ElvUI minimap backdrop.
    local w = (Minimap:GetWidth() / 2) + 6
    local h = (Minimap:GetHeight() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function UpdateVisibility()
    if not button then
        return
    end
    if addon:IsMinimapButtonShown() then
        button:Show()
        UpdatePosition()
    else
        button:Hide()
    end
end

local function AngleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx or not my then
        return DEFAULT_ANGLE
    end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return deg(atan2(cy - my * scale, cx - mx * scale))
end

local function CreateButton()
    if button or not Minimap then
        return button
    end

    local btn = CreateFrame("Button", "ElvUI_BanbiMinimapButton", Minimap)
    btn:SetWidth(22)
    btn:SetHeight(22)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    if btn.SetTemplate then
        btn:SetTemplate("Default", true)
    else
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
        btn:SetBackdropBorderColor(23 / 255, 132 / 255, 209 / 255, 1)
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.icon = icon

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff1784d1" .. (L["Banbi"] or "Banbi") .. "|r")
        GameTooltip:AddLine(L["Minimap button tip line1"] or "左键：打开设置", 1, 1, 1)
        GameTooltip:AddLine(L["Minimap button tip line2"] or "拖动：调整位置", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnDragStart", function(self)
        self.dragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local cfg = Cfg()
            if cfg then
                cfg.angle = AngleFromCursor()
            end
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdatePosition()
    end)
    btn:SetScript("OnClick", function(self)
        if self.dragging then
            self.dragging = nil
            return
        end
        if addon.OpenOptions then
            addon:OpenOptions()
        end
    end)

    button = btn
    return btn
end

function addon:EnsureMinimapButton()
    if not Minimap then
        return
    end
    CreateButton()
    UpdateVisibility()
end

function addon:SetMinimapButtonShown(shown)
    local cfg = Cfg()
    if cfg then
        cfg.hide = not shown
    end
    if not button then
        addon:EnsureMinimapButton()
    else
        UpdateVisibility()
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    addon:EnsureMinimapButton()
end)
