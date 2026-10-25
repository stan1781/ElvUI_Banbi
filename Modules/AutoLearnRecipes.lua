-- ElvUI_Banbi — auto `.learn all recipes <中文专业>` for VIP when learning (or optionally opening) a profession.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "autoLearnRecipes"

local CreateFrame = CreateFrame
local GetNumSkillLines = GetNumSkillLines
local GetSkillLineInfo = GetSkillLineInfo
local GetTradeSkillLine = GetTradeSkillLine
local SendChatMessage = SendChatMessage
local hooksecurefunc = hooksecurefunc
local pairs = pairs
local type = type
local tostring = tostring
local format = string.format
local find = string.find

-- Canonical Chinese names used in `.learn all recipes …`
local PROFESSION_ORDER = {
    "锻造",
    "炼金术",
    "附魔",
    "工程学",
    "草药学",
    "铭文",
    "珠宝加工",
    "制皮",
    "裁缝",
    "采矿",
    "剥皮",
    "烹饪",
    "急救",
    "钓鱼",
}

-- Skill-line / trade-skill display names → canonical command name
local ALIASES = {
    ["锻造"] = "锻造",
    ["Blacksmithing"] = "锻造",
    ["炼金术"] = "炼金术",
    ["炼金"] = "炼金术",
    ["Alchemy"] = "炼金术",
    ["附魔"] = "附魔",
    ["Enchanting"] = "附魔",
    ["工程学"] = "工程学",
    ["工程"] = "工程学",
    ["Engineering"] = "工程学",
    ["草药学"] = "草药学",
    ["草药"] = "草药学",
    ["Herbalism"] = "草药学",
    ["铭文"] = "铭文",
    ["Inscription"] = "铭文",
    ["珠宝加工"] = "珠宝加工",
    ["珠宝"] = "珠宝加工",
    ["Jewelcrafting"] = "珠宝加工",
    ["制皮"] = "制皮",
    ["Leatherworking"] = "制皮",
    ["裁缝"] = "裁缝",
    ["Tailoring"] = "裁缝",
    ["采矿"] = "采矿",
    ["Mining"] = "采矿",
    ["剥皮"] = "剥皮",
    ["Skinning"] = "剥皮",
    ["烹饪"] = "烹饪",
    ["Cooking"] = "烹饪",
    ["急救"] = "急救",
    ["First Aid"] = "急救",
    ["钓鱼"] = "钓鱼",
    ["Fishing"] = "钓鱼",
}

local LEARN_DELAY = 0.4

local eventFrame
local active = false
local knownSkills = {} -- canonical → true
local sessionFired = {} -- canonical → true
local pendingFire = {} -- canonical → true (delay reserved)
local dragonHooked = false
local ready = false -- true after first PEW snapshot

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function Print(msg)
    local prefix = "|cff1784d1Banbi|r"
    local chat = DEFAULT_CHAT_FRAME or ChatFrame1
    if chat and chat.AddMessage then
        chat:AddMessage(prefix .. " " .. tostring(msg))
    end
end

local function After(delay, fn)
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(fn, delay)
        return
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
end

local function ResolveCanonical(name)
    if not name or name == "" then
        return nil
    end
    local exact = ALIASES[name]
    if exact then
        return exact
    end
    -- Prefer longer alias keys first to avoid short false positives
    local best, bestLen
    for alias, canon in pairs(ALIASES) do
        if find(name, alias, 1, true) then
            local len = #alias
            if not bestLen or len > bestLen then
                best = canon
                bestLen = len
            end
        end
    end
    return best
end

local function IsProfessionEnabled(canonical)
    local cfg = Cfg()
    if not cfg then
        return true
    end
    local map = cfg.professions
    if type(map) ~= "table" then
        return true
    end
    if map[canonical] == nil then
        return true
    end
    return map[canonical] and true or false
end

local function ScanProfessionSkills()
    local found = {} -- canonical → { rank, maxRank }
    local n = GetNumSkillLines and GetNumSkillLines() or 0
    for i = 1, n do
        local skillName, isHeader, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if not isHeader then
            local canon = ResolveCanonical(skillName)
            if canon then
                found[canon] = {
                    rank = skillRank or 0,
                    maxRank = skillMaxRank or 0,
                }
            end
        end
    end
    return found
end

local function FireLearn(canonical, delayed)
    if not canonical or sessionFired[canonical] or pendingFire[canonical] then
        return
    end
    if not IsProfessionEnabled(canonical) then
        return
    end

    local function doSend()
        pendingFire[canonical] = nil
        if not active or sessionFired[canonical] then
            return
        end
        if not IsProfessionEnabled(canonical) then
            return
        end
        sessionFired[canonical] = true
        SendChatMessage(".learn all recipes " .. canonical, "SAY")
        Print(format(L["AutoLearn: fired %s"] or "已自动学习配方：%s", canonical))
    end

    pendingFire[canonical] = true
    if delayed then
        After(LEARN_DELAY, doSend)
    else
        doSend()
    end
end

