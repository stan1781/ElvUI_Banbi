-- ElvUI_Banbi — bootstrap, feature registry, slash commands.

local ADDON_NAME, addon = ...

addon._dir = "Interface\\AddOns\\ElvUI_Banbi\\"
_G.ElvUI_Banbi = addon

addon.media = {
    root = addon._dir,
    textures = addon._dir .. "Textures\\",
    emotion = addon._dir .. "Media\\Emotion\\",
    icons = {
        dash = "Interface\\Icons\\Ability_Druid_Dash",
    },
}

local L = LibStub("AceLocale-3.0"):GetLocale("ElvUI_Banbi", true)
addon.L = L

-- ---------------------------------------------------------------------------
-- Feature registry
-- ---------------------------------------------------------------------------

local features = {}
local featureOrder = {}

function addon:RegisterFeature(key, def)
    if not key or type(def) ~= "table" then
        return
    end
    if not features[key] then
        featureOrder[#featureOrder + 1] = key
    end
    def.key = key
    def.category = def.category or "general"
    if def.default == nil then
        def.default = true
    end
    features[key] = def

    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.features
    if defaults and not defaults[key] then
        defaults[key] = { enabled = def.default and true or false }
    end
end

function addon:GetFeature(key)
    return features[key]
end

function addon:GetRegisteredFeatures()
    local list = {}
    for i = 1, #featureOrder do
        list[#list + 1] = features[featureOrder[i]]
    end
    return list
end

function addon:GetFeaturesByCategory(category)
    local list = {}
    for i = 1, #featureOrder do
        local def = features[featureOrder[i]]
        if def and def.category == category and not def.optionsHidden then
            list[#list + 1] = def
        end
    end
    return list
end

function addon:GetFeatureConfig(key)
    if not addon.db or not addon.db.profile then
        return nil
    end
    local feats = addon.db.profile.features
    if not feats then
        feats = {}
        addon.db.profile.features = feats
    end
    local cfg = feats[key]
    if type(cfg) ~= "table" then
        local def = features[key]
        cfg = { enabled = def and def.default ~= false }
        feats[key] = cfg
    end
    return cfg
end

function addon:IsFeatureEnabled(key)
    local cfg = self:GetFeatureConfig(key)
    return cfg and cfg.enabled and true or false
end

function addon:StartFeature(key)
    local def = features[key]
    if not def then
        return false
    end
    if def._active then
        return true
    end
    if type(def.OnEnable) == "function" then
        local ok, err = pcall(def.OnEnable, def)
        if not ok then
            geterrorhandler()("ElvUI_Banbi StartFeature(" .. tostring(key) .. "): " .. tostring(err))
            return false
        end
    end
    def._active = true
    return true
end

function addon:StopFeature(key)
    local def = features[key]
    if not def then
        return false
    end
    if not def._active then
        return true
    end
    if type(def.OnDisable) == "function" then
        local ok, err = pcall(def.OnDisable, def)
        if not ok then
            geterrorhandler()("ElvUI_Banbi StopFeature(" .. tostring(key) .. "): " .. tostring(err))
        end
    end
    def._active = false
    return true
end

function addon:EnableFeature(key)
    local cfg = self:GetFeatureConfig(key)
    if cfg then
        cfg.enabled = true
    end
    return self:StartFeature(key)
end

function addon:DisableFeature(key)
    local cfg = self:GetFeatureConfig(key)
    if cfg then
        cfg.enabled = false
    end
    return self:StopFeature(key)
end

function addon:SetFeatureEnabled(key, enabled)
    if enabled then
        return self:EnableFeature(key)
    end
    return self:DisableFeature(key)
end

function addon:ApplyAllFeatures()
    for i = 1, #featureOrder do
        local key = featureOrder[i]
        local def = features[key]
        if def and def.linkedTo then
            -- started by parent
        elseif self:IsFeatureEnabled(key) then
            self:StartFeature(key)
        else
            self:StopFeature(key)
        end
    end
end

function addon:GetE()
    if not ElvUI then
        return nil
    end
    return unpack(ElvUI)
end

function addon:OpenOptions()
    local E = self:GetE()
    if not E then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cff1784d1Banbi|r " .. (L["Cannot open options during combat."] or "Cannot open options during combat."))
        return
    end
    E:ToggleOptionsUI("banbi")
end

-- ---------------------------------------------------------------------------
-- AceAddon lifecycle
-- ---------------------------------------------------------------------------

addon.core = LibStub("AceAddon-3.0"):NewAddon(
    "ElvUI_Banbi",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)

function addon.core:OnInitialize()
    addon.db = LibStub("AceDB-3.0"):New("ElvUI_BanbiDB", addon.defaults, true)

    if addon.Migrate then
        addon:Migrate()
    end

    self:RegisterChatCommand("banbi", function()
        addon:OpenOptions()
    end)
    self:RegisterChatCommand("banbilegacy", function()
        if addon.ReportLegacyAddons then
            addon:ReportLegacyAddons(true)
        end
    end)

    addon.db.RegisterCallback(addon.core, "OnProfileChanged", "OnProfileRefresh")
    addon.db.RegisterCallback(addon.core, "OnProfileCopied", "OnProfileRefresh")
    addon.db.RegisterCallback(addon.core, "OnProfileReset", "OnProfileRefresh")

    if addon.RegisterOptions then
        addon:RegisterOptions()
    end
end

function addon.core:OnProfileRefresh()
    for i = 1, #featureOrder do
        addon:StopFeature(featureOrder[i])
    end
    addon:ApplyAllFeatures()
end

function addon.core:OnEnable()
    addon:ApplyAllFeatures()
    self:ScheduleTimer(function()
        if addon.MaybeWarnLegacyAddons then
            addon:MaybeWarnLegacyAddons()
        end
    end, 3)
end
