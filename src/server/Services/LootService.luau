-- OpenBox, CraftBlueprint, ScrapRoom remotes and the server RNG for loot rolls.
-- The rules (and every refusal) are in Rules/Rewards; each request mutates the
-- profile without yielding. Boxes and blueprints are gameplay-earned only.

local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local EventService = require(script.Parent.EventService)
local ProfileService = require(script.Parent.ProfileService)

local LootService = {}

-- One server RNG for every loot roll (EncounterService uses it for drops).
LootService.Rng = Random.new()

local BOX_TYPES = { Dungeon = true, Rare = true }

local function oneString(...)
	local value = ...
	return select("#", ...) == 1 and type(value) == "string" and #value >= 1 and #value <= 32
end

-- Runs a Rewards mutation for a loaded profile and pushes State on success.
local function apply(player: Player, fn, ...)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local ok, result = fn(profile, ...)
	if ok then
		ProfileService.Changed(player)
	end
	return ok, result
end

local function name(roomId: string): string
	local def = Rooms.Get(roomId)
	return def and def.DisplayName or roomId
end

function LootService.Init()
	Net.Handle("OpenBox", function(...)
		return oneString(...) and BOX_TYPES[(...)] == true
	end, function(player, boxType)
		local ok, result = apply(player, Rewards.OpenBox, boxType, LootService.Rng, EventService.ActiveId())
		if ok then
			local mod = if result.Modifier then `{result.Modifier} ` else ""
			Net.Fire("Notice", player, { Text = `You found a {mod}{result.Rarity} {name(result.RoomId)}!`, Kind = "Good" })
		end
		return ok, result
	end)
	Net.Handle("CraftBlueprint", oneString, function(player, roomId)
		local ok, result = apply(player, Rewards.Craft, roomId)
		if ok then
			Net.Fire("Notice", player, { Text = `Crafted a {name(roomId)}.`, Kind = "Good" })
		end
		return ok, result
	end)
	Net.Handle("ScrapRoom", oneString, function(player, instanceId)
		return apply(player, Rewards.Scrap, instanceId)
	end)
end

return LootService
