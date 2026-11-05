-- ElvUI_Banbi — one-shot read-only import from old SavedVariables.

local ADDON_NAME, addon = ...

local function Mark(key)
    local g = addon.db and addon.db.global
    if not g then return true end
    g.migrated = g.migrated or {}
    if g.migrated[key] then
        return true
    end
    g.migrated[key] = true
    return false
end

local function CopyTable(src, dst)
    if type(src) ~= "table" or type(dst) ~= "table" then
        return
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            CopyTable(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function addon:Migrate()
    if not addon.db then
        return
    end

    -- 关掉与 ElvUI 冲突的 Banbi 聊天时间戳（只执行一次）
    if not Mark("disableChatTimestamp") then
        local cfg = addon:GetFeatureConfig("chatEnhance")
        if cfg then
            cfg.timestamp = false
        end
    end

    -- TinyInspectConfig (panel toggles only; item-source tooltips removed)
    if not Mark("tinyInspect") then
        local old = _G.TinyInspectConfig
        if type(old) == "table" then
            local cfg = addon:GetFeatureConfig("inspectPanel")
            if cfg then
                if old.inspectWindow ~= nil then cfg.inspectWindow = old.inspectWindow and true or false end
                if old.charWindow ~= nil then cfg.charWindow = old.charWindow and true or false end
            end
        end
    end

    -- BagSyncTokenBarDB → infoBar
    if not Mark("tokenBar") then
        local old = _G.BagSyncTokenBarDB
        if type(old) == "table" then
            local cfg = addon:GetFeatureConfig("infoBar")
            if cfg and old.enabled ~= nil then
                cfg.enabled = old.enabled and true or false
            end
        end
    end

    -- Merge legacy tokenBar + statBar into infoBar (one-shot)
    if not Mark("infoBarMerge") then
        local feats = addon.db.profile.features
        if type(feats) == "table" then
            local oldToken = feats.tokenBar
            local oldStat = feats.statBar
            local cfg = addon:GetFeatureConfig("infoBar")
            if cfg and (type(oldToken) == "table" or type(oldStat) == "table") then
                local tOn = type(oldToken) == "table" and oldToken.enabled ~= false
                local sOn = type(oldStat) == "table" and oldStat.enabled ~= false
                if type(oldToken) == "table" or type(oldStat) == "table" then
                    cfg.enabled = (tOn or sOn) and true or false
                end
                if type(oldStat) == "table" then
                    if oldStat.fontSize ~= nil then cfg.fontSize = oldStat.fontSize end
                    if oldStat.showCorruption ~= nil then cfg.showCorruption = oldStat.showCorruption and true or false end
                    if oldStat.showPower ~= nil then cfg.showPower = oldStat.showPower and true or false end
                    if oldStat.showCrit ~= nil then cfg.showCrit = oldStat.showCrit and true or false end
                    if oldStat.showHaste ~= nil then cfg.showHaste = oldStat.showHaste and true or false end
                    if oldStat.powerMode ~= nil then cfg.powerMode = oldStat.powerMode end
                    if oldStat.posX ~= nil then cfg.posX = oldStat.posX end
                    if oldStat.posY ~= nil then cfg.posY = oldStat.posY end
                    if oldStat.anchor ~= nil then cfg.anchor = oldStat.anchor end
                end
                if type(oldToken) == "table" then
                    if type(oldToken.tokens) == "table" then
                        cfg.tokens = cfg.tokens or {}
                        CopyTable(oldToken.tokens, cfg.tokens)
                    end
                    -- Prefer stat position when present; else token
                    if type(oldStat) ~= "table" or oldStat.posX == nil then
                        if oldToken.posX ~= nil then cfg.posX = oldToken.posX end
                        if oldToken.posY ~= nil then cfg.posY = oldToken.posY end
                        if oldToken.anchor ~= nil then cfg.anchor = oldToken.anchor end
                    end
                end
            end
            feats.tokenBar = nil
            feats.statBar = nil
        end
    end

    -- bbToolsDB (rune / equipment / friendSync / autoJoinChannel)
    if not Mark("bbTools") then
        local old = _G.bbToolsDB
        if type(old) == "table" then
            local g = addon.db.global
            if type(old.runeActionBar) == "table" then
                CopyTable(old.runeActionBar, g.runeActionBar)
            end
            if type(old.equipment) == "table" then
                CopyTable(old.equipment, g.equipment)
            end
            if type(old.friendSync) == "table" then
                CopyTable(old.friendSync, g.friendSync)
            elseif type(old.FriendSync) == "table" then
                CopyTable(old.FriendSync, g.friendSync)
            end
            if type(old.settings) == "table" then
                if old.settings.autoJoinChannel ~= nil then
                    local cfg = addon:GetFeatureConfig("chatEnhance")
                    if cfg then
                        cfg.autoJoinLfg = old.settings.autoJoinChannel and true or false
                    end
                end
            end
        end
    end

    -- DragonUI_EnhancedDB as fill-in only (do not confuse with our own SV)
    if not Mark("dragonUIEnhanced") then
        local old = _G.DragonUI_EnhancedDB
        if type(old) == "table" then
            if type(old.profile) == "table" and type(old.profile.features) == "table" then
                local feats = addon.db.profile.features
                for key, src in pairs(old.profile.features) do
                    if type(src) == "table" and type(feats[key]) == "table" then
                        CopyTable(src, feats[key])
                    end
                end
            end
            if type(old.global) == "table" then
                local g = addon.db.global
                if type(old.global.runeActionBar) == "table" then
                    CopyTable(old.global.runeActionBar, g.runeActionBar)
                end
                if type(old.global.equipment) == "table" then
                    CopyTable(old.global.equipment, g.equipment)
                end
                if type(old.global.friendSync) == "table" then
                    CopyTable(old.global.friendSync, g.friendSync)
                end
            end
        end
    end
end
