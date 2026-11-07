-- Visitor timer, simulation loop, payouts and FX events. One 10 Hz stepper for all
-- plots. Payouts happen in the same step that sets sim.Result, guarded by
-- run.Paid and by removing the run first, so an encounter pays exactly once.
-- A player who leaves mid-encounter cancels it: no payout, no theft. A defeat's
-- coins, drops and XP are applied in that same non-yielding step (Rules/Rewards).
-- The visitor (from the active threat tier's roster), its variant and its base
-- coin reward are rolled on the server; the client only sees the results.

local RunService = game:GetService("RunService")

local Economy = require(script.Parent.Parent.Rules.Economy)
local Progression = require(script.Parent.Parent.Rules.Progression)
local Threat = require(script.Parent.Parent.Rules.Threat)
local Visitors = require(script.Parent.Parent.Definitions.Visitors)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Balance = require(script.Parent.Parent.Definitions.Balance)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local EncounterSim = require(script.Parent.Parent.Rules.EncounterSim)
local LayoutRules = require(script.Parent.Parent.Rules.LayoutRules)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local EventService = require(script.Parent.EventService)
local LootService = require(script.Parent.LootService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local TutorialService = require(script.Parent.TutorialService)

local EncounterService = {}

local STEP = 0.1
local FIRST_VISITOR = { Tutorial = 3, Normal = 10 }
local VISITOR_ATTRS = {
	"VisitorId",
	"VisitorHealth",
	"VisitorMaxHealth",
	"VisitorProgress",
	"VisitorFighting",
	"VisitorSlowed",
	"VisitorSpored",
	"VisitorBurning",
	"VisitorChilled",
	"VisitorVariant",
	"VisitorRewardMin",
	"VisitorRewardMax",
	"VisitorTheft",
}

local runs = {} -- Player -> { Id, Sim, Keys, VisitorId, Variant, Base, Threat, HasTreasure, Paid }
local planned = {} -- Player -> visitor id announced as NextVisitorId
local idle = {} -- Timers for encounters that ended without a defeat.
local nextRunId = 0
local accumulator = 0
local rng = LootService.Rng

local function notice(player: Player, text: string, kind: string)
	Net.Fire("Notice", player, { Text = text, Kind = kind })
end

local function clearVisitor(plot: Instance)
	for _, name in VISITOR_ATTRS do
		plot:SetAttribute(name, nil)
	end
end

local function unlockAll(player: Player): boolean
	return ProfileService.GetTransient(player, "ThreatUnlockAll") == true
end

-- Rewards.Context for the player now (active event, admin override).
local function context(player: Player, profile)
	return Rewards.Context(profile, EventService.ActiveId(), unlockAll(player))
end

-- Moves a plot's next visitor earlier (never later). Used by the tutorial, so it
-- also drops the interval rule until the next encounter ends.
function EncounterService.Expedite(player: Player, seconds: number)
	local plot = PlotService.GetPlot(player)
	if plot then
		idle[player] = nil
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

local function inRoster(visitorId: string?, tier: number): boolean
	for _, e in Threat.Roster(tier) do
		if e.Id == visitorId then
			return true
		end
	end
	return false
end

-- Who arrives next: the tutorial's practice visitor, else the planned visitor if it
-- still fits the active tier's roster, else a fresh roll from that roster.
local function planVisitor(player: Player, profile, reroll: boolean?): string
	if tutorialStep(profile) == "PracticeEncounter" then
		return "Practice"
	end
	local tier = Progression.ActiveThreat(profile, unlockAll(player))
	local current = planned[player]
	if not reroll and inRoster(current, tier) then
		return current :: string
	end
	return Threat.PickVisitor(tier, rng)
end

-- Sets NextVisitorId (and the plot's Threat) before the visitor enters.
local function announce(player: Player, plot: Instance, profile, reroll: boolean?)
	local visitorId = planVisitor(player, profile, reroll)
	planned[player] = visitorId
	plot:SetAttribute("NextVisitorId", visitorId)
	plot:SetAttribute("Threat", Progression.ActiveThreat(profile, unlockAll(player)))
end

local function cancel(player: Player)
	local run = runs[player]
	runs[player] = nil
	if run then
		local plot = PlotService.GetPlot(player)
		if plot then
			clearVisitor(plot)
			plot:SetAttribute("State", "Idle")
			plot:SetAttribute("NextVisitorId", nil)
		end
		planned[player] = nil
	end
end

local function displayName(visitorId: string, variant: string?): string
	local def = Visitors.Get(visitorId)
	local name = def and def.DisplayName or visitorId
	return if variant then `{variant} {name}` else name
end

-- The reward context for a run: the tier it spawned at (fixed for the encounter).
local function runContext(player: Player, profile, run)
	local ctx = context(player, profile)
	ctx.Threat = run.Threat
	ctx.Scale = Threat.Scale(run.Threat)
	return ctx
end

local function finish(player: Player, plot: Instance, profile, run, now: number)
	run.Paid = true
	runs[player] = nil -- first, so nothing below can ever pay twice

	local result, visitorId = run.Sim.Result, run.VisitorId
	local amount, destination = 0, "None"
	local reward = { Drops = {}, Xp = 0, LevelUp = nil }
	local stats = profile.Stats
	stats.Encounters += 1
	if result == "Defeated" then
		reward = Rewards.Defeat(profile, visitorId, rng, runContext(player, profile, run), run.Base, run.Variant)
		amount, destination = reward.Amount, "Bank"
		stats.Wins += 1
		stats.Earned += amount
	elseif result == "Robbed" then
		amount = Economy.Theft(visitorId, Progression.Vaulted(profile), run.VaultSnapshot, Progression.TheftScale(profile))
		profile.Coins -= amount
		destination = "Vault"
		stats.Robberies += 1
	else
		stats.Escapes += 1
	end

	local name = displayName(visitorId, run.Variant)
	if result == "Robbed" then
		notice(player, `The {name} reached your treasure and stole {amount} coins!`, "Bad")
	elseif result ~= "Defeated" then
		notice(player, `The {name} got through your dungeon without a fight.`, "Info")
	end
	for _, drop in reward.Drops do
		if drop.Overflow then
			local chest = if drop.Type == "Crystal" then "Crystal Chest" elseif drop.Type == "Rare" then "Royal Chest" else "Dungeon Chest"
			notice(player, `Storage full: {chest} converted to {Balance.Loot.BoxOverflowCoins[drop.Type]} coins.`, "Info")
		end
	end
	if reward.LevelUp then
		notice(player, `Keeper level {reward.LevelUp}! You earned a chest.`, "Good")
	end

	Net.FireAll("EncounterFx", {
		Plot = plot:GetAttribute("Index"),
		Kind = "End",
		Result = result,
		VisitorId = visitorId,
		Variant = run.Variant or "",
		Threat = run.Threat,
		Amount = amount,
		Destination = destination,
		Drops = reward.Drops,
		Xp = reward.Xp,
		LevelUp = reward.LevelUp,
	})
	clearVisitor(plot)
	plot:SetAttribute("State", "Idle")
	local at = if result == "Defeated" then now else now + Progression.VisitorInterval(profile, EventService.Effects())
	idle[player] = if result == "Defeated" then nil else { Since = now, Set = at }
	plot:SetAttribute("NextVisitorAt", at)
	PlotService.RefreshRoomAttrs(player)
	ProfileService.Changed(player)
	TutorialService.Notify(player, "EncounterEnd")
	announce(player, plot, profile, true) -- after the tutorial step advanced, so it never announces a stale Practice
end

-- What the encounter panel shows: the coin range if the visitor is defeated now
-- (bonuses and event applied; the base roll stays hidden until End) and what it
-- would steal on reaching the treasure. Display only; finish() pays.
local function setOutcomePreview(player: Player, plot: Instance, profile, run)
	local range = Rewards.CoinRange(run.VisitorId, runContext(player, profile, run), run.Variant)
	plot:SetAttribute("VisitorRewardMin", range and range.Min or 0)
	plot:SetAttribute("VisitorRewardMax", range and range.Max or 0)
	plot:SetAttribute(
		"VisitorTheft",
		if run.HasTreasure
			then Economy.Theft(run.VisitorId, Progression.Vaulted(profile), run.VaultSnapshot, Progression.TheftScale(profile))
			else 0
	)
end

local function stepRun(player: Player, plot: Instance, profile, run, dt: number, now: number)
	local sim = run.Sim
	setOutcomePreview(player, plot, profile, run) -- unchanged values do not replicate
	local events = sim:Step(dt)
	plot:SetAttribute("VisitorHealth", sim.Health)
	plot:SetAttribute("VisitorMaxHealth", sim.MaxHealth)
	plot:SetAttribute("VisitorProgress", sim.Progress)
	plot:SetAttribute("VisitorFighting", sim.Fighting)
	plot:SetAttribute("VisitorSlowed", sim.Slowed)
	plot:SetAttribute("VisitorSpored", sim.Spored)
	plot:SetAttribute("VisitorBurning", sim.Burning)
	plot:SetAttribute("VisitorChilled", sim.Chilled)
	local rooms = plot:FindFirstChild("Rooms")
	for index, defender in sim.Defenders do
		local model = rooms and rooms:FindFirstChild(run.Keys[index])
		if model then
			model:SetAttribute("DefenderHealth", defender.Health)
			model:SetAttribute("DefenderMaxHealth", defender.MaxHealth)
			model:SetAttribute("DefenderUnit", defender.Unit) -- 1-based; Goblin Barracks / Lich Sanctum step through units
		end
	end
	local plotIndex = plot:GetAttribute("Index")
	for _, event in events do
		if event.Kind ~= "End" then -- End is sent by finish() with the payout
			event.Plot = plotIndex
			if event.Kind == "Spawn" then
				event.VisitorId = run.VisitorId
				event.Variant = run.Variant or ""
				event.Threat = run.Threat
			end
			Net.FireAll("EncounterFx", event)
		end
	end
	if sim.Result ~= nil and not run.Paid then
		finish(player, plot, profile, run, now)
	end
end

local function retime(player: Player, plot: Instance, profile)
	local info = idle[player]
	if info == nil then return end
	local at = info.Since + Progression.VisitorInterval(profile, EventService.Effects())
	local current = plot:GetAttribute("NextVisitorAt")
	if current == info.Set or (current ~= nil and at > current) then
		info.Set = at
		plot:SetAttribute("NextVisitorAt", at)
	end
end

local function trySpawn(player: Player, plot: Instance, profile, now: number)
	if plot:GetAttribute("State") == "Encounter" then
		return
	end
	retime(player, plot, profile)
	if plot:GetAttribute("State") ~= "Idle" then
		return
	end
	if tutorialStep(profile) == "PracticeEncounter" and plot:GetAttribute("NextVisitorId") ~= "Practice" then
		announce(player, plot, profile) -- the tutorial moved on after the first announcement
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

	local route, levels, modifiers, hasTreasure = {}, {}, {}, false
	for i, key in routeCells do
		local instance = profile.Rooms[profile.Layout[key]]
		route[i] = cells[key]
		levels[i] = instance.Level
		modifiers[i] = instance.Modifier
		hasTreasure = hasTreasure or Rooms.IsTreasure(cells[key])
	end
	local visitorId = planVisitor(player, profile)
	local ctx = context(player, profile)
	local variant = Threat.RollVariant(visitorId, ctx.VariantMult, rng)
	local base = Economy.RollReward(visitorId, rng)
	local v = Threat.Variant(variant)
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
			modifiers = modifiers,
			healthBonus = Progression.DefenderHealthBonus(profile),
			visitorId = visitorId,
			visitorHealth = ctx.Scale.Health * (v and v.Health or 1),
			visitorDamage = ctx.Scale.Damage,
		}),
		Keys = routeCells,
		VisitorId = visitorId,
		Variant = variant,
		Base = base,
		Threat = ctx.Threat,
		HasTreasure = hasTreasure,
		VaultSnapshot = Progression.Vaulted(profile), -- theft never exceeds what was vaulted at spawn
		Paid = false,
	}
	runs[player] = run
	idle[player] = nil
	planned[player] = nil
	plot:SetAttribute("State", "Encounter")
	plot:SetAttribute("Threat", run.Threat)
	plot:SetAttribute("VisitorVariant", variant or "")
	setOutcomePreview(player, plot, profile, run) -- before VisitorId, so the panel never shows a stale value
	plot:SetAttribute("VisitorId", visitorId)
	if variant then
		notice(player, `A {displayName(visitorId, variant)} is coming!`, "Good")
	end
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

