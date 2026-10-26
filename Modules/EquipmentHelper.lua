-- ElvUI_Banbi — Equipment set bar (ported from ElvUI_bbTools EquipmentHelper).
-- Quick-switch buttons + talent/PvP/challenge auto-equip bindings.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "equipmentHelper"
local DEFAULT_CHALLENGE_MIN_LEVEL = 28
local CHALLENGE_BURDEN_SPELL_ID = 93514

local CHALLENGE_LEVEL_BY_SPELL = {
    [90207] = 1,  [91325] = 1,  [90208] = 2,  [91326] = 2,
    [90209] = 3,  [91327] = 3,  [90210] = 4,  [91328] = 4,
    [90211] = 5,  [91329] = 5,  [90212] = 6,  [91330] = 6,
    [90213] = 7,  [91331] = 7,  [90214] = 8,  [91332] = 8,
    [90215] = 9,  [91333] = 9,  [90216] = 10, [91334] = 10,
    [92538] = 11, [92543] = 11, [92539] = 12, [92544] = 12,
    [92540] = 13, [92545] = 13, [92541] = 14, [92546] = 14,
    [92542] = 15, [92547] = 15, [93395] = 16, [93410] = 16,
    [93396] = 17, [93411] = 17, [93397] = 18, [93412] = 18,
    [93398] = 19, [93413] = 19, [93399] = 20, [93414] = 20,
    [93400] = 21, [93415] = 21, [93401] = 22, [93416] = 22,
    [93402] = 23, [93417] = 23, [93403] = 24, [93418] = 24,
    [93404] = 25, [93419] = 25, [93405] = 26, [93420] = 26,
    [93406] = 27, [93421] = 27, [93407] = 28, [93422] = 28,
    [93408] = 29, [93423] = 29, [93409] = 30, [93424] = 30,
}

local PVP_MAP_IDS = {
    [545] = true, [979] = true, [2001] = true, [25] = true,
}

local PVP_ZONE_NAMES = {
    ["失落群岛"] = true, ["阿什兰"] = true, ["公海激战"] = true,
    ["希尔斯布莱德丘陵"] = true, ["Hillsbrad Foothills"] = true,
    ["Lost Isles"] = true, ["Ashran"] = true,
}

local EH = {}
local mainFrame, buttons, eventFrame, menuFrame
local editorRegistered = false
local active = false
local initialized = false
local isDragging = false
local setItemIDCache = {}
local pendingTalentSwitch
local pendingRetrySetName
-- Suppress talent auto-equip right after a meta-toggle equip (the rune pulse swaps
-- the rune -> PLAYER_TALENT_UPDATE, which would otherwise clobber the toggle set).
local metaEquipGuardUntil = 0
local retryCount, maxRetries = 0, 3
local retryTimer
local inPvPZone, inChallengeMode = false, false
local _tempCharDB
local _cachedPlayerMapID

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function After(delay, fn)
    if addon.core and addon.core.ScheduleTimer then
        return addon.core:ScheduleTimer(fn, delay)
    end
    local f = CreateFrame("Frame")
    local t = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t >= delay then
            f:SetScript("OnUpdate", nil)
            fn()
        end
    end)
    return f
end

local function CancelRetry()
    if not retryTimer then return end
    if type(retryTimer) == "table" and retryTimer.SetScript then
        retryTimer:SetScript("OnUpdate", nil)
    elseif addon.core and addon.core.CancelTimer then
        addon.core:CancelTimer(retryTimer, true)
    end
    retryTimer = nil
end

local function GetCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or name == "" or not realm or realm == "" then
        return nil
    end
    return name .. "-" .. realm
end

local function EnsureEquipmentRoot()
    if not addon.db then return nil end
    local g = addon.db.global
    g.equipment = g.equipment or { chars = {} }
    g.equipment.chars = g.equipment.chars or {}
    return g.equipment
end

local function DefaultCharDB()
    return {
        talentSets = {},
        metaSets = {},
        activeSetName = nil,
        autoSwitchOnTalent = true,
        autoSwitchOnMeta = true,
        pvpSet = nil,
        autoSwitchOnPvP = true,
        challengeSets = {},
        autoSwitchOnChallenge = true,
        challengeMinLevel = DEFAULT_CHALLENGE_MIN_LEVEL,
    }
end

