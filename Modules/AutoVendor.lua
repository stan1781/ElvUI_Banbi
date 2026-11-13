-- ElvUI_Banbi — auto sell / destroy / restock when a merchant is open.
-- Sell/buy settings are per-character (char.autoVendor).
-- Chest opening is account-wide (global.chestOpen); does not auto-loot (game handles it).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "autoVendor"
local TIP_NAME = "ElvUI_Banbi_AutoVendorTip"
local CORRUPTION_PATTERN = "%+(%d+)%s*腐蚀"
local DESTROY_POPUP_TIMEOUT = 3.0
local LOCK_RETRY_MAX = 25
local DEFAULT_CHEST_ID = 64827
-- Never sell or destroy items at or above this item level.
local MIN_SKIP_ITEM_LEVEL = 284

-- Never sell or destroy these item IDs (hard whitelist).
local PROTECT_IDS = {
    [60407] = true,
    [64820] = true,
    [64149] = true,
    [69496] = true,
    [69508] = true,
    [69502] = true,
    [60408] = true,
    [64821] = true,
    [64150] = true,
    [69501] = true,
    [65282] = true, -- 艾泽里特（开箱兑换货币）
}

local function IsProtectedItem(itemID)
    return itemID and PROTECT_IDS[itemID] and true or false
end

local CreateFrame = CreateFrame
local ClearCursor = ClearCursor
local CursorHasItem = CursorHasItem
local DeleteCursorItem = DeleteCursorItem
local GetContainerItemID = GetContainerItemID
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumFreeSlots = GetContainerNumFreeSlots
local GetContainerNumSlots = GetContainerNumSlots
local GetItemCount = GetItemCount
local GetItemInfo = GetItemInfo
local GetMerchantItemInfo = GetMerchantItemInfo
local GetMerchantItemLink = GetMerchantItemLink
local GetMerchantNumItems = GetMerchantNumItems
local GetMoney = GetMoney
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local PickupContainerItem = PickupContainerItem
local UseContainerItem = UseContainerItem
local BuyMerchantItem = BuyMerchantItem

local floor, ceil = math.floor, math.ceil
local format = string.format
local gsub = string.gsub
local match = string.match
local find = string.find
local gmatch = string.gmatch
local tonumber, tostring, type, pairs, select, unpack = tonumber, tostring, type, pairs, select, unpack
local tinsert, tremove = table.insert, table.remove

local active = false
local merchantOpen = false
local eventFrame
local ticker
local scanTip
local queue = {}
local pendingDestroy
local boughtThisVisit = false
local session
local warnedCursor = false

local chestQueue = {}
local chestTicker
local chestOpened = 0
local chestSlashRegistered = false

-- Per-character vendor settings (AceDB char.autoVendor).
local function Cfg()
    if not addon.db or not addon.db.char then
        return nil
    end
    local cfg = addon.db.char.autoVendor
    if type(cfg) ~= "table" then
        cfg = {}
        addon.db.char.autoVendor = cfg
    end
    return cfg
end

-- Account-wide chest settings (AceDB global.chestOpen).
local function ChestCfg()
    if not addon.db or not addon.db.global then
        return nil
    end
    local cfg = addon.db.global.chestOpen
    if type(cfg) ~= "table" then
        cfg = {}
        addon.db.global.chestOpen = cfg
    end
    if cfg.itemID == nil then
        cfg.itemID = DEFAULT_CHEST_ID
    end
    return cfg
end

local function SellEnabled()
    local cfg = Cfg()
    return cfg and cfg.sellEnabled and true or false
end

local function BuyEnabled()
    local cfg = Cfg()
    return cfg and cfg.buyEnabled and true or false
end

local function Print(msg)
    if not msg or msg == "" then
        return
    end
    local prefix = "|cff1784d1Banbi|r"
    local chat = DEFAULT_CHAT_FRAME or ChatFrame1
    if chat and chat.AddMessage then
        chat:AddMessage(prefix .. " " .. tostring(msg))
    end
end

local function ChatEnabled()
    local cfg = Cfg()
    return not cfg or cfg.chatFeedback ~= false
end

local function ChestChatEnabled()
    local cfg = ChestCfg()
    return not cfg or cfg.chatFeedback ~= false
end

local function NewSession()
    return {
        sold = 0,
        soldCopper = 0,
        destroyed = 0,
        bought = 0,
        summarized = false,
    }
end

local function FormatCopper(copper)
    copper = floor(tonumber(copper) or 0)
    if copper < 0 then
        copper = 0
    end
    local gold = floor(copper / 10000)
    local silver = floor((copper / 100) % 100)
    local c = copper % 100
    if gold > 0 and addon.FormatGoldAmount then
        return addon.FormatGoldAmount(gold)
    end
    local silverUnit = L["AutoVendor: silver"] or "s"
    local copperUnit = L["AutoVendor: copper"] or "c"
    if gold > 0 then
        return tostring(gold)
    end
    if silver > 0 and c > 0 then
        return format("%d%s%d%s", silver, silverUnit, c, copperUnit)
    elseif silver > 0 then
        return format("%d%s", silver, silverUnit)
    end
    return format("%d%s", c, copperUnit)
end

local function StripColors(text)
    if not text then
        return ""
    end
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    return text
end

local function ParseItemID(text)
    if not text or text == "" then
        return nil
    end
    local id = match(text, "|Hitem:(%d+)") or match(text, "item:(%d+)")
    if not id then
        id = match(text, "^%s*(%d+)%s*$")
    end
    return tonumber(id)
end

local function ParseSellLine(line)
    if not line then
        return nil
    end
    line = match(line, "^%s*(.-)%s*$") or ""
    if line == "" then
        return nil
    end
    return ParseItemID(line)
end

local function ParseBuyLine(line)
    return addon.ParseAutoVendorBuyLine(line)
end

local function EachLine(text, fn)
    text = tostring(text or "")
    text = gsub(text, "\r\n", "\n")
    text = gsub(text, "\r", "\n")
    for line in gmatch(text .. "\n", "(.-)\n") do
        fn(line)
    end
end

function addon.ParseAutoVendorSellList(text)
    local list = {}
    EachLine(text, function(line)
        local id = ParseSellLine(line)
        if id then
            list[id] = true
        end
    end)
    return list
end

function addon.ParseAutoVendorBuyList(text)
    local list = {}
    EachLine(text, function(line)
        local id, count = ParseBuyLine(line)
        if id and count then
            list[id] = count
        end
    end)
    return list
