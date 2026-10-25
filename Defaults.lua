-- ElvUI_Banbi — AceDB defaults.

local ADDON_NAME, addon = ...

addon.defaults = {
    profile = {
        features = {
            motionSpeed = {
                enabled = true,
                fontSize = 11,
                anchor = "CENTER",
                posX = 0,
                posY = 120,
            },
            tokenBar = {
                enabled = true,
                anchor = "TOPLEFT",
                posX = 20,
                posY = -8,
                tokens = {
                    [65085] = true, -- 虚空碎片
                    [65297] = true, -- 觉醒泰坦精华
                    [69885] = true, -- 灵魂灰烬
                    [60038] = true, -- 次级好运护符
                    [60039] = true, -- 长老的好运符
                    [70539] = true, -- 商贩标币
                    [70877] = true, -- 求知护符
                },
            },
            chatEnhance = {
                enabled = true,
                -- ElvUI Chat 自带精简时间戳；Banbi 不再叠一层 HH:MM:SS
                timestamp = false,
                tabSwitch = true,
                editHistory = false, -- ElvUI 已有会话内上下翻；需要跨重载记忆时再开
                editHistorySize = 20,
                autoJoinLfg = true, -- 登录自动加入寻求组队
            },
            chatBar = {
                enabled = true,
                fontSize = 15,
                anchorToChat = true,
                chatOffsetX = 0,
                chatOffsetY = 4,
                anchor = "BOTTOMLEFT",
                posX = 16,
                posY = 30,
            },
            inspectPanel = {
                enabled = true,
                charWindow = true,
                inspectWindow = true,
                charOffsetX = 0,      -- 角色窗：避开 DragonUI 属性栏
                inspectOffsetX = -30,   -- 观察窗：略贴紧面板
                offsetY = 0,
            },
            runeBar = {
                enabled = true,
            },
            equipmentHelper = {
                enabled = true,
                anchor = "CENTER",
                posX = 0,
                posY = -180,
                scale = 1,
            },
            friendSync = {
                enabled = true,
            },
            friendsMenuXP = {
                enabled = true,
            },
            autoTrack = {
                enabled = true,
                restoreOutOfCombat = true,
            },
            astralEnhance = {
                enabled = false,
                targetLevel = 9,
                clickDelay = 0.45,
                itemFilter = "",
                anchor = "CENTER",
                relAnchor = "CENTER",
                posX = 280,
                posY = 80,
            },
            autoLearnRecipes = {
                enabled = true,
                onLearn = true,
                onOpen = false,
                professions = {
                    ["锻造"] = true,
                    ["炼金术"] = true,
                    ["附魔"] = true,
                    ["工程学"] = true,
                    ["草药学"] = true,
                    ["铭文"] = true,
                    ["珠宝加工"] = true,
                    ["制皮"] = true,
                    ["裁缝"] = true,
                    ["采矿"] = true,
                    ["剥皮"] = true,
                    ["烹饪"] = true,
                    ["急救"] = true,
                    ["钓鱼"] = true,
                },
            },
        },
    },
    char = {
        chatEditHistory = {},
    },
    global = {
        migrated = {},
        runeActionBar = { chars = {} },
        equipment = { chars = {} },
        friendSync = {
            friendsByFaction = { Alliance = {}, Horde = {} },
            removedByFaction = { Alliance = {}, Horde = {} },
            friends = {},
            chars = {},
            settings = {
                autoSyncOnLogin = false,
                autoCleanOnLogin = true,
            },
        },
        version = 1,
    },
}
