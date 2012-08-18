--[[
	KillingSpree authored by Douglas Craig (chexsum) <chexsum@gmail.com>

	Announces consecutive killing blows. 

]]
KillingSpree = LibStub("AceAddon-3.0"):NewAddon("KillingSpree", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0", "LibSink-2.0")
local self = KillingSpree

local MULTITIMER = 120  -- Seconds given to perform multi kills
local SPREETIMER = 600  -- Seconds given to perform spree kills

local time = time
local string_format = string.format
local PlaySoundFile = PlaySoundFile
local InterfaceOptionsFrame_OpenToCategory = InterfaceOptionsFrame_OpenToCategory
local CombatLog_Object_IsA = CombatLog_Object_IsA
local COMBATLOG_FILTER_ME = COMBATLOG_FILTER_ME
local COMBATLOG_FILTER_MY_PET = COMBATLOG_FILTER_MY_PET
local COMBATLOG_FILTER_HOSTILE_UNITS = COMBATLOG_FILTER_HOSTILE_UNITS
local COMBATLOG_FILTER_HOSTILE_PLAYERS = COMBATLOG_FILTER_HOSTILE_PLAYERS

local STRING_COLOR_BLACK = string_format("|cff%02x%02x%02x", 0, 0, 0)
local STRING_COLOR_WHITE = string_format("|cff%02x%02x%02x", 255, 255, 255)
local STRING_COLOR_YELLOW = string_format("|cff%02x%02x%02x", 255, 255, 0)
local STRING_COLOR_ORANGE = string_format("|cff%02x%02x%02x", 255, 128, 0)
local STRING_COLOR_CRIMSON = string_format("|cff%02x%02x%02x", 255, 0, 0)
local STRING_COLOR_MAROON = string_format("|cff%02x%02x%02x", 128, 0, 0)
local STRING_COLOR_GREEN = string_format("|cff%02x%02x%02x", 0, 255, 0)
local STRING_COLOR_BLUE = string_format("|cff%02x%02x%02x", 0, 0, 255)

function KillingSpree:OnInitialize()
	self.scheme = {}
	self.schemes = { "UT2k3", "UT2k4Male", "UT2k4Male2", "UT2k4Female", "UT2k4Female2" }
	for scheme = 1, #self.schemes do
		self.scheme[self.schemes[scheme]] = {
			['firstblood'] = { "firstblood.mp3", "First Blood!" },
			['multi'] = {
				[2] = { "doublekill.mp3", "Double Kill!" },
				[3] = { "multikill.mp3", "Multi Kill!" },
				[4] = { "megakill.mp3", "Mega Kill!" },
				[5] = { "ultrakill.mp3", "Ultra Kill!" },
				[6] = { "monsterkill.mp3", "Monster Kill!" },
			},
			['spree'] = {
				[10] = { "killingspree.mp3", "Killing Spree!" },
				[13] = { "rampage.mp3", "Rampage!" },
				[16] = { "dominating.mp3", "Dominating!" },
				[19] = { "unstoppable.mp3", "Unstoppable!" },
				[22] = { "godlike.mp3", "God-like!" },
			},
		}
		if self.schemes[scheme] ~= "UT2k3" then
			self.scheme[self.schemes[scheme]]['multi'][7] = { "ludicrouskill.mp3", "Ludicrous Kill!" }
			self.scheme[self.schemes[scheme]]['spree'][25] = { "wickedsick.mp3", "Wicked Sick!" }
		end
	end
	if UnitSex('player') == 3 then
		self.defaultscheme = "UT2k4Female"
	else
		self.defaultscheme = "UT2k4Male"
	end
	self.defaults = {
		profile = {
			pvp = true,
			pve = false,
			scheme = self.defaultscheme,
		},
	}
	self.db = LibStub("AceDB-3.0"):New("KillingSpreeDB", self.defaults, "Default")
	self.options = {
		type = 'group',
		name = "KillingSpree",
		desc = "Consecutive kill announcer",
		icon = "Interface\\AddOns\\KillingSpree\\icon",
		args = {
			pvp = {
				order = 1,
				type = 'toggle',
				name = "Show PVP",
				desc = "Show PVP kills",
				get = function(info)
					return self.db.profile.pvp
				end,
				set = function(info, value)
					self.db.profile.pvp = value
					self:UpdateVictims()
				end,
			},
			pve = {
				order = 2,
				type = 'toggle',
				name = "Show PVE",
				desc = "Show PVE kills",
				get = function(info)
					return self.db.profile.pve
				end,
				set = function(info, value)
					self.db.profile.pve = value
					self:UpdateVictims()
				end,
			},
			scheme = {
				order = 5,
				type = 'select',
				name = "Sound scheme",
				desc = "Selects the sound scheme",
				get = function(info)
					return self.db.profile.scheme
				end,
				set = function(info, value)
				    self.db.profile.scheme = value
				end,
				values = {
					["UT2k3"] = "UT2k3",
					["UT2k4Male"] = "UT2k4Male",
					["UT2k4Male2"] = "UT2k4Male2",
					["UT2k4Female"] = "UT2k4Female",
					["UT2k4Female2"] = "UT2k4Female2",
	            },
			},
		},
	}
	self:SetSinkStorage(self.db.profile)
	self.options.args.output = self:GetSinkAce3OptionsDataTable()
	LibStub("AceConfig-3.0"):RegisterOptionsTable("KillingSpree", self.options, {"killingspree"})
	self.optionsDialog = LibStub("AceConfigDialog-3.0")
	self.optionsFrame = self.optionsDialog:AddToBlizOptions("KillingSpree", "KillingSpree")
end

function KillingSpree:OnEnable()
	self:ResetVictims()
	self:RegisterEvent("PLAYER_DEAD", "ResetVictims")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ResetVictims")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLogEvent")
