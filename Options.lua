-- ElvUI_Banbi — inject into ElvUI options.

local ADDON_NAME, addon = ...
local L = addon.L

local EP = LibStub("LibElvUIPlugin-1.0", true)

-- ---------------------------------------------------------------------------
-- AceConfig adapter for module BuildOptions (C:AddToggle / AddSlider / ...)
-- ---------------------------------------------------------------------------

local function NewOptionBuilder(args, startOrder)
    local order = startOrder or 1
    local C = {}

    local function nextOrder()
        order = order + 1
        return order
    end

    local function nextKey(prefix)
        return (prefix or "opt") .. nextOrder()
    end

    function C:AddDescription(section, text)
        local key = nextKey("desc")
        args[key] = {
            type = "description",
            name = text or "",
            order = order,
        }
    end

    function C:AddToggle(section, opt)
        local key = nextKey("toggle")
        local entry = {
            type = "toggle",
            name = opt.label or key,
            desc = opt.desc,
            order = order,
            get = function()
                return opt.getFunc and opt.getFunc() and true or false
            end,
            set = function(_, value)
                if opt.setFunc then
                    opt.setFunc(value and true or false)
                end
            end,
        }
        if opt.disabled then
            entry.disabled = opt.disabled
        end
        args[key] = entry
    end

    function C:AddSlider(section, opt)
        local key = nextKey("slider")
        local entry = {
            type = "range",
            name = opt.label or key,
            desc = opt.desc,
            order = order,
            min = opt.min or 0,
            max = opt.max or 100,
            step = opt.step or 1,
            get = function()
                return opt.getFunc and opt.getFunc() or opt.min or 0
            end,
            set = function(_, value)
                if opt.setFunc then
                    opt.setFunc(value)
                end
            end,
        }
        if opt.disabled then
            entry.disabled = opt.disabled
        end
        args[key] = entry
    end

    function C:AddEditBox(section, opt)
        local key = nextKey("input")
        local entry = {
            type = "input",
            name = opt.label or key,
            desc = opt.desc,
            order = order,
            get = function()
                return opt.getFunc and tostring(opt.getFunc() or "") or ""
            end,
            set = function(_, value)
                if opt.setFunc then
                    opt.setFunc(value)
                end
            end,
        }
        if opt.disabled then
            entry.disabled = opt.disabled
        end
        args[key] = entry
    end

    function C:AddButton(section, opt)
        local key = nextKey("btn")
        local entry = {
            type = "execute",
            name = opt.label or key,
            desc = opt.desc,
            order = order,
            func = function()
                if opt.callback then
                    opt.callback()
                end
            end,
        }
        if opt.disabled then
            entry.disabled = opt.disabled
        end
        args[key] = entry
    end

    function C:AddColorPicker(section, opt)
        local key = nextKey("color")
        local entry = {
            type = "color",
            name = opt.label or key,
            desc = opt.desc,
            order = order,
            hasAlpha = false,
            get = function()
                if not opt.getFunc then
                    return 1, 1, 1
                end
                local r, g, b = opt.getFunc()
                return r or 1, g or 1, b or 1
            end,
            set = function(_, r, g, b)
                if opt.setFunc then
                    opt.setFunc(r, g, b)
                end
            end,
        }
        if opt.disabled then
            entry.disabled = opt.disabled
        end
        args[key] = entry
    end

    function C:GetOrder()
        return order
    end

    return C
end

local function FeatureToggle(key, order)
    local def = addon:GetFeature(key)
    local label = def and def.label and def.label() or key
    local desc = def and def.desc and def.desc() or ""
    return {
        type = "toggle",
        name = string.format(L["Enable %s"] or "Enable %s", label),
        desc = desc,
        order = order,
        get = function()
            return addon:IsFeatureEnabled(key)
        end,
        set = function(_, value)
            addon:SetFeatureEnabled(key, value)
            if def and def.Refresh then
                def.Refresh()
            end
        end,
    }
end

local function AppendFeatureSection(args, key, startOrder)
    local def = addon:GetFeature(key)
    if not def then
        return startOrder
    end

    local order = startOrder
    local label = def.label and def.label() or key

    args[key .. "Header"] = {
        type = "header",
        name = label,
        order = order,
    }
    order = order + 1

    args[key .. "Enable"] = FeatureToggle(key, order)
    order = order + 1

    if type(def.BuildOptions) == "function" then
        local C = NewOptionBuilder(args, order)
        def.BuildOptions(args, C)
        order = C:GetOrder() + 1
    end

    return order + 1
end

local function AppendLegacySection(args, startOrder)
    local order = startOrder
    args.legacyHeader = {
        type = "header",
        name = L["Legacy AddOns"] or "Legacy",
        order = order,
    }
    order = order + 1
    args.legacyDesc = {
        type = "description",
        name = L["Disable these folders after Banbi covers them. SavedVariables are not deleted."] or "",
        order = order,
    }
    order = order + 1
    args.legacyRecheck = {
        type = "execute",
        name = L["Recheck conflicting addons"] or "Recheck",
        order = order,
        func = function()
            if addon.ReportLegacyAddons then
                addon:ReportLegacyAddons(true)
            end
        end,
    }
    return order + 1
end

local function BuildTabFromFeatures(name, tabOrder, featureKeys, withLegacy)
    local args = {}
    local order = 1
    for i = 1, #featureKeys do
        order = AppendFeatureSection(args, featureKeys[i], order)
    end
    if withLegacy then
        AppendLegacySection(args, math.max(order, 90))
    end
    return {
        type = "group",
        name = name,
        order = tabOrder,
        args = args,
    }
end

local function BuildOptions()
    return {
        type = "group",
        name = "|cff1784d1" .. (L["Enhance [by Banbi]"] or "增强[by 斑比]") .. "|r",
        order = 85,
        childGroups = "tab",
        args = {
            general = BuildTabFromFeatures(L["General"] or "General", 1, {
                "motionSpeed",
                "tokenBar",
            }, true),
            chat = BuildTabFromFeatures(L["Chat"] or "Chat", 2, {
                "chatEnhance",
            }, false),
            equipment = BuildTabFromFeatures(L["Equipment"] or "Equipment", 3, {
                "inspectPanel",
                "itemInfo", -- 未进 TOC 时 GetFeature 为 nil，分区自动跳过
                "equipmentHelper",
            }, false),
            combat = BuildTabFromFeatures(L["Combat"] or "Combat", 4, {
                "runeBar",
                "astralEnhance",
                "autoTrack",
            }, false),
            social = BuildTabFromFeatures(L["Social"] or "Social", 5, {
                "friendSync",
                "friendsMenuXP",
            }, false),
        },
    }
end

function addon:RegisterOptions()
    local function inject()
        local E = addon:GetE()
        if not E then return end
        if not E.Options then E.Options = {} end
        if not E.Options.args then E.Options.args = {} end
        E.Options.args.banbi = BuildOptions()
    end

    if EP then
        EP:RegisterPlugin(ADDON_NAME, inject)
    else
        inject()
    end
end
