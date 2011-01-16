--[[
AdiCCMonitor - Crowd-control monitor.
Copyright 2011 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName, addon = ...
local L = addon.L

local mod = addon:NewModule('Alerts', 'AceEvent-3.0', 'AceTimer-3.0', 'LibSink-2.0')

local prefs

local DEFAULT_SETTINGS = {
	profile = {
		messages = { ['*'] = true },
		delay = 5,
	}
}

function mod:OnInitialize()
	self.db = addon.db:RegisterNamespace(self.moduleName, DEFAULT_SETTINGS)
end

function mod:OnEnable()
	prefs = self.db.profile
	self:SetSinkStorage(prefs)

	self:RegisterMessage('AdiCCMonitor_SpellAdded')
	self:RegisterMessage('AdiCCMonitor_SpellRemoved')
	self:RegisterMessage('AdiCCMonitor_SpellUpdated')
	self:RegisterMessage('AdiCCMonitor_WipeTarget', 'PlanNextUpdate')
	self.runningTimer = nil

	self:UpdateFailureListening()
end

function mod:OnDisable()
	addon.UnregisterAllCombatLogEvents(self)
end

function mod:OnConfigChanged(key, ...)
	if key == 'delay' or (key == 'messages' and ... == 'warning') then
		self:PlanNextUpdate()
	end
	self:UpdateFailureListening()
end

function mod:UpdateFailureListening()
	if prefs.messages.failure then
		addon.RegisterCombatLogEvent(self, 'SPELL_CAST_FAILED')
	else
		addon.UnregisterCombatLogEvent(self, 'SPELL_CAST_FAILED')
	end
end

function mod:SPELL_CAST_FAILED(event, _, _, _, _, _, _, _, spellName, _, reason)
	self:Alert('failure', spellName, reason)
end

function mod:PlanNextUpdate()
	if self.runningTimer then
		self:CancelTimer(self.runningTimer, true)
		self.runningTimer = nil
	end
	if not prefs.messages.warning then return end
	self:Debug('PlanNextUpdate')
	local delay = prefs.delay
	local nextTime
	local now = GetTime()
	for guid, spellId, spell in addon:IterateSpells() do
		local alertTime = spell.expires - delay
		local fadingSoon
		if alertTime > now then
			if not nextTime or alertTime < nextTime then
				nextTime = alertTime
			end
		else
			fadingSoon = true
		end
		if spell.fadingSoon ~= fadingSoon then
			spell.fadingSoon = fadingSoon
			if fadingSoon then
				self:Alert('warning', spell.target, spell.symbol, spell.expires)
			end
		end
	end
	if nextTime then
		self:Debug('Next update in', nextTime - now)
		self.runningTimer = self:ScheduleTimer('PlanNextUpdate', nextTime - now)
	end
end

function mod:AdiCCMonitor_SpellAdded(event, guid, spellID, spell)
	self:Alert('applied', spell.target, spell.symbol, spell.expires)
	return self:PlanNextUpdate()
end

function mod:AdiCCMonitor_SpellUpdated(event, guid, spellID, spell)
	return self:PlanNextUpdate()
end

function mod:AdiCCMonitor_SpellRemoved(event, guid, spellID, spell, brokenByName)
	self:PlanNextUpdate()
	local messageID = "removed"
	if brokenByName and prefs.messages.early and not (prefs.messages.warning and spell.fadingSoon) then
			messageID = "early"
	end
	self:Alert(messageID, spell.target, spell.symbol, spell.expires, brokenByName)
end

local SYMBOLS = {}
for i = 1, 8 do SYMBOLS[i] = '{'.._G["RAID_TARGET_"..i]..'}' end

function mod:Alert(messageID, ...)
	if not prefs.messages[messageID] or not IsInInstance() then
		return
	end
	self:Debug('Alert', messageID, ...)
	local message
	if messageID == 'failure' then
		local spell, reason = ...
		message = spell..': '..reason
	else
		local target, symbol, expires, moreArg = ...
		local targetName = SYMBOLS[symbol or false] or target
		local timeLeft = expires and floor(expires - GetTime() + 0.5)
		if messageID == 'applied' or messageID == 'warning' then
			message = format(L['%s will break free in %d secs.'], targetName, timeLeft)
		elseif messageID == 'removed' then
			message = format(L['%s is free !'], targetName)
		elseif messageID == 'early' then
			message = format(L['%s has been freed by %s !'], targetName, moreArg)
		end
	end
	if message then
		self:Pour('<<'..message..'>>', 1, 1, 1)
	end
end

function mod:GetOptions()
	local sinkOpts = self:GetSinkAce3OptionsDataTable()
	sinkOpts.order = 30
	sinkOpts.inline = true
	return {
		name = L['Alerts'],
		type = 'group',
		handler = addon:GetOptionHandler(self),
		set = 'Set',
		get = 'Get',
		disabled = 'IsDisabled',
		args = {
			messages = {
				name = L['Messages'],
				width = 'full',
				type = 'multiselect',
				values = {
					applied = L['Applied'],
					removed = L['Removed'],
					warning = L['About to end'],
					failure = L['Failures'],
					early = L['Broken early'],
				},
				order = 10,
			},
			delay = {
				name = L['Warning threshold (sec)'],
				desc = L['A warning message is sent when the time left for a spell runs below this value.'],
				type = 'range',
				min = 2,
				max = 15,
				step = 1,
				disabled = function(info) return info.handler:IsDisabled(info) or not prefs.messages.warning end,
				order = 20,
			},			
			output = sinkOpts,
		},
	}
end
