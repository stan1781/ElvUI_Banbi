--[[
	text,                                              --按钮名称
	textHeight,                                        --按钮字体大小
	icon,                                              --按钮图片路径
	tCoordLeft, tCoordRight, tCoordTop, tCoordBottom,  --按钮图片的相对部分
	textR, textG, textB,                               --按钮文字顔色
	tooltipText,                                       --提示信息
	show,                                              --判断是否显示该按钮的函数
	func,                                              --点击按钮所进行的操作
	notClickable,                                      --不可点击(灰色按钮)
	justifyH,                                          --文字对其方式, LEFT或CENTER
	isSecure,                                          --是否是安全按钮
	attributes,                                        --安全按钮的属性, 格式为"属性1:值1; 属性2:值2"
]]

--{ "WHISPER", "INVITE", "TARGET", "IGNORE", "REPORT_SPAM", "GUILD_PROMOTE", "GUILD_LEAVE", "CANCEL" };
function NoSelfShow(name) return UnitName("player")~=name; end

FriendsMenuXP_Buttons = {};

FriendsMenuXP_Buttons["WHISPER"] = {
	text = WHISPER,
	func = function(name) ChatFrame_SendTell(name); end,
	--show = NoSelfShow,
};

FriendsMenuXP_Buttons["INVITE"] = {
	text = PARTY_INVITE,
	func = function(name) InviteUnit(name); end,
	show = NoSelfShow,
};

FriendsMenuXP_Buttons["TARGET"] = {
	text = TARGET,
	isSecure = 1,
	attributes = "type: macro;    macrotext: /targetexact $name$",
	func = function(name)
		if(UnitName("target")~=name) then 
			DEFAULT_CHAT_FRAME:AddMessage(string.gsub(FRIENDS_MENU_XP_CANNOT_TARGET, "%$name%$", name), 1,1,0); 
		end
	end,
};

FriendsMenuXP_Buttons["IGNORE"] = {
	text = IGNORE,
	func = function(name) AddOrDelIgnore(name); end,
	--show = NoSelfShow,
};

FriendsMenuXP_Buttons["REPORT_SPAM"] = {
	text = REPORT_SPAM
	,
	func = function(name, flags) 
		local dialog = StaticPopup_Show("CONFIRM_REPORT_SPAM_CHAT", name);
		if ( dialog ) then
			dialog.data = flags.lineID;
		end
	end
	,
	show = function(name, flags) return flags.lineID and CanComplainChat(flags.lineID) end
	,
};

FriendsMenuXP_Buttons["CANCEL"] = {
	text = CANCEL,
};

FriendsMenuXP_Buttons["ADD_FRIEND"] = {
	text = FMXP_BUTTON_ADD_FRIEND
	,
	func = function (name) AddFriend(name); end
	,
	show = function(name)
		if(name == UnitName("player")) then return end;
		for i = 1, GetNumFriends() do
			if(name == GetFriendInfo(i)) then
				return nil;
			end
		end
		return 1;
	end
	,
}

FriendsMenuXP_Buttons["REMOVE_FRIEND"] = {
	text = REMOVE_FRIEND
	,
	func = function (name) RemoveFriend(name); end
	,
	show = function(name)
		if(name == UnitName("player")) then return end;
		for i = 1, GetNumFriends() do
			if(name == GetFriendInfo(i)) then
				return true;
			end
		end
	end
	,
}

FriendsMenuXP_Buttons["SET_NOTE"] = {
	text = SET_NOTE
	,
	func = function (name) 		
		FriendsFrame.NotesID = name;
		StaticPopup_Show("SET_FRIENDNOTE", name);
		PlaySound("igCharacterInfoClose"); 
	end
	,
	show = function(name)
		if(name == UnitName("player")) then return end;
		for i = 1, GetNumFriends() do
			if(name == GetFriendInfo(i)) then
				return true;
			end
		end
	end
	,
}

FriendsMenuXP_Buttons["GUILD_LEAVE"] = {
	text = FMXP_BUTTON_GUILD_LEAVE
	,
	func = function (name) StaticPopup_Show("CONFIRM_GUILD_LEAVE", GetGuildInfo("player")); end
	,
	show = function(name)
		if(name ~= UnitName("player") or not GuildFrame:IsShown()) then return end;
		return 1;
	end
	,
}

