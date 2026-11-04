-- ElvUI_Banbi — show "+N" corruption on ElvUI bag/bank item icons (TOPRIGHT).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "bagCorruption"
local CORRUPTION_PATTERN = "%+(%d+)%s*腐蚀"
local CORRUPTION_COLOR = { 0.58, 0.40, 0.90 }

local format = string.format
local gsub = string.gsub
local match = string.match
local tonumber = tonumber

local active = false
local hooked = false
local scanTip

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function StripColors(text)
    if not text then
        return ""
    end
    text = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = gsub(text, "|r", "")
    return text
end

local function EnsureScanTip()
    if scanTip then
        return scanTip
    end
    scanTip = CreateFrame("GameTooltip", "ElvUI_Banbi_CorruptionTip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

local function GetBags()
    local E = addon:GetE()
    if not E then
        return nil
    end
    return E:GetModule("Bags", true)
end

local function ApplyFont(fs)
    if not fs then
        return
    end
    local E = addon:GetE()
    local font = STANDARD_TEXT_FONT
    local size = 10
    local outline = "OUTLINE"
    if E and E.db and E.db.bags then
        local bags = E.db.bags
        if E.Libs and E.Libs.LSM and bags.itemLevelFont then
            font = E.Libs.LSM:Fetch("font", bags.itemLevelFont) or font
        end
        size = bags.itemLevelFontSize or size
        outline = bags.itemLevelFontOutline or outline
    end
    local cfg = Cfg()
    if cfg and cfg.fontSize and cfg.fontSize > 0 then
        size = cfg.fontSize
    end
    if fs.FontTemplate then
        fs:FontTemplate(font, size, outline)
    else
        fs:SetFont(font, size, outline)
    end
end

local function EnsureOverlay(slot)
    local fs = slot.banbiCorruption
    if fs then
        return fs
    end
    fs = slot:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPRIGHT", -1, -2)
    fs:SetJustifyH("RIGHT")
    slot.banbiCorruption = fs
    ApplyFont(fs)
    return fs
end

local function ClearOverlay(slot)
    if slot and slot.banbiCorruption then
        slot.banbiCorruption:SetText("")
    end
end

local function ScanCorruption(slot, bagID, slotID)
    local tip = EnsureScanTip()
    tip:ClearLines()
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    if slot.GetInventorySlot then
        tip:SetInventoryItem("player", slot:GetInventorySlot())
    else
        tip:SetBagItem(bagID, slotID)
    end

    local value
    local num = tip:NumLines() or 0
    for i = 2, num do
        local line = _G["ElvUI_Banbi_CorruptionTipTextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" then
            local n = match(StripColors(text), CORRUPTION_PATTERN)
            if n then
                value = tonumber(n)
                break
            end
        end
    end
    tip:Hide()
    return value
end

local function UpdateSlotCorruption(bagFrame, bagID, slotID)
    local B = GetBags()
    if not B or not bagFrame or not bagFrame.Bags then
        return
    end
    local bag = bagFrame.Bags[bagID]
    local slot = bag and bag[slotID]
    if not slot then
        return
    end

    if not active then
        ClearOverlay(slot)
        return
    end

    local link = GetContainerItemLink(bagID, slotID)
    if not link then
        ClearOverlay(slot)
        return
    end

    -- Skip known non-equipment before tooltip scan (nil equipLoc = uncached; still scan).
    local equipLoc = select(9, GetItemInfo(link))
    if equipLoc == "" or equipLoc == "INVTYPE_BAG" or equipLoc == "INVTYPE_QUIVER" or equipLoc == "INVTYPE_AMMO" or equipLoc == "INVTYPE_TABARD" then
        ClearOverlay(slot)
        return
    end

    local value = ScanCorruption(slot, bagID, slotID)
    if not value then
        ClearOverlay(slot)
        return
    end

    local fs = EnsureOverlay(slot)
    ApplyFont(fs)
    fs:SetText(format("+%d", value))
    fs:SetTextColor(CORRUPTION_COLOR[1], CORRUPTION_COLOR[2], CORRUPTION_COLOR[3])
end

local function RefreshAll()
    local B = GetBags()
    -- BagFrames is nil until ElvUI bags finish constructing; calling UpdateAllBagSlots then errors.
    if B and B.BagFrames and B.UpdateAllBagSlots then
        B:UpdateAllBagSlots()
    end
end

local function InstallHook()
    if hooked then
        return true
    end
    local B = GetBags()
    if not B or not B.UpdateSlot then
        return false
    end
    hooked = true
    hooksecurefunc(B, "UpdateSlot", function(_, bagFrame, bagID, slotID)
        UpdateSlotCorruption(bagFrame, bagID, slotID)
    end)
    return true
end

local function OnEnable()
    active = true
    if InstallHook() then
        RefreshAll()
        return
    end
    -- Bags module may not be ready yet; retry shortly. Skip RefreshAll until BagFrames exists.
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            if not active then
                return
            end
            InstallHook()
            RefreshAll()
        end, 1)
    end
end

local function OnDisable()
    active = false
    RefreshAll()
end

addon:RegisterFeature(KEY, {
    category = "equipment",
    default = true,
    label = function()
        return L["Bag Corruption"]
    end,
    desc = function()
        return L["Show item corruption (+N) on bag and bank icons."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = RefreshAll,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Shows +N in the top-right of ElvUI bag/bank equipment icons when the tooltip has「+N 腐蚀」."])
        C:AddSlider(section, {
            label = L["Font Size"],
            desc = L["0 = follow ElvUI bag item level font size."],
            min = 0,
            max = 18,
            step = 1,
            getFunc = function()
                local cfg = Cfg()
                return (cfg and cfg.fontSize) or 0
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.fontSize = val
                end
                RefreshAll()
            end,
        })
    end,
})
