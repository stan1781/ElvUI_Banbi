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
            moneyFormat = {
                enabled = true,
            },
            -- Module master switch only; per-character lists live in char.autoVendor.
            autoVendor = {
                enabled = true,
            },
            infoBar = {
                enabled = true,
                fontSize = 12,
                anchor = "TOPLEFT",
                posX = 20,
                posY = -8,
                tokens = {
                    [65085] = false, -- 虚空碎片
                    [65297] = false, -- 觉醒泰坦精华
                    [69885] = false, -- 灵魂灰烬
                    [60038] = true, -- 次级好运护符
                    [60039] = true, -- 长老的好运符
                    [70539] = false, -- 商贩标币
                    [70877] = false, -- 求知护符
                },
                showCorruption = true,
                showPower = true,
                showCrit = true,
                showHaste = true,
                powerMode = "auto", -- auto | melee | ranged | spell
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
            bagCorruption = {
                enabled = true,
                fontSize = 0, -- 0 = follow ElvUI bags itemLevel font size
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
            aspectBar = {
                enabled = true,
                buttonSize = 28,
                spacing = 4,
                columns = 12,
                anchor = "CENTER",
                posX = 0,
                posY = -160,
                showBackdrop = true,
                autoSwitch = true,
                autoSwitchTarget = "monkey",
                highlightActive = true,
            },
            astralEnhance = {
                enabled = false,
                targetLevel = 9,
                clickDelay = 0.45,
                itemFilter = "",
                attrExclude = "",
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
        -- Per-character vendor sell/buy (reagents differ by class).
        autoVendor = {
            sellEnabled = true,           -- bag-button sell/destroy only (never auto on merchant open)
            buyEnabled = true,
            scanOrder = "asc",
            scanSlotLimit = 80,
            sellZoneSlots = 0,
            destroyUnsellable = false,
            maxCorruption = 0,
            sellInterval = 0.2,
            chatFeedback = true,
            sellList = {},
            buyList = {                 -- quest restock preset (all characters)
                [69473] = 300,
                [69477] = 3,
                [69479] = 4,
                [69485] = 2,
                [69487] = 1,
                [69489] = 3,
                [69491] = 5,
                [69464] = 100,
                [69466] = 30,
                [69470] = 60,
                [69474] = 250,
                [69476] = 20,
                [69480] = 6,
                [69484] = 10,
                [69488] = 100,
                [69494] = 30,
                [69469] = 50,
                [69463] = 50,
            },
            sellListText = "",
            buyListText = "69473 300\n69477 3\n69479 4\n69485 2\n69487 1\n69489 3\n69491 5\n69464 100\n69466 30\n69470 60\n69474 250\n69476 20\n69480 6\n69484 10\n69488 100\n69494 30\n69469 50\n69463 50",
        },
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
        -- Shared across characters: open legendary chests (auto-loot is game-side).
        chestOpen = {
            itemID = 64827, -- 艾泽拉斯传奇宝箱
            interval = 0.4,
            scanOrder = "asc",
            scanSlotLimit = 0, -- 0 = all bags
            chatFeedback = true,
        },
        version = 1,
    },
}
