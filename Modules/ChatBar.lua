-- ElvUI_Banbi — Quick chat channel bar (SimpleChat style) + AddOnSkins size/spacing.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "chatBar"
local DEFAULT_FONT_SIZE = 15
local DEFAULT_BTN = 23
local DEFAULT_GAP = 6

local barFrame
local buttons = {}
local moverRegistered = false
local active = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function SkinDB()
    local E = addon:GetE()
    return E and E.db and E.db.addOnSkins
end

local function FontSize()
    local cfg = Cfg()
    local size = cfg and tonumber(cfg.fontSize) or DEFAULT_FONT_SIZE
    if size < 10 then size = 10 elseif size > 24 then size = 24 end
    return size
end

-- Hitbox must cover the glyph; AddOnSkins size is a floor only.
local function ButtonSize()
    local font = FontSize()
    local minSize = font + 8
    local db = SkinDB()
    local skinSize = db and tonumber(db.chatBarSize)
    if skinSize and skinSize > minSize then
        return skinSize
    end
    return math.max(minSize, DEFAULT_BTN)
end

local function ButtonGap()
    local db = SkinDB()
    local gap = db and tonumber(db.chatBarSpacing)
    if gap and gap >= 0 then
        return gap
    end
    return DEFAULT_GAP
end

local function ApplyFontSize()
    local size = FontSize()
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn and btn.text then
            btn.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        end
    end
end

local function SelectedChatFrame()
    return SELECTED_DOCK_FRAME or SELECTED_CHAT_FRAME or ChatFrame1
end

local function OpenChat(slash)
    ChatFrame_OpenChat(slash, SelectedChatFrame())
end

local function LfgChannelName()
    local cfg = Cfg()
    local name = cfg and cfg.lfgChannelName
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "寻求组队"
end

local function OnLfgClick(_, button)
    local chatFrame = SelectedChatFrame()
    local channelName = LfgChannelName()
    if button == "RightButton" then
        local id = GetChannelName(channelName)
        if not id or id == 0 then
            JoinPermanentChannel(channelName, nil, 1, 1)
            if ChatFrame_AddChannel then
                ChatFrame_AddChannel(chatFrame, channelName)
            end
            print("|cff00d200已加入" .. channelName .. "|r")
        else
            LeaveChannelByName(channelName)
            print("|cffd20000已离开" .. channelName .. "|r")
        end
    else
        local id = GetChannelName(channelName)
        if id and id > 0 then
            OpenChat("/" .. id .. " ")
        else
            print("|cffffcc00尚未加入" .. channelName .. "（右键按钮可加入）|r")
        end
    end
end

local function OnEmoteClick()
    if addon.ChatEmote then
        addon.ChatEmote:Toggle()
    end
end

local BUTTON_DEFS = {
    { key = "say", text = "说", color = {1.00, 1.00, 1.00}, click = function() OpenChat("/s ") end },
    { key = "yell", text = "喊", color = {1.00, 0.25, 0.25}, click = function() OpenChat("/y ") end },
    { key = "party", text = "队", color = {0.66, 0.66, 1.00}, click = function() OpenChat("/p ") end },
    { key = "guild", text = "会", color = {0.25, 1.00, 0.25}, click = function() OpenChat("/g ") end },
    { key = "raid", text = "团", color = {1.00, 0.50, 0.00}, click = function() OpenChat("/raid ") end },
    { key = "bg", text = "战", color = {1.00, 0.50, 0.00}, click = function() OpenChat("/bg ") end },
    { key = "ch1", text = "综", color = {0.82, 0.70, 0.55}, click = function() OpenChat("/1 ") end },
    { key = "ch2", text = "交", color = {0.20, 0.60, 0.80}, click = function() OpenChat("/2 ") end },
    { key = "ch3", text = "防", color = {0.80, 0.30, 0.30}, click = function() OpenChat("/3 ") end },
    { key = "lfg", text = "组", color = {0.78, 1.00, 0.59}, click = OnLfgClick, anyClick = true },
    { key = "emote", text = "表", color = {1.00, 0.50, 1.00}, click = OnEmoteClick },
    { key = "roll", text = "骰", color = {1.00, 1.00, 0.00}, click = function() RandomRoll(1, 100) end },
}