local function GetCharEquipmentDB()
    local root = EnsureEquipmentRoot()
    if not root then
        _tempCharDB = _tempCharDB or DefaultCharDB()
        return _tempCharDB
    end
    local key = GetCharKey()
    if not key then
        _tempCharDB = _tempCharDB or DefaultCharDB()
        return _tempCharDB
    end
    local charDB = root.chars[key]
    if not charDB then
        charDB = DefaultCharDB()
        root.chars[key] = charDB
    end
    charDB.talentSets = charDB.talentSets or {}
    charDB.metaSets = charDB.metaSets or {}
    charDB.challengeSets = charDB.challengeSets or {}
    -- Drop legacy single-slot challenge binding; user rebinds per talent.
    charDB.challengeSet = nil
    if charDB.autoSwitchOnTalent == nil then charDB.autoSwitchOnTalent = true end
    if charDB.autoSwitchOnMeta == nil then charDB.autoSwitchOnMeta = true end
    if charDB.autoSwitchOnPvP == nil then charDB.autoSwitchOnPvP = true end
    if charDB.autoSwitchOnChallenge == nil then charDB.autoSwitchOnChallenge = true end
    if charDB.challengeMinLevel == nil then charDB.challengeMinLevel = DEFAULT_CHALLENGE_MIN_LEVEL end

    if _tempCharDB then
        local temp = _tempCharDB
        for k, v in pairs(temp.talentSets or {}) do charDB.talentSets[k] = v end
        for k, v in pairs(temp.metaSets or {}) do charDB.metaSets[k] = v end
        for k, v in pairs(temp.challengeSets or {}) do charDB.challengeSets[k] = v end
        if temp.activeSetName then charDB.activeSetName = temp.activeSetName end
        if temp.autoSwitchOnTalent ~= nil then charDB.autoSwitchOnTalent = temp.autoSwitchOnTalent end
        if temp.autoSwitchOnMeta ~= nil then charDB.autoSwitchOnMeta = temp.autoSwitchOnMeta end
        if temp.pvpSet then charDB.pvpSet = temp.pvpSet end
        if temp.autoSwitchOnPvP ~= nil then charDB.autoSwitchOnPvP = temp.autoSwitchOnPvP end
        if temp.autoSwitchOnChallenge ~= nil then charDB.autoSwitchOnChallenge = temp.autoSwitchOnChallenge end
        if temp.challengeMinLevel ~= nil then charDB.challengeMinLevel = temp.challengeMinLevel end
        _tempCharDB = nil
    end
    return charDB
end

EH.GetCharEquipmentDB = GetCharEquipmentDB

local function MigrateFromBbTools()
    if not addon.db or not addon.db.global then return end
    local g = addon.db.global
    g.migrated = g.migrated or {}
    if g.migrated.equipmentHelper then return end
    g.migrated.equipmentHelper = true

    local src = _G.bbToolsDB and _G.bbToolsDB.equipment
    if type(src) ~= "table" then return end

    local root = EnsureEquipmentRoot()
    local imported = 0
    if type(src.chars) == "table" then
        for key, charDB in pairs(src.chars) do
            if type(charDB) == "table" and not root.chars[key] then
                root.chars[key] = {}
                for k, v in pairs(charDB) do
                    if k == "talentSets" and type(v) == "table" then
                        root.chars[key].talentSets = {}
                        for tg, sn in pairs(v) do
                            root.chars[key].talentSets[tg] = sn
                        end
                    else
                        root.chars[key][k] = v
                    end
                end
                imported = imported + 1
            end
        end
    end

    local cfg = Cfg()
    if cfg and src.position and type(src.position.x) == "number" then
        if cfg.posX == nil or (cfg.posX == 0 and cfg.posY == -180) then
            cfg.anchor = "CENTER"
            cfg.posX = src.position.x
            cfg.posY = src.position.y
        end
    end

    if imported > 0 then
        print("|cff00ff00[装备助手]|r 已从 bbToolsDB 导入 " .. imported .. " 个角色的配装绑定。")
    end
end

local function PersistPosition()
    if not mainFrame then return end
    local cfg = Cfg()
    if not cfg then return end
    local point, _, _, x, y = mainFrame:GetPoint(1)
    cfg.anchor = point or "CENTER"
    cfg.posX = x or 0
    cfg.posY = y or -180
end

local function ApplyPosition()
    if not mainFrame then return end
    local cfg = Cfg() or {}
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint(cfg.anchor or "CENTER", UIParent, cfg.anchor or "CENTER", cfg.posX or 0, cfg.posY or -180)
    mainFrame:SetScale(cfg.scale or 1)
end

