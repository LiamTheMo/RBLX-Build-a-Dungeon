-- Visitor timer, simulation loop, payouts and FX events. One 10 Hz stepper for all
-- plots. Payouts happen in the same step that sets sim.Result, guarded by
-- run.Paid and by removing the run first, so an encounter pays exactly once.
-- A player who leaves mid-encounter cancels it: no payout, no theft. A defeat's
-- drops and XP are rolled in that same non-yielding step (Rules/Rewards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage.Shared.Definitions.Balance)
local Economy = require(ReplicatedStorage.Shared.Rules.Economy)
local Progression = require(ReplicatedStorage.Shared.Rules.Progression)
local VisitorRotation = require(ReplicatedStorage.Shared.Rules.VisitorRotation)
local Rooms = require(ReplicatedStorage.Shared.Definitions.Rooms)
local Visitors = require(ReplicatedStorage.Shared.Definitions.Visitors)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local EncounterSim = require(script.Parent.Parent.Rules.EncounterSim)
local LayoutRules = require(script.Parent.Parent.Rules.LayoutRules)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local LootService = require(script.Parent.LootService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local TutorialService = require(script.Parent.TutorialService)

local EncounterService = {}

local STEP = 0.1
local FIRST_VISITOR = { Tutorial = 3, Normal = 10 }
local VISITOR_ATTRS =
	{ "VisitorId", "VisitorHealth", "VisitorMaxHealth", "VisitorProgress", "VisitorFighting", "VisitorSlowed", "VisitorSpored" }

local runs = {} -- Player -> { Id, Sim, Keys, VisitorId, HasTreasure, Paid }
local challengerReadyAt = {} -- Player -> server time the next challenger invite is allowed
local queued = {} -- Player -> true (Armored Challenger invited)
local nextRunId = 0
local accumulator = 0

local function notice(player: Player, text: string, kind: string)
	Net.Fire("Notice", player, { Text = text, Kind = kind })
end

local function clearVisitor(plot: Instance)
	for _, name in VISITOR_ATTRS do
		plot:SetAttribute(name, nil)
	end
end

-- Moves a plot's next visitor earlier (never later).
function EncounterService.Expedite(player: Player, seconds: number)
	local plot = PlotService.GetPlot(player)
	if plot then
		local at = workspace:GetServerTimeNow() + seconds
		local current = plot:GetAttribute("NextVisitorAt")
		if current == nil or current > at then
			plot:SetAttribute("NextVisitorAt", at)
		end
	end
end

local function tutorialStep(profile): string
	return if profile.Tutorial.Done then "Done" else profile.Tutorial.Step
end

-- Who arrives next, by the rules: tutorial practice, an invited challenger, else
-- the rotation. The plot attribute NextVisitorId announces it before it enters.
local function planVisitor(player: Player, profile): string
	if tutorialStep(profile) == "PracticeEncounter" then
		return "Practice"
	elseif queued[player] then
		return "ArmoredChallenger"
	end
	return VisitorRotation.Pick(profile.Tutorial.Done, profile.Stats.Wins, profile.Stats.Encounters)
end

local function announce(player: Player, plot: Instance, profile)
	plot:SetAttribute("NextVisitorId", planVisitor(player, profile))
end

local function cancel(player: Player)
	local run = runs[player]
	runs[player] = nil
	if run then
		if run.VisitorId == "ArmoredChallenger" then
			challengerReadyAt[player] = workspace:GetServerTimeNow() + Balance.Loot.ChallengerCooldown
		end
		local plot = PlotService.GetPlot(player)
		if plot then
			clearVisitor(plot)
			plot:SetAttribute("State", "Idle")
			plot:SetAttribute("NextVisitorId", nil)
		end
	end
end

local function finish(player: Player, plot: Instance, profile, run, now: number)
	run.Paid = true
	runs[player] = nil -- first, so nothing below can ever pay twice
	if run.VisitorId == "ArmoredChallenger" then
		challengerReadyAt[player] = now + Balance.Loot.ChallengerCooldown
	end

	local result, visitorId = run.Sim.Result, run.VisitorId
	local amount, destination = 0, "None"
	local reward = { Drops = {}, Xp = 0, LevelUp = nil }
	local stats = profile.Stats
	stats.Encounters += 1
	if result == "Defeated" then
		local bonuses = Progression.Bonuses(profile)
		amount, destination =
			Economy.WinPayout(visitorId, profile.Vault, run.HasTreasure, bonuses.Coins, Progression.VaultCapBonus(profile))
		if destination == "Bank" then
			profile.Coins += amount
		else
			profile.Vault += amount
		end
		stats.Wins += 1
		stats.Earned += amount
		reward = Rewards.Defeat(profile, visitorId, LootService.Rng, bonuses)
	elseif result == "Robbed" then
		amount = Economy.Theft(visitorId, profile.Vault)
		profile.Vault -= amount
		destination = "Vault"
		stats.Robberies += 1
	else
		stats.Escapes += 1
	end

	local names = {
		ArmoredChallenger = "The Armored Challenger",
		Practice = "The practice adventurer",
		Scout = "A scout",
		Cleric = "A cleric",
	}
	local name = names[visitorId] or "A novice"
	if result == "Defeated" then
		local where = if destination == "Vault" then " to your vault" else ""
		notice(player, `{name} was defeated! +{amount} coins{where}.`, "Good")
	elseif result == "Robbed" then
		notice(player, `{name} reached your treasure and stole {amount} coins!`, "Bad")
	else
		notice(player, `{name} got through your dungeon without a fight.`, "Info")
	end
	for _, drop in reward.Drops do
		if drop.Source == "Visitor" then
			local def = drop.RoomId and Rooms.Get(drop.RoomId)
			local what = if drop.Kind == "Box" then `a {drop.Type} Box` else `a {def and def.DisplayName} blueprint`
			notice(player, `{name} dropped {what}!`, "Good")
		end
	end
	for _, drop in reward.Drops do
		if drop.Overflow then
			notice(player, `Box storage full: your {drop.Type} Box became {Balance.Loot.BoxOverflowCoins[drop.Type]} coins.`, "Info")
		end
	end
	if reward.LevelUp then
		notice(player, `Keeper level {reward.LevelUp}! You earned a box.`, "Good")
	end

	Net.FireAll("EncounterFx", {
		Plot = plot:GetAttribute("Index"),
		Kind = "End",
		Result = result,
		Amount = amount,
		Destination = destination,
		Drops = reward.Drops,
		Xp = reward.Xp,
		LevelUp = reward.LevelUp,
	})
	clearVisitor(plot)
	plot:SetAttribute("State", "Idle")
	plot:SetAttribute("NextVisitorAt", now + Economy.VisitorInterval(run.HasTreasure, Progression.IntervalReduction(profile)))
	PlotService.RefreshRoomAttrs(player)
	ProfileService.Changed(player)
	TutorialService.Notify(player, "EncounterEnd")
	announce(player, plot, profile) -- after the tutorial step advanced, so it never announces a stale Practice
end

local function stepRun(player: Player, plot: Instance, profile, run, dt: number, now: number)
	local sim = run.Sim
	local events = sim:Step(dt)
	plot:SetAttribute("VisitorHealth", sim.Health)
	plot:SetAttribute("VisitorMaxHealth", sim.MaxHealth)
	plot:SetAttribute("VisitorProgress", sim.Progress)
	plot:SetAttribute("VisitorFighting", sim.Fighting)
	plot:SetAttribute("VisitorSlowed", sim.Slowed)
	plot:SetAttribute("VisitorSpored", sim.Spored)
	local rooms = plot:FindFirstChild("Rooms")
	for index, defender in sim.Defenders do
		local model = rooms and rooms:FindFirstChild(run.Keys[index])
		if model then
			model:SetAttribute("DefenderHealth", defender.Health)
			model:SetAttribute("DefenderMaxHealth", defender.MaxHealth)
		end
	end
	local plotIndex = plot:GetAttribute("Index")
	for _, event in events do
		if event.Kind ~= "End" then -- End is sent by finish() with the payout
			event.Plot = plotIndex
			if event.Kind == "Spawn" then
				event.VisitorId = run.VisitorId
			end
			Net.FireAll("EncounterFx", event)
		end
	end
	if sim.Result ~= nil and not run.Paid then
		finish(player, plot, profile, run, now)
	end
end

local function trySpawn(player: Player, plot: Instance, profile, now: number)
	if plot:GetAttribute("State") ~= "Idle" then
		return
	end
	local nextAt = plot:GetAttribute("NextVisitorAt")
	if nextAt == nil then
		local step = tutorialStep(profile)
		plot:SetAttribute("NextVisitorAt", now + (if step == "PracticeEncounter" then FIRST_VISITOR.Tutorial else FIRST_VISITOR.Normal))
		announce(player, plot, profile)
		return
	end
	if now < nextAt then
		return
	end
	local ok, routeCells, cells = LayoutRules.Validate(profile, profile.Layout)
	if not ok or #routeCells == 0 then
		return
	end

	local route, levels, rarities, hasTreasure = {}, {}, {}, false
	for i, key in routeCells do
		local instance = profile.Rooms[profile.Layout[key]]
		route[i] = cells[key]
		levels[i] = instance.Level
		rarities[i] = instance.Rarity
		hasTreasure = hasTreasure or cells[key] == "TreasureRoom"
	end
	-- What was announced stands unless the tutorial or an invite overrides it.
	local visitorId = planVisitor(player, profile)
	local announced = plot:GetAttribute("NextVisitorId")
	local def = Visitors.Get(visitorId)
	local announcedDef = if type(announced) == "string" then Visitors.Get(announced) else nil
	if def and def.Arrival == "Automatic" and announcedDef and announcedDef.Arrival == "Automatic" then
		visitorId = announced
	end
	if visitorId == "ArmoredChallenger" then
		challengerReadyAt[player] = math.huge -- cooldown starts when the encounter ends
		queued[player] = nil
		ProfileService.SetTransient(player, "ChallengerQueued", false)
	end
	if not profile.Discovered[visitorId] then
		profile.Discovered[visitorId] = true
		ProfileService.Changed(player)
	end

	nextRunId += 1
	local run = {
		Id = nextRunId,
		Sim = EncounterSim.new({
			route = route,
			levels = levels,
			rarities = rarities,
			healthBonus = Progression.DefenderHealthBonus(profile),
			visitorId = visitorId,
		}),
		Keys = routeCells,
		VisitorId = visitorId,
		HasTreasure = hasTreasure,
		Paid = false,
	}
	runs[player] = run
	plot:SetAttribute("State", "Encounter")
	plot:SetAttribute("VisitorId", visitorId)
	stepRun(player, plot, profile, run, STEP, now)
end

local function tick(dt: number)
	local now = workspace:GetServerTimeNow()
	for player, plot in PlotService.Owned() do
		local profile = ProfileService.Get(player)
		if profile == nil then
			cancel(player)
		else
			local ok, err = pcall(function()
				local run = runs[player]
				if run then
					stepRun(player, plot, profile, run, dt, now)
				else
					trySpawn(player, plot, profile, now)
				end
			end)
			if not ok then
				warn("[EncounterService] tick failed: " .. tostring(err))
				cancel(player)
			end
		end
	end
end

function EncounterService.Init()
	Net.Handle("InviteChallenger", function(...)
		return select("#", ...) == 0
	end, function(player)
		local profile = ProfileService.Get(player)
		if profile == nil then
			return false, "ProfileNotLoaded"
		end
		if not profile.ChallengerUnlocked then
			return false, "ChallengerLocked"
		end
		if queued[player] then
			return false, "ChallengerQueued"
		end
		if workspace:GetServerTimeNow() < (challengerReadyAt[player] or 0) then
			return false, "ChallengerCooldown"
		end
		queued[player] = true
		local plot = PlotService.GetPlot(player)
		if plot and plot:GetAttribute("State") ~= "Encounter" then
			announce(player, plot, profile)
		end
		ProfileService.SetTransient(player, "ChallengerQueued", true)
		notice(player, "The Armored Challenger will arrive with your next visitor.", "Info")
		return true, nil
	end)
end

function EncounterService.Start()
	ProfileService.Left:Connect(function(player)
		cancel(player)
		queued[player] = nil
		challengerReadyAt[player] = nil
	end)
	TutorialService.WantsVisitor:Connect(EncounterService.Expedite)
	RunService.Heartbeat:Connect(function(dt)
		accumulator = math.min(accumulator + dt, 0.5)
		if accumulator >= STEP then
			local step = accumulator
			accumulator = 0
			tick(step)
		end
	end)
end

return EncounterService
