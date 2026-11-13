-- ElvUI_Banbi — compact gold display (万 / 亿) for bags, datatexts, and mail.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "moneyFormat"

local abs, floor = math.abs, math.floor
local format = string.format
local hooksecurefunc = hooksecurefunc
local tonumber, tostring, type = tonumber, tostring, type

local COLOR_COPPER, COLOR_SILVER, COLOR_GOLD = "|cffeda55f", "|cffc7c7cf", "|cffffd700"
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12|t"
local ICON_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"

local active = false
local hooked = false
local orig = {}

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function TrimDecimals(value)
    local text = format("%.2f", value)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

-- 90000000 -> 9000万, 150000000 -> 1.5亿, 12345 -> 1.23万, 9999 stays 9999
function addon.FormatGoldAmount(gold)
    gold = tonumber(gold) or 0
    local sign = ""
    if gold < 0 then
        sign = "-"
        gold = -gold
    end
    gold = floor(gold + 0.5)

    if gold >= 100000000 then
        local yi = gold / 100000000
        local rounded = floor(yi * 100 + 0.5) / 100
        if rounded == floor(rounded) then
            return sign .. format("%d亿", rounded)
        end
        return sign .. TrimDecimals(rounded) .. "亿"
    elseif gold >= 10000 then
        local wan = gold / 10000
        local rounded = floor(wan * 100 + 0.5) / 100
        if rounded >= 10000 then
            return sign .. "1亿"
        end
        if rounded == floor(rounded) then
            return sign .. format("%d万", rounded)
        end
        return sign .. TrimDecimals(rounded) .. "万"
    end

    return sign .. format("%d", gold)
end

local function GoldText(gold)
    return addon.FormatGoldAmount(gold)
end

local function ElvLocale()
    if ElvUI then
        local _, locale = unpack(ElvUI)
        return locale
    end
end

local function FormatMoney(amount, style, textonly)
    local locale = ElvLocale()
    local coppername = textonly and (locale and locale["copperabbrev"] or "c") or ICON_COPPER
    local silvername = textonly and (locale and locale["silverabbrev"] or "s") or ICON_SILVER
    local goldname = textonly and (locale and locale["goldabbrev"] or "g") or ICON_GOLD

    amount = tonumber(amount) or 0
    local value = abs(amount)
    local gold = floor(value / 10000)
    local silver = floor((value / 100) % 100)
    local copper = floor(value % 100)
    local goldstr = GoldText(gold)

    if not style or style == "SMART" then
        local str = ""
        if gold > 0 then
            str = format("%s%s%s", goldstr, goldname, (silver > 0 or copper > 0) and " " or "")
        end
        if silver > 0 then
            str = format("%s%d%s%s", str, silver, silvername, copper > 0 and " " or "")
        end
        if copper > 0 or value == 0 then
            str = format("%s%d%s", str, copper, coppername)
        end
        return str
    end

    if style == "FULL" then
        if gold > 0 then
            return format("%s%s %d%s %d%s", goldstr, goldname, silver, silvername, copper, coppername)
        elseif silver > 0 then
            return format("%d%s %d%s", silver, silvername, copper, coppername)
        else
            return format("%d%s", copper, coppername)
        end
    elseif style == "SHORT" then
        if gold > 0 then
            if gold >= 10000 then
                return format("%s%s", goldstr, goldname)
            end
            return format("%.1f%s", amount / 10000, goldname)
        elseif silver > 0 then
            return format("%.1f%s", amount / 100, silvername)
        else
            return format("%d%s", amount, coppername)
        end
    elseif style == "SHORTINT" then
        if gold > 0 then
            return format("%s%s", goldstr, goldname)
        elseif silver > 0 then
            return format("%d%s", silver, silvername)
        else
            return format("%d%s", copper, coppername)
        end
    elseif style == "CONDENSED" then
        if gold > 0 then
            return format("%s%s|r.%s%02d|r.%s%02d|r", COLOR_GOLD, goldstr, COLOR_SILVER, silver, COLOR_COPPER, copper)
        elseif silver > 0 then
            return format("%s%d|r.%s%02d|r", COLOR_SILVER, silver, COLOR_COPPER, copper)
        else
            return format("%s%d|r", COLOR_COPPER, copper)
        end
    elseif style == "BLIZZARD" then
        if gold > 0 then
            return format("%s%s %d%s %d%s", goldstr, goldname, silver, silvername, copper, coppername)
        elseif silver > 0 then
            return format("%d%s %d%s", silver, silvername, copper, coppername)
        else
            return format("%d%s", copper, coppername)
        end
    end

    return FormatMoney(amount, "SMART", textonly)
end

local function FormatBagMoney(amount)
    local str, coppername, silvername, goldname = "", "|cffeda55fc|r", "|cffc7c7cfs|r", "|cffffd700g|r"
    amount = tonumber(amount) or 0
    local value = abs(amount)
    local gold = floor(value / 10000)
    local silver = floor((value / 100) % 100)
    local copper = floor(value % 100)

    if gold > 0 then
        str = format("%s%s%s", GoldText(gold), goldname, (silver > 0 or copper > 0) and " " or "")
    end
    if silver > 0 then
        str = format("%s%d%s%s", str, silver, silvername, copper > 0 and " " or "")
    end
    if copper > 0 or value == 0 then
        str = format("%s%d%s", str, copper, coppername)
    end
    return str
end

local function CoinTexture(kind, amount)
    local icon = kind == "gold" and ICON_GOLD or (kind == "silver" and ICON_SILVER or ICON_COPPER)
    if kind == "gold" then
        return GoldText(amount) .. icon
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
        return sign .. format("%s金 %d银 %d铜", GoldText(gold), silver, copper)
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
    goldButton:SetText(GoldText(gold))
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
    if not orig.PostalGetMoneyStringPlain then
        orig.PostalGetMoneyStringPlain = Postal.GetMoneyStringPlain
        function Postal:GetMoneyStringPlain(money)
            if not active then
                if orig.PostalGetMoneyStringPlain then
                    return orig.PostalGetMoneyStringPlain(self, money)
                end
                return FormatPostalMoney(money, false)
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
        if not active or type(text) ~= "string" then
            return text
        end
        money = tonumber(money) or 0
        local gold = floor(abs(money) / 10000)
        if gold < 10000 then
            return text
        end
        local raw = tostring(gold)
        local idx = text:find(raw, 1, true)
        if not idx then
            return text
        end
        return text:sub(1, idx - 1) .. GoldText(gold) .. text:sub(idx + #raw)
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
            if not active then
                return orig.FormatMoney(self, amount, style, textonly)
            end
            return FormatMoney(amount, style, textonly)
        end
    end

    if E then
        local B = E.GetModule and E:GetModule("Bags", true)
        if B and B.FormatMoney and not orig.BagFormatMoney then
            orig.BagFormatMoney = B.FormatMoney
            function B:FormatMoney(amount)
                if not active then
                    return orig.BagFormatMoney(self, amount)
                end
                return FormatBagMoney(amount)
            end
        end
    end

    if type(MoneyFrame_Update) == "function" and not orig.MoneyFrame_Update then
        orig.MoneyFrame_Update = MoneyFrame_Update
        if hooksecurefunc then
            hooksecurefunc("MoneyFrame_Update", ApplyMoneyFrameGold)
        else
            MoneyFrame_Update = function(frameName, money)
                orig.MoneyFrame_Update(frameName, money)
                ApplyMoneyFrameGold(frameName, money)
            end
        end
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
