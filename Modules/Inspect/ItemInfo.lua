-- ElvUI_Banbi — Item source tooltips (from ElvUI_TinyInspect Tooltips + FindItem).
-- Does NOT port inspect/char equipment list windows (DragonUI already covers ilvl).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "itemInfo"
local gmatch = string.gmatch
local tinsert = table.insert
local tonumber = tonumber

local active = false
local hooked = false
local embJustice, embHeroism, embValor, embConquest, embTriumph, embFrost

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function IS()
    return _G.TinyInspect_ItemSources
end

local function MigrateFromTinyInspect()
    if not addon.db or not addon.db.global then return end
    local g = addon.db.global
    g.migrated = g.migrated or {}
    if g.migrated.tinyInspectTooltip then return end
    g.migrated.tinyInspectTooltip = true
    local old = _G.TinyInspectConfig
    if type(old) ~= "table" then return end
    local cfg = Cfg()
    if not cfg then return end
    if old.showUnknown ~= nil then
        cfg.showUnknown = old.showUnknown and true or false
    end
    if old.ttR then cfg.ttR = old.ttR end
    if old.ttG then cfg.ttG = old.ttG end
    if old.ttB then cfg.ttB = old.ttB end
end

local function RefreshEmblemNames()
    embJustice = GetItemInfo(29434) or embJustice or "公正徽章"
    embHeroism = GetItemInfo(40752) or embHeroism or "英雄纹章"
    embValor = GetItemInfo(40753) or embValor or "勇气纹章"
    embConquest = GetItemInfo(45624) or embConquest or "征服纹章"
    embTriumph = GetItemInfo(47241) or embTriumph or "凯旋纹章"
    embFrost = GetItemInfo(49426) or embFrost or "冰霜纹章"
end

local srctypes_d = {
    ["n"] = function() return L["Normal"] end,
    ["h"] = function() return L["Heroic"] end,
    ["q"] = function() return L["Quest Reward"] end,
}
local srctypes_r = {
    ["N"] = function() return L["Heroic"] end,
    ["H"] = function() return L["Heroic"] end,
    ["q"] = function() return L["Quest Reward"] end,
    ["Q"] = function() return L["Quest Reward"] end,
}
local pvptypes = {
    ["m"] = function() return L["Accessories"] end,
    ["l"] = function() return L["Low level PvP"] end,
    ["w"] = function() return L["World PvP"] end,
    ["s1"] = function() return L["Season 1"] end,
    ["s2"] = function() return L["Season 2"] end,
    ["s3"] = function() return L["Season 3"] end,
    ["s4"] = function() return L["Season 4"] end,
    ["s5"] = function() return L["Season 5"] end,
    ["s6"] = function() return L["Season 6"] end,
    ["s7"] = function() return L["Season 7"] end,
    ["s8"] = function() return L["Season 8"] end,
    ["g"] = function() return L["Lake Wintergrasp"] end,
}

