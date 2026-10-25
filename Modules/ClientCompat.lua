-- ClientCompat — work around 64-bit / custom-title DB holes in PaperDoll titles.
-- Blizzard PlayerTitleFrame_UpdateTitles does strtrim(GetTitleName(i)) without a nil check.
-- After GetNumTitles grew (e.g. to 228), some IsTitleKnown indices return no name string.

local ADDON_NAME, addon = ...

local rawIsTitleKnown = IsTitleKnown
local rawGetTitleName = GetTitleName

-- Treat "known but nameless" titles as unknown so all callers skip them.
-- Must run before ElvUI_Enhanced (loads after Banbi alphabetically) caches IsTitleKnown.
function IsTitleKnown(index)
    local known = rawIsTitleKnown(index)
    if not known or known == 0 then
        return known
    end
    local name = rawGetTitleName(index)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return known
end

local function TitleKnown(i)
    local known = IsTitleKnown(i)
    return known and known ~= 0
end

local function PlayerTitleSort(a, b)
    return a.name < b.name
end

local function SafeUpdateTitles()
    if not PlayerTitlePickerScrollFrame or not PlayerTitleFrame then
        return
    end

    local buttons = PlayerTitlePickerScrollFrame.buttons
    if not buttons or not buttons[1] then
        return
    end

    local fontstringText = buttons[1].text or buttons[1].TitleText
    if not fontstringText then
        local btnName = buttons[1]:GetName()
        fontstringText = btnName and _G[btnName .. "TitleText"]
    end
    if not fontstringText then
        return
    end

    local playerTitles = {}
    local currentTitle = GetCurrentTitle()
    local titleCount = 1
    local fontstringWidth
    local maxWidth = 0

    PlayerTitleFrame.selected = -1
    playerTitles[1] = {}
    playerTitles[1].name = "       "
    playerTitles[1].id = -1

    for i = 1, GetNumTitles() do
        if TitleKnown(i) then
            local rawName = GetTitleName(i)
            if type(rawName) == "string" and rawName ~= "" then
                titleCount = titleCount + 1
                playerTitles[titleCount] = playerTitles[titleCount] or {}
                playerTitles[titleCount].name = strtrim(rawName)
                playerTitles[titleCount].id = i
                if i == currentTitle then
                    PlayerTitleFrame.selected = i
                end
                fontstringText:SetText(playerTitles[titleCount].name)
                fontstringWidth = fontstringText:GetWidth()
                if fontstringWidth > maxWidth then
                    maxWidth = fontstringWidth
                end
            end
        end
    end

    if titleCount < 2 then
        PlayerTitleFrame:Hide()
        if PlayerTitlePickerFrame then
            PlayerTitlePickerFrame:Hide()
        end
        return
    end

    PlayerTitleFrame:Show()
    if currentTitle == 0 then
        PlayerTitleFrameText:SetText(PAPERDOLL_SELECT_TITLE)
    elseif currentTitle == -1 then
        PlayerTitleFrameText:SetText(NONE)
    else
        local curName = GetTitleName(currentTitle)
        PlayerTitleFrameText:SetText(type(curName) == "string" and curName or PAPERDOLL_SELECT_TITLE)
    end

    table.sort(playerTitles, PlayerTitleSort)
    playerTitles[1].name = NONE
    PlayerTitleFrame.titles = playerTitles

    maxWidth = maxWidth + 10
    for i = 1, #buttons do
        buttons[i]:SetWidth(maxWidth)
    end
    PlayerTitlePickerScrollFrame:SetWidth(maxWidth + 34)
    if PlayerTitlePickerScrollFrameScrollChild then
        PlayerTitlePickerScrollFrameScrollChild:SetWidth(maxWidth + 34)
    end

    local displayed = PLAYER_DISPLAYED_TITLES or 6
    local rowHeight = PLAYER_TITLE_HEIGHT or 16
    if titleCount <= displayed then
        PlayerTitlePickerFrame:SetWidth(maxWidth + 56)
        PlayerTitlePickerFrame:SetHeight(titleCount * rowHeight + 26)
        PlayerTitlePickerScrollFrame:SetHeight(titleCount * rowHeight + 1)
    else
        PlayerTitlePickerFrame:SetWidth(maxWidth + 76)
        PlayerTitlePickerFrame:SetHeight(rowHeight * displayed + 26)
        PlayerTitlePickerScrollFrame:SetHeight(rowHeight * displayed + 1)
    end

    HybridScrollFrame_CreateButtons(PlayerTitlePickerScrollFrame, "PlayerTitleButtonTemplate")
    HybridScrollFrame_Update(PlayerTitlePickerScrollFrame, titleCount * rowHeight, PlayerTitlePickerScrollFrame:GetHeight())
    if PlayerTitlePickerScrollFrame_Update then
        PlayerTitlePickerScrollFrame_Update()
    end
end

local function SafeSetTitleByName(name)
    if type(name) ~= "string" then
        return false
    end
    name = strlower(name)
    for i = 1, GetNumTitles() do
        if TitleKnown(i) then
            local rawName = GetTitleName(i)
            if type(rawName) == "string" then
                local title = strlower(strtrim(rawName))
                if title:find(name) == 1 then
                    SetCurrentTitle(i)
                    return true
                end
            end
        end
    end
    return false
end

-- FrameXML loads before addons; replace the fragile globals immediately.
if type(PlayerTitleFrame_UpdateTitles) == "function" then
    PlayerTitleFrame_UpdateTitles = SafeUpdateTitles
end
if type(SetTitleByName) == "function" then
    SetTitleByName = SafeSetTitleByName
end

addon.ClientCompat = {
    PlayerTitleFrame_UpdateTitles = SafeUpdateTitles,
    SetTitleByName = SafeSetTitleByName,
}