local function SnapshotSkills(fireNew)
    local found = ScanProfessionSkills()

    if fireNew and ready then
        local cfg = Cfg()
        if not cfg or cfg.onLearn ~= false then
            for canon in pairs(found) do
                if not knownSkills[canon] then
                    FireLearn(canon, true)
                end
            end
        end
    end

    -- Drop abandoned professions so re-learn can fire again
    for canon in pairs(knownSkills) do
        if not found[canon] then
            knownSkills[canon] = nil
            sessionFired[canon] = nil
            pendingFire[canon] = nil
        end
    end
    for canon in pairs(found) do
        knownSkills[canon] = true
    end
end

local function TryOpenRefill()
    local cfg = Cfg()
    if not cfg or not cfg.onOpen then
        return
    end
    if not GetTradeSkillLine then
        return
    end

    -- 3.3.5: GetTradeSkillLine() → name, currentLevel, maxLevel
    local name, rank, maxRank = GetTradeSkillLine()
    local canon = ResolveCanonical(name)
    if not canon then
        return
    end
    rank = tonumber(rank) or 0
    maxRank = tonumber(maxRank) or 0
    if maxRank > 0 and rank >= maxRank then
        return
    end
    -- maxRank == 0: still allow refill (unknown max / custom UI)
    FireLearn(canon, false)
end

local function TryHookDragonUI()
    if dragonHooked then
        return
    end
    local dui = _G.DragonUI
    if type(dui) ~= "table" then
        return
    end
    if type(dui.ToggleProfessionsBook) ~= "function" then
        return
    end
    local ok = pcall(function()
        hooksecurefunc(dui, "ToggleProfessionsBook", function()
            if not active then
                return
            end
            After(0.5, TryOpenRefill)
        end)
    end)
    if ok then
        dragonHooked = true
    end
end

local function OnEvent(_, event)
    if not active then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        SnapshotSkills(false)
        ready = true
        TryHookDragonUI()
        return
    end
    if event == "SKILL_LINES_CHANGED" then
        if not ready then
            return
        end
        SnapshotSkills(true)
        return
    end
    if event == "TRADE_SKILL_SHOW" then
        TryOpenRefill()
        return
    end
end

local function EnsureFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame", "ElvUI_Banbi_AutoLearnRecipes")
    eventFrame:SetScript("OnEvent", OnEvent)
    return eventFrame
end

local function ClearSessionFired()
    for k in pairs(sessionFired) do
        sessionFired[k] = nil
    end
    for k in pairs(pendingFire) do
        pendingFire[k] = nil
    end
    Print(L["AutoLearn: session cleared"] or "已清空本会话自动学习记录")
end

local function OnEnable()
    active = true
    ready = false
    knownSkills = {}
    sessionFired = {}
    pendingFire = {}
    local f = EnsureFrame()
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("SKILL_LINES_CHANGED")
    f:RegisterEvent("TRADE_SKILL_SHOW")
    SnapshotSkills(false)
    ready = true
    TryHookDragonUI()
end

local function OnDisable()
    active = false
    ready = false
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

addon:RegisterFeature(KEY, {
    category = "general",
    default = true,
    label = function()
        return L["Auto Learn Recipes"] or "自动学习专业配方"
    end,
    desc = function()
        return L["Auto Learn Recipes Desc"]
            or "学会专业时自动发送 .learn all recipes（顶 V）；可选打开未满级专业时再补。"
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    BuildOptions = function(section, C)
        C:AddDescription(
            section,
            L["Auto Learn Recipes Help"]
                or "顶 V 可用 .learn all recipes。无权限时服务器会报错，可自行关闭。打开再补依赖原版/可探测的专业 UI，DragonUI 可能无效。"
        )
        C:AddToggle(section, {
            label = L["AutoLearn: on learn"] or "学会专业时自动满级",
            desc = L["AutoLearn: on learn desc"] or "检测到新专业技能行时发送命令。",
            getFunc = function()
                local cfg = Cfg()
                return not cfg or cfg.onLearn ~= false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.onLearn = val and true or false
                end
            end,
        })
        C:AddToggle(section, {
            label = L["AutoLearn: on open"] or "打开未满级专业时再补",
            desc = L["AutoLearn: on open desc"]
                or "TRADE_SKILL_SHOW / 可探测 UI 时，未满级且本会话未发过则再发一次。默认关闭。",
            getFunc = function()
                local cfg = Cfg()
                return cfg and cfg.onOpen and true or false
            end,
            setFunc = function(val)
                local cfg = Cfg()
                if cfg then
                    cfg.onOpen = val and true or false
                end
            end,
        })
        C:AddDescription(section, L["AutoLearn: professions header"] or "启用的专业")
        for i = 1, #PROFESSION_ORDER do
            local name = PROFESSION_ORDER[i]
            C:AddToggle(section, {
                label = name,
                getFunc = function()
                    return IsProfessionEnabled(name)
                end,
                setFunc = function(val)
                    local cfg = Cfg()
                    if not cfg then
                        return
                    end
                    if type(cfg.professions) ~= "table" then
                        cfg.professions = {}
                    end
                    cfg.professions[name] = val and true or false
                end,
            })
        end
        C:AddButton(section, {
            label = L["AutoLearn: clear session"] or "清空本会话已发送记录",
            desc = L["AutoLearn: clear session desc"] or "允许同一次登录内对同一专业再次自动发送。",
            callback = ClearSessionFired,
        })
    end,
})
