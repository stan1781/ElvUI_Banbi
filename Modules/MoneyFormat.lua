-- ElvUI_Banbi — compact gold display (万 / 亿) for bags, datatexts, and mail.

local _, addon = ...
local L = addon.L

local KEY = "moneyFormat"

local abs, floor = math.abs, math.floor
local format = string.format
local tonumber, tostring, type = tonumber, tostring, type

local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12|t"
local ICON_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"

local active = false
local hooked = false
local moneyFrameHooked = false
local orig = {}

-- Format centi-units (value * 100, already rounded) as "N", "N.D", or "N.DD" + unit.
local function FormatCompact(centi, unit)
    local whole = floor(centi / 100)
    local frac = centi % 100
    if frac == 0 then
        return format("%d%s", whole, unit)
    end
    if frac % 10 == 0 then
        return format("%d.%d%s", whole, frac / 10, unit)
    end
    return format("%d.%02d%s", whole, frac, unit)
end

-- 90000000 -> 9000万, 150000000 -> 1.5亿, 12345 -> 1.23万, 9999 stays 9999
-- Uses integer rounding to avoid float errors (e.g. 100500000 -> 1.01亿, not 1亿).
function addon.FormatGoldAmount(gold)
    gold = tonumber(gold) or 0
    local sign = ""
    if gold < 0 then
        sign = "-"
        gold = -gold
    end
    gold = floor(gold + 0.5)

    if gold >= 100000000 then
        -- round(gold / 1e8, 2) via integer: centi-亿 = round(gold / 1e6)
        return sign .. FormatCompact(floor((gold + 500000) / 1000000), "亿")
    elseif gold >= 10000 then
        -- round(gold / 1e4, 2) via integer: centi-万 = round(gold / 100)
        local centi = floor((gold + 50) / 100)
        if centi >= 1000000 then
            -- 10000万 rounds up to 1亿
            return sign .. FormatCompact(floor((gold + 500000) / 1000000), "亿")
        end
        return sign .. FormatCompact(centi, "万")
    end

    return sign .. format("%d", gold)
end

