-- ElvUI_Banbi — token counts content for Info Bar (left side).

local ADDON_NAME, addon = ...
local L = addon.L

local CFG_KEY = "infoBar"
local ICON_SIZE = 20
local GAP = 10
local PAD_X = 6

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

local host
local buttons = {}
local active = false
local contentWidth = 0
local fontPath, fontSize

local function Cfg()
    return addon:GetFeatureConfig(CFG_KEY)
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
    if addon.InfoBar and addon.InfoBar.StartDrag then
        addon.InfoBar.StartDrag()
    end
end

local function StopDrag()
    if addon.InfoBar and addon.InfoBar.StopDrag then
        addon.InfoBar.StopDrag()
    end
end

local function NotifyRelayout()
    if addon.InfoBar and addon.InfoBar.Relayout then
        addon.InfoBar.Relayout()
    end
end

local function CreateButton(parent)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetHeight(ICON_SIZE)
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
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
    if fontPath and fontSize then
        countText:SetFont(fontPath, fontSize, "OUTLINE")
    end
    btn.countText = countText
    return btn
end

local function Refresh()
    if not host or not active then
        contentWidth = 0
        if host then
            host:Hide()
        end
        NotifyRelayout()
        return
    end
    local x = 0
    local anyShown = false
    for i, info in ipairs(WATCHED_TOKENS) do
        local btn = buttons[i]
        if not btn then
            btn = CreateButton(host)
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
            btn:SetPoint("LEFT", host, "LEFT", x, 0)
            btn:Show()
            x = x + btn:GetWidth() + GAP
            anyShown = true
        end
    end
    if anyShown then
        contentWidth = math.max(x - GAP, 0)
        host:SetWidth(contentWidth)
        host:Show()
    else
        contentWidth = 0
        host:SetWidth(1)
        host:Hide()
    end
    NotifyRelayout()
end

local function ApplyFont(font, size)
    fontPath, fontSize = font, size
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn and btn.countText then
            btn.countText:SetFont(font, size, "OUTLINE")
        end
    end
    if active then
        Refresh()
    end
end

local function Attach(parent)
    if host then
        host:SetParent(parent)
        host:ClearAllPoints()
        host:SetPoint("LEFT", parent, "LEFT", PAD_X, 0)
        return host
    end
    host = CreateFrame("Frame", "ElvUI_Banbi_InfoBarTokens", parent)
    host:SetHeight(ICON_SIZE)
    host:SetPoint("LEFT", parent, "LEFT", PAD_X, 0)
    host:EnableMouse(false)
    host:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE" or event == "PLAYER_LOGIN" then
            Refresh()
        end
    end)
    return host
end

local function Enable()
    active = true
    if not host then return end
    host:RegisterEvent("PLAYER_LOGIN")
    host:RegisterEvent("PLAYER_ENTERING_WORLD")
    host:RegisterEvent("BAG_UPDATE")
    Refresh()
end

local function Disable()
    active = false
    contentWidth = 0
    if host then
        host:UnregisterAllEvents()
        host:Hide()
    end
    NotifyRelayout()
end

local function BuildOptions(section, C)
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
                if active then
                    Refresh()
                end
            end,
        })
    end
end

addon.InfoBarTokens = {
    Attach = Attach,
    Enable = Enable,
    Disable = Disable,
    Refresh = Refresh,
    ApplyFont = ApplyFont,
    BuildOptions = BuildOptions,
    GetContentWidth = function()
        return contentWidth or 0
    end,
    HasContent = function()
        return (contentWidth or 0) > 0
    end,
    GetIconSize = function()
        return ICON_SIZE
    end,
    GetPadX = function()
        return PAD_X
    end,
}
