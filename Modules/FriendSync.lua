-- ElvUI_Banbi — Account friend list sync (ported from ElvUI_bbTools FriendSync).
-- Per-faction shared pool + removed list so other alts clean up and Collect never restores deletes.

local ADDON_NAME, addon = ...
local L = addon.L

local KEY = "friendSync"
local FriendSync = {}
local eventFrame
local queueFrame
local addQueue = {}
local removeQueue = {}
local queueBusy = false
local suppressFriendUpdate = false
local lastLocalFriends = nil -- nil = 尚未建立快照，不据此推断删除
local active = false
local loginHandled = false
local friendsMenuXPHooked = false

local QUEUE_INTERVAL = 0.4

local function Print(msg)
	local prefix = "|cff1784d1ElvUI|r|cffe5e3e3 Banbi|r|cff1784d1:|r"
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(prefix .. " " .. tostring(msg))
end

-- silent: true=不输出；"skipEmpty"=仅在有实际增删时输出；false/nil=照常输出（含无变更）
local function ShouldPrint(silent, count)
	if silent == true then
		return false
	end
	if silent == "skipEmpty" then
		return (count or 0) > 0
	end
	return true
end

local function Trim(value)
	if type(value) ~= "string" then
		return ""
	end
	return (value:match("^%s*(.-)%s*$")) or ""
end

local function NormalizeName(name)
	name = Trim(name)
	if name == "" then
		return nil
	end
	-- 本服好友通常无服务器后缀；若有则保留完整名
	return name
end

local function CharKey()
	local name = UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or (GetCVar and GetCVar("realmName")) or "?"
	return name .. "-" .. realm
end

local function GetFactionKey()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	if faction == "Alliance" or faction == "Horde" then
		return faction
	end
	return nil
end

local function FactionLabel(faction)
	if faction == "Alliance" then
		return "联盟"
	elseif faction == "Horde" then
		return "部落"
	end
	return faction or "未知"
end

local function MigrateFromBbTools()
	if not addon.db or not addon.db.global then return end
	local g = addon.db.global
	g.migrated = g.migrated or {}
	if g.migrated.friendSync then return end
	g.migrated.friendSync = true
	local src = _G.bbToolsDB and _G.bbToolsDB.friendSync
	if type(src) ~= "table" then return end
	if type(g.friendSync) == "table" and type(g.friendSync.friendsByFaction) == "table" then
		local a = g.friendSync.friendsByFaction.Alliance
		local h = g.friendSync.friendsByFaction.Horde
		if (type(a) == "table" and next(a)) or (type(h) == "table" and next(h)) then
			return
		end
	end
	local function copymap(t)
		local o = {}
		if type(t) ~= "table" then return o end
		for k, v in pairs(t) do
			if type(v) == "table" then
				local inner = {}
				for ik, iv in pairs(v) do inner[ik] = iv end
				o[k] = inner
			else
				o[k] = v
			end
		end
		return o
	end
	g.friendSync = g.friendSync or {}
	local dst = g.friendSync
	if type(src.friendsByFaction) == "table" then
		dst.friendsByFaction = {
			Alliance = copymap(src.friendsByFaction.Alliance),
			Horde = copymap(src.friendsByFaction.Horde),
		}
	end
	if type(src.removedByFaction) == "table" then
		dst.removedByFaction = {
			Alliance = copymap(src.removedByFaction.Alliance),
			Horde = copymap(src.removedByFaction.Horde),
		}
	end
	if type(src.settings) == "table" then
		dst.settings = {}
		for k, v in pairs(src.settings) do dst.settings[k] = v end
	end
	if type(src.chars) == "table" then
		dst.chars = copymap(src.chars)
	end
	if type(src.friends) == "table" then
		dst.friends = copymap(src.friends)
	end
	local n = 0
	if dst.friendsByFaction then
		for _, pool in pairs(dst.friendsByFaction) do
			if type(pool) == "table" then
				for _ in pairs(pool) do n = n + 1 end
			end
		end
	end
	if n > 0 then
		print("|cff00ff00[好友同步]|r 已从 bbToolsDB 导入共享库（约 " .. n .. " 人）。")
	end
end