-- Replace the first gold digit run in an ElvUI/BagSync money string.
-- goldAbs: absolute gold coins; signed: true when SHORT may include a leading minus.
local function ReplaceGoldInText(text, goldAbs, style, signed)
    if type(text) ~= "string" or goldAbs < 10000 then
        return text
    end
    local goldstr = addon.FormatGoldAmount(signed and -goldAbs or goldAbs)
    -- SHORT uses "%.1f" on copper/10000, so digits may be "12345.6" rather than "12345".
    if style == "SHORT" then
        local replaced, n = text:gsub("^%-?%d+%.%d+", goldstr, 1)
        if n > 0 then
            return replaced
        end
    end
    local raw = tostring(goldAbs)
    local idx = text:find(raw, 1, true)
    if not idx then
        return text
    end
    return text:sub(1, idx - 1) .. goldstr .. text:sub(idx + #raw)
end

local function ApplyCompactMoney(text, amount, style)
    if not active or type(text) ~= "string" then
        return text
    end
    amount = tonumber(amount) or 0
    local gold = floor(abs(amount) / 10000)
    -- Only SHORT embeds the sign in the leading float; other styles use abs(amount).
    return ReplaceGoldInText(text, gold, style, style == "SHORT" and amount < 0)
end

local function CoinTexture(kind, amount)
    local icon = kind == "gold" and ICON_GOLD or (kind == "silver" and ICON_SILVER or ICON_COPPER)
    if kind == "gold" then
        return addon.FormatGoldAmount(amount) .. icon
    end
    return tostring(amount) .. icon
end

local function FormatPostalMoney(money, textured)
    money = tonumber(money) or 0
    local sign = ""
    if money < 0 then
        sign = "-"
        money = -money
    end
    local gold = floor(money / 10000)
    local silver = floor((money - gold * 10000) / 100)
    local copper = money % 100
    if textured then
        if gold > 0 then
            return sign .. CoinTexture("gold", gold) .. " " .. CoinTexture("silver", silver) .. " " .. CoinTexture("copper", copper)
        elseif silver > 0 then
            return sign .. CoinTexture("silver", silver) .. " " .. CoinTexture("copper", copper)
        else
            return sign .. CoinTexture("copper", copper)
        end
    end
    if gold > 0 then
        return sign .. format("%s金 %d银 %d铜", addon.FormatGoldAmount(gold), silver, copper)
    elseif silver > 0 then
        return sign .. format("%d银 %d铜", silver, copper)
    else
        return sign .. format("%d铜", copper)
    end
end

local function IsMoneyInputFrame(name, frame)
    if not name then
        return false
    end
    local goldEdit = _G[name .. "Gold"]
    if goldEdit and goldEdit.GetObjectType and goldEdit:GetObjectType() == "EditBox" then
        return true
    end
    if frame and frame.gold and frame.gold.GetObjectType and frame.gold:GetObjectType() == "EditBox" then
        return true
    end
    return false
end

local function ApplyMoneyFrameGold(frameName, money)
    if not active or money == nil then
        return
    end
    local frame, name
    if type(frameName) == "table" then
        frame = frameName
        name = frame.GetName and frame:GetName()
    else
        name = frameName
        frame = name and _G[name]
    end
    if IsMoneyInputFrame(name, frame) then
        return
    end
    money = tonumber(money) or 0
    local gold = floor(abs(money) / 10000)
    if gold < 10000 then
        return
    end
    local goldButton = (name and _G[name .. "GoldButton"]) or (frame and frame.GoldButton)
    if not goldButton or not goldButton.SetText then
        return
    end
    goldButton:SetText(addon.FormatGoldAmount(gold))
end

local function HookPostal()
    if not Postal then
        return
    end
    if Postal.GetMoneyString and not orig.PostalGetMoneyString then
        orig.PostalGetMoneyString = Postal.GetMoneyString
        function Postal:GetMoneyString(money)
            if not active then
                return orig.PostalGetMoneyString(self, money)
            end
            return FormatPostalMoney(money, true)
        end
    end
    if Postal.GetMoneyStringPlain and not orig.PostalGetMoneyStringPlain then
        orig.PostalGetMoneyStringPlain = Postal.GetMoneyStringPlain
        function Postal:GetMoneyStringPlain(money)
            if not active then
                return orig.PostalGetMoneyStringPlain(self, money)
            end
            return FormatPostalMoney(money, false)
        end
    end
end

local function HookBagSync()
    if not BagSync or not BagSync.buildMoneyString then
        return
    end
    if orig.BagSyncBuildMoneyString then
        return
    end
    orig.BagSyncBuildMoneyString = BagSync.buildMoneyString
    function BagSync:buildMoneyString(money, color)
        local text = orig.BagSyncBuildMoneyString(self, money, color)
        return ApplyCompactMoney(text, money)
    end
end

local function HookAll()
    if hooked then
        HookPostal()
        HookBagSync()
        return
    end
    hooked = true

    local E = addon:GetE()
    if E and E.FormatMoney and not orig.FormatMoney then
        orig.FormatMoney = E.FormatMoney
        function E:FormatMoney(amount, style, textonly)
            local text = orig.FormatMoney(self, amount, style, textonly)
            return ApplyCompactMoney(text, amount, style)
        end
    end

    if E then
        local B = E.GetModule and E:GetModule("Bags", true)
        if B and B.FormatMoney and not orig.BagFormatMoney then
            orig.BagFormatMoney = B.FormatMoney
            function B:FormatMoney(amount)
                local text = orig.BagFormatMoney(self, amount)
                return ApplyCompactMoney(text, amount)
            end
        end
    end

    if not moneyFrameHooked and type(MoneyFrame_Update) == "function" then
        moneyFrameHooked = true
        hooksecurefunc("MoneyFrame_Update", ApplyMoneyFrameGold)
    end

    HookPostal()
    HookBagSync()
end

local loader
local function EnsureLoader()
    if loader then
        return
    end
    loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(_, _, name)
        if name == "Postal" or name == "BagSync" then
            HookPostal()
            HookBagSync()
        end
    end)
end

local function RefreshDisplays()
    local E = addon:GetE()
    if E then
        local B = E.GetModule and E:GetModule("Bags", true)
        if B and B.UpdateGoldText then
            pcall(B.UpdateGoldText, B)
        end
        local DT = E.GetModule and E:GetModule("DataTexts", true)
        if DT and DT.RequestAllUpdates then
            pcall(DT.RequestAllUpdates, DT)
        end
    end
    if MoneyFrame_UpdateMoney then
        pcall(MoneyFrame_UpdateMoney)
    end
    if InboxFrame and InboxFrame.IsShown and InboxFrame:IsShown() and InboxFrame_Update then
        pcall(InboxFrame_Update)
    end
    if SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() and SendMailFrame_Update then
        pcall(SendMailFrame_Update)
    end
    if OpenMailFrame and OpenMailFrame.IsShown and OpenMailFrame:IsShown() and OpenMail_Update then
        pcall(OpenMail_Update)
    end
end

local function OnEnable()
    active = true
    EnsureLoader()
    HookAll()
    RefreshDisplays()
end

local function OnDisable()
    active = false
    RefreshDisplays()
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function()
        return L["Gold Format"]
    end,
    desc = function()
        return L["Show gold amounts of 10,000 and above as 万/亿 in bags, datatexts, and mailbox inbox/send."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = RefreshDisplays,
    BuildOptions = function(section, C)
        C:AddDescription(
            section,
            L["Examples: 90000000 → 9000万, 150000000 → 1.5亿. Mail money input boxes stay numeric so you can still type an amount."]
        )
    end,
})