end

local function ApplyListText(kind, text)
    local cfg = Cfg()
    if not cfg then
        return
    end
    text = tostring(text or "")
    if kind == "sell" then
        cfg.sellListText = text
        cfg.sellList = addon.ParseAutoVendorSellList(text)
    else
        cfg.buyListText = text
        cfg.buyList = addon.ParseAutoVendorBuyList(text)
    end
end

local function SyncListsFromText()
    local cfg = Cfg()
    if not cfg then
        return
    end
    if type(cfg.sellListText) == "string" and cfg.sellListText ~= "" then
        cfg.sellList = addon.ParseAutoVendorSellList(cfg.sellListText)
    elseif type(cfg.sellList) ~= "table" then
        cfg.sellList = {}
    end
    if type(cfg.buyListText) == "string" and cfg.buyListText ~= "" then
        cfg.buyList = addon.ParseAutoVendorBuyList(cfg.buyListText)
    elseif type(cfg.buyList) ~= "table" then
        cfg.buyList = {}
    end
end

local function EnsureScanTip()
    if scanTip then
        return scanTip
    end
    scanTip = CreateFrame("GameTooltip", TIP_NAME, UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

local function QueryItemInfo(link)
    if not link or link == "" then
        return
    end
    local tip = EnsureScanTip()
    tip:Hide()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    pcall(tip.SetHyperlink, tip, link)
    tip:Hide()
end

local function GetCorruption(bag, slot)
    local tip = EnsureScanTip()
    tip:Hide()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetBagItem(bag, slot)

    local value = 0
    local num = tip:NumLines() or 0
    for i = 2, num do
        local line = _G[TIP_NAME .. "TextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" then
            local n = match(StripColors(text), CORRUPTION_PATTERN)
            if n then
                value = tonumber(n) or 0
                break
            end
        end
    end
    tip:Hide()
    return value
end

local function GetSlotItemID(bag, slot)
    if GetContainerItemID then
        local id = GetContainerItemID(bag, slot)
        if id then
            return tonumber(id)
        end
    end
    return ParseItemID(GetContainerItemLink(bag, slot))
end

-- One GetItemInfo call: name, itemLevel, sellPrice. Returns nil fields when uncached.
local function GetItemSellInfo(itemID, link)
    local name, _, _, ilvl, _, _, _, _, _, _, sellPrice
    if itemID then
        name, _, _, ilvl, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
    end
    if (name == nil or ilvl == nil or sellPrice == nil) and link then
        local n2, _, _, i2, _, _, _, _, _, _, p2 = GetItemInfo(link)
        if name == nil or name == "" then
            name = n2
        end
        if ilvl == nil then
            ilvl = i2
        end
        if sellPrice == nil then
            sellPrice = p2
        end
    end
    if ilvl == nil and sellPrice == nil and (name == nil or name == "") then
        return nil, nil, nil
    end
    return name, tonumber(ilvl), sellPrice ~= nil and (tonumber(sellPrice) or 0) or nil
end

-- The openable chest itself (configured ID, default 64827, or name containing 宝箱).
local function IsChestItem(itemID, name, configuredChestID)
    if itemID then
        if itemID == DEFAULT_CHEST_ID then
            return true
        end
        if configuredChestID and itemID == configuredChestID then
            return true
        end
    end
    if name and find(name, "宝箱", 1, true) then
        return true
    end
    return false
end

local function IsQuestItem(itemID, bag, slot)
    if GetContainerItemQuestInfo and bag and slot then
        local isQuest = GetContainerItemQuestInfo(bag, slot)
        if isQuest then
            return true
        end
    end

    local itemType
    if itemID then
        itemType = select(6, GetItemInfo(itemID))
    end
    if not itemType or itemType == "" then
        -- Unknown type: never destroy.
        return true
    end
    if itemType == "Quest" or itemType == "任务" then
        return true
    end
    return false
end

local function IsBuySellTab()
    if not MerchantFrame then
        return true
    end
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
        return false
    end
    return true
end

local function IsMerchantAvailable()
    if not active or not merchantOpen then
        return false
    end
    if MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown() then
        return false
    end
    return true
end

local function IsDeletePopupVisible()
    if StaticPopup_Visible then
        if StaticPopup_Visible("DELETE_ITEM")
            or StaticPopup_Visible("DELETE_GOOD_ITEM")
            or StaticPopup_Visible("DELETE_QUEST_ITEM")
            or StaticPopup_Visible("DELETE_GOOD_QUEST_ITEM") then
            return true
        end
    end
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup and popup.IsShown and popup:IsShown() and popup.which then
            local which = tostring(popup.which)
            if find(which, "DELETE") then
                return true
            end
        end
    end
    return false
end

local function ClearCursorSafe()
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    elseif GetCursorInfo and GetCursorInfo() then
        ClearCursor()
    end
end

local function CursorIsBusy()
    if CursorHasItem and CursorHasItem() then
        return true
    end
    if GetCursorInfo and GetCursorInfo() then
        return true
    end
    return false
end

local function WarnCursor()
    if warnedCursor or not ChatEnabled() then
        return
    end
    warnedCursor = true
    Print(L["AutoVendor: cursor busy"] or "鼠标上已有物品，已跳过摧毁。")
end

local function ClearQueue()
    for i = #queue, 1, -1 do
        queue[i] = nil
    end
    pendingDestroy = nil
end

local function StopTicker()
    if ticker then
        ticker:Hide()
    end
end

local function SellInterval()
    local cfg = Cfg()
    local interval = cfg and tonumber(cfg.sellInterval) or 0.2
    if interval < 0.05 then
        interval = 0.05
    end
    return interval
end

local function PrintSummary()
    if not session or session.summarized then
        return
    end
    session.summarized = true
    if not ChatEnabled() then
        return
    end
    if session.sold <= 0 and session.destroyed <= 0 and session.bought <= 0 then
        return
    end

    local parts = {}
    if session.sold > 0 then
        if session.soldCopper > 0 then
            tinsert(parts, format(
                L["AutoVendor: sold with gold"] or "售出 %d 件（%s）",
                session.sold,
                FormatCopper(session.soldCopper)
            ))
        else
            tinsert(parts, format(L["AutoVendor: sold"] or "售出 %d 件", session.sold))
        end
    end
    if session.destroyed > 0 then
        tinsert(parts, format(L["AutoVendor: destroyed"] or "摧毁 %d 件", session.destroyed))
    end
    if session.bought > 0 then
        tinsert(parts, format(L["AutoVendor: bought"] or "购入 %d 件", session.bought))
    end
    if #parts > 0 then
        Print(table.concat(parts, "，"))
    end
end

local function AbortPendingDestroy(reason)
    if not pendingDestroy then
        return
    end
    pendingDestroy = nil
    ClearCursorSafe()
    if StaticPopup_Hide then
        StaticPopup_Hide("DELETE_ITEM")
        StaticPopup_Hide("DELETE_GOOD_ITEM")
        StaticPopup_Hide("DELETE_QUEST_ITEM")
        StaticPopup_Hide("DELETE_GOOD_QUEST_ITEM")
    end
    if ChatEnabled() and reason then
        Print(reason)
    end
end

local function ResolvePendingDestroy()
    if not pendingDestroy then
        return false
    end
    if IsDeletePopupVisible() then
        local started = pendingDestroy.started or GetTime()
        if (GetTime() - started) >= DESTROY_POPUP_TIMEOUT then
            AbortPendingDestroy(L["AutoVendor: destroy timeout"] or "摧毁确认超时，已跳过该物品。")
            return false
        end
        return true
    end
    local info = pendingDestroy
    pendingDestroy = nil
    local stillThere = GetSlotItemID(info.bag, info.slot) == info.id
    if not stillThere then
        session.destroyed = session.destroyed + (info.count or 1)
    end
    return false
end

local function DestroySlot(entry)
    if not IsMerchantAvailable() then
        return "stop"
    end
    if CursorIsBusy() then
        ClearCursorSafe()
        if CursorIsBusy() then
            WarnCursor()
            return "skip"
        end
    end

    PickupContainerItem(entry.bag, entry.slot)
    if not CursorIsBusy() then
        ClearCursorSafe()
        return "skip"
    end

    DeleteCursorItem()

    if IsDeletePopupVisible() then
        pendingDestroy = {
            bag = entry.bag,
            slot = entry.slot,
            id = entry.id,
            count = entry.count or 1,
            started = GetTime(),
        }
        return "wait"
    end

    if CursorIsBusy() then
        ClearCursorSafe()
        WarnCursor()
        return "skip"
    end

    session.destroyed = session.destroyed + (entry.count or 1)
    return "ok"
end

local function SellSlot(entry)
    if not IsMerchantAvailable() then
        return "stop"
    end
    UseContainerItem(entry.bag, entry.slot)
    session.sold = session.sold + (entry.count or 1)
    session.soldCopper = session.soldCopper + (entry.stackPrice or 0)
    return "ok"
end

-- Returns: "ok" | "locked" | "gone"
local function ClassifyQueueEntry(entry)
    if not entry then
        return "gone"
    end
    local id = GetSlotItemID(entry.bag, entry.slot)
    if not id or id ~= entry.id then
        return "gone"
    end
    local locked = select(3, GetContainerItemInfo(entry.bag, entry.slot))
    if locked then
        return "locked"
    end
    return "ok"
end

-- 3.3.5 FrameXML: honorPoints, arenaPoints, itemCount
-- Later clients: itemCount only. Detect by the third return.
local function GetMerchantCostBreakdown(index)
    local r1, r2, r3 = GetMerchantItemCostInfo(index)
    if r3 ~= nil then
        return tonumber(r1) or 0, tonumber(r2) or 0, tonumber(r3) or 0
    end
    return 0, 0, tonumber(r1) or 0
end

local function GetOwnedCostAmount(link)
    if not link or link == "" then
        return nil
    end
    local currencyID = tonumber(match(link, "|Hcurrency:(%d+)") or match(link, "currency:(%d+)"))
    if currencyID and GetCurrencyInfo then
        local _, amount = GetCurrencyInfo(currencyID)
        if amount ~= nil then
            return tonumber(amount) or 0
        end
    end
    local itemID = ParseItemID(link)
    if itemID then
        return GetItemCount(itemID) or 0
    end
    return nil
end

local function CanPayMerchantCost(index, buyCount, unitPrice, moneyHint)
    local costCopper = ceil((tonumber(unitPrice) or 0) * (buyCount or 0))
    local money = moneyHint
    if money == nil then
        money = GetMoney()
    end
    if money < costCopper then
        return false, "money"
    end

    local _, _, _, quantity, _, _, extendedCost = GetMerchantItemInfo(index)
    if not extendedCost then
        return true
    end
    -- If cost APIs are missing, let the game enforce the purchase.
    if not GetMerchantItemCostInfo then
        return true
    end

    quantity = tonumber(quantity) or 1
    if quantity < 1 then
        quantity = 1
    end
    local packs = ceil(buyCount / quantity)
    local honor, arena, itemCount = GetMerchantCostBreakdown(index)

    if honor > 0 and GetHonorCurrency and (GetHonorCurrency() or 0) < honor * packs then
        return false, "currency"
    end
    if arena > 0 and GetArenaCurrency and (GetArenaCurrency() or 0) < arena * packs then
        return false, "currency"
    end

    if itemCount > 0 and GetMerchantItemCostItem then
        for i = 1, itemCount do
            local _, value, link = GetMerchantItemCostItem(index, i)
            value = tonumber(value) or 0
            local need = value * packs
            if need > 0 then
                local have = GetOwnedCostAmount(link)
                if have ~= nil and have < need then
                    return false, "currency"
                end
            end
        end
    end
    return true
end

local function ItemLabel(link, name, itemID)
    if link and link ~= "" then
        return link
    end
    if name and name ~= "" then
        return name
    end
    return tostring(itemID or "?")
end

local function MergeBuyTargets(dst, src)
    if type(src) ~= "table" then
        return false
    end
    local any = false
    for key, count in pairs(src) do
        local id = tonumber(key)
        local target = tonumber(count)
        if id and target and target > 0 then
            dst[id] = target
            any = true
        end
    end
    return any
end

local function RunBuyRestock()
    if boughtThisVisit then
        return
    end
    boughtThisVisit = true
    if not BuyEnabled() then
        return
    end
    if not IsMerchantAvailable() or not IsBuySellTab() then
        return
    end

    local cfg = Cfg()
    local targets = {}
    local hasTarget = MergeBuyTargets(targets, addon.autoVendorBrainQuestBuyList)
    if MergeBuyTargets(targets, cfg and cfg.buyList) then
        hasTarget = true
    end
    if not hasTarget then
        return
    end

    local num = GetMerchantNumItems and GetMerchantNumItems() or 0
    local handled = {}

    for index = 1, num do
        if not IsMerchantAvailable() then
            return
        end
        local link = GetMerchantItemLink and GetMerchantItemLink(index)
        local id = ParseItemID(link)
        if id and targets[id] and not handled[id] then
            handled[id] = true
            local target = targets[id]
            local have = GetItemCount(id) or 0
            local needed = target - have
            if needed > 0 then
                local name, _, price, quantity, numAvailable = GetMerchantItemInfo(index)
                price = tonumber(price) or 0
                quantity = tonumber(quantity) or 1
                if quantity < 1 then
                    quantity = 1
                end
                local unitPrice = price / quantity

                if numAvailable and numAvailable >= 0 and needed > numAvailable then
                    needed = numAvailable
                end

                local stackMax
                if GetMerchantItemMaxStack then
                    stackMax = GetMerchantItemMaxStack(index)
                end
                if not stackMax or stackMax < 1 then
                    stackMax = select(8, GetItemInfo(id)) or 1
                end
                if stackMax < 1 then
                    stackMax = 1
                end

                local bought = 0
                local skippedReason
                local moneyLeft = GetMoney()
                while needed > 0 do
                    local buyCount = needed
                    if buyCount > stackMax then
                        buyCount = stackMax
                    end
                    local ok, reason = CanPayMerchantCost(index, buyCount, unitPrice, moneyLeft)
                    if not ok then
                        skippedReason = reason
                        break
                    end
                    BuyMerchantItem(index, buyCount)
                    moneyLeft = moneyLeft - ceil(unitPrice * buyCount)
                    if moneyLeft < 0 then
                        moneyLeft = 0
                    end
                    bought = bought + buyCount
                    needed = needed - buyCount
                end

                if bought > 0 then
                    session.bought = session.bought + bought
                end
                if skippedReason and ChatEnabled() then
                    local label = ItemLabel(link, name, id)
                    if skippedReason == "money" then
                        Print(format(L["AutoVendor: not enough money"] or "金币不足，已跳过购买：%s", label))
                    elseif skippedReason == "currency" then
                        Print(format(L["AutoVendor: not enough currency"] or "兑换货币不足，已跳过购买：%s", label))
                    else
                        Print(format(L["AutoVendor: extended cost skipped"] or "无法确认货币消耗，已跳过购买：%s", label))
                    end
                end
            end
        end
    end
end

local ProcessQueueHead

local function EnsureTicker()
    if ticker then
        return ticker
    end
    ticker = CreateFrame("Frame", "ElvUI_Banbi_AutoVendorTicker")
    ticker:Hide()
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        if ResolvePendingDestroy() then
            return
        end
        self.elapsed = self.elapsed + elapsed
        local interval = SellInterval()
        if self.elapsed < interval then
            return
        end
        self.elapsed = 0
        ProcessQueueHead()
    end)
    return ticker
end

local function StartTicker(immediate)
    EnsureTicker()
    ticker.elapsed = immediate and SellInterval() or 0
    ticker:Show()
end

local function FinishMerchantActions()
    StopTicker()
    RunBuyRestock()
    PrintSummary()
end

ProcessQueueHead = function()
    if not IsMerchantAvailable() then
        StopTicker()
        return
    end
    if not IsBuySellTab() then
        return
    end

    while #queue > 0 do
        local entry = tremove(queue, 1)
        local state = ClassifyQueueEntry(entry)
        if state == "locked" then
            entry.lockRetries = (entry.lockRetries or 0) + 1
            if entry.lockRetries <= LOCK_RETRY_MAX then
                tinsert(queue, entry)
                return
            end
            -- Drop after too many lock retries.
        elseif state == "ok" then
            local result
            if entry.action == "destroy" then
                result = DestroySlot(entry)
            else
                result = SellSlot(entry)
            end
            if result == "stop" then
                StopTicker()
                return
            end
            if result == "wait" then
                return
            end
            if #queue > 0 then
                return
            end
        end
        -- "gone" / skip / exhausted lock retries → continue to next
    end

    FinishMerchantActions()
end

-- Walk bag slots in scan order. Optional limit: stop after N existing slots (empty counts).
-- callback(bag, slot, index); return false from callback to abort early.
local function ForEachBagSlot(callback, limit, order)
    order = order or "asc"
    limit = tonumber(limit) or 0
    if limit < 0 then
        limit = 0
    end
    local index = 0
    local lastBag = 4

    local function visit(bag, slot)
        index = index + 1
        if limit > 0 and index > limit then
            return false
        end
        if callback(bag, slot, index) == false then
            return false
        end
        return true
    end

    if order == "desc" then
        for bag = lastBag, 0, -1 do
            local n = GetContainerNumSlots(bag) or 0
            for slot = n, 1, -1 do
                if not visit(bag, slot) then
                    return
                end
            end
        end
    else
        for bag = 0, lastBag do
            local n = GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                if not visit(bag, slot) then
                    return
                end
            end
        end
    end
end

local function BuildQueue(force)
    ClearQueue()
    if not force and not SellEnabled() then
        return
    end

    local cfg = Cfg()
    if not cfg then
        return
    end

    local sellList = type(cfg.sellList) == "table" and cfg.sellList or {}
    local zoneSize = tonumber(cfg.sellZoneSlots) or 0
    if zoneSize < 0 then
        zoneSize = 0
    end
    local scanLimit = tonumber(cfg.scanSlotLimit)
    if scanLimit == nil then
        scanLimit = 80
    end
    if scanLimit < 0 then
        scanLimit = 0
    end
    -- Sell zone cannot extend past the scan range.
    if scanLimit > 0 and zoneSize > scanLimit then
        zoneSize = scanLimit
    end
    local maxCorruption = tonumber(cfg.maxCorruption) or 0
    local destroyUnsellable = cfg.destroyUnsellable and true or false
    local order = cfg.scanOrder or "asc"
    local chestCfg = ChestCfg()
    local configuredChestID = chestCfg and tonumber(chestCfg.itemID) or nil

    ForEachBagSlot(function(bag, slot, index)
        local inZone = zoneSize > 0 and index <= zoneSize
        local itemID = GetSlotItemID(bag, slot)
        if not itemID then
            return
        end
        if IsProtectedItem(itemID) then
            return
        end
        -- Fast path: known chest IDs before heavier bag lookups.
        if IsChestItem(itemID, nil, configuredChestID) then
            return
        end

        local listed = sellList[itemID] or sellList[tostring(itemID)]
        if not inZone and not listed then
            return
        end

        local texture, count, locked = GetContainerItemInfo(bag, slot)
        if not texture or locked then
            return
        end

        local corruption = GetCorruption(bag, slot)
        if corruption > maxCorruption then
            return
        end

        local link = GetContainerItemLink(bag, slot)
        local name, itemLevel, itemPrice = GetItemSellInfo(itemID, link)
        if IsChestItem(itemID, name, configuredChestID) then
            return
        end
        if itemPrice == nil or itemLevel == nil then
            QueryItemInfo(link or ("item:" .. tostring(itemID)))
            return
        end
        if itemLevel >= MIN_SKIP_ITEM_LEVEL then
            return
        end

        count = tonumber(count) or 1
        local entry = {
            bag = bag,
            slot = slot,
            id = itemID,
            count = count,
            stackPrice = itemPrice * count,
            link = link,
            lockRetries = 0,
        }

        if inZone then
            if itemPrice > 0 then
                entry.action = "sell"
                tinsert(queue, entry)
            elseif destroyUnsellable and not IsQuestItem(itemID, bag, slot) then
                entry.action = "destroy"
                entry.stackPrice = 0
                tinsert(queue, entry)
            end
            return
        end

        if listed and itemPrice > 0 then
            entry.action = "sell"
            tinsert(queue, entry)
        end
    end, scanLimit, order)
end

-- ---------------------------------------------------------------------------
-- Chest open (global settings; safe while merchant is open).
-- ---------------------------------------------------------------------------

local function CountFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        free = free + (GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

local function ClearChestQueue()
    for i = #chestQueue, 1, -1 do
        chestQueue[i] = nil
    end
end

local function StopChestTicker()
    if chestTicker then
        chestTicker:Hide()
    end
end

local function ChestInterval()
    local cfg = ChestCfg()
    local interval = cfg and tonumber(cfg.interval) or 0.4
    if interval < 0.1 then
        interval = 0.1
    end
    return interval
end

local function IsMerchantFrameOpen()
    return MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
end

local function IsMerchantSessionOpen()
    return merchantOpen or IsMerchantFrameOpen()
end

-- UseContainerItem sells when a merchant session is open. Open chests by use-item instead.
local function UseChestSlot(bag, slot)
    if IsMerchantSessionOpen() and UseItemByName then
        local link = GetContainerItemLink(bag, slot)
        if link and link ~= "" then
            UseItemByName(link)
            return
        end
        local id = GetSlotItemID(bag, slot)
        local name = id and GetItemInfo(id)
        if name and name ~= "" then
            UseItemByName(name)
            return
        end
        if id then
            UseItemByName("item:" .. tostring(id))
            return
        end
    end
    UseContainerItem(bag, slot)
end

local ProcessChestQueueHead

local function EnsureChestTicker()
    if chestTicker then
        return chestTicker
    end
    chestTicker = CreateFrame("Frame", "ElvUI_Banbi_ChestOpenTicker")
    chestTicker:Hide()
    chestTicker.elapsed = 0
    chestTicker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < ChestInterval() then
            return
        end
        self.elapsed = 0
        ProcessChestQueueHead()
    end)
    return chestTicker
end

local function FinishChestOpen()
    StopChestTicker()
    ClearChestQueue()
    if ChestChatEnabled() then
        if chestOpened > 0 then
            Print(format(L["AutoVendor: chests opened"] or "已打开宝箱 %d 个。可打开商人进行自动清理。", chestOpened))
        else
            Print(L["AutoVendor: no chests"] or "背包中未找到可打开的宝箱。")
        end
    end
end

ProcessChestQueueHead = function()
    if InCombatLockdown and InCombatLockdown() then
        if ChestChatEnabled() then
            Print(L["AutoVendor: chest stop combat"] or "战斗中，已停止开箱。")
        end
        StopChestTicker()
        ClearChestQueue()
        return
    end
    if CountFreeBagSlots() <= 0 then
        if ChestChatEnabled() then
            Print(L["AutoVendor: chest stop full"] or "背包已满，已停止开箱。")
        end
        FinishChestOpen()
        return
    end

    while #chestQueue > 0 do
        local entry = tremove(chestQueue, 1)
        local id = GetSlotItemID(entry.bag, entry.slot)
        if id and id == entry.id then
            local locked = select(3, GetContainerItemInfo(entry.bag, entry.slot))
            if locked then
                entry.lockRetries = (entry.lockRetries or 0) + 1
                if entry.lockRetries <= LOCK_RETRY_MAX then
                    tinsert(chestQueue, 1, entry)
                end
                return
            end
            UseChestSlot(entry.bag, entry.slot)
            chestOpened = chestOpened + 1
            if #chestQueue > 0 then
                return
            end
        end
    end

    FinishChestOpen()
end

local function BuildChestQueue()
    ClearChestQueue()
    local cfg = ChestCfg()
    local itemID = tonumber(cfg and cfg.itemID) or DEFAULT_CHEST_ID
    local order = (cfg and cfg.scanOrder == "desc") and "desc" or "asc"
    local limit = cfg and tonumber(cfg.scanSlotLimit) or 0
    if limit and limit < 0 then
        limit = 0
    end

    ForEachBagSlot(function(bag, slot)
        local id = GetSlotItemID(bag, slot)
        if id == itemID then
            local texture, _, locked = GetContainerItemInfo(bag, slot)
            if texture and not locked then
                tinsert(chestQueue, {
                    bag = bag,
                    slot = slot,
                    id = itemID,
                    lockRetries = 0,
                })
            end
        end
    end, limit, order)
end

local function StopChestOpen(silent)
    StopChestTicker()
    ClearChestQueue()
    if not silent and ChestChatEnabled() then
        Print(L["AutoVendor: chest stopped"] or "已停止开箱。")
    end
end

local function StartChestOpen()
    if not active then
        Print(L["AutoVendor: module off"] or "请先启用「自动购卖」功能。")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        Print(L["AutoVendor: chest stop combat"] or "战斗中，已停止开箱。")
        return
    end

    StopChestOpen(true)
    chestOpened = 0
    BuildChestQueue()
    if #chestQueue == 0 then
        FinishChestOpen()
        return
    end

    if ChestChatEnabled() then
        local cfg = ChestCfg()
        local id = tonumber(cfg and cfg.itemID) or DEFAULT_CHEST_ID
        local name = GetItemInfo(id)
        Print(format(
            L["AutoVendor: chest starting"] or "开始打开宝箱（%s）×%d…",
            name or tostring(id),
            #chestQueue
        ))
    end

    EnsureChestTicker()
    chestTicker.elapsed = ChestInterval()
    chestTicker:Show()
end

function addon.StartAutoChestOpen()
    StartChestOpen()
end

function addon.StopAutoChestOpen()
    StopChestOpen(false)
end

-- Manual sell/destroy from bag button only (requires merchant open).
function addon.RunAutoVendorSellNow()
    if not active then
        Print(L["AutoVendor: module off"] or "请先启用「自动购卖」功能。")
        return
    end
    if not SellEnabled() then
        Print(L["AutoVendor: sell disabled"] or "出售区功能未启用：请在设置中开启「启用出售区清理」。")
        return
    end
    if not IsMerchantFrameOpen() then
        Print(L["AutoVendor: sell need merchant"] or "请先打开商人，再点出售区清理。")
        return
    end
    merchantOpen = true
    if not session or session.summarized then
        session = NewSession()
        -- Keep boughtThisVisit if this merchant visit already restocked.
    end
    warnedCursor = false
    StopTicker()
    -- force=true builds from zone/list; sell never auto-runs on MERCHANT_SHOW.
    BuildQueue(true)
    if #queue == 0 then
        if ChatEnabled() then
            Print(L["AutoVendor: nothing to sell"] or "出售区/列表中没有可处理的物品。")
        end
        return
    end
    if ChatEnabled() then
        Print(format(L["AutoVendor: sell starting"] or "开始处理出售区（%d 件队列）…", #queue))
    end
    StartTicker(true)
end

-- ---------------------------------------------------------------------------
-- ElvUI bag toolbar buttons
-- ---------------------------------------------------------------------------

local bagButtonsAttached = false

local function GetBagsModule()
    local E = addon:GetE()
    if not E or not E.GetModule then
        return nil
    end
    return E:GetModule("Bags", true)
end

local function BagTooltipShow(self)
    local B = GetBagsModule()
    if B and B.Tooltip_Show then
        B.Tooltip_Show(self)
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 4)
    GameTooltip:ClearLines()
    if self.ttText then
        GameTooltip:AddLine(self.ttText)
    end
    if self.ttText2 then
        GameTooltip:AddLine(self.ttText2, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function StyleElvBagButton(btn, texture)
    local E = addon:GetE()
    local border = (E and E.Border) or 1
    local coords = (E and E.TexCoords) or { 0.08, 0.92, 0.08, 0.92 }
    btn:Size(16 + border)
    if btn.SetTemplate then
        btn:SetTemplate()
    end
    btn:SetNormalTexture(texture)
    local nt = btn:GetNormalTexture()
    if nt then
        nt:SetTexCoord(unpack(coords))
        if nt.SetInside then
            nt:SetInside()
        end
    end
    btn:SetPushedTexture(texture)
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetTexCoord(unpack(coords))
        if pt.SetInside then
            pt:SetInside()
        end
    end
    if btn.StyleButton then
        btn:StyleButton(nil, true)
    end
end

local function RefreshBagButtonTooltips()
    local B = GetBagsModule()
    local f = B and B.BagFrame
    if not f then
        return
    end
    if f.banbiChestButton then
        f.banbiChestButton.ttText = L["Bag button: open chests"] or "开箱"
        f.banbiChestButton.ttText2 = L["Bag button: open chests tip"]
            or "左键：按序打开宝箱（商人开着也可以）。右键：停止。"
    end
    if f.banbiSellZoneButton then
        local cfg = Cfg()
        local zone = (cfg and tonumber(cfg.sellZoneSlots)) or 0
        f.banbiSellZoneButton.ttText = L["Bag button: sell zone"] or "出售区"
        f.banbiSellZoneButton.ttText2 = format(
            L["Bag button: sell zone tip"] or "左键：对商人清理出售区（当前 %d 格）。需先打开商人。设置里可改格数/摧毁。",
            zone
        )
    end
end

local function AttachBagButtons()
    local E = addon:GetE()
    local B = GetBagsModule()
    if not E or not B or not B.BagFrame or not B.BagFrame.holderFrame then
        return false
    end
    local f = B.BagFrame
    if f.banbiChestButton and f.banbiSellZoneButton then
        RefreshBagButtonTooltips()
        f.banbiChestButton:Show()
        f.banbiSellZoneButton:Show()
        bagButtonsAttached = true
        return true
    end

    local anchor = f.vendorGraysButton or f.bagsButton
    if not anchor then
        return false
    end

    -- Order (right → left): bags / vendorGrays / sellZone / chest / search
    local sellBtn = CreateFrame("Button", "ElvUI_Banbi_BagSellZoneButton", f.holderFrame)
    StyleElvBagButton(sellBtn, "Interface\\Icons\\INV_Misc_Coin_02")
    sellBtn:Point("RIGHT", anchor, "LEFT", -5, 0)
    sellBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sellBtn:SetScript("OnEnter", function(self)
        RefreshBagButtonTooltips()
        BagTooltipShow(self)
    end)
    sellBtn:SetScript("OnLeave", GameTooltip_Hide)
    sellBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            addon:OpenOptions()
            return
        end
        addon.RunAutoVendorSellNow()
    end)
    f.banbiSellZoneButton = sellBtn

    local chestBtn = CreateFrame("Button", "ElvUI_Banbi_BagChestButton", f.holderFrame)
    StyleElvBagButton(chestBtn, "Interface\\Icons\\INV_Misc_Bag_07")
    chestBtn:Point("RIGHT", sellBtn, "LEFT", -5, 0)
    chestBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    chestBtn:SetScript("OnEnter", function(self)
        RefreshBagButtonTooltips()
        BagTooltipShow(self)
    end)
    chestBtn:SetScript("OnLeave", GameTooltip_Hide)
    chestBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            StopChestOpen(false)
        else
            StartChestOpen()
        end
    end)
    f.banbiChestButton = chestBtn

    if f.editBox and f.editBox.ClearAllPoints then
        -- Keep ElvUI search box ending at our leftmost button.
        f.editBox:ClearAllPoints()
        f.editBox:Point("BOTTOMLEFT", f.holderFrame, "TOPLEFT", (E.Border * 2) + 18, E.Border * 2 + 2)
        f.editBox:Point("RIGHT", chestBtn, "LEFT", -5, 0)
        if f.editBox.backdrop then
            f.editBox.backdrop:ClearAllPoints()
            f.editBox.backdrop:Point("TOPLEFT", f.editBox, "TOPLEFT", -20, 2)
            f.editBox.backdrop:Point("BOTTOMRIGHT", f.editBox, "BOTTOMRIGHT", 0, -2)
        end
    end

    RefreshBagButtonTooltips()
    bagButtonsAttached = true
    return true
end

local function HideBagButtons()
    local B = GetBagsModule()
    local f = B and B.BagFrame
    if not f then
        return
    end
    if f.banbiChestButton then
        f.banbiChestButton:Hide()
    end
    if f.banbiSellZoneButton then
        f.banbiSellZoneButton:Hide()
    end
end

local function EnsureBagButtons()
    if AttachBagButtons() then
        return
    end
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            if active then
                AttachBagButtons()
            end
        end, 1)
        addon.core:ScheduleTimer(function()
            if active then
                AttachBagButtons()
            end
        end, 3)
    end