local function EnsureDB()
	if not addon.db then
		return {
			friendsByFaction = { Alliance = {}, Horde = {} },
			removedByFaction = { Alliance = {}, Horde = {} },
			friends = {},
			chars = {},
			settings = { autoSyncOnLogin = true, autoCleanOnLogin = true },
		}
	end
	local g = addon.db.global
	g.friendSync = g.friendSync or {}
	local db = g.friendSync
	if type(db.friendsByFaction) ~= "table" then
		db.friendsByFaction = {}
	end
	if type(db.friendsByFaction.Alliance) ~= "table" then
		db.friendsByFaction.Alliance = {}
	end
	if type(db.friendsByFaction.Horde) ~= "table" then
		db.friendsByFaction.Horde = {}
	end
	-- 已删除名单：按阵营记录，防止其他角色登录时 Collect 把人写回共享库
	if type(db.removedByFaction) ~= "table" then
		db.removedByFaction = {}
	end
	if type(db.removedByFaction.Alliance) ~= "table" then
		db.removedByFaction.Alliance = {}
	end
	if type(db.removedByFaction.Horde) ~= "table" then
		db.removedByFaction.Horde = {}
	end
	-- 兼容旧版扁平 friends：不再用于同步，收集时迁入当前阵营库后清除
	if type(db.friends) ~= "table" then
		db.friends = {}
	end
	if type(db.chars) ~= "table" then
		db.chars = {}
	end
	if type(db.settings) ~= "table" then
		db.settings = {}
	end
	if db.settings.autoSyncOnLogin == nil then
		db.settings.autoSyncOnLogin = true
	end
	if db.settings.autoCleanOnLogin == nil then
		db.settings.autoCleanOnLogin = true
	end
	return db
end

-- 仅当前角色阵营的共享库（联盟/部落分开，避免跨阵营互相添加）
local function GetFactionPool(db, faction)
	db = db or EnsureDB()
	faction = faction or GetFactionKey()
	if not faction or not db.friendsByFaction[faction] then
		return nil, faction
	end
	return db.friendsByFaction[faction], faction
end

-- 当前阵营的「已删除」对照名单
local function GetRemovedPool(db, faction)
	db = db or EnsureDB()
	faction = faction or GetFactionKey()
	if not faction or not db.removedByFaction[faction] then
		return nil, faction
	end
	return db.removedByFaction[faction], faction
end

local function GetLocalFriendsSet()
	local set = {}
	local count = 0
	local num = GetNumFriends and GetNumFriends() or 0
	for i = 1, num do
		local name = GetFriendInfo(i)
		name = NormalizeName(name)
		if name then
			set[name] = true
			count = count + 1
		end
	end
	return set, count
end

local function CountPool(pool)
	local n = 0
	if type(pool) ~= "table" then
		return 0
	end
	for _ in pairs(pool) do
		n = n + 1
	end
	return n
end

local function IsLocalFriend(name)
	name = NormalizeName(name)
	if not name then
		return false
	end
	local num = GetNumFriends and GetNumFriends() or 0
	for i = 1, num do
		local friendName = NormalizeName(GetFriendInfo(i))
		if friendName and strlower(friendName) == strlower(name) then
			return true, friendName
		end
	end
	return false
end

local function FindPoolKey(pool, name)
	name = NormalizeName(name)
	if not name or type(pool) ~= "table" then
		return nil
	end
	if pool[name] then
		return name
	end
	local lower = strlower(name)
	for key in pairs(pool) do
		if strlower(key) == lower then
			return key
		end
	end
	return nil
end

local function IsMarkedRemoved(name)
	local removed = GetRemovedPool()
	return removed and FindPoolKey(removed, name) ~= nil
end

-- 记入已删除名单，并从共享库移除（核心：跨角色对照删除）
local function MarkAsRemoved(name)
	name = NormalizeName(name)
	if not name then
		return nil
	end

	local pool, faction = GetFactionPool()
	local removed = GetRemovedPool(nil, faction)
	if not removed then
		return nil
	end

	local poolKey = pool and FindPoolKey(pool, name)
	if poolKey then
		pool[poolKey] = nil
		name = poolKey
	end

	local db = EnsureDB()
	if type(db.friends) == "table" then
		local legacyKey = FindPoolKey(db.friends, name)
		if legacyKey then
			db.friends[legacyKey] = nil
		end
	end

	local existing = FindPoolKey(removed, name)
	if existing then
		removed[existing].removedBy = CharKey()
		removed[existing].removedAt = time and time() or 0
		return existing, faction
	end

	removed[name] = {
		removedBy = CharKey(),
		removedAt = time and time() or 0,
	}
	return name, faction
