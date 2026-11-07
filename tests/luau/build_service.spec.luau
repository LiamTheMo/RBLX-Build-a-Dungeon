local Server = game:GetService("ServerScriptService").Server
local services = { "ServerScriptService", "Server", "Services" }
local function mock(name, value)
	local path = table.clone(services)
	table.insert(path, name)
	__defineModule(path, function() return value end)
end

local attrs = { State = "Encounter", NextVisitorAt = 90 }
local plot = {}
function plot:GetAttribute(name) return attrs[name] end
function plot:SetAttribute(name, value) attrs[name] = value end
local player = {}
local loaded, running, cancelled, announced, flag = true, true, 0, 0, nil
local profile = {}
mock("PlotService", { GetPlot = function() return plot end })
mock("ProfileService", { Get = function() return if loaded then profile else nil end, SetTransient = function(_, _, value) flag = value end })
mock("EncounterService", {
	InEncounter = function() return running end,
	CancelForBuild = function() running = false; cancelled += 1 end,
	Reannounce = function(_, reroll) expectEq(reroll, false, "preserve announced visitor"); announced += 1 end,
})
mock("TutorialService", {})
__defineModule({ "ServerScriptService", "Server", "Infrastructure", "Net" }, function() return {} end)
workspace = { GetServerTimeNow = function() return 100 end }
local BuildService = require(Server.Services.BuildService)

test("build mode interrupts once, pauses, then resumes with a delay", function()
	expect(BuildService.SetBuilding(player, true), "enter build mode")
	expectEq(cancelled, 1, "one active encounter cancelled")
	expectEq(attrs.State, "Building", "spawning remains paused")
	expectEq(flag, true, "building state replicated")
	expect(BuildService.SetBuilding(player, true), "repeat entry")
	expectEq(cancelled, 1, "repeat does not cancel again")
	expect(BuildService.SetBuilding(player, false), "exit build mode")
	expectEq(attrs.State, "Idle", "spawning resumes")
	expectEq(attrs.NextVisitorAt, 105, "resume delay")
	expectEq(announced, 1, "visitor announced once")
	expectEq(flag, false, "building state cleared")
	BuildService.SetBuilding(player, false)
	expectEq(announced, 1, "replayed exit does not announce again")
end)

test("missing profile cannot interrupt an encounter", function()
	loaded, running = false, true
	local ok, reason = BuildService.SetBuilding(player, true)
	expect(not ok, "request rejected")
	expectEq(reason, "ProfileNotLoaded", "missing profile reason")
	expect(running, "encounter left alone")
	loaded = true
end)
