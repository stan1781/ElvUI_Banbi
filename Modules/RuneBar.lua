-- ElvUI_Banbi — Rune action bar restore (ported from ElvUI_bbTools RuneActionBar).
-- 私服符文装备技能脱装后会被清出动作条；穿回后自动填回原格子。

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "runeBar"
local RuneActionBar = {}
local enabled = false
local initialized = false
local eventFrame
local tip
local debugMode = false
local slashRegistered = false

local NUM_ACTION_SLOTS = 120
-- 换装/换天赋会连发大量事件：先合并，稳定后再一次性回填所有空孔
local RESTORE_DEBOUNCE = 0.4
local RESTORE_RETRY_INTERVAL = 0.5
local RESTORE_WATCH_SECONDS = 3

local memory = {} -- [slot] = { type=, name=, pickup=, texture= }
local pending = {} -- [slot] = info  -- 仅「原先有记忆、当前空」的孔
local needRestoreAfterCombat = false
local suppressing = false
local enteredWorldAt = 0
local LOGIN_GRACE_SECONDS = 6
local watchUntil = 0
local debounceLeft = 0
local retryElapsed = 0
local restoreQueued = false

local function Debug(...)
	if not debugMode then return end
	local parts = {"|cff00ff00[符文条]|r"}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
end

local function GetCharKey()
	local name = UnitName("player")
	local realm = GetRealmName()
	if not name or name == "" or not realm or realm == "" then
		return nil
	end
	return name .. "-" .. realm
end

local function MigrateFromBbTools()
	if not addon.db or not addon.db.global then return end
	local g = addon.db.global
	g.migrated = g.migrated or {}
	if g.migrated.runeActionBar then return end
	g.migrated.runeActionBar = true
	if not (_G.bbToolsDB and _G.bbToolsDB.runeActionBar and _G.bbToolsDB.runeActionBar.chars) then
		return
	end
	g.runeActionBar = g.runeActionBar or { chars = {} }
	g.runeActionBar.chars = g.runeActionBar.chars or {}
	local imported = 0
	for key, charDB in pairs(_G.bbToolsDB.runeActionBar.chars) do
		if type(charDB) == "table" and type(charDB.slots) == "table" and not g.runeActionBar.chars[key] then
			g.runeActionBar.chars[key] = { slots = {} }
			for slotKey, info in pairs(charDB.slots) do
				g.runeActionBar.chars[key].slots[slotKey] = info
			end
			imported = imported + 1
		end
	end
	if imported > 0 then
		print("|cff00ff00[符文条]|r 已从 bbToolsDB 导入 " .. imported .. " 个角色的动作条记忆。")
	end
end

local function EnsureDB()
	if not addon.db then return nil end
	addon.db.global = addon.db.global or {}
	local g = addon.db.global
	g.runeActionBar = g.runeActionBar or { chars = {} }
	g.runeActionBar.chars = g.runeActionBar.chars or {}
	local key = GetCharKey()
	if not key then return nil end
	if not g.runeActionBar.chars[key] then
		g.runeActionBar.chars[key] = { slots = {} }
	end
	if not g.runeActionBar.chars[key].slots then
		g.runeActionBar.chars[key].slots = {}
	end
	return g.runeActionBar.chars[key]
end

local function PersistMemory()
	local charDB = EnsureDB()
	if not charDB then return end
	local slots = {}
	for slot, info in pairs(memory) do
		if info and info.type and info.name then
			slots[tostring(slot)] = {
				type = info.type,
				name = info.name,
				pickup = info.pickup,
				texture = info.texture,
			}
		end
	end
	charDB.slots = slots
end

local function WipeTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

local function LoadMemory()
	WipeTable(memory)
	WipeTable(pending)
	local charDB = EnsureDB()
	if not charDB or not charDB.slots then return end
	for slotKey, info in pairs(charDB.slots) do
		local slot = tonumber(slotKey)
		if slot and info and info.type and info.name then
			memory[slot] = {
				type = info.type,
				name = info.name,
				pickup = info.pickup or info.name,
				texture = info.texture,
			}
		end
	end