end

-- 重新加好友时清除删除标记，否则永远无法再同步回来
local function ClearRemovedMark(name)
	name = NormalizeName(name)
	if not name then
		return nil
	end
	local removed = GetRemovedPool()
	if not removed then
		return nil
	end
	local key = FindPoolKey(removed, name)
	if key then
		removed[key] = nil
		return key
	end
	return nil
end

local function SnapshotLocalFriends()
	local set = GetLocalFriendsSet()
	lastLocalFriends = {}
	for name in pairs(set) do
		lastLocalFriends[name] = true
	end
	return set
end

-- 当前角色好友列表里少了的人 → 写入已删除名单 + 移出共享库
local function ApplyLocalRemovalsToPool(silent)
	if not lastLocalFriends then
		SnapshotLocalFriends()
		return 0
	end

	local pool, faction = GetFactionPool()
	if not pool then
		SnapshotLocalFriends()
		return 0
	end

	local current = GetLocalFriendsSet()
	local removedNames = {}

	for name in pairs(lastLocalFriends) do
		local stillThere = false
		for cur in pairs(current) do
			if strlower(cur) == strlower(name) then
				stillThere = true
				break
			end
		end
		if not stillThere then
			local marked = MarkAsRemoved(name)
			if marked then
				table.insert(removedNames, marked)
			end
		end
	end

	SnapshotLocalFriends()

	if #removedNames > 0 and not silent then
		table.sort(removedNames)
		Print(string.format(
			"已记入%s删除名单 %d 人（当前角色删除，同阵营其他角色登录后会对照删除）：%s",
			FactionLabel(faction),
			#removedNames,
			table.concat(removedNames, "、")
		))
	end
	return #removedNames
end

local function ProcessQueues()
	if queueBusy then
		return
	end
	if #removeQueue > 0 then
		queueBusy = true
		local name = table.remove(removeQueue, 1)
		suppressFriendUpdate = true
		pcall(RemoveFriend, name)
		queueBusy = false
		if queueFrame then
			queueFrame.elapsed = 0
		end
		return
	end
	if #addQueue > 0 then
		queueBusy = true
		local name = table.remove(addQueue, 1)
		if not IsLocalFriend(name) then
			suppressFriendUpdate = true
			pcall(AddFriend, name)
		end
		queueBusy = false
		if queueFrame then
			queueFrame.elapsed = 0
		end
		return
	end
	if queueFrame then
		queueFrame:SetScript("OnUpdate", nil)
		queueFrame.elapsed = 0
	end
end

local function EnsureQueueFrame()
	if queueFrame then
		return
	end
	queueFrame = CreateFrame("Frame")
	queueFrame.elapsed = 0
end

local function StartQueue()
	EnsureQueueFrame()
	if queueFrame:GetScript("OnUpdate") then
		return
	end
	queueFrame.elapsed = QUEUE_INTERVAL
	queueFrame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed
		if self.elapsed < QUEUE_INTERVAL then
			return
		end
		self.elapsed = 0
		if #addQueue == 0 and #removeQueue == 0 then
			self:SetScript("OnUpdate", nil)
			return
		end
		ProcessQueues()
	end)
end

local function EnqueueAdd(names)
	for _, name in ipairs(names) do
		local n = NormalizeName(name)
		if n then
			local exists = false
			for _, q in ipairs(addQueue) do
				if strlower(q) == strlower(n) then
					exists = true
					break
				end
			end
			if not exists and not IsLocalFriend(n) then
				table.insert(addQueue, n)
			end
		end
	end
	if #addQueue > 0 then
		StartQueue()
	end
end

local function EnqueueRemove(names)
	for _, name in ipairs(names) do
		local n = NormalizeName(name)
		if n then
			local ok, actual = IsLocalFriend(n)
			if ok then
				local target = actual or n
				local exists = false
				for _, q in ipairs(removeQueue) do
					if strlower(q) == strlower(target) then
						exists = true
						break
					end
				end
				if not exists then
					table.insert(removeQueue, target)
				end
			end
		end
	end
	if #removeQueue > 0 then
		StartQueue()
	end