FriendsMenuXP_Buttons["GUILD_PROMOTE"] = {
	text = FMXP_BUTTON_GUILD_PROMOTE
	,
	func = function (name) local dialog = StaticPopup_Show("CONFIRM_GUILD_PROMOTE", name); dialog.data = name; end
	,
	show = function(name)
		if ( not IsGuildLeader() or not UnitIsInMyGuild(name) or name == UnitName("player") or not GuildFrame:IsShown() ) then return end;
		return 1;
	end
	,
}

FriendsMenuXP_Buttons["PVP_REPORT_AFK"] = {
	text = FMXP_BUTTON_PVP_REPORT_AFK
	,
	func = function (name) ReportPlayerIsPVPAFK(name); end
	,
	show = function(name)
		if ( UnitInBattleground("player") == 0 or GetCVar("enablePVPNotifyAFK") == "0" ) then
			return;
		else
			if ( name == UnitName("player") ) then
				return;
			elseif ( not UnitInBattleground(name) ) then
				return;
			end
		end
		return 1;
	end
	,
}

FriendsMenuXP_Buttons["SET_FOCUS"] = {
	text = FMXP_BUTTON_SET_FOCUS
	,
	isSecure = 1
	,
	attributes = "type1:macro;macrotext1:/focus $name$"
	,
}

FriendsMenuXP_Buttons["PROMOTE"] = {
	text = FMXP_BUTTON_PROMOTE
	,
	func = function (name) PromoteToLeader(name, 1); end
	,
	show = function (name) 
		if (GetNumPartyMembers() > 0 and UnitInParty(name) and IsPartyLeader()) or (GetNumRaidMembers() > 0 and UnitInRaid(name) and IsRaidOfficer()) then
			return 1
		end
	end
	,
}

FriendsMenuXP_Buttons["LOOT_PROMOTE"] = {
	text = FMXP_BUTTON_LOOT_PROMOTE
	,
	func = function (name) SetLootMethod("master", name, 1); end
	,
	show = function (name) 
		if (GetNumPartyMembers() > 0 and UnitInParty(name) and IsPartyLeader()) or (GetNumRaidMembers() > 0 and UnitInRaid(name) and IsRaidOfficer()) then
			return 1
		end
	end
	,
}

FriendsMenuXP_Buttons["ACHIEVEMENTS"] = {
	text = FMXP_BUTTON_ACHIEVEMENTS
	,
	func = function (name) InspectAchievements(name); end
	,
}

FriendsMenuXP_Buttons["SEND_WHO"] = {
	text = FMXP_BUTTON_SEND_WHO,
	func = function (name) SendWho("n-"..name); end,
}

FriendsMenuXP_Buttons["ADD_GUILD"] = {
	text = FMXP_BUTTON_ADD_GUILD,
	func = function (name) GuildInvite(name); end,
	show = function (name) return name~=UnitName("player") and CanGuildInvite() end,
}

FriendsMenuXP_Buttons["GET_NAME"] = {
	text = FMXP_BUTTON_GET_NAME
	,
	func = function (name) 
		if ( ChatFrame1EditBox:IsVisible() ) then
			ChatFrame1EditBox:Insert(name);
		elseif( SendMailNameEditBox and SendMailNameEditBox:IsVisible() ) then
			SendMailNameEditBox:Insert(name);
		elseif( CT_MailNameEditBox and CT_MailNameEditBox:IsVisible() ) then
			CT_MailNameEditBox:Insert(name);
		else
			ChatFrame1EditBox:Show();
			ChatFrame1EditBox:SetText(name);
			ChatFrame1EditBox:HighlightText()
		end
	end
	,
}

FriendsMenuXP_Buttons["TRADE"] = {
	text = FMXP_BUTTON_TRADE,
	isSecure = 1,
	attributes = "type:macro;macrotext:/targetexact $name$",
	func = function (name) InitiateTrade("target"); end,
}

FriendsMenuXP_ButtonSet = {};
-- 私服精简：无职业 buff / 英雄榜；保留常用社交项
FriendsMenuXP_ButtonSet["NORMAL"] = {
	"WHISPER",
	"INVITE",
	"IGNORE",
	"PROMOTE",
	"REPORT_SPAM",
	"ADD_FRIEND",
	"REMOVE_FRIEND",
	"SET_NOTE",
	"ADD_GUILD",
	"PVP_REPORT_AFK",
	"ACHIEVEMENTS",
	"CANCEL",
}

FriendsMenuXP_ButtonSet["RAID"] = {
	"WHISPER",
	"PROMOTE",
	"ACHIEVEMENTS",
	"ADD_FRIEND",
	"REMOVE_FRIEND",
	"CANCEL",
}
