-- ElvUI_Banbi — Hunter Aspect Bar (WotLK 3.3.5a / Interface 30300).
-- 第一版：把猎人「姿态栏」里已学会的守护列成一条可点击、可拖动、可调尺寸的按钮条。
-- 增量：猎豹/豹群守护下挨打时，自动切换到指定守护（灵猴/雄鹰/龙鹰，可选）。
--   - 检测：COMBAT_LOG_EVENT_UNFILTERED 中自己是受击方 + 当前姿态是猎豹系。
--   - 施法：CastSpellByName。官方客户端会拦（触发 ADDON_ACTION_BLOCKED，这里只提示一次）；
--     私服/改客户端不拦时生效——多玩 3.3.5 同类功能即依赖这种环境。
-- 按钮条本身只在玩家真实点击时施放；不做循环输出；战斗中不改受保护按钮的属性/位置/显示。

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "aspectBar"
local MAX_BUTTONS = 12
local PAD = 4
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- 首次使用 / 旧配置缺字段时补齐用；只补缺，不清空用户原有值。
local DEFAULTS = {
    buttonSize = 36,
    spacing = 4,
    columns = 6,
    anchor = "CENTER",
    posX = 0,
    posY = -160,
    showBackdrop = true,
    autoSwitch = true,
    autoSwitchTarget = "monkey",
    highlightActive = true,
}

-- --- 挨打自动换守护：守护识别（名字为主、技能 ID 为辅，均需按当前客户端核对） ---
local CHEETAH_IDS = {
    [5118] = true,  -- 猎豹守护 Aspect of the Cheetah
    [13159] = true, -- 豹群守护 Aspect of the Pack
}
local CHEETAH_NAMES = {
    ["猎豹守护"] = true,
    ["豹群守护"] = true,
    ["Aspect of the Cheetah"] = true,
    ["Aspect of the Pack"] = true,
}
local FALLBACK_ASPECTS = {
    monkey = { id = 13163, names = { "灵猴守护", "Aspect of the Monkey" } },
    hawk = { id = 13165, names = { "雄鹰守护", "Aspect of the Hawk" } },
    dragonhawk = { id = 61847, names = { "龙鹰守护", "Aspect of the Dragonhawk" } },
}
-- 只算直接命中（猎豹眩晕来自被击中）；DoT/环境跳字不算
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    DAMAGE_SHIELD = true,
    DAMAGE_SPLIT = true,
}
local SWITCH_THROTTLE = 1.0 -- 守护公共冷却 1 秒