end

function FriendSync:GetStatus()
	local db = EnsureDB()
	local pool, faction = GetFactionPool(db)
	local removed = GetRemovedPool(db, faction)
	local localSet, localCount = GetLocalFriendsSet()
	local poolCount = CountPool(pool)
	local removedCount = CountPool(removed)
	local missing = 0
	local extras = 0
	local pendingDelete = 0
	if pool then
		for name in pairs(pool) do
			local found = false
			for localName in pairs(localSet) do
				if strlower(localName) == strlower(name) then
					found = true
					break
				end
			end
			if not found then
				missing = missing + 1
			end
		end
		for name in pairs(localSet) do
			if not FindPoolKey(pool, name) then
				extras = extras + 1
			end
			if removed and FindPoolKey(removed, name) then
				pendingDelete = pendingDelete + 1
			end
		end
	end
	return {
		poolCount = poolCount,
		removedCount = removedCount,
		pendingDelete = pendingDelete,
		localCount = localCount,
		missing = missing,
		extras = extras,
		autoSyncOnLogin = db.settings.autoSyncOnLogin and true or false,
		faction = faction,
		factionLabel = FactionLabel(faction),
		allianceCount = CountPool(db.friendsByFaction.Alliance),
		hordeCount = CountPool(db.friendsByFaction.Horde),
		charKey = CharKey(),
	}
end

function FriendSync:CollectFromCurrent(silent)
	local db = EnsureDB()
	local pool, faction = GetFactionPool(db)
	local removed = GetRemovedPool(db, faction)
	if not pool then
		if not silent then
			Print("无法识别阵营，跳过汇总。")
		end
		return 0, 0, 0
	end

	local charKey = CharKey()
	local localSet, localCount = GetLocalFriendsSet()
	local added = 0
	local skippedRemoved = 0
	local now = time and time() or 0

	for name in pairs(localSet) do
		-- 已删除名单中的人：绝不写回共享库
		if removed and FindPoolKey(removed, name) then
			skippedRemoved = skippedRemoved + 1
		else
			-- 旧版扁平库中的同名条目迁入当前阵营库
			if type(db.friends) == "table" then
				local legacyKey = FindPoolKey(db.friends, name)
				if legacyKey then
					db.friends[legacyKey] = nil
				end
			end
			if not FindPoolKey(pool, name) then
				pool[name] = {
					addedBy = charKey,
					addedAt = now,
					faction = faction,
				}
				added = added + 1
			end
		end
	end

	db.chars[charKey] = {
		lastSync = now,
		count = localCount,
		faction = faction,
	}

	SnapshotLocalFriends()

	if not silent then
		if added == 0 and skippedRemoved == 0 then
			Print(string.format("当前角色好友已在%s共享库中，无新增。", FactionLabel(faction)))
		else
			Print(string.format(
				"已汇总当前角色好友到%s库。新增 %d（库共 %d，当前角色 %d）",
				FactionLabel(faction), added, CountPool(pool), localCount
			))
			if skippedRemoved > 0 then
				Print(string.format("跳过 %d 人（在删除名单中，不会写回共享库）。", skippedRemoved))
			end
		end
	end
	return added, CountPool(pool), localCount
end

