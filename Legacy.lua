-- ElvUI_Banbi — superseded standalone addons checklist.

local ADDON_NAME, addon = ...
local L = addon.L

local LEGACY = {
    { name = "MotionSpeed", noteKey = "legacy_MotionSpeed" },
    { name = "ChatBar", noteKey = "legacy_ChatBar" },
    { name = "FriendsMenuXP", noteKey = "legacy_FriendsMenuXP" },
    { name = "ElvUI_TinyInspect", noteKey = "legacy_TinyInspect" },
    { name = "ElvUI_bbTools", noteKey = "legacy_bbTools" },
    { name = "BagSync", noteKey = "legacy_BagSyncToken", soft = true },
}

local function AddonPresent(name)
    local _, _, _, enabled, loadable, reason = GetAddOnInfo(name)
    if reason == "MISSING" then
        return false, false
    end
    local loaded = IsAddOnLoaded(name)
    local on = loaded or (enabled ~= nil and enabled ~= 0 and enabled ~= false)
    return true, on or loaded
end

function addon:GetLegacyAddonList()
    return LEGACY
end

function addon:ScanLegacyAddons()
    local active = {}
    for i = 1, #LEGACY do
        local entry = LEGACY[i]
        local present, on = AddonPresent(entry.name)
        if present and on then
            -- BagSync: only warn if TokenBar frame/DB exists (bag search alone is fine)
            if entry.name == "BagSync" then
                if _G.BagSync_TokenBar or _G.BagSyncTokenBarDB then
                    active[#active + 1] = entry
                end
            else
                active[#active + 1] = entry
            end
        end
    end
    return active
end

function addon:ReportLegacyAddons(force)
    local active = self:ScanLegacyAddons()
    if #active == 0 then
        if force then
            print("|cff00ff00[Banbi]|r " .. (L["No conflicting standalone addons detected."] or "None."))
        end
        return active
    end

    print("|cffff8000[Banbi]|r " .. (L["These standalone addons overlap with Banbi — disable them to avoid double hooks:"] or "Overlap:"))
    for i = 1, #active do
        local e = active[i]
        local note = L[e.noteKey] or e.name
        print(string.format("  - |cffffffff%s|r → %s", e.name, note))
    end
    return active
end

function addon:MaybeWarnLegacyAddons()
    self:ReportLegacyAddons(false)
end