-- Re-rolls the announced visitor after the active tier changed (not mid-encounter).
function EncounterService.Reannounce(player: Player, reroll: boolean?)
	local plot = PlotService.GetPlot(player)
	local profile = ProfileService.Get(player)
	if plot and profile and runs[player] == nil then
		announce(player, plot, profile, reroll ~= false)
	end
end

-- SetThreat selects the tier for the next visitor; a running encounter keeps its own tier.
function EncounterService.SetThreat(player: Player, tier: number)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	if not Threat.Valid(tier) then return false, "BadArgs" end
	if tier > Progression.ThreatUnlocked(profile, unlockAll(player)) then
		return false, "ThreatLocked"
	end
	if profile.Threat ~= tier then
		profile.Threat = tier
		ProfileService.Changed(player)
		EncounterService.Reannounce(player)
	end
	return true, tier
end

-- Whether a visitor is inside the player's dungeon (server truth).
function EncounterService.InEncounter(player: Player): boolean
	return runs[player] ~= nil
end

-- Build mode discards an active visit before layout editing; cancel() removes
-- the run before any result can be resolved, so it cannot pay or steal.
function EncounterService.CancelForBuild(player: Player)
	if runs[player] then
		cancel(player)
		PlotService.RefreshRoomAttrs(player)
	end
end

function EncounterService.Init()
	Net.Handle("SetThreat", function(...)
		local tier = ...
		return select("#", ...) == 1 and Threat.Valid(tier)
	end, EncounterService.SetThreat)
end

function EncounterService.Start()
	ProfileService.Left:Connect(function(player)
		cancel(player)
		planned[player] = nil
		idle[player] = nil
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
