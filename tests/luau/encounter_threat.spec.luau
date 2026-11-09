-- Integration spec for the service-owned threat snapshot across a live run.
local Heartbeat = {}
function Heartbeat:Connect(callback)
	self.Callback = callback
	return { Disconnect = function() end }
end

local originalGetService = game.GetService
game.GetService = function(self, name)
	if name == "RunService" then
		return { Heartbeat = Heartbeat }
	end
	return originalGetService(self, name)
end

local now = 0
workspace = { GetServerTimeNow = function() return now end }
warn = print

local player = {}
local attrs = { State = "Idle", NextVisitorAt = 0, Index = 1 }
local plot = {}
function plot:GetAttribute(name)
	return attrs[name]
end
function plot:SetAttribute(name, value)
	attrs[name] = value
end
function plot:FindFirstChild()
	return nil
end

local profile = {
	Threat = 1,
	Level = 8,
	Tutorial = { Done = true, Step = "Done" },
	Layout = { Cell = "Room" },
	Rooms = { Room = { Id = "SlimeNest", Level = 1 } },
	Discovered = {},
	Coins = 0,
	Stats = { Encounters = 0, Wins = 0, Earned = 0, Robberies = 0, Escapes = 0 },
}
local remoteCheck, remoteHandler
local simResult = "Defeated"
local encounterFx = {}

local function mock(path, value)
	__defineModule(path, function() return value end)
end

mock({ "ServerScriptService", "Server", "Rules", "Economy" }, {
	RollReward = function() return 100 end,
	Theft = function() return 0 end,
})
mock({ "ServerScriptService", "Server", "Rules", "Progression" }, {
	ActiveThreat = function(p) return p.Threat end,
	ThreatUnlocked = function() return 2 end,
	DefenderHealthBonus = function() return 0 end,
	Vaulted = function() return 0 end,
	TheftScale = function() return 1 end,
})
mock({ "ServerScriptService", "Server", "Rules", "ProfileSchema" }, { MAX_MONEY = 1e9 })
mock({ "ServerScriptService", "Server", "Rules", "LayoutRules" }, {
	Validate = function() return true, { "Cell" }, { Cell = "SlimeNest" } end,
})
mock({ "ServerScriptService", "Server", "Rules", "EncounterSim" }, {
	new = function(args)
		local sim = {
			VisitorId = args.visitorId,
			Health = 20,
			MaxHealth = 20,
			Progress = 0,
			Fighting = 0,
			Slowed = false,
			Spored = false,
			Burning = false,
			Chilled = false,
			Defenders = {},
			Result = nil,
			Steps = 0,
		}
		function sim:Step()
			self.Steps += 1
			if self.Steps == 1 then
				return { { Kind = "Spawn" } }
			end
			self.Result = simResult
			return {}
		end
		return sim
	end,
})
mock({ "ServerScriptService", "Server", "Rules", "Rewards" }, {
	Context = function(p)
		local Threat = require(game:GetService("ServerScriptService").Server.Rules.Threat)
		return { Threat = p.Threat, Scale = Threat.Scale(p.Threat), VariantMult = 1 }
	end,
	CoinRange = function(_, ctx)
		return { Min = 10 * ctx.Scale.Coins, Max = 20 * ctx.Scale.Coins }
	end,
	Defeat = function(_, _, _, ctx)
		return { Amount = 100 * ctx.Scale.Coins, Drops = {}, Xp = 0, LevelUp = nil }
	end,
})
mock({ "ServerScriptService", "Server", "Definitions", "Rooms" }, {
	IsTreasure = function() return false end,
})
mock({ "ServerScriptService", "Server", "Infrastructure", "Net" }, {
	Fire = function() end,
	FireAll = function(_, payload)
		table.insert(encounterFx, payload)
	end,
	Handle = function(_, check, handler)
		remoteCheck, remoteHandler = check, handler
	end,
})
mock({ "ServerScriptService", "Server", "Services", "EventService" }, {
	ActiveId = function() return nil end,
	Effects = function() return {} end,
})
mock({ "ServerScriptService", "Server", "Services", "LootService" }, {
	Rng = { NextNumber = function() return 0.99 end },
})
mock({ "ServerScriptService", "Server", "Services", "PlotService" }, {
	GetPlot = function() return plot end,
	Owned = function() return { [player] = plot } end,
	RefreshRoomAttrs = function() end,
})
mock({ "ServerScriptService", "Server", "Services", "ProfileService" }, {
	Get = function() return profile end,
	GetTransient = function() return nil end,
	Changed = function() end,
	Left = { Connect = function() end },
})
mock({ "ServerScriptService", "Server", "Services", "TutorialService" }, {
	WantsVisitor = { Connect = function() end },
	Notify = function() end,
})

local Server = game:GetService("ServerScriptService").Server
local Threat = require(Server.Rules.Threat)
local EncounterService = require(Server.Services.EncounterService)
EncounterService.Init()
EncounterService.Start()