end

local function OnMerchantShow()
    if not active then
        return
    end

    merchantOpen = true
    -- Sell/destroy is manual only (bag "Sell Zone" button) for safety.
    -- Opening a merchant never auto-sells.
    ClearQueue()
    StopTicker()

    if not BuyEnabled() then
        return
    end

    boughtThisVisit = false
    warnedCursor = false
    session = NewSession()

    if IsBuySellTab() then
        RunBuyRestock()
        PrintSummary()
    end
end

local function OnMerchantClosed()
    merchantOpen = false
    AbortPendingDestroy(nil)
    StopTicker()
    ClearQueue()
    PrintSummary()
    boughtThisVisit = true
end

local function EnsureFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame", "ElvUI_Banbi_AutoVendor")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            OnMerchantShow()
        elseif event == "MERCHANT_CLOSED" then
            OnMerchantClosed()
        end
    end)
    return eventFrame
end

local function RegisterChestSlash()
    if chestSlashRegistered then
        return
    end
    chestSlashRegistered = true
    if addon.core and addon.core.RegisterChatCommand then
        addon.core:RegisterChatCommand("banbichest", function(input)
            input = string.lower(tostring(input or ""))
            if find(input, "stop", 1, true) then
                StopChestOpen(false)
            else
                StartChestOpen()
            end
        end)
    end