local function FindItem(itemLink, includeUnknown)
    local db = IS()
    if not db or not db.Items then return nil end
    local id = tonumber(itemLink:match("item:(%d+)"))
    if not id then return nil end

    local data = db.Items[id]
    if data then
        local sources = {}
        for entry in gmatch(data, "[^;]+") do
            local next_field = gmatch(entry, "[^_]+")
            local cat = next_field()

            if cat == "r" or cat == "d" then
                local catname = (cat == "r") and L["Raid"] or L["Instances"]
                local zoneId = tonumber(next_field() or 0)
                local zone = db.Zones[zoneId]
                local lootTable = next_field()
                local srctype
                if cat == "r" then
                    local f = srctypes_r[lootTable]
                    srctype = f and f()
                    if lootTable == "n" or lootTable == "N" or lootTable == "q" then
                        zone = (zone or "?") .. "-10"
                    elseif lootTable == "h" or lootTable == "H" or lootTable == "Q" then
                        zone = (zone or "?") .. "-25"
                    elseif lootTable == "4" then
                        zone = (zone or "?") .. "-40"
                    end
                else
                    local f = srctypes_d[lootTable]
                    srctype = f and f()
                end
                local boss = db.Bosses[tonumber(next_field() or 0)]
                local setname = next_field()
                if setname == "+" then
                    setname = L["Hard mode"]
                end
                tinsert(sources, { catname, zone, srctype, boss, nil, setname })
            elseif cat == "j" then
                tinsert(sources, { L["Emblem rewards"], embJustice, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "h" then
                tinsert(sources, { L["Emblem rewards"], embHeroism, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "v" then
                tinsert(sources, { L["Emblem rewards"], embValor, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "u" then
                tinsert(sources, { L["Emblem rewards"], embConquest, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "i" then
                tinsert(sources, { L["Emblem rewards"], embTriumph, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "o" then
                tinsert(sources, { L["Emblem rewards"], embFrost, nil, nil, tonumber(next_field()), next_field() })
            elseif cat == "t" then
                tinsert(sources, { L["Argent Tournament"], nil, nil, nil, tonumber(next_field()) })
            elseif cat == "c" then
                local prof = GetSpellInfo(tonumber(next_field() or "0"))
                tinsert(sources, { L["Crafted"], nil, nil, prof })
            elseif cat == "f" then
                tinsert(sources, { L["Reputation rewards"] })
            elseif cat == "e" then
                tinsert(sources, { L["World events"] })
            elseif cat == "m" then
                tinsert(sources, { L["Darkmoon Faire"] })
            elseif cat == "g" then
                tinsert(sources, { L["Vendor"] })
            elseif cat == "p" then
                local key = next_field()
                local f = pvptypes[key]
                tinsert(sources, { L["PvP"], f and f() })
            end
        end
        if #sources > 0 then
            return sources
        end
    elseif includeUnknown then
        local _, _, rarity = GetItemInfo(id)
        if rarity and rarity >= 2 then
            return { { L["Unknown"] } }
        end
    end
    return nil
end

-- Compact one-line source for the equipment list panel (TinyInspect MyFindItem).
local function FormatLootString(itemLink, includeUnknown)
    local db = IS()
    if not db or not db.Items then return nil end
    local id = tonumber(itemLink:match("item:(%d+)"))
    if not id then return nil end
    local data = db.Items[id]
    if not data then
        if includeUnknown then
            local _, _, rarity = GetItemInfo(id)
            if rarity and rarity >= 2 then
                return L["Unknown"]
            end
        end
        return nil
    end
    local lootString
    for entry in gmatch(data, "[^;]+") do
        local next_field = gmatch(entry, "[^_]+")
        local cat = next_field()
        if cat == "r" or cat == "d" then
            local zoneId = tonumber(next_field() or 0)
            local zone = db.Zones[zoneId] or "?"
            local lootTable = next_field()
            local srctype
            if cat == "r" then
                local f = srctypes_r[lootTable]
                srctype = f and f()
                if lootTable == "n" or lootTable == "N" or lootTable == "q" then
                    zone = zone .. "(10"
                    if srctype == L["Heroic"] then zone = zone .. "H" end
                    zone = zone .. ")"
                elseif lootTable == "h" or lootTable == "H" or lootTable == "Q" then
                    zone = zone .. "(25"
                    if srctype == L["Heroic"] then zone = zone .. "H" end
                    zone = zone .. ")"
                elseif lootTable == "4" then
                    zone = zone .. "(40)"
                end
            else
                local f = srctypes_d[lootTable]
                srctype = f and f()
                if srctype == L["Heroic"] then
                    zone = zone .. "(" .. srctype .. ")"
                end
            end
            local boss = db.Bosses[tonumber(next_field() or 0)]
            local setname = next_field()
            if setname == "+" then setname = L["Hard mode"] end
            lootString = zone
            if boss then
                lootString = lootString .. "-" .. boss
                if setname then lootString = lootString .. "(" .. setname .. ")" end
            end
        elseif cat == "j" then
            lootString = (next_field() or "") .. L["Badge of Justice rewards"]
        elseif cat == "h" then
            lootString = (next_field() or "") .. L["Emblem of Heroism rewards"]
        elseif cat == "v" then
            lootString = (next_field() or "") .. L["Emblem of Valor rewards"]
        elseif cat == "u" then
            lootString = (next_field() or "") .. L["Emblem of Conquest rewards"]
        elseif cat == "i" then
            lootString = (next_field() or "") .. L["Emblem of Triumph rewards"]
        elseif cat == "o" then
            lootString = (next_field() or "") .. L["Emblem of Frost rewards"]
        elseif cat == "t" then
            lootString = L["Argent Tournament"]
        elseif cat == "c" then
            local prof = GetSpellInfo(tonumber(next_field() or "0"))
            lootString = L["Crafted"] .. (prof and ("-" .. prof) or "")
        elseif cat == "f" then
            lootString = L["Reputation rewards"]
        elseif cat == "e" then
            lootString = L["World events"]
        elseif cat == "m" then
            lootString = L["Darkmoon Faire"]
        elseif cat == "g" then
            lootString = L["Vendor"]
        elseif cat == "p" then
            local f = pvptypes[next_field()]
            lootString = L["PvP"] .. (f and ("-" .. f()) or "")
        end
    end
    return lootString
end

local function AddToTooltip(tip, itemLink)
    if not active then return end
    local cfg = Cfg()
    if not cfg then return end
    if tip.DragonUIEnhancedItem == itemLink then return end
    tip.DragonUIEnhancedItem = itemLink

    local sources = FindItem(itemLink, cfg.showUnknown)
    if not sources then return end

    local r = cfg.ttR or 0.9
    local g = cfg.ttG or 0.75
    local b = cfg.ttB or 0.35
    for _, entry in pairs(sources) do
        local src, subsrc, lootTable, boss, cost, setname = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
        local str = src or ""
        if subsrc then str = str .. ": " .. subsrc end
        if lootTable then str = str .. " (" .. lootTable .. ")" end
        if boss then str = str .. ": " .. boss end
        if cost and cost ~= 0 then str = str .. " (" .. cost .. ")" end
        if setname then str = str .. " (" .. setname .. ")" end
        tip:AddDoubleLine(L["Source"] .. ":", str, r, g, b, r, g, b)
    end
    tip:Show()
end

local function ClearTip(tooltip)
    tooltip.DragonUIEnhancedItem = nil
end

local function HookTipScript(tooltip)
    if not tooltip or not tooltip.HookScript then return end
    tooltip:HookScript("OnTooltipSetItem", function(tip)
        if not active then return end
        local _, link = tip:GetItem()
        if link and GetItemInfo(link) then
            AddToTooltip(tip, link)
        end
    end)
    tooltip:HookScript("OnTooltipCleared", ClearTip)
end

local function HookCompareTip(tooltip)
    if not tooltip then return end
    hooksecurefunc(tooltip, "SetHyperlinkCompareItem", function(tip)
        if not active then return end
        local _, link = tip:GetItem()
        if link then
            AddToTooltip(tip, link)
        end
    end)
end

local function InstallHooks()
    if hooked then return end
    hooked = true
    HookTipScript(GameTooltip)
    HookTipScript(ItemRefTooltip)
    HookCompareTip(ShoppingTooltip1)
    HookCompareTip(ShoppingTooltip2)
    HookCompareTip(ShoppingTooltip3)
    HookCompareTip(ItemRefShoppingTooltip1)
    HookCompareTip(ItemRefShoppingTooltip2)
    HookCompareTip(ItemRefShoppingTooltip3)
    if AtlasLootTooltip then
        HookTipScript(AtlasLootTooltip)
    end
end

local function OnEnable()
    MigrateFromTinyInspect()
    RefreshEmblemNames()
    InstallHooks()
    active = true
    if not addon._itemInfoEmblemFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        f:SetScript("OnEvent", RefreshEmblemNames)
        addon._itemInfoEmblemFrame = f
    end
end

local function OnDisable()
    active = false
end

addon:RegisterFeature(KEY, {
    category = "equipment",
    default = true,
    requiresReload = true,
    label = function() return L["Item Source Tooltip"] end,
    desc = function()
        return L["Show item drop/source lines on tooltips (from TinyInspect data)."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Add「出处」lines to item tooltips. Disable TinyInspect to avoid duplicate lines."])
        C:AddToggle(section, {
            label = L["Include Unknown Items"],
            desc = L["Show an Unknown line for uncommon+ items missing from the database."],
            getFunc = function() return Cfg().showUnknown and true or false end,
            setFunc = function(val)
                Cfg().showUnknown = val and true or false
            end,
        })
        if C.AddColorPicker then
            C:AddColorPicker(section, {
                label = L["Tooltip text color"],
                getFunc = function()
                    local cfg = Cfg()
                    return cfg.ttR or 0.9, cfg.ttG or 0.75, cfg.ttB or 0.35
                end,
                setFunc = function(r, g, b)
                    local cfg = Cfg()
                    cfg.ttR, cfg.ttG, cfg.ttB = r, g, b
                end,
            })
        end
    end,
})

addon.ItemInfo = {
    FindItem = FindItem,
    FormatLootString = FormatLootString,
    AddToTooltip = AddToTooltip,
}