test("the current run keeps its tier snapshot and the next run uses the selected tier", function()
	local spawned = {}
	-- Read the visitor announced on the plot after each real service spawn.
	local function tick(at)
		now = at
		Heartbeat.Callback(0.1)
	end

	tick(0) -- Tier 1 spawn.
	expectEq(attrs.VisitorId, "Novice", "tier 1 roster visitor")
	expectEq(attrs.Threat, 1, "spawned tier 1")
	spawned[1] = attrs.VisitorId

	local accepted, selected = EncounterService.SetThreat(player, 2)
	expect(accepted, "tier changes during an active run")
	expectEq(selected, 2, "new selection returned")
	expectEq(attrs.Threat, 1, "running visitor keeps the original tier attribute")
	expectEq(attrs.VisitorId, "Novice", "running visitor remains unchanged")
	tick(1) -- Run 1 resolves; payout must still use tier 1.
	expectEq(profile.Stats.Encounters, 1, "first run finished")
	expectEq(attrs.Threat, 2, "announcement reflects latest selection")

	tick(2) -- Tier 2 visitor now spawns.
	expectEq(attrs.VisitorId, "Scout", "tier 2 roster visitor")
	expectEq(attrs.Threat, 2, "spawned tier 2")
	spawned[2] = attrs.VisitorId

	local lowered, selectedAgain = EncounterService.SetThreat(player, 1)
	expect(lowered, "tier changes from high to low during the second active run")
	expectEq(selectedAgain, 1, "reverse selection returned")
	expectEq(attrs.Threat, 2, "second running visitor keeps the high tier")
	expectEq(attrs.VisitorId, "Scout", "second running visitor remains unchanged")
	tick(3) -- Run 2 resolves with tier 2, despite the changed selection.
	expectEq(profile.Stats.Encounters, 2, "second run finished")
	expectEq(attrs.Threat, 1, "reverse announcement reflects latest selection")

	tick(4)
	expectEq(attrs.VisitorId, "Novice", "tier 1 roster restored")
	expectEq(attrs.Threat, 1, "third spawn uses latest selected tier")
	expectEq(spawned[1], "Novice", "low-to-high transition begins at low tier")
	expectEq(spawned[2], "Scout", "high-tier spawn follows selection")
	local lowScale = Threat.Scale(1)
	local highScale = Threat.Scale(2)
	expectEq(lowScale.Coins, 1, "tier 1 multiplier fixture")
	expectEq(highScale.Coins, 1.5, "tier 2 multiplier fixture")
	-- Rewards.Defeat above derives its amount from the service's runContext scale.
	expectEq(profile.Stats.Earned, 100 + 150, "payouts used each run's original tier scale")
	local run1Fx, run2Fx = nil, nil
	for _, event in encounterFx do
		if event.Kind == "End" then
			if run1Fx == nil then run1Fx = event else run2Fx = event end
		end
	end
	expectEq(run1Fx and run1Fx.Threat, 1, "first end event keeps tier 1")
	expectEq(run2Fx and run2Fx.Threat, 2, "second end event keeps tier 2")
	EncounterService.CancelForBuild(player)
end)

test("an escape or robbery is followed by the next visitor at once (no interval)", function()
	for _, result in { "Escaped", "Robbed" } do
		simResult = result
		now += 10
		attrs.State, attrs.NextVisitorAt = "Idle", now
		local before = profile.Stats.Encounters
		Heartbeat.Callback(0.1) -- spawn
		expectEq(attrs.State, "Encounter", result .. ": visitor spawned")
		now += 1
		Heartbeat.Callback(0.1) -- resolves
		expectEq(profile.Stats.Encounters, before + 1, result .. ": one encounter ended")
		expectEq(attrs.State, "Idle", result .. ": idle between visitors")
		expectEq(attrs.NextVisitorAt, now, result .. ": next visitor is due immediately")
		now += 0.1
		Heartbeat.Callback(0.1)
		expectEq(attrs.State, "Encounter", result .. ": next visitor chained")
		expect(profile.Stats.Encounters == before + 1, result .. ": exactly one visitor per step")
		simResult = "Defeated"
		now += 1
		Heartbeat.Callback(0.1) -- resolve the chained one
	end
	expect(profile.Stats.Escapes >= 1 and profile.Stats.Robberies >= 1, "escape and robbery were counted")
	EncounterService.CancelForBuild(player)
end)

test("locked and malformed threat requests are rejected", function()
	profile.Threat = 1
	local ok, reason = EncounterService.SetThreat(player, 3)
	expect(not ok, "locked tier rejected")
	expectEq(reason, "ThreatLocked", "locked reason")
	expectEq(profile.Threat, 1, "locked request leaves selected tier unchanged")
	local malformed, malformedReason = EncounterService.SetThreat(player, "2")
	expect(not malformed, "malformed direct request rejected")
	expectEq(malformedReason, "BadArgs", "malformed direct request reason")
	expect(remoteCheck(2), "valid integer tier passes remote check")
	for _, bad in { "2", 1.5, 0, 7, {} } do
		expect(not remoteCheck(bad), "malformed or out-of-range tier rejected: " .. tostring(bad))
	end
	expect(type(remoteHandler) == "function", "guard installed service handler")
end)
