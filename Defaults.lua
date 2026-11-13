-- ElvUI_Banbi — AceDB defaults.

local ADDON_NAME, addon = ...

-- Fixed 主脑任务 restock; applied automatically, not shown in the editable buy list.
-- Single source of truth: edit the table only; text is derived below.
addon.autoVendorBrainQuestBuyList = {
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
}

do
    local parts = {}
    for id, count in pairs(addon.autoVendorBrainQuestBuyList) do
        parts[#parts + 1] = { id = id, count = count }
    end
    table.sort(parts, function(a, b)
        return a.id < b.id
    end)
    local lines = {}
    for i = 1, #parts do
        lines[i] = parts[i].id .. " " .. parts[i].count
    end
    addon.autoVendorBrainQuestBuyListText = table.concat(lines, "\n")
end

-- Shared buy-list line parser (Migrate + AutoVendor). Returns id, count.
function addon.ParseAutoVendorBuyLine(line)
    if not line then
        return nil
    end
    line = line:match("^%s*(.-)%s*$") or ""
    if line == "" then
        return nil
    end

    local id, rest
    local linkStart, linkEnd, linkId = line:find("|c%x%x%x%x%x%x%x%x|Hitem:(%d+).-|h.-|h|r")
    if not linkId then
        linkStart, linkEnd, linkId = line:find("|Hitem:(%d+).-|h.-|h|r")
    end
    if not linkId then
        linkStart, linkEnd, linkId = line:find("|Hitem:(%d+)")
    end
    if not linkId then
        linkStart, linkEnd, linkId = line:find("item:(%d+)[:%d]*")
    end

    if linkId then
        id = tonumber(linkId)
        rest = (line:sub(1, linkStart - 1) .. line:sub(linkEnd + 1))
        rest = rest:match("^%s*(.-)%s*$") or ""
    else
        local plainId, trailing = line:match("^(%d+)%s+(.+)$")
        id = tonumber(plainId)
        rest = trailing and (trailing:match("^%s*(.-)%s*$") or "") or ""
    end

    local count = rest and tonumber(rest:match("^(%d+)$"))
    if id and count and count > 0 then
        return id, count
    end
    return nil
end

-- Extract item id from a buy-list line even when count is missing (migration helpers).
function addon.ParseAutoVendorBuyLineItemID(line)
    local id = addon.ParseAutoVendorBuyLine(line)
    if id then
        return id
    end
    if not line or line == "" then
        return nil
    end
    id = line:match("|Hitem:(%d+)") or line:match("item:(%d+)") or line:match("^%s*(%d+)%s*")
    return tonumber(id)
end

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
            buyList = {},               -- extra items only; 主脑任务 preset is built-in
            sellListText = "",
            buyListText = "",
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
