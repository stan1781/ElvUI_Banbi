-- ElvUI_Banbi — lock celestial time of day (debugHour) on login.
-- The client's "一天中的时间（预览）" CVar is not archived, so it resets
-- to -1 (follow the game / local clock) every login.

local ADDON_NAME, addon = ...

local CVAR = "debugHour"
local DEFAULT_HOUR = 10

local function Cfg()
    if not addon.db or not addon.db.global then
        return nil
    end
    local cfg = addon.db.global.dayTime
    if type(cfg) ~= "table" then
        cfg = { enabled = true, hour = DEFAULT_HOUR }
        addon.db.global.dayTime = cfg
    end
    if cfg.enabled == nil then
        cfg.enabled = true
    end
    if type(cfg.hour) ~= "number" then
        cfg.hour = DEFAULT_HOUR
    end
    return cfg
end

function addon:IsDayTimeLocked()
    local cfg = Cfg()
    return not cfg or cfg.enabled ~= false
end

function addon:GetDayTimeHour()
    local cfg = Cfg()
    local hour = (cfg and cfg.hour) or DEFAULT_HOUR
    if hour < 0 then
        hour = 0
    end
    if hour > 24 then
        hour = 24
    end
    return hour
end

function addon:ApplyDayTime()
    if not SetCVar then
        return
    end
    if addon:IsDayTimeLocked() then
        SetCVar(CVAR, tostring(addon:GetDayTimeHour()))
    end
end

function addon:SetDayTimeLocked(enabled)
    local cfg = Cfg()
    if cfg then
        cfg.enabled = enabled and true or false
    end
    if not SetCVar then
        return
    end
    if enabled then
        addon:ApplyDayTime()
    else
        SetCVar(CVAR, "-1")
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function(self, event)
    addon:ApplyDayTime()
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent(event)
    end
end)