local function ResetPosition()
    local cfg = Cfg()
    local d = addon.defaults.profile.features.equipmentHelper
    if cfg and d then
        cfg.anchor = d.anchor
        cfg.posX = d.posX
        cfg.posY = d.posY
        cfg.scale = d.scale
    end
    ApplyPosition()
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end
    GetCharEquipmentDB()

    mainFrame = CreateFrame("Frame", "ElvUI_Banbi_EquipmentFrame", UIParent)
    mainFrame:SetSize(300, 50)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetFrameLevel(1)
    mainFrame:SetClampedToScreen(true)
    if mainFrame.SetBackdrop then
        mainFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            insets = { left = 2, top = 2, right = 2, bottom = 2 },
            tile = true,
        })
        mainFrame:SetBackdropColor(0, 0, 0, 0)
    end
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not IsShiftKeyDown() then return end
        if InCombatLockdown and InCombatLockdown() then return end
        isDragging = true
        self:StartMoving()
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        if not isDragging then return end
        isDragging = false
        self:StopMovingOrSizing()
        PersistPosition()
    end)
    mainFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Equipment Helper"], 1, 1, 1)
        GameTooltip:AddLine(L["Shift+drag to move. Right-click a set to bind talent/PvP/challenge."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    mainFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ApplyPosition()
    return mainFrame
end

function EH:GetEquipmentSetStats(setID)
    local totalItems, equippedItems = 0, 0
    local setName = GetEquipmentSetInfo(setID)
    if not setName then return 0, 0, 0 end
    setItemIDCache = {}
    setItemIDCache = GetEquipmentSetItemIDs(setName, setItemIDCache)
    if not setItemIDCache then return 0, 0, 0 end
    for slotID, setItemID in pairs(setItemIDCache) do
        if type(slotID) == "number" and setItemID and setItemID > 0 then
            totalItems = totalItems + 1
            if GetInventoryItemID("player", slotID) == setItemID then
                equippedItems = equippedItems + 1
            end
        end
    end
    return totalItems, equippedItems, 19 - totalItems
end

function EH:IsEquipmentSetFullyEquipped(setID)
    local total, equipped = self:GetEquipmentSetStats(setID)
    if total == 0 then return true end
    return equipped == total
end

function EH:IsEquipmentSetEquipped(setID)
    local setName = GetEquipmentSetInfo(setID)
    local activeSetName = GetCharEquipmentDB().activeSetName
    if not setName or not activeSetName then return false end
    return activeSetName == setName
end

function EH:SetActiveSetName(setName)
    if not setName then return end
    GetCharEquipmentDB().activeSetName = setName
    if active then self:UpdateButtons() end
end

function EH:DetectLoginActiveSet()
    local charDB = GetCharEquipmentDB()
    for id = 1, GetNumEquipmentSets() do
        local name, _, _, isEquipped = GetEquipmentSetInfo(id)
        if name and isEquipped then
            charDB.activeSetName = name
            return name
        end
    end
    return charDB.activeSetName
end

function EH:CheckAndRetryEquip()
    if not pendingRetrySetName then return end
    local targetSetID
    for id = 1, GetNumEquipmentSets() do
        if GetEquipmentSetInfo(id) == pendingRetrySetName then
            targetSetID = id
            break
        end
    end
    if not targetSetID then
        pendingRetrySetName = nil
        return
    end
    if self:IsEquipmentSetFullyEquipped(targetSetID) then
        pendingRetrySetName = nil
        retryCount = 0
        return
    end
    retryCount = retryCount + 1
    if retryCount <= maxRetries then
        if EquipmentManager_EquipSet then
            EquipmentManager_EquipSet(pendingRetrySetName)
        else
            UseEquipmentSet(pendingRetrySetName)
        end
        retryTimer = After(0.5, function()
            retryTimer = nil
            EH:CheckAndRetryEquip()
        end)
    else
        pendingRetrySetName = nil
        retryCount = 0
    end
end

function EH:EquipTalentSet(setName, reason)
    if not setName then return end
    if InCombatLockdown() then
        pendingTalentSwitch = setName
        print("|cff00ff00" .. L["Will switch after combat:"] .. "|r " .. setName)
        return
    end
    self:SetActiveSetName(setName)
    if EquipmentManager_EquipSet then
        EquipmentManager_EquipSet(setName)
    else
        UseEquipmentSet(setName)
    end
    print("|cff00ff00" .. (reason or L["Talent auto-equip"]) .. ":|r " .. setName)
    pendingRetrySetName = setName
    retryCount = 0
    CancelRetry()
    retryTimer = After(0.5, function()
        retryTimer = nil
        EH:CheckAndRetryEquip()
    end)
end

function EH:ShowTalentBindingMenu(button)
    if not button.name then return end
    local charDB = GetCharEquipmentDB()
    local currentBinding
    for talentGroup, setName in pairs(charDB.talentSets) do
        if setName == button.name then
            currentBinding = talentGroup
            break
        end
    end

    local menu = {}
    if currentBinding then
        table.insert(menu, { text = L["Bound to talent group"] .. " " .. currentBinding, notCheckable = true, isTitle = true })
    else
        table.insert(menu, { text = L["Not bound to talent"], notCheckable = true, isTitle = true })
    end
    table.insert(menu, { text = " " })

    for tg = 1, 2 do
        table.insert(menu, {
            text = L["Bind to talent group"] .. " " .. tg,
            notCheckable = true,
            func = function()
                local db = GetCharEquipmentDB()
                for k, sn in pairs(db.talentSets) do
                    if sn == button.name then db.talentSets[k] = nil end
                end
                db.talentSets[tg] = button.name
                print("|cff00ff00" .. L["Bound:"] .. "|r " .. button.name .. " -> " .. L["Talent group"] .. " " .. tg)
                EH:UpdateButtons()
            end,
        })
    end
    table.insert(menu, { text = " " })
    if currentBinding then
        table.insert(menu, {
            text = L["Unbind talent"],
            notCheckable = true,
            func = function()
                GetCharEquipmentDB().talentSets[currentBinding] = nil
                print("|cff00ff00" .. L["Unbound:"] .. "|r " .. button.name)
                EH:UpdateButtons()
            end,
        })
    end
    table.insert(menu, { text = " " })

    -- bbRotHelper warlock toggle bindings (恶魔变形 / 暗影箭雨).
    local metaBindings = {
        { key = "meta", label = L["Bind as Metamorphosis set"],
          bound = L["Bound as Metamorphosis set"], unbind = L["Unbind Metamorphosis"],
          done = L["Metamorphosis bound:"], undone = L["Metamorphosis unbound:"] },
        { key = "rain", label = L["Bind as Shadow Bolt Rain set"],
          bound = L["Bound as Shadow Bolt Rain set"], unbind = L["Unbind Shadow Bolt Rain"],
          done = L["Shadow Bolt Rain bound:"], undone = L["Shadow Bolt Rain unbound:"] },
    }
    for _, binding in ipairs(metaBindings) do
        if charDB.metaSets[binding.key] == button.name then
            table.insert(menu, { text = binding.bound, notCheckable = true, isTitle = true })
            table.insert(menu, {
                text = binding.unbind,
                notCheckable = true,
                func = function()
                    local db = GetCharEquipmentDB()
                    for k, sn in pairs(db.metaSets) do
                        if sn == button.name then db.metaSets[k] = nil end
                    end
                    print("|cff00ff00" .. binding.undone .. "|r " .. button.name)
                    EH:UpdateButtons()
                end,
            })
        else
            table.insert(menu, {
                text = binding.label,
                notCheckable = true,
                func = function()
                    local db = GetCharEquipmentDB()
                    for k, sn in pairs(db.metaSets) do
                        if sn == button.name then db.metaSets[k] = nil end
                    end
                    db.metaSets[binding.key] = button.name
                    print("|cff00ff00" .. binding.done .. "|r " .. button.name)
                    EH:UpdateButtons()
                end,
            })
        end
    end
    table.insert(menu, { text = " " })

    if charDB.pvpSet == button.name then
        table.insert(menu, { text = L["Bound as PvP set"], notCheckable = true, isTitle = true })
        table.insert(menu, {
            text = L["Unbind PvP"],
            notCheckable = true,
            func = function()
                GetCharEquipmentDB().pvpSet = nil
                print("|cff00ff00" .. L["PvP unbound:"] .. "|r " .. button.name)
                EH:UpdateButtons()
            end,
        })
    else
        table.insert(menu, {
            text = L["Bind as PvP set"],
            notCheckable = true,
            func = function()
                GetCharEquipmentDB().pvpSet = button.name
                print("|cff00ff00" .. L["PvP bound:"] .. "|r " .. button.name)
                EH:UpdateButtons()
            end,
        })
    end
    table.insert(menu, { text = " " })

    local minLv = charDB.challengeMinLevel or DEFAULT_CHALLENGE_MIN_LEVEL
    local challengeBound
    for tg, sn in pairs(charDB.challengeSets) do
        if sn == button.name then
            challengeBound = true
            table.insert(menu, {
                text = string.format(L["Bound as challenge set (≥%d) talent %d"], minLv, tg),
                notCheckable = true, isTitle = true,
            })
        end
    end
    for tg = 1, 2 do
        table.insert(menu, {
            text = string.format(L["Bind as challenge set (≥%d) talent %d"], minLv, tg),
            notCheckable = true,
            func = function()
                local db = GetCharEquipmentDB()
                db.challengeSets = db.challengeSets or {}
                db.challengeSets[tg] = button.name
                db.challengeMinLevel = db.challengeMinLevel or DEFAULT_CHALLENGE_MIN_LEVEL
                print("|cff00ff00" .. string.format(L["Challenge bound talent %d:"], tg) .. "|r " .. button.name)
                EH:UpdateButtons()
            end,
        })
    end
    if challengeBound then
        table.insert(menu, {
            text = L["Unbind challenge"],
            notCheckable = true,
            func = function()
                local db = GetCharEquipmentDB()
                for tg, sn in pairs(db.challengeSets) do
                    if sn == button.name then db.challengeSets[tg] = nil end
                end
                print("|cff00ff00" .. L["Challenge unbound:"] .. "|r " .. button.name)
                EH:UpdateButtons()
            end,
        })
    end

    if not menuFrame then
        menuFrame = CreateFrame("Frame", "ElvUI_Banbi_EquipMenu", UIParent, "UIDropDownMenuTemplate")
    end
    EasyMenu(menu, menuFrame, button, 0, 0, "MENU")
end

local function CreateEquipmentButton(parent, index)
    local button = CreateFrame("Button", "ElvUI_Banbi_EquipBtn" .. index, parent)
    local buttonSize, spacing, startGap = 24, 3, 5
    button:SetSize(buttonSize, buttonSize)
    button:SetPoint("LEFT", parent, "LEFT", startGap + (index - 1) * (buttonSize + spacing), 0)

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
    button:SetPushedTexture([[Interface\Buttons\UI-Quickslot-Depress]])
    button:RegisterForClicks("AnyUp")

    button:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" then EH:ShowTalentBindingMenu(self) end
    end)

    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    button.text:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.text:SetWidth(35)
    button.text:SetJustifyH("CENTER")

    button.badge = button:CreateFontString(nil, "OVERLAY")
    button.badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    button.badge:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.badge:SetTextColor(1, 0.82, 0)
    button.badge:Hide()

    button:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print("|cffff0000" .. L["Cannot switch equipment sets in combat."] .. "|r")
            return
        end
        if not self.setID then return end
        if EH:IsEquipmentSetEquipped(self.setID) and EH:IsEquipmentSetFullyEquipped(self.setID) then
            return
        end
        local charDB = GetCharEquipmentDB()
        local isRetry = (charDB.activeSetName == self.name)
        EH:SetActiveSetName(self.name)
        if EquipmentManager_EquipSet then
            EquipmentManager_EquipSet(self.name)
        else
            UseEquipmentSet(self.name)
        end
        if not isRetry then
            print("|cff00ff00" .. L["Switched to set:"] .. "|r " .. self.name)
        end
    end)

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if not IsShiftKeyDown() or not mainFrame then return end
        if InCombatLockdown and InCombatLockdown() then return end
        isDragging = true
        mainFrame:StartMoving()
    end)
    button:SetScript("OnDragStop", function()
        if not isDragging or not mainFrame then return end
        isDragging = false
        mainFrame:StopMovingOrSizing()
        PersistPosition()
    end)

    button:SetScript("OnEnter", function(self)
        if not self.setID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Equipment set"], 1, 1, 1)
        GameTooltip:AddLine(self.name, 0, 1, 0)
        local totalItems, equippedItems, ignoredSlots = EH:GetEquipmentSetStats(self.setID)
        if totalItems > 0 then
            GameTooltip:AddLine(string.format(L["Progress: %d/%d"], equippedItems, totalItems), 1, 1, 1)
            if ignoredSlots > 0 then
                GameTooltip:AddLine(string.format(L["Ignored slots: %d"], ignoredSlots), 0.8, 0.8, 0.8)
            end
            local charDB = GetCharEquipmentDB()
            for talentGroup, setName in pairs(charDB.talentSets) do
                if setName == self.name then
                    GameTooltip:AddLine(string.format(L["Bound to talent group %d"], talentGroup), 1, 0.82, 0)
                    break
                end
            end
            if charDB.pvpSet == self.name then
                GameTooltip:AddLine(L["Bound as PvP set"], 1, 0.4, 0.4)
            end
            if charDB.metaSets then
                if charDB.metaSets.meta == self.name then
                    GameTooltip:AddLine(L["Bound as Metamorphosis set"], 0.5, 1, 0.5)
                end
                if charDB.metaSets.rain == self.name then
                    GameTooltip:AddLine(L["Bound as Shadow Bolt Rain set"], 0.5, 1, 0.5)
                end
            end
            local minLv = charDB.challengeMinLevel or DEFAULT_CHALLENGE_MIN_LEVEL
            for tg, sn in pairs(charDB.challengeSets) do
                if sn == self.name then
                    GameTooltip:AddLine(string.format(L["Bound as challenge set (≥%d) talent %d"], minLv, tg), 0.6, 0.8, 1)
                end
            end
            if EH:IsEquipmentSetEquipped(self.setID) then
                GameTooltip:AddLine(L["Currently equipped"], 1, 1, 0)
            else
                GameTooltip:AddLine(L["Click to equip this set"], 1, 1, 1)
            end
        else
            GameTooltip:AddLine(L["Empty equipment set"], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

function EH:UpdateButtons()
    if not mainFrame or not active then return end
    buttons = buttons or {}
    local numSets = GetNumEquipmentSets()
    local buttonCount = math.min(numSets, 10)
    local buttonSize, spacing = 24, 3
    mainFrame:SetWidth(10 + buttonCount * (buttonSize + spacing) - spacing)

    for i = 1, buttonCount do
        local name, icon = GetEquipmentSetInfo(i)
        if not buttons[i] then
            buttons[i] = CreateEquipmentButton(mainFrame, i)
        end
        local btn = buttons[i]
        btn:Show()
        btn.icon:SetTexture(icon or 134400)
        local displayName = name
        if string.len(name) > 8 then
            displayName = string.sub(name, 1, 8) .. ".."
        end
        btn.text:SetText(displayName)
        if self:IsEquipmentSetEquipped(i) then
            btn.text:SetTextColor(1, 1, 0)
            btn.icon:SetVertexColor(1, 0.82, 0)
        else
            btn.icon:SetVertexColor(1, 1, 1)
            btn.text:SetTextColor(1, 1, 1)
        end
        btn.name = name
        btn.setID = i

        local charDB = GetCharEquipmentDB()
        local boundTalent
        for talentGroup, setName in pairs(charDB.talentSets) do
            if setName == name then boundTalent = talentGroup break end
        end
        local metaTag
        if charDB.metaSets then
            if charDB.metaSets.meta == name then metaTag = "M"
            elseif charDB.metaSets.rain == name then metaTag = "R" end
        end
        local challengeGroups = {}
        for tg, setName in pairs(charDB.challengeSets) do
            if setName == name then
                challengeGroups[#challengeGroups + 1] = tg
            end
        end
        if boundTalent then
            btn.badge:SetText(boundTalent)
            btn.badge:SetTextColor(1, 0.82, 0)
            btn.badge:Show()
        elseif metaTag then
            btn.badge:SetText(metaTag)
            btn.badge:SetTextColor(0.5, 1, 0.5)
            btn.badge:Show()
        elseif #challengeGroups > 0 then
            if #challengeGroups >= 2 then
                btn.badge:SetText("C")
            else
                btn.badge:SetText("C" .. challengeGroups[1])
            end
            btn.badge:SetTextColor(0.6, 0.8, 1)
            btn.badge:Show()
        elseif charDB.pvpSet == name then
            btn.badge:SetText("P")
            btn.badge:SetTextColor(1, 0.4, 0.4)
            btn.badge:Show()
        else
            btn.badge:Hide()
        end
    end
    for i = buttonCount + 1, #buttons do
        if buttons[i] then buttons[i]:Hide() end
    end
end

function EH:GetPlayerMapID()
    if not GetCurrentMapAreaID then return 0 end
    if WorldMapFrame and WorldMapFrame:IsShown() then
        return _cachedPlayerMapID or 0
    end
    if SetMapToCurrentZone then SetMapToCurrentZone() end
    local mapID = GetCurrentMapAreaID() or 0
    if mapID > 0 then _cachedPlayerMapID = mapID end
    return mapID
end

local function ParseChallengeLevelFromText(text)
    if not text or text == "" then return nil end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    local start = plain:find("挑战等级", 1, true)
    if not start then return nil end
    local level = tonumber(plain:match("(%d+)", start))
    if level and level > 0 then return level end
    return nil
end

local function ScanChallengeLevelFromWorldState()
    if not GetWorldStateUIInfo then return nil end
    local fallback
    for i = 1, 40 do
        local _, state, text = GetWorldStateUIInfo(i)
        local level = ParseChallengeLevelFromText(text)
        if level then
            if state == 1 then return level end
            fallback = fallback or level
        end
    end
    return fallback
end

local function ScanChallengeLevelFromAlwaysUp()
    local preferred = _G["AlwaysUpFrame2Text"]
    if preferred and preferred.GetText then
        local level = ParseChallengeLevelFromText(preferred:GetText())
        if level then return level end
    end
    for i = 1, (NUM_ALWAYS_UP_UI_FRAMES or 10) do
        local fs = _G["AlwaysUpFrame" .. i .. "Text"]
        if fs and fs.GetText then
            local level = ParseChallengeLevelFromText(fs:GetText())
            if level then return level end
        end
    end
    return nil
end

local function ScanUnitAurasForChallenge(getter)
    local foundBurden, foundLevel = false, nil
    for i = 1, 80 do
        local name, _, _, _, _, _, _, _, _, _, spellId = getter("player", i)
        if not name then break end
        if spellId == CHALLENGE_BURDEN_SPELL_ID or name == "挑战者的负担" then
            foundBurden = true
        end
        local byId = spellId and CHALLENGE_LEVEL_BY_SPELL[spellId]
        if byId then
            foundLevel = byId
        else
            local byName = name:match("^挑战等级(%d+)$")
            if byName then foundLevel = tonumber(byName) end
        end
    end
    return foundLevel, foundBurden
end

function EH:GetChallengeLevel()
    local levelBuff, burden = ScanUnitAurasForChallenge(UnitBuff)
    local levelDebuff, burden2 = ScanUnitAurasForChallenge(UnitDebuff)
    local inChallenge = burden or burden2 or (levelBuff ~= nil) or (levelDebuff ~= nil)
    if not inChallenge then return nil, false end
    local level = ScanChallengeLevelFromWorldState()
        or ScanChallengeLevelFromAlwaysUp()
        or levelBuff
        or levelDebuff
    if level then return level, true end
    return nil, true
end

function EH:ResolveChallengeEquipSet()
    local charDB = GetCharEquipmentDB()
    local tg = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    return charDB.challengeSets[tg] or charDB.talentSets[tg]
end

function EH:ShouldUseChallengeSet()
    local charDB = GetCharEquipmentDB()
    if not charDB.autoSwitchOnChallenge then return false end
    local level = self:GetChallengeLevel()
    if not level then return false end
    return level >= (charDB.challengeMinLevel or DEFAULT_CHALLENGE_MIN_LEVEL)
end

function EH:IsInPvPZone()
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "pvp" or instanceType == "arena") then return true end
    local mapID = self:GetPlayerMapID()
    if mapID and PVP_MAP_IDS[mapID] then return true end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    if zone ~= "" and PVP_ZONE_NAMES[zone] then
        return true
    end
    return false
end

function EH:OnChallengeChanged()
    local charDB = GetCharEquipmentDB()
    local level = self:GetChallengeLevel()
    if not charDB.autoSwitchOnChallenge then
        inChallengeMode = self:ShouldUseChallengeSet()
        return
    end
    if self:IsInPvPZone() and charDB.pvpSet then
        inChallengeMode = false
        return
    end
    local nowInChallenge = self:ShouldUseChallengeSet()
    local targetSet = self:ResolveChallengeEquipSet()
    if nowInChallenge and not inChallengeMode then
        inChallengeMode = true
        if targetSet and charDB.activeSetName ~= targetSet then
            charDB.preChallengeSetName = charDB.activeSetName
            self:EquipTalentSet(targetSet, string.format(L["Challenge %d auto-equip"], level or 0))
        end
    elseif not nowInChallenge and inChallengeMode then
        inChallengeMode = false
        local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1
        local restoreSet = charDB.talentSets[activeTalentGroup] or charDB.preChallengeSetName
        charDB.preChallengeSetName = nil
        if restoreSet and charDB.activeSetName ~= restoreSet then
            self:EquipTalentSet(restoreSet, L["Leave challenge equip"])
        end
    else
        inChallengeMode = nowInChallenge
    end
end

function EH:OnZoneChanged()
    local charDB = GetCharEquipmentDB()
    if not charDB.autoSwitchOnPvP then
        inPvPZone = self:IsInPvPZone()
        return
    end
    local pvpSet = charDB.pvpSet
    if not pvpSet then
        inPvPZone = self:IsInPvPZone()
        return
    end
    local nowInPvP = self:IsInPvPZone()
    if nowInPvP and not inPvPZone then
        inPvPZone = true
        inChallengeMode = false
        if charDB.activeSetName ~= pvpSet then
            charDB.prePvPSetName = charDB.activeSetName
            self:EquipTalentSet(pvpSet, L["PvP zone auto-equip"])
        end
    elseif not nowInPvP and inPvPZone then
        inPvPZone = false
        if self:ShouldUseChallengeSet() then
            inChallengeMode = true
            local challengeTarget = self:ResolveChallengeEquipSet()
            if challengeTarget and charDB.activeSetName ~= challengeTarget then
                self:EquipTalentSet(challengeTarget, L["Challenge auto-equip"])
            end
            charDB.prePvPSetName = nil
            return
        end
        local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1
        local restoreSet = charDB.talentSets[activeTalentGroup] or charDB.prePvPSetName
        charDB.prePvPSetName = nil
        if restoreSet and restoreSet ~= pvpSet and charDB.activeSetName ~= restoreSet then
            self:EquipTalentSet(restoreSet, L["Leave PvP zone equip"])
        end
    else
        inPvPZone = nowInPvP
    end
end

function EH:OnTalentChanged()
    local charDB = GetCharEquipmentDB()
    if not charDB.autoSwitchOnTalent then return end
    if GetTime() < metaEquipGuardUntil then return end
    if self:IsInPvPZone() and charDB.pvpSet then return end
    local activeTalentGroup = GetActiveTalentGroup()
    local targetSetName
    local reason
    if self:ShouldUseChallengeSet() then
        targetSetName = self:ResolveChallengeEquipSet()
        reason = L["Challenge auto-equip"]
    else
        targetSetName = charDB.talentSets[activeTalentGroup]
    end
    if not targetSetName then return end
    for id = 1, GetNumEquipmentSets() do
        if GetEquipmentSetInfo(id) == targetSetName then
            if self:IsEquipmentSetEquipped(id) and self:IsEquipmentSetFullyEquipped(id) then
                return
            end
            break
        end
    end
    if InCombatLockdown() then
        pendingTalentSwitch = targetSetName
        print("|cff00ff00" .. L["Will switch after combat:"] .. "|r " .. targetSetName)
    else
        self:EquipTalentSet(targetSetName, reason)
    end
end

-- bbRotHelper warlock "恶魔变形" toggle: ON -> meta set, OFF -> 暗影箭雨 set.
-- In combat EquipTalentSet queues the swap until combat ends (engine cannot swap gear in combat).
function EH:OnWarlockMetaToggle(enabled)
    local charDB = GetCharEquipmentDB()
    if charDB.autoSwitchOnMeta == false then return end
    if self:IsInPvPZone() and charDB.pvpSet then return end
    if self:ShouldUseChallengeSet() then return end
    local setName = charDB.metaSets[enabled and "meta" or "rain"]
    if not setName then return end

    local targetSetID
    for id = 1, GetNumEquipmentSets() do
        if GetEquipmentSetInfo(id) == setName then
            targetSetID = id
            break
        end
    end
    if not targetSetID then return end
    if self:IsEquipmentSetFullyEquipped(targetSetID) then
        return
    end
    self:EquipTalentSet(setName, enabled and L["Metamorphosis auto-equip"] or L["Shadow Bolt Rain auto-equip"])
    metaEquipGuardUntil = GetTime() + 3
end

local toggleListenerCancel
local function RegisterRotationToggleListener()
    if toggleListenerCancel then return true end
    local bb = _G.bbRotHelperAddon
    local rot = bb and bb.Rotation
    if not (rot and rot.RegisterToggleListener) then return false end
    toggleListenerCancel = rot:RegisterToggleListener("rotationUseMeta", function(on)
        if active then EH:OnWarlockMetaToggle(on) end
    end)
    return true
end

local function UnregisterRotationToggleListener()
    if not toggleListenerCancel then return end
    toggleListenerCancel()
    toggleListenerCancel = nil
end

local function OnEvent(_, event, ...)
    if not active then return end
    if event == "UNIT_AURA" then
        if (...) == "player" then EH:OnChallengeChanged() end
    elseif event == "UPDATE_WORLD_STATES" then
        EH:OnChallengeChanged()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if event == "PLAYER_ENTERING_WORLD" then
            EH:DetectLoginActiveSet()
            EH:UpdateButtons()
        end
        After(0.3, function()
            if active then
                EH:OnZoneChanged()
                EH:OnChallengeChanged()
            end
        end)
    elseif event == "EQUIPMENT_SWAP_FINISHED" then
        local completed, setName = ...
        if completed and setName and setName ~= "" then
            GetCharEquipmentDB().activeSetName = setName
        elseif not completed then
            EH:DetectLoginActiveSet()
        end
        EH:UpdateButtons()
    elseif event == "PLAYER_TALENT_UPDATE" then
        if GetCharEquipmentDB().autoSwitchOnTalent then
            EH:OnTalentChanged()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingTalentSwitch then
            EH:EquipTalentSet(pendingTalentSwitch)
            pendingTalentSwitch = nil
        end
    elseif event == "PLAYER_LOGIN" then
        -- bbRotHelper may load after this addon; retry the toggle listener hook.
        RegisterRotationToggleListener()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SETS_CHANGED" then
        EH:UpdateButtons()
    end
end

local function EnsureEvents()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", OnEvent)
end

local function RegisterEvents()
    EnsureEvents()
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("UPDATE_WORLD_STATES")
end

local function UnregisterEvents()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

local hooksInstalled = false
local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true
    if EquipmentManager_EquipSet then
        hooksecurefunc("EquipmentManager_EquipSet", function(setName)
            if active then EH:SetActiveSetName(setName) end
        end)
    end
    if UseEquipmentSet and UseEquipmentSet ~= EquipmentManager_EquipSet then
        hooksecurefunc("UseEquipmentSet", function(setName)
            if active and type(setName) == "string" then EH:SetActiveSetName(setName) end
        end)
    end
    if WorldStateAlwaysUpFrame_Update then
        hooksecurefunc("WorldStateAlwaysUpFrame_Update", function()
            if active then EH:OnChallengeChanged() end
        end)
    end
end

local function RegisterEditor()
    if editorRegistered or not mainFrame then return end
    local E = addon:GetE()
    if not (E and E.CreateMover) then return end
    E:CreateMover(mainFrame, "BanbiEquipmentHelperMover", L["Equipment Helper"] or "Equipment Helper", nil, nil, function()
        PersistPosition()
    end)
    editorRegistered = true
end

local function OnEnable()
    MigrateFromBbTools()
    active = true
    CreateMainFrame()
    buttons = buttons or {}
    RegisterEditor()
    ApplyPosition()
    InstallHooks()
    RegisterEvents()
    mainFrame:Show()
    After(1, function()
        if active then
            EH:DetectLoginActiveSet()
            EH:UpdateButtons()
            EH:OnZoneChanged()
            EH:OnChallengeChanged()
            RegisterRotationToggleListener()
        end
    end)
    EH:DetectLoginActiveSet()
    EH:UpdateButtons()
    initialized = true
end

local function OnDisable()
    active = false
    CancelRetry()
    pendingTalentSwitch = nil
    UnregisterRotationToggleListener()
    UnregisterEvents()
    if mainFrame then mainFrame:Hide() end
end

addon:RegisterFeature(KEY, {
    category = "equipment",
    default = true,
    label = function() return L["Equipment Helper"] end,
    desc = function()
        return L["Equipment set shortcut bar with talent/PvP/challenge auto-switch. Shift+drag to move."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Right-click a set button to bind talent/PvP/challenge. Shift+drag moves the bar."])
        C:AddToggle(section, {
            label = L["Auto-switch on talent change"],
            getFunc = function() return GetCharEquipmentDB().autoSwitchOnTalent ~= false end,
            setFunc = function(val) GetCharEquipmentDB().autoSwitchOnTalent = val and true or false end,
        })
        C:AddToggle(section, {
            label = L["Auto-switch in PvP zones"],
            getFunc = function() return GetCharEquipmentDB().autoSwitchOnPvP ~= false end,
            setFunc = function(val) GetCharEquipmentDB().autoSwitchOnPvP = val and true or false end,
        })
        C:AddToggle(section, {
            label = L["Auto-switch in challenge"],
            getFunc = function() return GetCharEquipmentDB().autoSwitchOnChallenge ~= false end,
            setFunc = function(val)
                GetCharEquipmentDB().autoSwitchOnChallenge = val and true or false
                if active then EH:OnChallengeChanged() end
            end,
        })
        C:AddToggle(section, {
            label = L["Auto-switch on warlock meta toggle"],
            getFunc = function() return GetCharEquipmentDB().autoSwitchOnMeta ~= false end,
            setFunc = function(val) GetCharEquipmentDB().autoSwitchOnMeta = val and true or false end,
        })
        C:AddSlider(section, {
            label = L["Challenge min level"],
            min = 1,
            max = 30,
            step = 1,
            getFunc = function()
                return GetCharEquipmentDB().challengeMinLevel or DEFAULT_CHALLENGE_MIN_LEVEL
            end,
            setFunc = function(val)
                GetCharEquipmentDB().challengeMinLevel = val
                if active then EH:OnChallengeChanged() end
            end,
        })
        C:AddSlider(section, {
            label = L["Scale"],
            min = 0.5,
            max = 2,
            step = 0.05,
            getFunc = function() return (Cfg().scale) or 1 end,
            setFunc = function(val)
                Cfg().scale = val
                ApplyPosition()
            end,
        })
    end,
    Refresh = function()
        if addon:IsFeatureEnabled(KEY) then
            ApplyPosition()
            EH:UpdateButtons()
        end
    end,
})

addon.EquipmentHelper = EH