-- 固定显示顺序：龙鹰/猎豹/灵猴/野兽/自然/蝰蛇/豹群/雄鹰
local ASPECT_ORDER = { "dragonhawk", "cheetah", "monkey", "beast", "wild", "viper", "pack", "hawk" }
local ASPECT_META = {
    dragonhawk = {
        ids = { 61847, 61846 },
        names = { "龙鹰守护", "Aspect of the Dragonhawk" },
    },
    cheetah = {
        ids = { 5118 },
        names = { "猎豹守护", "Aspect of the Cheetah" },
    },
    hawk = {
        ids = { 13165 },
        names = { "雄鹰守护", "Aspect of the Hawk" },
    },
    monkey = {
        ids = { 13163 },
        names = { "灵猴守护", "Aspect of the Monkey" },
    },
    beast = {
        ids = { 13161 },
        names = { "野兽守护", "Aspect of the Beast" },
    },
    wild = {
        ids = { 20043 },
        names = { "野性守护", "自然守护", "Aspect of the Wild" },
    },
    viper = {
        ids = { 34074 },
        names = { "蝰蛇守护", "Aspect of the Viper" },
    },
    pack = {
        ids = { 13159 },
        names = { "豹群守护", "Aspect of the Pack" },
    },
}
local ASPECT_SPELL_IDS = {}
local SPELL_ID_TO_KEY = {}
local NAME_TO_KEY = {}
do
    for i = 1, #ASPECT_ORDER do
        local key = ASPECT_ORDER[i]
        local meta = ASPECT_META[key]
        if meta then
            for j = 1, #meta.ids do
                local id = meta.ids[j]
                ASPECT_SPELL_IDS[#ASPECT_SPELL_IDS + 1] = id
                SPELL_ID_TO_KEY[id] = key
            end
            for j = 1, #meta.names do
                NAME_TO_KEY[meta.names[j]] = key
            end
        end
    end
end
local DRAGONHAWK_IDS = {
    [61847] = true,
    [61846] = true,
}
local DRAGONHAWK_NAMES = {
    ["龙鹰守护"] = true,
    ["Aspect of the Dragonhawk"] = true,
}

local bar
local buttons = {}
local aspects = {}
local active = false
local pendingLayout = false
local moverRegistered = false
local playerGUID
local isHunter = false
local lastSwitchTry = 0
local blockedNoticeShown = false
local missingTargetNotified = {}

-- ---------------------------------------------------------------------------
-- 配置（ElvUI_BanbiDB 已在 toc 声明，AceDB 按 profile 存取）
-- ---------------------------------------------------------------------------

local function Cfg()
    return addon:GetFeatureConfig(KEY)
end

local function NormalizeConfig()
    local cfg = Cfg()
    if not cfg then
        return nil
    end
    for k, v in pairs(DEFAULTS) do
        if cfg[k] == nil then
            cfg[k] = v
        end
    end
    return cfg
end

local function AspectKeyOf(info)
    if not info then
        return nil
    end
    if info.spellID and SPELL_ID_TO_KEY[info.spellID] then
        return SPELL_ID_TO_KEY[info.spellID]
    end
    if info.name and NAME_TO_KEY[info.name] then
        return NAME_TO_KEY[info.name]
    end
    return nil
end

local function SortAspects(list)
    local rank = {}
    for i = 1, #ASPECT_ORDER do
        rank[ASPECT_ORDER[i]] = i
    end
    table.sort(list, function(a, b)
        local ka, kb = AspectKeyOf(a), AspectKeyOf(b)
        local ra = (ka and rank[ka]) or 1000
        local rb = (kb and rank[kb]) or 1000
        if ra ~= rb then
            return ra < rb
        end
        return (a.index or 0) < (b.index or 0)
    end)
    return list
end

local function Num(key, minV, maxV, fallback)
    local cfg = Cfg()
    local v = cfg and tonumber(cfg[key])
    if not v then
        return fallback
    end
    if v < minV then
        return minV
    elseif v > maxV then
        return maxV
    end
    return v
end

local function IsHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-- ---------------------------------------------------------------------------
-- 读取姿态栏：不硬编码守护名与技能 ID，客户端给什么就显示什么
-- 3.3.5 返回值形状: texture, name, isActive, isCastable, spellID
-- 较新客户端形状:   icon, isActive, isCastable, spellID（第二返回值不再是名字）
-- 取不到名字时用 spellID 向 GetSpellInfo 补一个本地化名字。
-- ---------------------------------------------------------------------------

local function ParseFormInfo(a, b, c, d, e)
    local texture, name, isActive, spellID
    if type(b) == "string" then
        texture, name, isActive = a, b, c
        if type(e) == "number" then
            spellID = e
        elseif type(d) == "number" then
            spellID = d
        end
    elseif type(a) == "string" or type(a) == "number" then
        -- 新客户端 / 部分私服：icon, isActive, isCastable, spellID
        texture, isActive = a, b
        if type(d) == "number" then
            spellID = d
        elseif type(c) == "number" then
            spellID = c
        end
    end
    if not name and spellID and GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    if (not texture or texture == "") and spellID and GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellID)
        texture = icon
    end
    return texture, name, isActive, spellID
end

local function ResolveAspectIcon(name, spellID, texture)
    -- 本服龙鹰图标以 61847 为准
    if (spellID and DRAGONHAWK_IDS[spellID]) or (name and DRAGONHAWK_NAMES[name]) then
        local _, _, icon = GetSpellInfo(61847)
        if icon then
            return icon
        end
        _, _, icon = GetSpellInfo(61846)
        if icon then
            return icon
        end
    end
    if (not texture or texture == "" or texture == QUESTION_ICON) and spellID and GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellID)
        if icon then
            return icon
        end
    end
    return texture or QUESTION_ICON
end

-- 用名字 / 图标路径匹配玩家身上的守护 buff（3.3.5 UnitBuff 无 spellID）
local function IsAspectBuffActive(name, spellID, texture)
    if not UnitBuff then
        return false
    end
    local expectIcon = ResolveAspectIcon(name, spellID, texture)
    for i = 1, 40 do
        local buffName, _, buffIcon = UnitBuff("player", i)
        if not buffName then
            break
        end
        if name and buffName == name then
            return true
        end
        if expectIcon and buffIcon and expectIcon == buffIcon then
            return true
        end
    end
    return false
