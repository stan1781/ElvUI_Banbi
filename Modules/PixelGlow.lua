-- ElvUI_Banbi — shared Autocast-style border glow.
-- Canonical attachment is in Core.lua (always loaded). This file stays in the
-- toc as a fallback if those methods are missing.

local ADDON_NAME, ns = ...
local addon = ns or _G.ElvUI_Banbi
if type(addon) ~= "table" or addon.SetPixelGlow then
    return
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW_COLOR = { 1, 0.82, 0.2, 1 }
local GLOW_DOTS = 8          -- 每圈点数
local GLOW_GROUPS = 2        -- 几组错开的点轨
local GLOW_DOT_SIZE = 3      -- 点的边长（像素）
local GLOW_FREQ = 0.45
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local DEFAULT_KEY = "BanbiGlow"

local function DotGlowOnSizeChanged(self)
    local w, h = self:GetWidth(), self:GetHeight()
    if w <= 0 or h <= 0 then
        return
    end
    local info = self.info
    info.width = w
    info.height = h
    info.perimeter = 2 * (w + h)
    info.bottomlim = h * 2 + w
    info.rightlim = h + w
    info.space = info.perimeter / info.N
end

local function DotGlowOnUpdate(self, elapsed)
    local info = self.info
    if not info.width then
        DotGlowOnSizeChanged(self)
        if not info.width then
            return
        end
    end
    local texIndex = 0
    local size = info.dotSize
    for g = 1, info.groups do
        self.timer[g] = self.timer[g] + elapsed / (info.period * g)
        if self.timer[g] > 1 or self.timer[g] < -1 then
            self.timer[g] = self.timer[g] % 1
        end
        for i = 1, info.N do
            texIndex = texIndex + 1
            local tex = self.textures[texIndex]
            local position = (info.space * i + info.perimeter * self.timer[g]) % info.perimeter
            tex:SetWidth(size)
            tex:SetHeight(size)
            tex:ClearAllPoints()
            if position > info.bottomlim then
                tex:SetPoint("CENTER", self, "BOTTOMRIGHT", -position + info.bottomlim, 0)
            elseif position > info.rightlim then
                tex:SetPoint("CENTER", self, "TOPRIGHT", 0, -position + info.rightlim)
            elseif position > info.height then
                tex:SetPoint("CENTER", self, "TOPLEFT", position - info.height, 0)
            else
                tex:SetPoint("CENTER", self, "BOTTOMLEFT", 0, position)
            end
        end
    end
end

function addon:StopPixelGlow(btn, key)
    if not btn then
        return
    end
    key = key or btn._banbiGlowKey or DEFAULT_KEY
    if LCG then
        if LCG.AutoCastGlow_Stop then
            LCG.AutoCastGlow_Stop(btn, key)
        end
        if LCG.PixelGlow_Stop then
            LCG.PixelGlow_Stop(btn, key)
        end
    end
    if btn._banbiPixelGlow then
        btn._banbiPixelGlow:Hide()
        btn._banbiPixelGlow:SetScript("OnUpdate", nil)
    end
    btn._banbiGlowOn = false
end

function addon:StartPixelGlow(btn, key)
    if not btn then
        return
    end
    key = key or DEFAULT_KEY
    btn._banbiGlowKey = key
    -- WA：Autocast 就是沿边跑的金色/彩色小点
    if LCG and LCG.AutoCastGlow_Start then
        LCG.AutoCastGlow_Start(btn, GLOW_COLOR, GLOW_DOTS, GLOW_FREQ, 1.1, 0, 0, key)
        btn._banbiGlowOn = true
        return
    end
    local f = btn._banbiPixelGlow
    local total = GLOW_DOTS * GLOW_GROUPS
    if not f then
        f = CreateFrame("Frame", nil, btn)
        f:SetAllPoints(btn)
        f:SetFrameLevel((btn:GetFrameLevel() or 0) + 8)
        f.textures = {}
        f.info = {
            N = GLOW_DOTS,
            groups = GLOW_GROUPS,
            period = 1 / GLOW_FREQ,
            dotSize = GLOW_DOT_SIZE,
        }
        f.timer = {}
        for g = 1, GLOW_GROUPS do
            f.timer[g] = (g - 1) / GLOW_GROUPS
        end
        for i = 1, total do
            local tex = f:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(WHITE)
            tex:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            tex:SetBlendMode("ADD")
            tex:SetWidth(GLOW_DOT_SIZE)
            tex:SetHeight(GLOW_DOT_SIZE)
            f.textures[i] = tex
        end
        f:SetScript("OnSizeChanged", DotGlowOnSizeChanged)
        btn._banbiPixelGlow = f
    end
    f:Show()
    for g = 1, GLOW_GROUPS do
        f.timer[g] = (g - 1) / GLOW_GROUPS
    end
    DotGlowOnSizeChanged(f)
    f:SetScript("OnUpdate", DotGlowOnUpdate)
    btn._banbiGlowOn = true
end

function addon:SetPixelGlow(btn, enabled, key)
    if not btn then
        return
    end
    if enabled then
        if not btn._banbiGlowOn then
            self:StartPixelGlow(btn, key)
        end
    else
        if btn._banbiGlowOn then
            self:StopPixelGlow(btn, key)
        end
    end
end

function addon:SetActiveGlowBorder(btn, enabled)
    if not btn then
        return
    end
    if btn.backdrop and btn.backdrop.SetBackdropBorderColor then
        if enabled then
            btn.backdrop:SetBackdropBorderColor(1, 0.82, 0.2, 1)
        else
            local E = addon.GetE and addon:GetE()
            local b = E and E.media and E.media.bordercolor
            if b then
                btn.backdrop:SetBackdropBorderColor(b.r or 0, b.g or 0, b.b or 0, 1)
            else
                btn.backdrop:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
        return
    end
    local border = btn._banbiActiveBorder
    if enabled then
        if not border then
            border = CreateFrame("Frame", nil, btn)
            border:SetAllPoints(btn)
            border:SetFrameLevel((btn:GetFrameLevel() or 0) + 6)
            if border.SetBackdrop then
                border:SetBackdrop({
                    edgeFile = WHITE,
                    edgeSize = 1,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                })
            end
            btn._banbiActiveBorder = border
        end
        if border.SetBackdropBorderColor then
            border:SetBackdropBorderColor(1, 0.82, 0.2, 1)
        end
        border:Show()
    elseif border then
        border:Hide()
    end
end