end

local function EnsureTooltip()
	if tip then return tip end
	tip = CreateFrame("GameTooltip", "ElvUI_Banbi_RuneTip", nil, "GameTooltipTemplate")
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	return tip
end

local function StripColors(text)
	if not text then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
	text = text:match("^%s*(.-)%s*$") or text
	if text == "" then return nil end
	return text
end

-- 动作条上就是正式技能名；只去掉颜色码和等级括号，不做名称映射
local function NormalizeOfficialSpellName(spellName)
	spellName = StripColors(spellName)
	if not spellName then
		return nil
	end
	local plain = spellName:match("^(.-)%s*%(") or spellName
	plain = plain:match("^%s*(.-)%s*$") or plain
	if plain == "" then
		return nil
	end
	return plain
end

local function GetActionSlotName(slot)
	EnsureTooltip()
	tip:ClearLines()
	tip:SetAction(slot)
	local text = _G["ElvUI_Banbi_RuneTipTextLeft1"]
	local name = text and text:GetText() or nil
	tip:Hide()
	return StripColors(name)
end

local function RankNumber(rank)
	if not rank or rank == "" then
		return 0
	end
	local n = tonumber(rank:match("(%d+)"))
	return n or 0
end

-- 与 MySlot 一致：书页索引 -> "正式技能名" 或 "正式技能名(等级)"
local function SpellPickupStringFromBookIndex(bookIndex)
	if not bookIndex or bookIndex == 0 then
		return nil, nil
	end
	local name, rank = GetSpellName(bookIndex, BOOKTYPE_SPELL)
	name = NormalizeOfficialSpellName(name)
	if not name or name == "" then
		return nil, nil
	end
	if rank and rank ~= "" then
		return name, name .. "(" .. rank .. ")"
	end
	return name, name
end

-- 按名称查找技能书：必须取最高等级（同名技能书中靠前的多为 1 级）
local function FindSpellBookIndexByName(spellName)
	local official = NormalizeOfficialSpellName(spellName)
	if not official then
		return nil
	end

	local bestIndex, bestOfficial, bestWithRank, bestRankNum
	local exactIndex, exactOfficial, exactWithRank

	local i = 1
	while true do
		local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then
			break
		end
		local bookOfficial = NormalizeOfficialSpellName(name)
		if not bookOfficial then
			i = i + 1
		else
			local withRank = (rank and rank ~= "") and (bookOfficial .. "(" .. rank .. ")") or bookOfficial
			local rn = RankNumber(rank)

			if withRank == spellName or (rank and rank ~= "" and (official .. "(" .. rank .. ")") == spellName) then
				exactIndex, exactOfficial, exactWithRank = i, bookOfficial, withRank
			end

			if bookOfficial == official then
				if not bestIndex or rn > bestRankNum or (rn == bestRankNum and i > bestIndex) then
					bestIndex = i
					bestOfficial = bookOfficial
					bestWithRank = withRank
					bestRankNum = rn
				end
			end
			i = i + 1
		end
	end

	if exactIndex then
		return exactIndex, exactOfficial, exactWithRank
	end
	if bestIndex then
		return bestIndex, bestOfficial, bestWithRank
	end

	return nil
end