end

local function SyncActiveFlags()
    for i = 1, #aspects do
        local info = aspects[i]
        if info then
            local formActive = info.formActive and true or false
            info.active = formActive or IsAspectBuffActive(info.name, info.spellID, info.texture)
        end
    end
end

local function ReadAspectsFromSpells()
    local list = {}
    if not IsSpellKnown or not GetSpellInfo then
        return list
    end
    local seen = {}
    for i = 1, #ASPECT_SPELL_IDS do
        local spellID = ASPECT_SPELL_IDS[i]
        if IsSpellKnown(spellID) then
            local name, _, icon = GetSpellInfo(spellID)
            if name and not seen[name] then
                seen[name] = true
                icon = ResolveAspectIcon(name, spellID, icon)
                list[#list + 1] = {
                    index = #list + 1,
                    name = name,
                    spellID = spellID,
                    texture = icon or QUESTION_ICON,
                    formActive = false,
                    active = IsAspectBuffActive(name, spellID, icon),
                }
            end
        end
    end
    return list
end

local function ReadAspects()
    local list = {}
    if not isHunter then
        return list
    end
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local n = GetNumShapeshiftForms() or 0
        for i = 1, math.min(n, MAX_BUTTONS) do
            local texture, name, isActive, spellID = ParseFormInfo(GetShapeshiftFormInfo(i))
            -- 姿态栏若带回旧龙鹰 ID，纠正为 61847 图标与施法名
            if (spellID and DRAGONHAWK_IDS[spellID]) or (name and DRAGONHAWK_NAMES[name]) then
                spellID = 61847
                local fixedName = GetSpellInfo(61847)
                if fixedName then
                    name = fixedName
                end
            end
            texture = ResolveAspectIcon(name, spellID, texture)
            list[#list + 1] = {
                index = i,
                name = name,
                spellID = spellID,
                texture = texture or QUESTION_ICON,
                formActive = isActive and true or false,
                active = false,
            }
        end
    end
    if #list == 0 then
        list = ReadAspectsFromSpells()
    else
        for i = 1, #list do
            local info = list[i]
            info.active = info.formActive or IsAspectBuffActive(info.name, info.spellID, info.texture)
        end
    end
    return SortAspects(list)
end

-- ---------------------------------------------------------------------------
-- 外观与位置（对齐 ElvUI SetTemplate / StyleButton / CreateMover）
-- ---------------------------------------------------------------------------

local function ApplyButtonSkin(btn)
    if not btn then
        return
    end
    local E = addon:GetE()
    if btn.icon then
        if E and E.TexCoords then
            btn.icon:SetTexCoord(unpack(E.TexCoords))
        else
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if btn.icon.SetInside then
            btn.icon:SetInside()
        else
            btn.icon:ClearAllPoints()
            btn.icon:SetPoint("TOPLEFT", 2, -2)
            btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        end
    end
    if not btn._banbiSkinned then
        if btn.CreateBackdrop then
            btn:CreateBackdrop("Default", true)
            if btn.backdrop then
                btn.backdrop:SetAllPoints()
            end
        elseif btn.SetTemplate then
            btn:SetTemplate("Default", true)
        end
        if btn.StyleButton then
            btn:StyleButton(true, nil, true)
        end
        btn._banbiSkinned = true
    end
end

