-- ElvUI_Banbi — Hunter auto tracking for Improved Tracking (WotLK 3.3.5).
-- Enter combat: remember current tracking, switch to target creature type.
-- Leave combat: restore previous tracking (ore/herb/none).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "autoTrack"

local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDead = UnitIsDead
local UnitCreatureType = UnitCreatureType
local UnitAffectingCombat = UnitAffectingCombat
local GetNumTrackingTypes = GetNumTrackingTypes
local GetTrackingInfo = GetTrackingInfo
local SetTracking = SetTracking
local InCombatLockdown = InCombatLockdown
local string_find = string.find

local eventFrame
local active = false
local savedTrackingIndex -- number or false (explicitly none); nil = not saved this combat
local hasSaved = false

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function IsHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

local function GetActiveTrackingIndex()
    local n = GetNumTrackingTypes and GetNumTrackingTypes() or 0
    for i = 1, n do
        local _, _, isActive = GetTrackingInfo(i)
        if isActive then
            return i
        end
    end
    return nil
end

local function ApplyTrackingIndex(index)
    if not SetTracking then
        return
    end
    if index then
        local _, _, isActive = GetTrackingInfo(index)
        if not isActive then
            SetTracking(index)
        end
        return
    end
    -- Clear to none (Blizzard minimap "None" uses nil).
    if GetActiveTrackingIndex() then
        SetTracking(nil)
    end
end

local function FindTrackingIndexForCreatureType(creatureType)
    if not creatureType or creatureType == "" then
        return nil
    end
    local n = GetNumTrackingTypes and GetNumTrackingTypes() or 0
    for i = 1, n do
        local name = GetTrackingInfo(i)
        if name and string_find(name, creatureType, 1, true) then
            return i
        end
    end
    return nil
end

local function ShouldTrackTarget()
    if not UnitExists("target") then
        return false
    end
    if UnitIsDead("target") then
        return false
    end
    if not UnitCanAttack("player", "target") then
        return false
    end
    return true
end

local function SwitchToTargetTracking()
    if not ShouldTrackTarget() then
        return
    end
    local creatureType = UnitCreatureType("target")
    local index = FindTrackingIndexForCreatureType(creatureType)
    if not index then
        return
    end
    ApplyTrackingIndex(index)
end

local function RememberTracking()
    if hasSaved then
        return
    end
    local idx = GetActiveTrackingIndex()
    if idx then
        savedTrackingIndex = idx
    else
        savedTrackingIndex = false
    end
    hasSaved = true
end

local function RestoreTracking()
    if not hasSaved then
        return
    end
    local cfg = Cfg()
    if cfg and cfg.restoreOutOfCombat == false then
        hasSaved = false
        savedTrackingIndex = nil
        return
    end
    if savedTrackingIndex == false then
        ApplyTrackingIndex(nil)
    else
        ApplyTrackingIndex(savedTrackingIndex)
    end
    hasSaved = false
    savedTrackingIndex = nil
end

local function OnCombatStart()
    if not IsHunter() then
        return
    end
    RememberTracking()
    SwitchToTargetTracking()
end

local function OnCombatEnd()
    if not IsHunter() then
        return
    end
    RestoreTracking()
end

local function OnTargetChanged()
    if not IsHunter() then
        return
    end
    if not (InCombatLockdown() or UnitAffectingCombat("player")) then
        return
    end
    if not hasSaved then
        RememberTracking()
    end
    SwitchToTargetTracking()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Drop stale restore state across zoning / reload mid-combat edge cases.
        if not (InCombatLockdown() or UnitAffectingCombat("player")) then
            hasSaved = false
            savedTrackingIndex = nil
        end
    end
end

local function EnsureFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame", "ElvUI_Banbi_AutoTrack")
    eventFrame:SetScript("OnEvent", OnEvent)
    return eventFrame
end

local function OnEnable()
    active = true
    hasSaved = false
    savedTrackingIndex = nil
    local f = EnsureFrame()
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    if IsHunter() and (InCombatLockdown() or UnitAffectingCombat("player")) then
        OnCombatStart()
    end
end

local function OnDisable()
    active = false
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if hasSaved and IsHunter() and not (InCombatLockdown() or UnitAffectingCombat("player")) then
        RestoreTracking()
    else
        hasSaved = false
        savedTrackingIndex = nil
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Auto Tracking"]
    end,
    desc = function()
        return L["Hunter only: in combat, auto-switch tracking to the target type for Improved Tracking; restore previous tracking after combat."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(
            section,
            L["Only works on Hunters. Switches Track Beasts/Demons/etc. to match your attackable target while in combat."]
        )
        C:AddToggle(section, {
            label = L["Restore tracking out of combat"],
            desc = L["When leaving combat, restore the tracking you had before the fight (e.g. herbs/minerals)."],
            getFunc = function()
                local cfg = Cfg()
                return not cfg or cfg.restoreOutOfCombat ~= false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.restoreOutOfCombat = val and true or false
                end
            end,
            disabled = function()
                return not IsHunter()
            end,
        })
    end,
})
