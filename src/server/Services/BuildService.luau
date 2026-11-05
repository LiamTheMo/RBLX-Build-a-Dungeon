-- Build mode and layout commits. The server re-validates every layout against the
-- player's owned rooms and the route rules; the client only proposes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage.Shared.Definitions.Grid)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local LayoutRules = require(script.Parent.Parent.Rules.LayoutRules)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local TutorialService = require(script.Parent.TutorialService)

local BuildService = {}

local MAX_CELLS = Grid.Columns * Grid.Rows - 1
local RESUME_DELAY = 5
local COMMIT_COOLDOWN = 1 -- seconds; every commit may rebuild the plot's models
local building = {} -- Player -> true
local lastCommit = {} -- Player -> os.clock() of the last accepted commit attempt

local function checkLayout(...)
	if select("#", ...) ~= 1 then
		return false
	end
	local layout = ...
	if type(layout) ~= "table" or getmetatable(layout) ~= nil then
		return false
	end
	local count = 0
	for key, value in layout do
		count += 1
		if count > MAX_CELLS or type(key) ~= "string" or #key > 8 or type(value) ~= "string" or #value > 32 then
			return false
		end
	end
	return true
end

function BuildService.IsBuilding(player: Player): boolean
	return building[player] == true
end

function BuildService.SetBuilding(player: Player, on: boolean)
	local plot = PlotService.GetPlot(player)
	if plot == nil or ProfileService.Get(player) == nil then
		return false, "ProfileNotLoaded"
	end
	if on then
		if plot:GetAttribute("State") == "Encounter" then
			return false, "EncounterActive"
		end
		building[player] = true
		plot:SetAttribute("State", "Building")
	elseif building[player] then
		building[player] = nil
		plot:SetAttribute("State", "Idle")
		local previous = plot:GetAttribute("NextVisitorAt") or 0
		plot:SetAttribute("NextVisitorAt", math.max(previous, workspace:GetServerTimeNow() + RESUME_DELAY))
	end
	ProfileService.SetTransient(player, "Building", on)
	return true, nil
end

function BuildService.CommitLayout(player: Player, layout: { [string]: string })
	local profile = ProfileService.Get(player)
	local plot = PlotService.GetPlot(player)
	if profile == nil or plot == nil then
		return false, "ProfileNotLoaded"
	end
	if not building[player] then
		return false, "NotBuilding"
	end
	if plot:GetAttribute("State") == "Encounter" then
		return false, "EncounterActive"
	end
	local clock = os.clock()
	if lastCommit[player] and clock - lastCommit[player] < COMMIT_COOLDOWN then
		return false, "RateLimited"
	end
	lastCommit[player] = clock
	local ok, routeCells, cells = LayoutRules.Validate(profile, layout)
	if not ok then
		return false, routeCells
	end

	local unchanged = true
	for key, instanceId in layout do
		if profile.Layout[key] ~= instanceId then
			unchanged = false
			break
		end
	end
	if unchanged then
		for key in profile.Layout do
			if layout[key] == nil then
				unchanged = false
				break
			end
		end
	end
	if unchanged then
		return true, routeCells -- nothing to rebuild or replicate
	end

	local newLayout, hasTreasure = {}, false
	for key, instanceId in layout do
		newLayout[key] = instanceId
		if cells[key] == "TreasureRoom" then
			hasTreasure = true
		end
	end
	profile.Layout = newLayout
	if not hasTreasure and profile.Vault > 0 then
		local banked = profile.Vault
		profile.Coins += banked
		profile.Vault = 0
		Net.Fire("Notice", player, { Text = `Your vault was banked: +{banked} coins.`, Kind = "Info" })
	end
	PlotService.Render(player)
	ProfileService.Changed(player)
	TutorialService.Notify(player, "Commit")
	return true, routeCells
end

function BuildService.Init()
	Net.Handle("SetBuilding", function(...)
		return select("#", ...) == 1 and type((...)) == "boolean"
	end, BuildService.SetBuilding)
	Net.Handle("CommitLayout", checkLayout, BuildService.CommitLayout)
end

function BuildService.Start()
	ProfileService.Left:Connect(function(player)
		building[player] = nil
		lastCommit[player] = nil
	end)
end

return BuildService