function FriendSync:SyncToCurrent(silent)
	local pool, faction = GetFactionPool()
	local removed = GetRemovedPool(nil, faction)
	if not pool then
		if ShouldPrint(silent, 1) then
			Print("无法识别阵营，跳过同步。")
		end
		return 0
	end

	self:CollectFromCurrent(true)

	local missing = {}
	for name in pairs(pool) do
		-- 防御：删除名单中的人即使残留在库里也不再添加
		if not (removed and FindPoolKey(removed, name)) and not IsLocalFriend(name) then
			table.insert(missing, name)
		end
	end
	table.sort(missing)

	if #missing == 0 then
		if ShouldPrint(silent, 0) then
			Print(string.format("当前角色已覆盖%s共享库，无需添加。", FactionLabel(faction)))
		end
		return 0
	end

	EnqueueAdd(missing)
	if ShouldPrint(silent, #missing) then
		Print(string.format(
			"开始同步%s库：将添加 %d 个好友到当前角色（排队中）…",
			FactionLabel(faction), #missing
		))
	end
	return #missing
end

function FriendSync:AddToPool(name, alsoAddLocal)
	local pool, faction = GetFactionPool()
	if not pool then
		Print("无法识别阵营。")
		return false
	end

	name = NormalizeName(name)
	if not name then
		Print("请提供有效角色名。")
		return false
	end

	-- 手动重新添加 → 清除删除标记，允许再次进入共享库
	local cleared = ClearRemovedMark(name)
	if cleared then
		Print(string.format("已从%s删除名单移除：%s（允许重新同步）", FactionLabel(faction), cleared))
	end

	local key = FindPoolKey(pool, name)
	if not key then
		pool[name] = {
			addedBy = CharKey(),
			addedAt = time and time() or 0,
			faction = faction,
		}
		Print(string.format("已加入%s共享库：%s", FactionLabel(faction), name))
	else
		Print(string.format("%s共享库已有：%s", FactionLabel(faction), key))
		name = key
	end

	if alsoAddLocal ~= false and not IsLocalFriend(name) then
		EnqueueAdd({ name })
		Print("正在添加到当前角色好友：" .. name)
	end
	return true
end

function FriendSync:RemoveFromPool(name, alsoRemoveLocal)
	local pool, faction = GetFactionPool()
	if not pool then
		Print("无法识别阵营。")
		return false
	end

	name = NormalizeName(name)
	if not name then
		Print("请提供有效角色名。")
		return false
	end

	local marked = MarkAsRemoved(name)
	if marked then
		Print(string.format("已从%s共享库移除并记入删除名单：%s", FactionLabel(faction), marked))
		name = marked
	else
		Print(string.format("无法写入%s删除名单：%s", FactionLabel(faction), name))
		return false
	end

	if alsoRemoveLocal ~= false and IsLocalFriend(name) then
		EnqueueRemove({ name })
		Print("正在从当前角色移除好友：" .. name)
	end
	return true
end

-- 对照删除名单：把当前角色好友里「已标记删除」的人排队移除
function FriendSync:ApplyRemovedListToLocal(silent)
	local removed, faction = GetRemovedPool()
	if not removed then
		if ShouldPrint(silent, 1) then
			Print("无法识别阵营，跳过删除名单对照。")
		end
		return 0
	end

	local localSet = GetLocalFriendsSet()
	local toRemove = {}
	for name in pairs(localSet) do
		if FindPoolKey(removed, name) then
			table.insert(toRemove, name)
		end
	end
	table.sort(toRemove)

	if #toRemove == 0 then
		if ShouldPrint(silent, 0) then
			Print(string.format("当前角色没有需要对照%s删除名单清理的好友。", FactionLabel(faction)))
		end
		return 0
	end

	EnqueueRemove(toRemove)
	if ShouldPrint(silent, #toRemove) then
		Print(string.format(
			"对照%s删除名单：将从当前角色移除 %d 人：%s",
			FactionLabel(faction), #toRemove, table.concat(toRemove, "、")
		))
	end
	return #toRemove
end

function FriendSync:RemoveLocalNotInPool(silent)
	local pool, faction = GetFactionPool()
	if not pool then
		if ShouldPrint(silent, 1) then
			Print("无法识别阵营，跳过清理。")
		end
		return 0
	end

	local localSet = GetLocalFriendsSet()
	local extras = {}
	for name in pairs(localSet) do
		if not FindPoolKey(pool, name) then
			table.insert(extras, name)
		end
	end
	table.sort(extras)

	if #extras == 0 then
		if ShouldPrint(silent, 0) then
			Print(string.format("当前角色没有「不在%s共享库」的多余好友。", FactionLabel(faction)))
		end
		return 0
	end

	EnqueueRemove(extras)
	if ShouldPrint(silent, #extras) then
		Print(string.format(
			"开始清理：将从当前角色移除 %d 个不在%s共享库的好友：%s",
			#extras, FactionLabel(faction), table.concat(extras, "、")
		))
	end
	return #extras
end

function FriendSync:ListRemoved(limit)
	local removed, faction = GetRemovedPool()
	if not removed then
		Print("无法识别阵营。")
		return
	end
	local names = {}
	for name in pairs(removed) do
		table.insert(names, name)
	end
	table.sort(names)
	limit = tonumber(limit) or 50
	local total = #names
	Print(string.format(
		"%s删除名单共 %d 人（显示前 %d）：",
		FactionLabel(faction), total, math.min(limit, total)
	))
	for i = 1, math.min(limit, total) do
		local info = removed[names[i]]
		local by = info and info.removedBy or "?"
		Print(string.format("  %d. %s （由 %s 删除）", i, names[i], by))
	end
	if total > limit then
		Print(string.format("  …还有 %d 人未显示", total - limit))
	end
end

function FriendSync:ClearRemovedEntry(name)
	name = NormalizeName(name)
	if not name then
		Print("请提供角色名。")
		return false
	end
	local _, faction = GetRemovedPool()
	local key = ClearRemovedMark(name)
	if key then
		Print(string.format("已从%s删除名单清除：%s（不会自动加回好友）", FactionLabel(faction), key))
		return true
	end
	Print(string.format("%s删除名单中未找到：%s", FactionLabel(faction), name))
	return false
end

function FriendSync:SetAutoSyncOnLogin(enabled)
	local db = EnsureDB()
	db.settings.autoSyncOnLogin = enabled and true or false
	Print(db.settings.autoSyncOnLogin and "登录自动同步（添加）：开" or "登录自动同步（添加）：关")
	return db.settings.autoSyncOnLogin
end

function FriendSync:IsAutoSyncOnLogin()
	return EnsureDB().settings.autoSyncOnLogin and true or false
end

function FriendSync:SetAutoCleanOnLogin(enabled)
	local db = EnsureDB()
	db.settings.autoCleanOnLogin = enabled and true or false
	Print(db.settings.autoCleanOnLogin and "登录自动清理（删除）：开" or "登录自动清理（删除）：关")
	return db.settings.autoCleanOnLogin
end

function FriendSync:IsAutoCleanOnLogin()
	local db = EnsureDB()
	return db.settings.autoCleanOnLogin ~= false
end

function FriendSync:ListPool(limit)
	local pool, faction = GetFactionPool()
	if not pool then
		Print("无法识别阵营。")
		return
	end
	local names = {}
	for name in pairs(pool) do
		table.insert(names, name)
	end
	table.sort(names)
	limit = tonumber(limit) or 50
	local total = #names
	Print(string.format(
		"%s共享库共 %d 人（显示前 %d）：",
		FactionLabel(faction), total, math.min(limit, total)
	))
	for i = 1, math.min(limit, total) do
		local info = pool[names[i]]
		local by = info and info.addedBy or "?"
		Print(string.format("  %d. %s （来自 %s）", i, names[i], by))
	end
	if total > limit then
		Print(string.format("  …还有 %d 人未显示", total - limit))
	end
end

function FriendSync:PrintStatus()
	local s = self:GetStatus()
	Print(string.format(
		"当前阵营 %s | 本阵营库 %d（联盟 %d / 部落 %d）| 删除名单 %d | 当前角色 %d | 缺失 %d | 待对照删 %d | 多余 %d | 自动添加 %s | 自动清理 %s | %s",
		s.factionLabel or "?",
		s.poolCount, s.allianceCount or 0, s.hordeCount or 0,
		s.removedCount or 0,
		s.localCount, s.missing, s.pendingDelete or 0, s.extras,
		s.autoSyncOnLogin and "开" or "关",
		self:IsAutoCleanOnLogin() and "开" or "关",
		s.charKey
	))
end

local function IsInFactionPool(name)
	local pool = GetFactionPool()
	return pool and FindPoolKey(pool, name) ~= nil
end

local friendsMenuXPSkinned = false

local function SkinFriendsMenuXP()
	if friendsMenuXPSkinned then
		return
	end
	if not FriendsMenuXP and not FriendsMenuXPSecure then
		return
	end
	local E = addon:GetE()
	if not E then
		return
	end
	local S = E:GetModule("Skins", true)
	if not S then
		return
	end
	local maxButtons = FRIENDSMENU_MAXBUTTONS or 20
	local function skinMenuFrame(frame)
		if not frame or frame.isElvSkinned then
			return
		end
		local name = frame:GetName()
		local backdrop = _G[name .. "Backdrop"]
		local menuBackdrop = _G[name .. "MenuBackdrop"]
		if backdrop and backdrop.SetTemplate then
			backdrop:SetTemplate("Transparent")
		end
		if menuBackdrop and menuBackdrop.SetTemplate then
			menuBackdrop:SetTemplate("Transparent")
		elseif frame.SetTemplate then
			frame:SetTemplate("Transparent")
		end
		for i = 1, maxButtons do
			local button = _G[name .. "Button" .. i]
			if button and not button.isElvSkinned then
				local highlight = _G[name .. "Button" .. i .. "Highlight"]
				if highlight and S.HandleButtonHighlight then
					S:HandleButtonHighlight(highlight)
				end
				local normalText = _G[name .. "Button" .. i .. "NormalText"]
				if normalText and normalText.FontTemplate then
					normalText:FontTemplate(nil, 12, "")
				end
				local icon = _G[name .. "Button" .. i .. "Icon"]
				if icon then
					icon:SetSize(14, 14)
					icon:ClearAllPoints()
					icon:SetPoint("RIGHT", button, "RIGHT", -4, 0)
				end
				button.isElvSkinned = true
			end
		end
		frame:HookScript("OnShow", function(self)
			local mb = _G[self:GetName() .. "MenuBackdrop"]
			local bd = _G[self:GetName() .. "Backdrop"]
			local border = E.media.bordercolor
			local fade = E.media.backdropfadecolor
			if mb then
				mb:SetBackdropBorderColor(border[1], border[2], border[3])
				mb:SetBackdropColor(fade[1], fade[2], fade[3], fade[4])
			end
			if bd then
				bd:SetBackdropBorderColor(border[1], border[2], border[3])
				bd:SetBackdropColor(fade[1], fade[2], fade[3], fade[4])
			end
			if self.maxWidth then
				self:SetWidth(self.maxWidth + 10)
			end
		end)
		frame.isElvSkinned = true
	end
	skinMenuFrame(FriendsMenuXP)
	skinMenuFrame(FriendsMenuXPSecure)
	friendsMenuXPSkinned = true
end

local function HookFriendsMenuXP()
	if not active then
		return
	end
	SkinFriendsMenuXP()
	if type(FriendsMenuXP_Buttons) ~= "table" then
		return
	end

	local addBtn = FriendsMenuXP_Buttons["ADD_FRIEND"]
	if addBtn then
		addBtn.text = "加为好友(同步)"
		addBtn.func = function(name)
			FriendSync:AddToPool(name, true)
		end
		addBtn.show = function(name)
			if not name or name == UnitName("player") then
				return
			end
			if IsLocalFriend(name) then
				return
			end
			return 1
		end
	end

	local removeBtn = FriendsMenuXP_Buttons["REMOVE_FRIEND"]
	if removeBtn then
		removeBtn.text = "删除好友(同步)"
		removeBtn.func = function(name)
			FriendSync:RemoveFromPool(name, true)
		end
		-- 当前角色好友，或仅存在于本阵营共享库时均可删除
		removeBtn.show = function(name)
			if not name or name == UnitName("player") then
				return
			end
			if IsLocalFriend(name) or IsInFactionPool(name) then
				return true
			end
		end
	end
	friendsMenuXPHooked = true
end

function FriendSync.ApplyMenuHooks()
	friendsMenuXPHooked = false
	HookFriendsMenuXP()
end

local function OnEvent(_, event, ...)
	if not active then
		return
	end
	if event == "ADDON_LOADED" then
		-- Standalone FriendsMenuXP or our embedded menus finishing load.
		if FriendsMenuXP_Buttons then
			HookFriendsMenuXP()
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		EnsureDB()
		HookFriendsMenuXP()
		loginHandled = false
		if ShowFriends then
			pcall(ShowFriends)
		end
		local delay = CreateFrame("Frame")
		delay.t = 0
		delay:SetScript("OnUpdate", function(self, elapsed)
			self.t = self.t + elapsed
			if self.t < 1.5 then
				return
			end
			self:SetScript("OnUpdate", nil)
			if loginHandled then
				return
			end
			loginHandled = true
			-- 先快照，避免登录瞬间把「尚未加载完的空列表」当成全删
			SnapshotLocalFriends()
			local deleted, extras, added = 0, 0, 0
			local didAuto = false
			-- 1) 先对照删除名单从当前角色删人（避免随后 Collect 把已删的人写回库）
			if FriendSync:IsAutoCleanOnLogin() then
				didAuto = true
				deleted = FriendSync:ApplyRemovedListToLocal("skipEmpty")
			end
			-- 2) 汇总时会跳过删除名单中的名字
			FriendSync:CollectFromCurrent(true)
			-- 3) 再清掉不在共享库的多余好友
			if FriendSync:IsAutoCleanOnLogin() then
				extras = FriendSync:RemoveLocalNotInPool("skipEmpty")
			end
			if FriendSync:IsAutoSyncOnLogin() then
				didAuto = true
				added = FriendSync:SyncToCurrent("skipEmpty")
			end
			-- 各项都无增删时只提示一句，避免多条「无需xxx」刷屏
			if didAuto and deleted + extras + added == 0 then
				Print("登录好友同步完成：无需增删。")
			end
		end)
	elseif event == "FRIENDLIST_UPDATE" then
		if suppressFriendUpdate then
			-- 插件自己排队增删触发的更新：只刷新快照/汇总，避免重复提示
			suppressFriendUpdate = false
			FriendSync:CollectFromCurrent(true)
			return
		end
		-- 好友界面手动删人 → 记入删除名单并移出共享库
		ApplyLocalRemovalsToPool(false)
		FriendSync:CollectFromCurrent(true)
	elseif event == "PLAYER_LOGOUT" then
		FriendSync:CollectFromCurrent(true)
	end
