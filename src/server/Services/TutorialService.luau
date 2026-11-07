-- Tutorial driver. The state machine is pure (Rules/TutorialRules); this applies
-- its side effects: the one-time Spike Hall grant and visitor timing. Other services call Notify(player, event).
-- The Spike Hall grant happens once ever: never if the player owns or has ever
-- owned a SpikeHall (Discovered.SpikeHall). Ownership alone is not enough since
-- rooms can be scrapped for blueprints (a scrap-and-regrant loop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local RoomInventory = require(script.Parent.Parent.Rules.RoomInventory)
local TutorialRules = require(script.Parent.Parent.Rules.TutorialRules)
local ProfileService = require(script.Parent.ProfileService)

local TutorialService = {}

-- (player, seconds): the tutorial wants the next visitor within `seconds`.
TutorialService.WantsVisitor = Signal.new()

local VISITOR_SOON = { PracticeEncounter = 3, WatchNovice = 5 }
local ACTIONS = { Next = true, Skip = true, DeclineTreasure = true }

local function notice(player: Player, text: string, kind: string)
	Net.Fire("Notice", player, { Text = text, Kind = kind })
end

function TutorialService.Notify(player: Player, event: string)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return
	end
	local tutorial = profile.Tutorial
	local old = if tutorial.Done then "Done" else tutorial.Step
	local step = TutorialRules.Reduce(old, event, TutorialRules.Context(profile))
	local changed = step ~= old

	if changed then
		tutorial.Step = step
		tutorial.Done = step == "Done"
		local soon = VISITOR_SOON[step]
		if soon then
			TutorialService.WantsVisitor:Fire(player, soon)
		end
	end
	local hadSpike = RoomInventory.Owns(profile, "SpikeHall") or profile.Discovered.SpikeHall == true
	if TutorialRules.Rank(step) >= TutorialRules.Rank("PlaceSpike") and not hadSpike then
		if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
			notice(player, "Your room storage is full, so the Spike Hall wasn't granted. Scrap a room to make space.", "Bad")
		elseif not RoomInventory.CanAdd(profile, 1) then
			notice(player, "Room storage is unavailable. Please contact support.", "Bad")
		else
			RoomInventory.Add(profile, "SpikeHall")
			notice(player, "You received a Spike Hall. Place it behind your slime!", "Good")
			changed = true
		end
	end
	if changed then
		ProfileService.Changed(player)
	end
end

function TutorialService.Init()
	Net.Handle("TutorialAction", function(...)
		local action = ...
		return select("#", ...) == 1 and type(action) == "string" and #action <= 32 and ACTIONS[action] == true
	end, function(player, action)
		if action == "Skip" then
			local profile = ProfileService.Get(player)
			if profile == nil then
				return false, "ProfileNotLoaded"
			end
			if not TutorialRules.CanSkip(profile) then
				return false, "TutorialSkipLocked"
			end
		end
		TutorialService.Notify(player, action)
		return true, nil
	end)
end

function TutorialService.Start()
	ProfileService.Loaded:Connect(function(player)
		TutorialService.Notify(player, "Load")
		task.delay(1, function()
			if player.Parent == nil then
				return
			end
			TutorialService.Notify(player, "Next") -- only moves Welcome
		end)
	end)
end

return TutorialService