local function PersistPosition()
    if not barFrame then return end
    local cfg = Cfg()
    if not cfg then return end
    cfg.anchorToChat = false
    local point, _, _, x, y = barFrame:GetPoint(1)
    cfg.anchor = point or "BOTTOMLEFT"
    cfg.posX = x or 0
    cfg.posY = y or 30
end

local function ApplyPosition()
    if not barFrame then return end
    local cfg = Cfg()
    local defaults = addon.defaults.profile.features.chatBar
    barFrame:SetScale(1)
    barFrame:ClearAllPoints()

    if cfg.anchorToChat ~= false then
        local cf = ChatFrame1 or SELECTED_CHAT_FRAME or SELECTED_DOCK_FRAME
        if cf then
            barFrame:SetPoint(
                "BOTTOMLEFT",
                cf,
                "TOPLEFT",
                cfg.chatOffsetX or defaults.chatOffsetX or 0,
                cfg.chatOffsetY or defaults.chatOffsetY or 4
            )
            return
        end
    end

    barFrame:SetPoint(
        cfg.anchor or defaults.anchor,
        UIParent,
        cfg.anchor or defaults.anchor,
        cfg.posX or defaults.posX,
        cfg.posY or defaults.posY
    )
end

function addon.ResetChatBarPosition()
    local cfg = Cfg()
    if not cfg then return end
    local d = addon.defaults.profile.features.chatBar
    cfg.anchorToChat = true
    cfg.chatOffsetX = d.chatOffsetX
    cfg.chatOffsetY = d.chatOffsetY
    cfg.anchor = d.anchor
    cfg.posX = d.posX
    cfg.posY = d.posY
    ApplyPosition()
end

local function StartBarDrag()
    if InCombatLockdown and InCombatLockdown() then return end
    if not IsShiftKeyDown() then return end
    if barFrame then barFrame:StartMoving() end
end

local function StopBarDrag()
    if barFrame then
        barFrame:StopMovingOrSizing()
        PersistPosition()
    end
end

local function LayoutButtons()
    if not barFrame then return end
    local size = ButtonSize()
    local gap = ButtonGap()
    local n = #buttons
    for i = 1, n do
        local btn = buttons[i]
        btn:SetWidth(size)
        btn:SetHeight(size)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", barFrame, "LEFT", (i - 1) * (size + gap), 0)
        -- SimpleChat: glyph IS the button — never apply classic ChatBar text offsets
        if btn.text then
            btn.text:ClearAllPoints()
            btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.text:SetJustifyH("CENTER")
            btn.text:SetJustifyV("MIDDLE")
        end
        local hl = btn:GetHighlightTexture()
        if hl then
            hl:ClearAllPoints()
            hl:SetAllPoints(btn)
        end
    end
    barFrame:SetWidth(math.max(n * size + (n - 1) * gap, 1))
    barFrame:SetHeight(size)
end

local function CreateButton(parent, def, index)
    local btn = CreateFrame("Button", "ElvUI_Banbi_ChatBarBtn" .. index, parent)
    btn:SetWidth(DEFAULT_BTN)
    btn:SetHeight(DEFAULT_BTN)
    if def.anyClick then
        btn:RegisterForClicks("AnyUp")
    else
        btn:RegisterForClicks("LeftButtonUp")
    end
    btn:SetScript("OnClick", def.click)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", StartBarDrag)
    btn:SetScript("OnDragStop", StopBarDrag)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, FontSize(), "OUTLINE")
    fs:SetShadowOffset(0.8, -0.8)
    fs:SetShadowColor(0.3, 0.3, 0.3, 0.7)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(def.text)
    fs:SetTextColor(def.color[1], def.color[2], def.color[3])
    btn.text = fs
    btn.Text = fs

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local hl = btn:GetHighlightTexture()
    if hl then
        hl:SetAllPoints(btn)
        hl:SetAlpha(0.35)
    end
    return btn
end