local function CaptureSlot(slot)
	if not HasAction(slot) then
		return nil
	end

	local texture = GetActionTexture(slot)

	if GetActionInfo then
		local actionType, id = GetActionInfo(slot)
		if actionType == "macro" then
			local macroName = (GetMacroInfo(id))
			if macroName and macroName ~= "" then
				return { type = "macro", name = macroName, pickup = macroName, texture = texture }
			end
		elseif actionType == "spell" then
			-- 本客户端 GetActionInfo("spell") 的 id 是技能书索引（同 MySlot）
			local name, pickup = SpellPickupStringFromBookIndex(id)
			if not name then
				name = GetActionSlotName(slot)
				pickup = name
			end
			if name and name ~= "" then
				return { type = "spell", name = name, pickup = pickup or name, texture = texture, bookIndex = id }
			end
		elseif actionType == "item" then
			local name = GetItemInfo(id) or GetActionSlotName(slot)
			if name and name ~= "" then
				return { type = "item", name = name, pickup = id or name, texture = texture, itemID = id }
			end
		end
	end

	local macroName = GetActionText(slot)
	if macroName and macroName ~= "" then
		return { type = "macro", name = macroName, pickup = macroName, texture = texture }
	end

	local name = GetActionSlotName(slot)
	if not name or name == "" then
		return nil
	end

	if IsEquippedAction(slot) or IsConsumableAction(slot) then
		return { type = "item", name = name, pickup = name, texture = texture }
	end

	return { type = "spell", name = name, pickup = name, texture = texture }
end

local function CanPlace(info)
	if not info or not info.type or not info.name then
		return false
	end
	if info.type == "spell" then
		return FindSpellBookIndexByName(info.pickup or info.name) ~= nil
	elseif info.type == "macro" then
		local idx = GetMacroIndexByName(info.name)
		return idx and idx > 0
	elseif info.type == "item" then
		if type(info.pickup) == "number" then
			return GetItemCount(info.pickup) > 0 or IsEquippedItem(info.pickup)
		end
		return GetItemCount(info.name) > 0 or IsEquippedItem(info.name)
	end
	return false
end

local function IsCursorBusy()
	if CursorHasItem and CursorHasItem() then
		return true
	end
	if CursorHasMoney and CursorHasMoney() then
		return true
	end
	if GetCursorInfo then
		return GetCursorInfo() ~= nil
	end
	return false
end

local function SlotSpellMatches(slot, wantName)
	local got = NormalizeOfficialSpellName(GetActionSlotName(slot))
	local want = NormalizeOfficialSpellName(wantName)
	return got and want and got == want
end

-- PlaceAction 每次都会响入栏音；批量回填时临时静音（钩子 + SFX）
local muteDepth = 0
local savedEnableSFX
local hookedPlaySound
local hookedPlaySoundFile

local function BeginMutePlaceSounds()
	muteDepth = muteDepth + 1
	if muteDepth > 1 then
		return
	end
	if GetCVar and SetCVar then
		savedEnableSFX = GetCVar("Sound_EnableSFX")
		SetCVar("Sound_EnableSFX", "0")
	end
	hookedPlaySound = _G.PlaySound
	hookedPlaySoundFile = _G.PlaySoundFile
	_G.PlaySound = function() end
	if _G.PlaySoundFile then
		_G.PlaySoundFile = function() end
	end
end

local function EndMutePlaceSounds()
	if muteDepth <= 0 then
		return
	end
	muteDepth = muteDepth - 1
	if muteDepth > 0 then
		return
	end
	if hookedPlaySound then
		_G.PlaySound = hookedPlaySound
		hookedPlaySound = nil
	end
	if hookedPlaySoundFile then
		_G.PlaySoundFile = hookedPlaySoundFile
		hookedPlaySoundFile = nil
	end
	if savedEnableSFX ~= nil and SetCVar then
		SetCVar("Sound_EnableSFX", savedEnableSFX)
		savedEnableSFX = nil
	end
end

local function TryPickupSpellString(spellArg, slot, wantName)
	if not spellArg or spellArg == "" then
		return false
	end
	ClearCursor()
	pcall(function() PickupSpell(spellArg) end)
	PlaceAction(slot)
	ClearCursor()
	if HasAction(slot) and SlotSpellMatches(slot, wantName) then
		return true
	end
	-- 放错技能则清掉，避免把错误技能留在格子上
	if HasAction(slot) and not SlotSpellMatches(slot, wantName) then
		PickupAction(slot)
		ClearCursor()
	end
	return false
end

