-- Pure tutorial state machine (docs/PHASE0.md, "First five minutes"). Events:
-- Next, Skip, DeclineTreasure, EncounterEnd, Banked, Commit, Bought, Load.
-- Reduce() never leaves a player stuck: after every event the step is "settled"
-- against what the profile actually contains (placed spike, placed treasure,
-- owned guard), so unexpected actions just move the tutorial to a sensible step.

local TutorialRules = {}

TutorialRules.Steps = table.freeze({
	"Welcome", "PracticeEncounter", "PlaceSpike", "WatchNovice",
	"TreasureOffer", "BankVault", "BuyGuard", "Done",
})

local rank = {}
for i, step in TutorialRules.Steps do
	rank[step] = i
end

function TutorialRules.Rank(step: any): number?
	return rank[step]
end

-- What the profile holds right now.
function TutorialRules.Context(profile: any)
	local ctx = { SpikePlaced = false, TreasurePlaced = false, OwnsGuard = false }
	for _, instanceId in profile.Layout do
		local room = profile.Rooms[instanceId]
		if room and room.Id == "SpikeHall" then
			ctx.SpikePlaced = true
		elseif room and room.Id == "TreasureRoom" then
			ctx.TreasurePlaced = true
		end
	end
	for _, room in profile.Rooms do
		if room.Id == "GuardRoom" then
			ctx.OwnsGuard = true
		end
	end
	return ctx
end

-- Skip is locked on the very first session: allowed once the player has finished
-- at least one encounter (also covers every later session).
function TutorialRules.CanSkip(profile: any): boolean
	local stats = profile.Stats
	return type(stats) == "table" and type(stats.Encounters) == "number" and stats.Encounters >= 1
end

local function advance(step: string, event: string): string
	if event == "Skip" then
		return "Done"
	elseif step == "Welcome" and event == "Next" then
		return "PracticeEncounter"
	elseif step == "PracticeEncounter" and event == "EncounterEnd" then
		return "PlaceSpike"
	elseif step == "WatchNovice" and event == "EncounterEnd" then
		return "TreasureOffer"
	elseif step == "TreasureOffer" and event == "DeclineTreasure" then
		return "BuyGuard"
	elseif step == "BankVault" and (event == "Banked" or event == "DeclineTreasure") then
		return "BuyGuard"
	end
	return step
end

local function settle(step: string, ctx: any): string
	if step == "Done" then
		return step
	end
	if rank[step] >= rank.PlaceSpike and ctx.OwnsGuard then
		return "Done"
	elseif step == "PlaceSpike" and ctx.SpikePlaced then
		return "WatchNovice"
	elseif step == "WatchNovice" and not ctx.SpikePlaced then
		return "PlaceSpike"
	elseif step == "TreasureOffer" and ctx.TreasurePlaced then
		return "BankVault"
	elseif step == "BankVault" and not ctx.TreasurePlaced then
		return "BuyGuard"
	end
	return step
end

-- Unknown steps restart at Welcome. Returns the new step.
function TutorialRules.Reduce(step: any, event: any, ctx: any): string
	if rank[step] == nil then
		step = "Welcome"
	end
	step = advance(step, event)
	for _ = 1, #TutorialRules.Steps do
		local settled = settle(step, ctx)
		if settled == step then
			break
		end
		step = settled
	end
	return step
end

return TutorialRules