local function ApplyChrome()
    if not bar then
        return
    end
    local cfg = NormalizeConfig()
    local show = not cfg or cfg.showBackdrop ~= false
    if bar.SetTemplate then
        if show then
            bar:SetTemplate("Transparent")
        else
            bar:SetTemplate("NoBackdrop")
        end
        return
    end
    if not show then
        if bar.SetBackdrop then
            bar:SetBackdrop(nil)
        end
        return
    end
    if not bar.SetBackdrop then
        return
    end
    local E = addon.GetE and addon:GetE()
    local tex = (E and E.media and (E.media.blankTex or E.media.normTex)) or WHITE
    bar:SetBackdrop({
        bgFile = tex,
        edgeFile = tex,
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.6)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
end

local function PersistPosition()
    if not bar then
        return
    end
    local cfg = NormalizeConfig()
    if not cfg then
        return
    end
    local source = bar.mover or bar
    local cx, cy = source:GetCenter()
    local px, py = UIParent:GetCenter()
    if not cx or not cy or not px or not py then
        return
    end
    cfg.anchor = "CENTER"
    cfg.posX = cx - px
    cfg.posY = cy - py
end

local function ApplyPosition()
    if not bar then
        return
    end
    -- ElvUI mover 接管锚点后，不要再 ClearAllPoints 打断绑定
    if bar.mover then
        return
    end
    local cfg = NormalizeConfig()
    local x = (cfg and cfg.posX) or DEFAULTS.posX
    local y = (cfg and cfg.posY) or DEFAULTS.posY
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function RegisterMover()
    if moverRegistered or not bar then
        return
    end
    local E = addon:GetE()
    if not (E and E.CreateMover) then
        return
    end
    E:CreateMover(bar, "BanbiAspectBarMover", L["Aspect Bar"] or "Aspect Bar", nil, nil, function()
        PersistPosition()
    end, "ALL,ACTIONBARS")
    moverRegistered = true
end

-- ---------------------------------------------------------------------------
-- 按钮：SecureActionButtonTemplate，只在硬件点击时施放
-- ---------------------------------------------------------------------------

local function OnEnter(self)
    if not self.aspectName then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.aspectName)
    if self.isActive then
        GameTooltip:AddLine(L["Active aspect"] or "Active aspect", 0.3, 1, 0.3)
    end
    GameTooltip:AddLine(L["Click to switch aspect"] or "Click to switch aspect", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

-- ---------------------------------------------------------------------------
-- 金色点点沿边框跑动：共用实现见 Modules/PixelGlow.lua
-- ---------------------------------------------------------------------------

local function StartPixelGlow(btn)
    addon:StartPixelGlow(btn, "BanbiAspect")
end

local function StopPixelGlow(btn)
    addon:StopPixelGlow(btn, "BanbiAspect")
end

local function CreateButton(i)
    local btn = CreateFrame("Button", "ElvUI_Banbi_AspectButton" .. i, bar, "SecureActionButtonTemplate")
    btn:SetWidth(DEFAULTS.buttonSize)
    btn:SetHeight(DEFAULTS.buttonSize)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    -- 硬件点击施放；属性只在非战斗时写入
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", "")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexture(QUESTION_ICON)
    btn.icon = icon

    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    ApplyButtonSkin(btn)
    btn:Hide()
    return btn
end

local function EnsureBar()
    if bar then
        return bar
    end
    bar = CreateFrame("Frame", "ElvUI_Banbi_AspectBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(50)
    bar:SetWidth(DEFAULTS.buttonSize + PAD * 2)
    bar:SetHeight(DEFAULTS.buttonSize + PAD * 2)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    -- 位置由 ElvUI 锚点（BanbiAspectBarMover）控制，不再提供条本身拖动/锁定
    ApplyPosition()
    ApplyChrome()
    for i = 1, MAX_BUTTONS do
        buttons[i] = CreateButton(i)
    end
    RegisterMover()
    return bar
end

-- 只刷高亮：不动按钮属性/位置/显示，战斗中也可安全执行
local function RefreshActive()
    local cfg = NormalizeConfig()
    local highlight = not cfg or cfg.highlightActive ~= false
    SyncActiveFlags()
    for i = 1, MAX_BUTTONS do
        local btn = buttons[i]
        local info = aspects[i]
        if btn then
            local isOn = highlight and info and info.active or false
            btn.isActive = isOn
            -- 图标始终保持清晰，不再用半透明白膜盖住
            if btn.icon then
                btn.icon:SetVertexColor(1, 1, 1)
            end
            if isOn then
                if not btn._banbiGlowOn then
                    StartPixelGlow(btn)
                end
            else
                if btn._banbiGlowOn then
                    StopPixelGlow(btn)
                end
            end
            if btn.backdrop and btn.backdrop.SetBackdropBorderColor then
                if isOn then
                    btn.backdrop:SetBackdropBorderColor(1, 0.82, 0.2, 1)
                else
                    local E = addon:GetE()
                    local b = E and E.media and E.media.bordercolor
                    if b then
                        btn.backdrop:SetBackdropBorderColor(b.r or 0, b.g or 0, b.b or 0, 1)
                    else
                        btn.backdrop:SetBackdropBorderColor(0, 0, 0, 1)
                    end
                end
            end
        end
    end
end

local function ApplyLayout()
    if not active then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        return
    end
    pendingLayout = false
    if not isHunter then
        if bar then
            bar:Hide()
        end
        return
    end
    EnsureBar()

    local size = Num("buttonSize", 20, 64, DEFAULTS.buttonSize)
    local gap = Num("spacing", 0, 16, DEFAULTS.spacing)
    local cols = Num("columns", 1, MAX_BUTTONS, DEFAULTS.columns)
    local shown = #aspects
    if shown > MAX_BUTTONS then
        shown = MAX_BUTTONS
    end

    for i = 1, MAX_BUTTONS do
        local btn = buttons[i]
        if i <= shown then
            local info = aspects[i]
            local castName = info.name
            btn.aspectName = castName or ((L["Aspect"] or "Aspect") .. " " .. i)
            btn.icon:SetTexture(info.texture or QUESTION_ICON)
            -- 没取到守护名就不绑定施法，避免误施放别的技能
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", castName or "")
            btn:SetWidth(size)
            btn:SetHeight(size)
            ApplyButtonSkin(btn)
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + col * (size + gap), -PAD - row * (size + gap))
            btn:Show()
        else
            btn:Hide()
        end
    end
    RefreshActive()

    local usedCols = shown > 0 and math.min(cols, shown) or 1
    local rows = shown > 0 and math.ceil(shown / cols) or 1
    local width = math.max(PAD * 2 + usedCols * size + (usedCols - 1) * gap, size + PAD * 2)
    local height = math.max(PAD * 2 + rows * size + (rows - 1) * gap, size + PAD * 2)
    bar:SetWidth(width)
    bar:SetHeight(height)
    ApplyChrome()
    if bar.mover then
        bar.mover:SetWidth(width)
        bar.mover:SetHeight(height)
    else
        ApplyPosition()
    end
    -- 猎人启用时始终显示容器（即使暂时 0 个技能也方便拖动/确认加载）
    if isHunter then
        bar:Show()
    else
        bar:Hide()
    end
end

local function Rebuild()
    isHunter = IsHunter()
    aspects = ReadAspects()
    if InCombatLockdown and InCombatLockdown() then
        pendingLayout = true
        RefreshActive()
        return
    end
    ApplyLayout()
end

-- ---------------------------------------------------------------------------
-- 挨打自动换守护（仅当前姿态为猎豹/豹群时）
-- ---------------------------------------------------------------------------

local function GetCurrentAspect()
    if GetShapeshiftForm and GetShapeshiftFormInfo then
        local idx = GetShapeshiftForm()
        if idx and idx ~= 0 then
            local _, name, _, spellID = ParseFormInfo(GetShapeshiftFormInfo(idx))
            if name or spellID then
                return name, spellID
            end
        end
    end
    -- 姿态栏读不到时，用 buff / 已知守护表兜底
    for i = 1, #aspects do
        local info = aspects[i]
        if info and info.name and IsAspectBuffActive(info.name, info.spellID, info.texture) then
            return info.name, info.spellID
        end
    end
    for name in pairs(CHEETAH_NAMES) do
        if IsAspectBuffActive(name) then
            return name, nil
        end
    end
    return nil, nil
end

local function IsCheetahAspect(name, spellID)
    if spellID and CHEETAH_IDS[spellID] then
        return true
    end
    if name and CHEETAH_NAMES[name] then
        return true
    end
    return false
end

-- 在姿态栏里找落地守护的名字（找到的才是本客户端认的名字）
local function FindFallbackAspectName(targetKey)
    local def = FALLBACK_ASPECTS[targetKey]
    if not def then
        return nil
    end
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        local n = GetNumShapeshiftForms() or 0
        for i = 1, n do
            local _, name, _, spellID = ParseFormInfo(GetShapeshiftFormInfo(i))
            if name then
                for j = 1, #def.names do
                    if name == def.names[j] then
                        return name
                    end
                end
            end
            if spellID and spellID == def.id then
                return name
            end
        end
    end
    -- 技能书兜底：按 ID 取本地化名（名字拿得到，施不施得出去由客户端的保护机制决定）
    if GetSpellInfo and def.id then
        return GetSpellInfo(def.id)
    end
    return nil
end

-- ADDON_ACTION_BLOCKED：参数顺序按 (addon, func) 处理，顺序不一致也兜住
local function OnAddonBlocked(...)
    if blockedNoticeShown then
        return
    end
    local a, b = ...
    local funcName, addonName
    if a == "CastSpellByName" then
        funcName, addonName = a, b
    elseif b == "CastSpellByName" then
        funcName, addonName = b, a
    else
        return
    end
    if addonName and addonName ~= ADDON_NAME then
        return
    end
    blockedNoticeShown = true
    print("|cff1784d1Banbi|r " .. (L["AspectBar: auto-switch blocked"]
        or "This client blocks addon casting (CastSpellByName); aspect auto-switch is unavailable. Display features still work."))
end

local function OnCombatLog(timestamp, eventType, sourceGUID, sourceName, sourceFlags, destGUID)
    if not active or not isHunter or not playerGUID then
        return
    end
    if not DAMAGE_EVENTS[eventType] then
        return
    end
    if destGUID ~= playerGUID then
        return
    end
    local cfg = Cfg()
    if not cfg or cfg.autoSwitch == false then
        return
    end

    local curName, curID = GetCurrentAspect()
    if not IsCheetahAspect(curName, curID) then
        return
    end

    local now = GetTime()
    if now - lastSwitchTry < SWITCH_THROTTLE then
        return
    end
    lastSwitchTry = now

    local target = FindFallbackAspectName(cfg.autoSwitchTarget)
    if not target or target == "" then
        local key = tostring(cfg.autoSwitchTarget or "?")
        if not missingTargetNotified[key] then
            missingTargetNotified[key] = true
            print("|cff1784d1Banbi|r " .. string.format(
                L["AspectBar: fallback aspect missing"] or "Aspect not found: %s", key))
        end
        return
    end

    -- 私服/改客户端不拦时施放成功并靠 UPDATE_SHAPESHIFT_FORM 刷新高亮；
    -- 官方客户端会触发 ADDON_ACTION_BLOCKED（见 OnAddonBlocked）。
    pcall(CastSpellByName, target)
end

-- ---------------------------------------------------------------------------
-- 事件
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

local function OnEvent(_, event, ...)
    if not active then
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog(...)
        return
    elseif event == "ADDON_ACTION_BLOCKED" then
        OnAddonBlocked(...)
        return
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            RefreshActive()
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 脱战统一重读一次：既补做战斗中攒下的布局改动，也保证高亮是最新的
        Rebuild()
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        isHunter = IsHunter()
        Rebuild()
        return
    end
    Rebuild()
end

eventFrame:SetScript("OnEvent", OnEvent)

local function RegisterEvents()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
end

-- ---------------------------------------------------------------------------
-- 生命周期与选项
-- ---------------------------------------------------------------------------

local function OnEnable()
    active = true
    NormalizeConfig()
    playerGUID = UnitGUID("player")
    isHunter = IsHunter()
    RegisterEvents()
    if isHunter then
        EnsureBar()
        RegisterMover()
    end
    Rebuild()
    -- 登录早期姿态栏 / 技能书可能还没刷出来，延迟再补两次
    if addon.core and addon.core.ScheduleTimer then
        addon.core:ScheduleTimer(function()
            if active then
                Rebuild()
            end
        end, 1)
        addon.core:ScheduleTimer(function()
            if active then
                Rebuild()
            end
        end, 3)
    end
end

local function OnDisable()
    active = false
    eventFrame:UnregisterAllEvents()
    for i = 1, MAX_BUTTONS do
        if buttons[i] then
            StopPixelGlow(buttons[i])
        end
    end
    if bar then
        bar:Hide()
    end
end

local function SetAndApply(key, value)
    local cfg = NormalizeConfig()
    if cfg then
        cfg[key] = value
    end
    if active then
        ApplyLayout()
    end
end

addon:RegisterFeature(KEY, {
    category = "combat",
    default = true,
    label = function()
        return L["Aspect Bar"] or "Aspect Bar"
    end,
    desc = function()
        return L["Hunter only: show every learned Aspect as a clickable button, highlight the active one."]
            or "Hunter only: clickable Aspect buttons with active highlight."
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
    Refresh = function()
        if active then
            Rebuild()
        end
    end,
    BuildOptions = function(section, C)
        C:AddDescription(section, L["Aspect Bar Help"] or "Click a button to switch Aspect. Move via ElvUI Movers.")
        C:AddDescription(section, L["Aspect Bar Mover Hint"]
            or "Position: ElvUI → Movers (Aspect Bar).")
        C:AddToggle(section, {
            label = L["Show backdrop"] or "Show backdrop",
            getFunc = function()
                local cfg = NormalizeConfig()
                return cfg and cfg.showBackdrop ~= false
            end,
            setFunc = function(val)
                SetAndApply("showBackdrop", val and true or false)
            end,
        })
        C:AddToggle(section, {
            label = L["Highlight active aspect"] or "Highlight active aspect",
            desc = L["Gold border and glow on the currently active Aspect; dim the others."]
                or "Gold border/glow on the active Aspect; dim others.",
            getFunc = function()
                local cfg = NormalizeConfig()
                return not cfg or cfg.highlightActive ~= false
            end,
            setFunc = function(val)
                local cfg = NormalizeConfig()
                if cfg then
                    cfg.highlightActive = val and true or false
                end
                if active then
                    RefreshActive()
                end
            end,
        })
        C:AddToggle(section, {
            label = L["Auto-switch when hit"] or "Auto-switch when hit",
            desc = L["While in Cheetah/Pack, taking a hit switches to the fallback Aspect (needs a client that does not block addon casting)."],
            getFunc = function()
                local cfg = NormalizeConfig()
                return cfg and cfg.autoSwitch ~= false
            end,
            setFunc = function(val)
                SetAndApply("autoSwitch", val and true or false)
            end,
            disabled = function()
                return not IsHunter()
            end,
        })
        C:AddSelect(section, {
            label = L["Fallback Aspect"] or "Fallback Aspect",
            desc = L["Which Aspect to switch to when you take a hit in Cheetah/Pack."],
            values = {
                monkey = L["Aspect of the Monkey"] or "Aspect of the Monkey",
                hawk = L["Aspect of the Hawk"] or "Aspect of the Hawk",
                dragonhawk = L["Aspect of the Dragonhawk"] or "Aspect of the Dragonhawk",
            },
            getFunc = function()
                local cfg = NormalizeConfig()
                local v = cfg and cfg.autoSwitchTarget
                if v ~= "monkey" and v ~= "hawk" and v ~= "dragonhawk" then
                    v = "monkey"
                end
                return v
            end,
            setFunc = function(val)
                SetAndApply("autoSwitchTarget", val)
            end,
        })
        C:AddSlider(section, {
            label = L["Button Size"] or "Button Size",
            min = 20,
            max = 64,
            step = 1,
            getFunc = function()
                return Num("buttonSize", 20, 64, DEFAULTS.buttonSize)
            end,
            setFunc = function(val)
                SetAndApply("buttonSize", val)
            end,
        })
        C:AddSlider(section, {
            label = L["Button Spacing"] or "Button Spacing",
            min = 0,
            max = 16,
            step = 1,
            getFunc = function()
                return Num("spacing", 0, 16, DEFAULTS.spacing)
            end,
            setFunc = function(val)
                SetAndApply("spacing", val)
            end,
        })
        C:AddSlider(section, {
            label = L["Buttons Per Row"] or "Buttons Per Row",
            min = 1,
            max = 12,
            step = 1,
            getFunc = function()
                return Num("columns", 1, 12, DEFAULTS.columns)
            end,
            setFunc = function(val)
                SetAndApply("columns", val)
            end,
        })
        C:AddButton(section, {
            label = L["Reset Position"] or "Reset Position",
            callback = function()
                if InCombatLockdown and InCombatLockdown() then
                    return
                end
                local cfg = NormalizeConfig()
                if cfg then
                    cfg.posX = DEFAULTS.posX
                    cfg.posY = DEFAULTS.posY
                end
                local E = addon:GetE()
                if bar and bar.mover and E and E.ResetMovers then
                    E:ResetMovers(L["Aspect Bar"] or "Aspect Bar")
                elseif bar then
                    if bar.mover then
                        bar.mover:ClearAllPoints()
                        bar.mover:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.posX, DEFAULTS.posY)
                    else
                        ApplyPosition()
                    end
                end
            end,
        })
    end,
})
