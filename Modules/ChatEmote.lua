-- ElvUI_Banbi — Chat emote picker + chat-message icon substitution (from ChatBar ChatEmote).

local ADDON_NAME, addon = ...

local ICON_SIZE = 25
local CUSTOM_START = 9
local EMOTION_ROOT = "Interface\\AddOns\\ElvUI_Banbi\\Media\\Emotion\\"

local emotes = {
    {"{rt1}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_1]]},
    {"{rt2}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_2]]},
    {"{rt3}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_3]]},
    {"{rt4}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_4]]},
    {"{rt5}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_5]]},
    {"{rt6}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_6]]},
    {"{rt7}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_7]]},
    {"{rt8}", [[Interface\TargetingFrame\UI-RaidTargetingIcon_8]]},
    {"{天使}", EMOTION_ROOT .. "angel"},
    {"{生气}", EMOTION_ROOT .. "angry"},
    {"{大笑}", EMOTION_ROOT .. "biglaugh"},
    {"{鼓掌}", EMOTION_ROOT .. "clap"},
    {"{酷}", EMOTION_ROOT .. "cool"},
    {"{哭}", EMOTION_ROOT .. "cry"},
    {"{可爱}", EMOTION_ROOT .. "cutie"},
    {"{鄙视}", EMOTION_ROOT .. "despise"},
    {"{美梦}", EMOTION_ROOT .. "dreamsmile"},
    {"{尴尬}", EMOTION_ROOT .. "embarrass"},
    {"{邪恶}", EMOTION_ROOT .. "evil"},
    {"{兴奋}", EMOTION_ROOT .. "excited"},
    {"{晕}", EMOTION_ROOT .. "faint"},
    {"{打架}", EMOTION_ROOT .. "fight"},
    {"{流感}", EMOTION_ROOT .. "flu"},
    {"{呆}", EMOTION_ROOT .. "freeze"},
    {"{皱眉}", EMOTION_ROOT .. "frown"},
    {"{致敬}", EMOTION_ROOT .. "greet"},
    {"{鬼脸}", EMOTION_ROOT .. "grimace"},
    {"{龇牙}", EMOTION_ROOT .. "growl"},
    {"{开心}", EMOTION_ROOT .. "happy"},
    {"{心}", EMOTION_ROOT .. "heart"},
    {"{恐惧}", EMOTION_ROOT .. "horror"},
    {"{生病}", EMOTION_ROOT .. "ill"},
    {"{无辜}", EMOTION_ROOT .. "Innocent"},
    {"{功夫}", EMOTION_ROOT .. "kongfu"},
    {"{花痴}", EMOTION_ROOT .. "love"},
    {"{邮件}", EMOTION_ROOT .. "mail"},
    {"{化妆}", EMOTION_ROOT .. "makeup"},
    {"{马里奥}", EMOTION_ROOT .. "mario"},
    {"{沉思}", EMOTION_ROOT .. "meditate"},
    {"{可怜}", EMOTION_ROOT .. "miserable"},
    {"{好}", EMOTION_ROOT .. "okay"},
    {"{漂亮}", EMOTION_ROOT .. "pretty"},
    {"{吐}", EMOTION_ROOT .. "puke"},
    {"{握手}", EMOTION_ROOT .. "shake"},
    {"{喊}", EMOTION_ROOT .. "shout"},
    {"{闭嘴}", EMOTION_ROOT .. "shuuuu"},
    {"{害羞}", EMOTION_ROOT .. "shy"},
    {"{睡觉}", EMOTION_ROOT .. "sleep"},
    {"{微笑}", EMOTION_ROOT .. "smile"},
    {"{吃惊}", EMOTION_ROOT .. "suprise"},
    {"{失败}", EMOTION_ROOT .. "surrender"},
    {"{流汗}", EMOTION_ROOT .. "sweat"},
    {"{流泪}", EMOTION_ROOT .. "tear"},
    {"{悲剧}", EMOTION_ROOT .. "tears"},
    {"{想}", EMOTION_ROOT .. "think"},
    {"{偷笑}", EMOTION_ROOT .. "Titter"},
    {"{猥琐}", EMOTION_ROOT .. "ugly"},
    {"{胜利}", EMOTION_ROOT .. "victory"},
    {"{雷锋}", EMOTION_ROOT .. "volunteer"},
    {"{委屈}", EMOTION_ROOT .. "wronged"},
}

local Emote = {
    filtersInstalled = false,
    frame = nil,
}

local function IconFmt()
    local size = ICON_SIZE
    local chat = SELECTED_CHAT_FRAME or ChatFrame1
    if chat and chat.GetFont then
        local _, fontSize = chat:GetFont()
        if fontSize and fontSize > 0 then
            size = math.max(math.floor(fontSize), ICON_SIZE)
        end
    end
    return format("\124T%%s:%d\124t", size)
end

local function ChatFilter(_, _, msg, ...)
    local fmt = IconFmt()
    for i = CUSTOM_START, #emotes do
        if msg:find(emotes[i][1], 1, true) then
            msg = msg:gsub(emotes[i][1], format(fmt, emotes[i][2]), 1)
            break
        end
    end
    return false, msg, ...
end

local FILTER_EVENTS = {
    "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_AFK", "CHAT_MSG_DND",
}

function Emote:InstallFilters()
    if self.filtersInstalled then return end
    for i = 1, #FILTER_EVENTS do
        ChatFrame_AddMessageEventFilter(FILTER_EVENTS[i], ChatFilter)
    end
    self.filtersInstalled = true
end

local function OnEmoteIconMouseUp(frame, button)
    if button == "LeftButton" then
        local editBox = ChatEdit_ChooseBoxForSend()
        if not editBox:IsShown() then
            ChatEdit_ActivateChat(editBox)
        end
        editBox:Insert(frame.text)
    end
    Emote:Toggle()
end

function Emote:EnsureFrame()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "ElvUI_Banbi_EmoteTable", UIParent)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3)
    f:SetWidth((ICON_SIZE + 6) * 12 + 10)
    f:SetHeight((ICON_SIZE + 6) * 5 + 10)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    f:EnableMouse(true)

    local row, col = 1, 1
    for i = 1, #emotes do
        local icon = CreateFrame("Frame", nil, f)
        icon:SetWidth(ICON_SIZE + 6)
        icon:SetHeight(ICON_SIZE + 6)
        icon.text = emotes[i][1]
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetTexture(emotes[i][2])
        icon.texture:SetAllPoints(icon)
        icon:SetPoint("TOPLEFT", 5 + (col - 1) * (ICON_SIZE + 6), -5 - (row - 1) * (ICON_SIZE + 6))
        icon:EnableMouse(true)
        icon:SetScript("OnMouseUp", OnEmoteIconMouseUp)
        col = col + 1
        if col > 12 then
            row = row + 1
            col = 1
        end
    end

    self.frame = f
    return f
end

function Emote:Toggle()
    local f = self:EnsureFrame()
    if f:IsShown() then
        f:Hide()
    else
        local anchor = ChatFrame1EditBox or (SELECTED_CHAT_FRAME and SELECTED_CHAT_FRAME.editBox)
        f:ClearAllPoints()
        if anchor then
            f:SetPoint("BOTTOM", anchor, "TOP", 30, 8)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        f:Show()
    end
end

function Emote:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

addon.ChatEmote = Emote
