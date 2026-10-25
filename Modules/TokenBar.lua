-- ElvUI_Banbi — top token bar (from BagSync_TokenBar / Enhanced infoBar tokens).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "tokenBar"
local ICON_SIZE = 20
local GAP = 10
local PAD_X = 6
local PAD_Y = 4

local WATCHED_TOKENS = {
    { id = 65085, name = "虚空碎片" },
    { id = 65297, name = "觉醒泰坦精华" },
    { id = 69885, name = "灵魂灰烬" },
    { id = 60038, name = "次级好运护符" },
    { id = 60039, name = "长老的好运符" },
    { id = 70539, name = "商贩标币" },
    { id = 70877, name = "求知护符" },
}

local SILVER = "|cffc7c7cf%s|r"
local MOSS = "|cFF80FF00%s|r"

local frame
local buttons = {}
local active = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function IsTokenShown(id)
    local cfg = Cfg()
    local t = cfg and cfg.tokens
    return not t or t[id] ~= false
end

local function EnsureTokensTable()
    local cfg = Cfg()
    if not cfg then return nil end
    if type(cfg.tokens) ~= "table" then
        cfg.tokens = {}
    end
    return cfg.tokens
end

local function NormTex()
    local E = addon:GetE()
    if E and E.media and E.media.normTex then
        return E.media.normTex
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function PersistPosition()
    if not frame then return end
    local cfg = Cfg()
    if not cfg then return end
    -- 相对屏幕，避免拖完后锚点落在临时父级上
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if not left or not top then return end
    local parent = UIParent
    local pLeft, pTop = parent:GetLeft() or 0, parent:GetTop() or 0
    cfg.anchor = "TOPLEFT"
    cfg.posX = left - pLeft
    cfg.posY = top - pTop
end

local function ApplyPosition()
    if not frame then return end
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
    if not frame then return end
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

local function GetTokenData(itemID)
    local realm = GetRealmName()
    local db = _G.BagSyncTOKEN_DB and realm and _G.BagSyncTOKEN_DB[realm] and _G.BagSyncTOKEN_DB[realm][itemID]
    local name, icon
    if db then
        name = db.name
        icon = db.icon
    end
    if not name or not icon then
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
        name = name or itemName
        icon = icon or itemIcon
    end
    return db, name, icon
end

local function GetTokenCount(itemID, db)
    local count = 0
    local player = UnitName("player")
    if db and player and db[player] then
        count = db[player] or 0
    end
    local bagCount = GetItemCount(itemID, true) or 0
    if bagCount > count then
        count = bagCount
    end
    return count
end

local function BuildCharTooltip(db)
    if not db then return nil end
    local tmp = {}
    for k, v in pairs(db) do
        if k ~= "name" and k ~= "icon" and k ~= "header" and type(v) == "number" then
            tmp[#tmp + 1] = { name = k, count = v }
        end
    end
    table.sort(tmp, function(a, b) return a.name < b.name end)
    return tmp
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.tokenName or "Token")
    if self.charTooltip and #self.charTooltip > 0 then
        GameTooltip:AddLine(" ")
        for i = 1, #self.charTooltip do
            GameTooltip:AddDoubleLine(format(MOSS, self.charTooltip[i].name), format(SILVER, self.charTooltip[i].count))
        end
    else
        GameTooltip:AddLine(format(SILVER, self.countText:GetText() or "0"), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

local function StartDrag()
    if not frame or not frame:IsMovable() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    frame.isMoving = true
    frame:StartMoving()
end

local function StopDrag()
    if not frame or not frame.isMoving then return end
    frame.isMoving = nil
    frame:StopMovingOrSizing()
    PersistPosition()
end

local function CreateButton(parent)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetHeight(ICON_SIZE)
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    -- 子按钮占满热区，需把拖动转给父栏（与 BagSync_TokenBar 一致）
    btn:SetScript("OnMouseDown", function()
        StartDrag()
    end)
    btn:SetScript("OnMouseUp", function()
        StopDrag()
    end)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(ICON_SIZE)
    icon:SetHeight(ICON_SIZE)
    icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    btn.icon = icon

    local countText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    countText:SetJustifyH("LEFT")
    countText:SetText("0")
    btn.countText = countText
    return btn
end

local function Refresh()
    if not frame or not active then
        if frame then frame:Hide() end
        return
    end
    local x = PAD_X
    local anyShown = false
    for i, info in ipairs(WATCHED_TOKENS) do
        local btn = buttons[i]
        if not btn then
            btn = CreateButton(frame)
            buttons[i] = btn
        end
        if not IsTokenShown(info.id) then
            btn:Hide()
        else
            local db, name, icon = GetTokenData(info.id)
            local count = GetTokenCount(info.id, db)
            btn.tokenName = name or info.name
            btn.charTooltip = BuildCharTooltip(db)
            btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            btn.countText:SetText(tostring(count or 0))
            local textWidth = btn.countText:GetStringWidth() or 20
            btn:SetWidth(ICON_SIZE + 3 + textWidth)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", frame, "LEFT", x, 0)
            btn:Show()
            x = x + btn:GetWidth() + GAP
            anyShown = true
        end
    end
    if anyShown then
        frame:SetWidth(math.max(x - GAP + PAD_X, 40))
    else
        frame:SetWidth(40)
    end
    frame:Show()
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "ElvUI_Banbi_TokenBar", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetHeight(ICON_SIZE + PAD_Y * 2)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            StartDrag()
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            StopDrag()
        end
    end)
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
    ApplyChrome()
    ApplyPosition()

    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE" or event == "PLAYER_LOGIN" then
            Refresh()
        end
    end)
    return frame
end

local function OnEnable()
    active = true
    EnsureFrame()
    ApplyChrome()
    ApplyPosition()
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("BAG_UPDATE")
    Refresh()
end

local function OnDisable()
    active = false
    if frame then
        frame:UnregisterAllEvents()
        frame:Hide()
    end
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function() return L["Token Bar"] end,
    desc = function() return L["Show watched currency/token counts at the top of the screen."] end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Drag the bar to move it."] or "Drag the bar to move it.")
        for _, info in ipairs(WATCHED_TOKENS) do
            local id = info.id
            C:AddToggle(section, {
                label = L[info.name] or info.name,
                getFunc = function()
                    return IsTokenShown(id)
                end,
                setFunc = function(val)
                    local tokens = EnsureTokensTable()
                    if tokens then
                        tokens[id] = val and true or false
                    end
                    Refresh()
                end,
            })
        end
    end,
    Refresh = function()
        if active then
            ApplyChrome()
            ApplyPosition()
            Refresh()
        end
    end,
})