end

local function OnEnable()
    active = true
    SyncListsFromText()
    EnsureFrame()
    eventFrame:RegisterEvent("MERCHANT_SHOW")
    eventFrame:RegisterEvent("MERCHANT_CLOSED")
    RegisterChestSlash()
    EnsureBagButtons()

    if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
        OnMerchantShow()
    end
end

local function OnDisable()
    active = false
    merchantOpen = false
    AbortPendingDestroy(nil)
    StopTicker()
    ClearQueue()
    StopChestOpen(true)
    HideBagButtons()
    if eventFrame then
        eventFrame:UnregisterEvent("MERCHANT_SHOW")
        eventFrame:UnregisterEvent("MERCHANT_CLOSED")
    end
end

addon:RegisterFeature(KEY, {
    category = "vendor",
    default = true,
    label = function()
        return L["Auto Vendor"] or "自动购卖"
    end,
    desc = function()
        return L["Auto Vendor Desc"]
            or "补货可在打开商人时自动进行；出售/摧毁仅由背包「出售区」按钮手动触发。开箱为全账号配置。"
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(
            section,
            L["Auto Vendor Help"]
                or "出售/摧毁仅由背包「出售区」按钮手动触发。白名单物品、装等 284 及以上、以及箱子本身永不出售/摧毁。流程：开箱 → 开商人 → 点出售区。"
        )
        C:AddDescription(
            section,
            L["Auto Vendor protect list"]
                or "永不出售/摧毁：白名单 60407, 64820, 64149, 69496, 69508, 69502, 60408, 64821, 64150, 69501, 65282（艾泽里特）；装等 284 及以上；宝箱本身（默认 64827，以及设置中的开箱 ID）。"
        )

        C:AddDescription(section, L["Auto Vendor: chest header"] or "|cff1784d1开箱（全账号）|r")
        C:AddEditBox(section, {
            label = L["Chest item ID"] or "宝箱物品 ID",
            desc = L["Chest item ID desc"] or "默认 64827（艾泽拉斯传奇宝箱）。全角色共用。",
            getFunc = function()
                local cfg = ChestCfg()
                return tostring((cfg and cfg.itemID) or DEFAULT_CHEST_ID)
            end,
            setFunc = function(val)
                local cfg = ChestCfg()
                if cfg then
                    cfg.itemID = tonumber(val) or DEFAULT_CHEST_ID
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Chest open interval"] or "开箱间隔",
            desc = L["Chest open interval desc"] or "每只宝箱之间的间隔（秒）。拾取由游戏自动完成。",
            min = 0.1,
            max = 1.5,
            step = 0.05,
            getFunc = function()
                local cfg = ChestCfg()
                return (cfg and tonumber(cfg.interval)) or 0.4
            end,
            setFunc = function(val)
                local cfg = ChestCfg()
                if cfg then
                    cfg.interval = val
                end
            end,
        })
        C:AddSelect(section, {
            label = L["Chest scan order"] or "开箱扫描顺序",
            values = {
                asc = L["Scan order: ascending"] or "正序（背包 0→4）",
                desc = L["Scan order: descending"] or "倒序（背包 4→0）",
            },
            getFunc = function()
                local cfg = ChestCfg()
                return (cfg and cfg.scanOrder == "desc") and "desc" or "asc"
            end,
            setFunc = function(val)
                local cfg = ChestCfg()
                if cfg then
                    cfg.scanOrder = (val == "desc") and "desc" or "asc"
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Chest scan slot limit"] or "开箱扫描格数上限",
            desc = L["Chest scan slot limit desc"] or "开箱时只扫前 N 格；0 表示扫完全部背包。",
            min = 0,
            max = 200,
            step = 1,
            getFunc = function()
                local cfg = ChestCfg()
                return (cfg and tonumber(cfg.scanSlotLimit)) or 0
            end,
            setFunc = function(val)
                local cfg = ChestCfg()
                if cfg then
                    cfg.scanSlotLimit = val
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Chest chat feedback"] or "开箱聊天反馈",
            getFunc = function()
                local cfg = ChestCfg()
                return not cfg or cfg.chatFeedback ~= false
            end,
            setFunc = function(val)
                local cfg = ChestCfg()
                if cfg then
                    cfg.chatFeedback = val and true or false
                end
            end,
        })
        C:AddDescription(
            section,
            L["Chest open via bag"]
                or "开箱请用 ElvUI 背包栏按钮（左键开始 / 右键停止），或命令 /banbichest、/banbichest stop。"
        )

        C:AddDescription(section, L["Auto Vendor: sell header"] or "|cff1784d1贩卖 / 补货（按角色）|r")
        C:AddToggle(section, {
            label = L["Enable auto sell/destroy"] or "启用出售区清理",
            desc = L["Enable auto sell/destroy desc"]
                or "允许使用背包「出售区」按钮手动卖出/摧毁。打开商人时不会自动出售，需你亲自点按钮。",
            getFunc = function()
                local cfg = Cfg()
                return not cfg or cfg.sellEnabled ~= false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.sellEnabled = val and true or false
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Enable auto buy"] or "启用自动补货",
            desc = L["Enable auto buy desc"]
                or "打开商人时先按主脑任务内置规划补货，再按下方采购清单购买额外物品。可日常保持开启。",
            getFunc = function()
                local cfg = Cfg()
                return not cfg or cfg.buyEnabled ~= false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.buyEnabled = val and true or false
                end
            end,
        })
        C:AddSelect(section, {
            label = L["Scan order"] or "扫描顺序",
            desc = L["Scan order desc"]
                or "出售区与贩卖列表按此顺序数格子（空格也计入）。默认正序与整理背包填充方向一致（行囊 0 → 扩展包 4）。",
            values = {
                asc = L["Scan order: ascending"] or "正序（背包 0→4）",
                desc = L["Scan order: descending"] or "倒序（背包 4→0）",
            },
            getFunc = function()
                local cfg = Cfg()
                local order = cfg and cfg.scanOrder or "asc"
                if order ~= "desc" then
                    order = "asc"
                end
                return order
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.scanOrder = (val == "desc") and "desc" or "asc"
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Scan slot limit"] or "扫描格数上限",
            desc = L["Scan slot limit desc"]
                or "只扫描顺序中的前 N 格（空格也计 1）。贩卖列表与出售区都不会超出此范围。默认 80，更安全；0 表示不限制（扫完全部背包）。",
            min = 0,
            max = 200,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                local v = cfg and tonumber(cfg.scanSlotLimit)
                if v == nil then
                    return 80
                end
                return v
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.scanSlotLimit = val
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Sell zone slots"] or "出售区格数",
            desc = L["Sell zone slots desc"]
                or "扫描范围内前 N 格为出售区（空格也计 1）。超过「扫描格数上限」时自动截断。0 为关闭出售区。",
            min = 0,
            max = 120,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and tonumber(cfg.sellZoneSlots)) or 0
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.sellZoneSlots = val
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Destroy unsellable"] or "摧毁无法出售的物品",
            desc = L["Destroy unsellable desc"]
                or "危险：仅对出售区内卖价为 0 的非任务物品永久删除，默认关闭，请慎重开启。出售区外即使卖价为 0 也不会摧毁。",
            getFunc = function()
                local cfg = Cfg()
                return cfg and cfg.destroyUnsellable and true or false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.destroyUnsellable = val and true or false
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Max corruption"] or "腐蚀阈值",
            desc = L["Max corruption desc"]
                or "腐蚀大于此值的物品不卖也不摧毁。工具提示中没有「+N 腐蚀」视为 0。",
            min = 0,
            max = 100,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and tonumber(cfg.maxCorruption)) or 0
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.maxCorruption = val
                end
            end,
        })
        C:AddSlider(section, {
            label = L["Sell interval"] or "出售间隔",
            desc = L["Sell interval desc"] or "每件出售或摧毁之间的间隔（秒）。",
            min = 0.05,
            max = 1.0,
            step = 0.05,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and tonumber(cfg.sellInterval)) or 0.2
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.sellInterval = val
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Chat feedback"] or "聊天栏反馈",
            desc = L["Chat feedback desc"] or "交易结束后在聊天栏显示售出、摧毁和购入的摘要。",
            getFunc = function()
                local cfg = Cfg()
                return not cfg or cfg.chatFeedback ~= false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.chatFeedback = val and true or false
                end
            end,
        })
        C:AddEditBox(section, {
            label = L["Sell list"] or "贩卖列表",
            desc = L["Sell list desc"]
                or "每行一件：Shift-点击物品链接，或直接填写物品 ID。例如 6948 或 item:6948:0:0:0。",
            multiline = true,
            width = "full",
            getFunc = function()
                local cfg = Cfg()
                return (cfg and cfg.sellListText) or ""
            end,
            setFunc = function(val)
                ApplyListText("sell", val)
            end,
        })
        C:AddDescription(section, (function()
            local parts = {}
            local preset = addon.autoVendorBrainQuestBuyList
            if type(preset) == "table" then
                local rows = {}
                for id, count in pairs(preset) do
                    rows[#rows + 1] = { id = id, count = count }
                end
                table.sort(rows, function(a, b)
                    return a.id < b.id
                end)
                for i = 1, #rows do
                    parts[i] = rows[i].id .. "×" .. rows[i].count
                end
            end
            return L["Auto Vendor: brain quest buy"]
                or ("|cff1784d1主脑任务内置补货（固定）|r\n" .. table.concat(parts, "，")
                    .. "\n打开商人时自动按上表补货，不必填入下方清单。同 ID 以采购清单为准。")
        end)())
        C:AddEditBox(section, {
            label = L["Buy list"] or "采购清单",
            desc = L["Buy list desc"]
                or "仅填写额外要买的物品。每行一件：物品链接或 ID，空格，然后是目标数量。主脑任务规划已内置，不必重复填写；同 ID 以本清单为准。Shift-点击可插入链接。",
            multiline = true,
            width = "full",
            getFunc = function()
                local cfg = Cfg()
                return (cfg and cfg.buyListText) or ""
            end,
            setFunc = function(val)
                ApplyListText("buy", val)
            end,
        })
    end,
})