local function EnsureBar()
    if barFrame then return barFrame end

    barFrame = CreateFrame("Frame", "ElvUI_Banbi_ChatBar", UIParent)
    _G.ChatBarFrame = barFrame
    barFrame:SetClampedToScreen(true)
    barFrame:SetMovable(true)
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")
    barFrame:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        if not IsShiftKeyDown() then return end
        self:StartMoving()
    end)
    barFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PersistPosition()
    end)

    for i = 1, #BUTTON_DEFS do
        buttons[i] = CreateButton(barFrame, BUTTON_DEFS[i], i)
        _G["ChatBarFrameButton" .. i] = buttons[i]
    end

    LayoutButtons()
    ApplyPosition()
    return barFrame
end

local function RegisterMover()
    if moverRegistered then return end
    local E = addon:GetE()
    if not (E and E.CreateMover) then return end
    E:CreateMover(barFrame, "BanbiChatBarMover", L["Quick Chat Bar"] or "Chat Bar", nil, nil, function()
        PersistPosition()
    end)
    moverRegistered = true
end

-- Optional border from AddOnSkins; text stays locked to CENTER.
local function ApplyElvUIButtonTemplates()
    local E = addon:GetE()
    if not E or not E.private or not E.private.addOnSkins or not E.private.addOnSkins.ChatBar then
        return
    end
    local size = ButtonSize()
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            if btn.SetTemplate then
                btn:SetTemplate("Transparent")
            end
            btn:SetWidth(size)
            btn:SetHeight(size)
        end
    end
end

function addon.ApplyChatBarSkinSettings()
    if not barFrame then return end
    ApplyFontSize()
    ApplyElvUIButtonTemplates()
    LayoutButtons()
end

function ChatBar_UpdateButtons()
    addon.ApplyChatBarSkinSettings()
end

function ChatBar_UpdateButtonOrientation()
    addon.ApplyChatBarSkinSettings()
end

local function OnEnable()
    active = true
    EnsureBar()
    RegisterMover()
    ApplyPosition()
    addon.ApplyChatBarSkinSettings()
    barFrame:Show()
    if addon.ChatEmote then
        addon.ChatEmote:InstallFilters()
    end
end

local function OnDisable()
    active = false
    if barFrame then
        barFrame:Hide()
    end
    if addon.ChatEmote then
        addon.ChatEmote:Hide()
    end
end

function addon.BuildChatBarOptions(section, C)
    C:AddDescription(section, L["Shift+drag to move the chat bar. Button size/spacing: ElvUI → Skins → ChatBar."]
        or "Shift+drag to move. Size/spacing via AddOnSkins ChatBar.")
    C:AddEditBox(section, {
        label = L["LFG Channel Name"],
        desc = L["Channel name used by the LFG button and auto-join."],
        getFunc = function()
            local cfg = Cfg()
            return (cfg and cfg.lfgChannelName) or "寻求组队"
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if not cfg then return end
            val = tostring(val or ""):match("^%s*(.-)%s*$") or ""
            cfg.lfgChannelName = (val ~= "") and val or nil
        end,
    })
    C:AddSlider(section, {
        label = L["Button Text Size"],
        min = 10,
        max = 24,
        step = 1,
        getFunc = function()
            local cfg = Cfg()
            return (cfg and cfg.fontSize) or DEFAULT_FONT_SIZE
        end,
        setFunc = function(val)
            local cfg = Cfg()
            if cfg then cfg.fontSize = val end
            if active then
                addon.ApplyChatBarSkinSettings()
            end
        end,
    })
    C:AddButton(section, {
        label = L["Reset to Above Chat"],
        callback = function()
            addon.ResetChatBarPosition()
        end,
    })
end

addon:RegisterFeature(KEY, {
    category = "chat",
    default = true,
    linkedTo = "chatEnhance",
    optionsHidden = true,
    label = function() return L["Quick Chat Bar"] end,
    desc = function()
        return L["Channel shorten, timestamp, Tab switch, edit history, and quick chat bar."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = function()
        if active then
            ApplyPosition()
            addon.ApplyChatBarSkinSettings()
        end
    end,
})
