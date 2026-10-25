-- ElvUI_Banbi — FriendsMenuXP player context menu (no class-buff cast entries).

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "friendsMenuXP"

local function OnEnable()
    if IsAddOnLoaded("FriendsMenuXP") then
        print("|cffff8000[玩家菜单]|r 请禁用独立插件 FriendsMenuXP，以免双份菜单。")
    end
    if _G.FriendsMenuXP_Enable then
        FriendsMenuXP_Enable()
    end
    -- Let FriendSync rewrite ADD_FRIEND / REMOVE_FRIEND to sync pool.
    if addon.FriendSync and addon.FriendSync.ApplyMenuHooks then
        addon.FriendSync.ApplyMenuHooks()
    end
end

local function OnDisable()
    if _G.FriendsMenuXP_Disable then
        FriendsMenuXP_Disable()
    end
end

addon:RegisterFeature(KEY, {
    category = "social",
    default = true,
    requiresReload = true,
    label = function() return L["Friends Menu XP"] end,
    desc = function()
        return L["Extended player context menu."]
    end,
    OnEnable = OnEnable,
    OnDisable = OnDisable,
})