local function PlaceCaptured(slot, info)
	if InCombatLockdown() or not info or HasAction(slot) or IsCursorBusy() then
		return false
	end

	suppressing = true
	local ok = false

	if info.type == "spell" then
		local pickup = info.pickup or info.name
		local wantName = info.name or pickup
		local attempts = {}

		-- 记忆中的带等级字符串优先（本客户端 PickupSpell 吃技能名，不是书页索引）
		if type(pickup) == "string" and pickup ~= "" then
			attempts[#attempts + 1] = pickup
		end
		if info.bookIndex then
			local _, rememberedRank = SpellPickupStringFromBookIndex(info.bookIndex)
			if rememberedRank then
				attempts[#attempts + 1] = rememberedRank
			end
		end
		local _, name, withRank = FindSpellBookIndexByName(pickup)
		if withRank then
			attempts[#attempts + 1] = withRank
		end
		-- 无等级纯名容易落到 1 级，放最后兜底
		if name and name ~= pickup then
			attempts[#attempts + 1] = name
		end

		local seen = {}
		for _, spellArg in ipairs(attempts) do
			if spellArg and not seen[spellArg] then
				seen[spellArg] = true
				if TryPickupSpellString(spellArg, slot, wantName) then
					ok = true
					break
				end
			end
		end
		Debug("恢复技能", slot, info.name, ok and "成功" or "失败", withRank or pickup or "")
	elseif info.type == "macro" then
		local idx = GetMacroIndexByName(info.name)
		if idx and idx > 0 then
			ClearCursor()
			PickupMacro(idx)
			PlaceAction(slot)
			ClearCursor()
			ok = HasAction(slot) and true or false
			Debug("恢复宏", slot, info.name, ok and "成功" or "失败")
		end
	elseif info.type == "item" then
		ClearCursor()
		if type(info.pickup) == "number" then
			pcall(function() PickupItem(info.pickup) end)
		else
			pcall(function() PickupItem(info.name) end)
		end
		PlaceAction(slot)
		ClearCursor()
		ok = HasAction(slot) and true or false
		Debug("恢复物品", slot, info.name, ok and "成功" or "失败")
	end

	suppressing = false
	return ok
end

local function StopWatch()
	watchUntil = 0
	debounceLeft = 0
	retryElapsed = 0
	restoreQueued = false
	if eventFrame then
		eventFrame:SetScript("OnUpdate", nil)
	end
end

local function CountPending()
	local n = 0
	for _ in pairs(pending) do
		n = n + 1
	end
	return n
end

-- 只处理 pending：原先记住、换装后变空的孔；同一帧批量 PlaceAction（静音）
local function TryRestorePending()
	if not enabled then
		return false
	end
	if InCombatLockdown() then
		needRestoreAfterCombat = true
		return false
	end
	if IsCursorBusy() then
		return false
	end

	local changed = false
	local stillNeed = false

	BeginMutePlaceSounds()
	local okRun, err = pcall(function()
		for slot, info in pairs(pending) do
			if HasAction(slot) then
				pending[slot] = nil
			elseif CanPlace(info) then
				if PlaceCaptured(slot, info) then
					pending[slot] = nil
					changed = true
				else
					stillNeed = true
				end
			else
				-- 技能书尚未刷出，保留 pending 短时重试
				stillNeed = true
			end
		end
	end)
	EndMutePlaceSounds()
	if not okRun then
		Debug("回填异常", err)
	end

	if changed then
		PersistMemory()
	end
	return stillNeed
end

local function ScheduleRestore(reason)
	if not enabled then
		return
	end
	-- 事件风暴只重置防抖，不立刻回填、不重启长轮询
	debounceLeft = RESTORE_DEBOUNCE
	watchUntil = GetTime() + RESTORE_WATCH_SECONDS
	restoreQueued = true
	Debug("安排恢复(防抖)", reason or "", "待填", CountPending())

	eventFrame:SetScript("OnUpdate", function(self, dt)
		if GetTime() > watchUntil then
			StopWatch()
			return
		end

		if restoreQueued then
			debounceLeft = debounceLeft - dt
			if debounceLeft > 0 then
				return
			end
			restoreQueued = false
			retryElapsed = 0
			local stillNeed = TryRestorePending()
			if not stillNeed or CountPending() == 0 then
				StopWatch()
			end
			return
		end

		-- 仅当还有「空孔 + 技能未就绪」时短时重试，不再每 0.25s 全量扫
		retryElapsed = retryElapsed + dt
		if retryElapsed < RESTORE_RETRY_INTERVAL then
			return
		end
		retryElapsed = 0
		if CountPending() == 0 then
			StopWatch()
			return
		end
		local stillNeed = TryRestorePending()
		if not stillNeed or CountPending() == 0 then
			StopWatch()
		end
	end)
end

local function SnapshotAllSlots()
	for slot = 1, NUM_ACTION_SLOTS do
		local info = CaptureSlot(slot)
		if info then
			memory[slot] = info
			pending[slot] = nil
		end
	end
	PersistMemory()
	Debug("已快照动作条")
end

local function OnActionBarSlotChanged(slot)
	if not enabled or suppressing or not slot or slot < 1 or slot > NUM_ACTION_SLOTS then
		return
	end

	if HasAction(slot) then
		local info = CaptureSlot(slot)
		if info then
			memory[slot] = info
			pending[slot] = nil
			PersistMemory()
			Debug("记住", slot, info.type, info.name)
		end
		return
	end

	local prev = memory[slot]
	if not prev then
		return
	end

	-- 玩家拖走时鼠标上通常有技能/宏；客户端因脱装清空时鼠标是空的
	if IsCursorBusy() then
		Debug("手动清空", slot, prev.name)
		memory[slot] = nil
		pending[slot] = nil
		PersistMemory()
		return
	end

	Debug("待恢复", slot, prev.type, prev.name)
	pending[slot] = prev
	-- 登录刚完成时动作条会抖动，跳过回填；真正换装走 EQUIPMENT 事件
	if enteredWorldAt > 0 and (GetTime() - enteredWorldAt) < LOGIN_GRACE_SECONDS then
		Debug("登录宽限期内，跳过格子回填", slot)
		return
	end
	-- 单格清空只记 pending；回填由换装事件防抖统一触发，避免每格开一轮轮询
	ScheduleRestore("slot-cleared")
end

-- 只把「记忆里有、当前空」的孔标成待填
local function MarkMissingSlotsPending()
	for slot, info in pairs(memory) do
		if not HasAction(slot) then
			pending[slot] = info
		else
			pending[slot] = nil
		end
	end
end

local function OnEvent(self, event, ...)
	if not enabled then
		return
	end

	if event == "ACTIONBAR_SLOT_CHANGED" then
		OnActionBarSlotChanged(...)
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" then
		MarkMissingSlotsPending()
		if CountPending() > 0 then
			ScheduleRestore(event)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if needRestoreAfterCombat then
			needRestoreAfterCombat = false
			MarkMissingSlotsPending()
			if CountPending() > 0 then
				ScheduleRestore("regen")
			end
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- 进游戏只同步记忆，不回填（避免登录多余写入）
		enteredWorldAt = GetTime()
		LoadMemory()
		for slot = 1, NUM_ACTION_SLOTS do
			if HasAction(slot) then
				local info = CaptureSlot(slot)
				if info then
					memory[slot] = info
					pending[slot] = nil
				end
			end
		end
		WipeTable(pending)
		PersistMemory()
		StopWatch()
	elseif event == "PLAYER_LOGIN" then
		LoadMemory()
	end
end

function RuneActionBar:Enable()
	if enabled then
		return
	end
	if not initialized then
		self:Initialize()
	end
	enabled = true
	if eventFrame then
		eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		eventFrame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("PLAYER_LOGIN")
	end
	SnapshotAllSlots()
end

function RuneActionBar:Disable()
	if not enabled then
		return
	end
	enabled = false
	StopWatch()
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
end

function RuneActionBar:IsEnabled()
	return enabled
end

function RuneActionBar:Initialize()
	if initialized then
		return
	end
	initialized = true

	eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnEvent", OnEvent)

	if EquipmentManager_EquipSet then
		hooksecurefunc("EquipmentManager_EquipSet", function()
			if enabled then
				MarkMissingSlotsPending()
				if CountPending() > 0 then
					ScheduleRestore("equipset")
				end
			end
		end)
	end
	if UseEquipmentSet and UseEquipmentSet ~= EquipmentManager_EquipSet then
		hooksecurefunc("UseEquipmentSet", function()
			if enabled then
				MarkMissingSlotsPending()
				if CountPending() > 0 then
					ScheduleRestore("equipset")
				end
			end
		end)
	end

	MigrateFromBbTools()
	LoadMemory()
end

function RuneActionBar:Dump()
	print("|cff00ff00[符文条]|r 状态:", enabled and "开启" or "关闭")
	local count = 0
	for slot, info in pairs(memory) do
		count = count + 1
		local has = HasAction(slot)
		local can = CanPlace(info)
		print(string.format("  格子%d: %s/%s 在条=%s 可放=%s pickup=%s",
			slot, info.type or "?", info.name or "?",
			has and "是" or "否", can and "是" or "否",
			tostring(info.pickup)))
	end
	if count == 0 then
		print("  （尚无记忆，请先把符文技能放到动作条上）")
	end
end

function RuneActionBar:ForceRestore()
	SnapshotAllSlots()
	MarkMissingSlotsPending()
	ScheduleRestore("manual")
	print("|cff00ff00[符文条]|r 已手动触发恢复")
end

local function HandleRuneSlash(msg)
	if not addon:IsFeatureEnabled(KEY) then
		print("|cff00ff00[符文条]|r 功能未启用。")
		return
	end
	local input = msg and msg:match("^%s*(.-)%s*$") or ""
	input = string.lower(input)
	if input == "debug" then
		debugMode = not debugMode
		print("|cff00ff00[符文条]|r 调试: " .. (debugMode and "开" or "关"))
	elseif input == "dump" or input == "status" then
		RuneActionBar:Dump()
	elseif input == "save" or input == "snap" then
		SnapshotAllSlots()
		print("|cff00ff00[符文条]|r 已重新记住当前动作条")
	elseif input == "restore" or input == "fix" then
		RuneActionBar:ForceRestore()
	else
		print("|cff00ff00[符文条]|r /bbrune save|restore|dump|debug")
	end
end

local function RegisterSlash()
	if slashRegistered then return end
	SLASH_banbiRUNE1 = "/bbrune"
	SLASH_banbiRUNE2 = "/bbrunes"
	SlashCmdList.banbiRUNE = HandleRuneSlash
	if hash_SlashCmdList then
		hash_SlashCmdList["/bbrune"] = nil
		hash_SlashCmdList["/bbrunes"] = nil
	end
	slashRegistered = true
end

local function OnEnable()
	RuneActionBar:Initialize()
	RegisterSlash()
	RuneActionBar:Enable()
end

local function OnDisable()
	RuneActionBar:Disable()
end

addon:RegisterFeature(KEY, {
	category = "combat",
	default = true,
	label = function() return L["Rune Action Bar Restore"] end,
	desc = function()
		return L["Remember rune spells on the action bar and put them back after gear swaps."]
	end,
	OnEnable = OnEnable,
	OnDisable = OnDisable,
	BuildOptions = function(section, C)
		C:AddDescription(section, L["Use the buttons below to snapshot or restore rune spells on the action bar."])
		C:AddButton(section, {
			label = L["Save Action Bar Now"],
			callback = function()
				if enabled then
					SnapshotAllSlots()
					print("|cff00ff00[符文条]|r 已重新记住当前动作条")
				end
			end,
		})
		C:AddButton(section, {
			label = L["Restore Now"],
			callback = function()
				if enabled then
					RuneActionBar:ForceRestore()
				end
			end,
		})
	end,
})

addon.RuneActionBar = RuneActionBar
