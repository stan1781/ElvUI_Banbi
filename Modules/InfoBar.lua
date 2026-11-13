-- ElvUI_Banbi — combined info bar shell (tokens left + stats right).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "infoBar"
local SECTION_GAP = 10
local PAD_X = 6
local PAD_Y = 4

local frame
local active = false
local isMoving = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function NormTex()
    local E = addon:GetE()
    if E and E.media and E.media.normTex then
        return E.media.normTex
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function FontPath()
    local E = addon:GetE()
    return (E and E.media and E.media.normFont) or STANDARD_TEXT_FONT
end

local function FontSize()
    local cfg = Cfg()
    local size = (cfg and tonumber(cfg.fontSize)) or 12
    if size < 8 then
        size = 8
    elseif size > 24 then
        size = 24
    end
    return size
end

local function PersistPosition()
    if not frame then
        return
    end
    local cfg = Cfg()
    if not cfg then
        return
    end
    local left = frame:GetLeft()
    local top = frame:GetTop()
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
        (cfg and cfg.posY) or -8
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
    local font = FontPath()
    local size = FontSize()
    if addon.InfoBarTokens and addon.InfoBarTokens.ApplyFont then
        addon.InfoBarTokens.ApplyFont(font, size)
    end
    if addon.InfoBarStats and addon.InfoBarStats.ApplyFont then
        addon.InfoBarStats.ApplyFont(font, size)
    end
end

local function Relayout()
    if not frame or not active then
        if frame then
            frame:Hide()
        end
        return
    end

    local tokens = addon.InfoBarTokens
    local stats = addon.InfoBarStats
    local tw = (tokens and tokens.GetContentWidth and tokens.GetContentWidth()) or 0
    local sw = (stats and stats.GetContentWidth and stats.GetContentWidth()) or 0
    local hasT = tw > 0
    local hasS = sw > 0

    if not hasT and not hasS then
        frame:Hide()
        return
    end

    local iconH = (tokens and tokens.GetIconSize and tokens.GetIconSize()) or 20
    local height = math.max(iconH, 24) + PAD_Y * 2
    frame:SetHeight(height)

    local tokenHost = _G.ElvUI_Banbi_InfoBarTokens
    local statHost = stats and stats.GetHost and stats.GetHost()
    local x = PAD_X
    if hasT then
        if tokenHost then
            tokenHost:ClearAllPoints()
            tokenHost:SetPoint("LEFT", frame, "LEFT", x, 0)
            tokenHost:Show()
        end
        x = x + tw
        if hasS then
            x = x + SECTION_GAP
        end
    elseif tokenHost then
        tokenHost:Hide()
    end

    if hasS then
        if statHost then
            statHost:ClearAllPoints()
            statHost:SetPoint("LEFT", frame, "LEFT", x, 0)
            statHost:Show()
        end
        x = x + sw
    elseif statHost then
        statHost:Hide()
    end

    frame:SetWidth(math.max(x + PAD_X, 40))
    frame:Show()
end

local function StartDrag()
    if not IsShiftKeyDown() then
        return
    end
    if not frame or not frame:IsMovable() then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    isMoving = true
    frame:StartMoving()
end

local function StopDrag()
    if not frame or not isMoving then
        return
    end
    isMoving = nil
    frame:StopMovingOrSizing()
    PersistPosition()
end

local function EnsureFrame()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "ElvUI_Banbi_InfoBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetHeight(28)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            StartDrag()
        end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            StopDrag()
        end
    end)
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
    ApplyChrome()
    ApplyPosition()

    if addon.InfoBarTokens then
        addon.InfoBarTokens.Attach(frame)
    end
    if addon.InfoBarStats then
        addon.InfoBarStats.Attach(frame)
    end
    return frame
end

local function OnEnable()
    active = true
    EnsureFrame()
    ApplyChrome()
    ApplyPosition()
    if addon.InfoBarTokens then
        addon.InfoBarTokens.Enable()
    end
    if addon.InfoBarStats then
        addon.InfoBarStats.Enable()
    end
    -- Font after Enable so newly created token buttons pick up the size.
    ApplyFont()
    Relayout()
end

local function OnDisable()
    active = false
    if addon.InfoBarTokens then
        addon.InfoBarTokens.Disable()
    end
    if addon.InfoBarStats then
        addon.InfoBarStats.Disable()
    end
    if frame then
        frame:Hide()
    end
end

addon.InfoBar = {
    StartDrag = StartDrag,
    StopDrag = StopDrag,
    Relayout = Relayout,
    ApplyFont = ApplyFont,
}

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function()
        return L["Info Bar"] or "Info Bar"
    end,
    desc = function()
        return L["Combined currency and stats bar at the top of the screen."]
            or "Combined currency and stats bar."
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
        if addon.InfoBarTokens then
            addon.InfoBarTokens.Refresh()
        end
        if addon.InfoBarStats then
            addon.InfoBarStats.Refresh()
        end
        Relayout()
    end,
    BuildOptions = function(section, C)
        C:AddDescription(
            section,
            L["Drag the bar to move it."] or "Shift+drag the bar to move it."
        )
        C:AddSlider(section, {
            label = L["Font Size"],
            min = 8,
            max = 24,
            step = 1,
            getFunc = function()
                return FontSize()
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.fontSize = val
                end
                if active then
                    ApplyFont()
                    Relayout()
                end
            end,
        })
        if addon.InfoBarTokens and addon.InfoBarTokens.BuildOptions then
            addon.InfoBarTokens.BuildOptions(section, C)
        end
        if addon.InfoBarStats and addon.InfoBarStats.BuildOptions then
            addon.InfoBarStats.BuildOptions(section, C)
        end
    end,
})