end

local function OnEnable()
	MigrateFromBbTools()
	active = true
	loginHandled = false
	EnsureDB()
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		eventFrame:SetScript("OnEvent", OnEvent)
	end
	eventFrame:RegisterEvent("PLAYER_LOGIN")
	eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
	eventFrame:RegisterEvent("PLAYER_LOGOUT")
	eventFrame:RegisterEvent("ADDON_LOADED")
	HookFriendsMenuXP()
	if UnitName("player") then
		OnEvent(nil, "PLAYER_LOGIN")
	end
end

local function OnDisable()
	active = false
	if eventFrame then
		eventFrame:UnregisterAllEvents()
	end
	if queueFrame then
		queueFrame:SetScript("OnUpdate", nil)
	end
	for i = #addQueue, 1, -1 do addQueue[i] = nil end
	for i = #removeQueue, 1, -1 do removeQueue[i] = nil end
	lastLocalFriends = nil
	loginHandled = false
end

addon:RegisterFeature(KEY, {
	category = "social",
	default = true,
	label = function() return L["Friend Sync"] end,
	desc = function()
		return L["Sync friends across alts per faction. Deletes go to a removed list so other characters clean up too."]
	end,
	OnEnable = OnEnable,
	OnDisable = OnDisable,
	BuildOptions = function(section, C)
		C:AddDescription(section, L["Use the buttons below, or add/remove friend (sync) from the player context menu. Alliance and Horde pools are separate."])
		C:AddToggle(section, {
			label = L["Auto-add on login"],
			desc = L["On login, add friends from the shared pool that are missing on this character."],
			getFunc = function() return FriendSync:IsAutoSyncOnLogin() end,
			setFunc = function(val)
				EnsureDB().settings.autoSyncOnLogin = val and true or false
			end,
		})
		C:AddToggle(section, {
			label = L["Auto-clean on login"],
			desc = L["On login, remove friends on the deleted list and extras not in the shared pool."],
			getFunc = function() return FriendSync:IsAutoCleanOnLogin() end,
			setFunc = function(val)
				EnsureDB().settings.autoCleanOnLogin = val and true or false
			end,
		})
		C:AddButton(section, {
			label = L["Collect current friends"],
			callback = function() FriendSync:CollectFromCurrent(false) end,
		})
		C:AddButton(section, {
			label = L["Sync to this character"],
			callback = function() FriendSync:SyncToCurrent(false) end,
		})
		C:AddButton(section, {
			label = L["Clean extras"],
			callback = function()
				FriendSync:ApplyRemovedListToLocal(false)
				FriendSync:RemoveLocalNotInPool(false)
			end,
		})
		C:AddButton(section, {
			label = L["Show status"],
			callback = function() FriendSync:PrintStatus() end,
		})
		C:AddButton(section, {
			label = L["List removed"],
			callback = function() FriendSync:ListRemoved(50) end,
		})
	end,
})

addon.FriendSync = FriendSync