end

function KillingSpree:ResetVictims()
	self.victims = {}
	self.kills = 0
	self.multi = 0
	self.spree = 0
	self.bestspree = 0
	self.bestmulti = 0
end

function KillingSpree:CombatLogEvent(event, timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceType, destinationGUID, destinationName, destinationFlags, destinationType, ...)
	if eventType and eventType == "PARTY_KILL" and sourceFlags and (CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_ME) or CombatLog_Object_IsA(sourceFlags, COMBATLOG_FILTER_MY_PET)) then
		if not self.db.profile.pvp and CombatLog_Object_IsA(destinationFlags, COMBATLOG_FILTER_HOSTILE_PLAYERS) then return end
		if not self.db.profile.pve and CombatLog_Object_IsA(destinationFlags, COMBATLOG_FILTER_HOSTILE_UNITS) then return end
		self.kills = self.kills + 1
		self.victims[self.kills] = {}
		self.victims[self.kills].tod = time()
		self.victims[self.kills].name = destinationName
		self:UpdateVictims()
		self:Announce()
	end
end

function KillingSpree:UpdateVictims()
	local multi, spree = 0, 0
	for victim = self.kills, 1, -1 do
		if self.victims[victim] then
			local difference = time() - self.victims[victim].tod
			if difference < MULTITIMER then
				multi = multi + 1
			elseif difference < SPREETIMER then
				spree = spree + 1
			end
		end
	end
	self.multi = multi
	self.spree = spree + multi
end

function KillingSpree:Announce()
	if self.spree > 1 and self.scheme[self.db.profile.scheme]['spree'][self.spree] and self.spree > self.bestspree then
		PlaySoundFile(string_format("Interface\\AddOns\\KillingSpree\\Snds\\%s\\%s", self.db.profile.scheme, self.scheme[self.db.profile.scheme]['spree'][self.spree][1]))
		self:Pour(string_format("%s", self.scheme[self.db.profile.scheme]['spree'][self.spree][2]), 1, 0, 0)
		self.bestspree = self.spree
	elseif self.spree > 1 and self.scheme[self.db.profile.scheme]['multi'][self.multi] and self.multi > self.bestmulti then
		PlaySoundFile(string_format("Interface\\AddOns\\KillingSpree\\Snds\\%s\\%s", self.db.profile.scheme, self.scheme[self.db.profile.scheme]['multi'][self.multi][1]))
		self:Pour(string_format("%s", self.scheme[self.db.profile.scheme]['multi'][self.multi][2]), 1, 0, 0)
		self.bestmulti = self.multi
	elseif self.spree == 1 and self.scheme[self.db.profile.scheme]['firstblood'] then
		PlaySoundFile(string_format("Interface\\AddOns\\KillingSpree\\Snds\\%s\\%s", self.db.profile.scheme, self.scheme[self.db.profile.scheme]['firstblood'][1]))
		self:Pour(string_format("%s", self.scheme[self.db.profile.scheme]['firstblood'][2]), 1, 0, 0)
	end
end
