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

local BOX_TYPES = { Dungeon = true, Rare = true, Crystal = true }

local function oneString(...)
	local value = ...
	return select("#", ...) == 1 and type(value) == "string" and #value >= 1 and #value <= 32
end

local function boxBatch(...)
	local boxType, count = ...
	return select("#", ...) == 2 and type(boxType) == "string" and BOX_TYPES[boxType] == true
		and type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 30
end

local function roomBatch(...)
	local ids = ...
	if select("#", ...) ~= 1 or type(ids) ~= "table" then return false end
	local n = #ids
	if n < 1 or n > 30 then return false end
	local keys = 0
	for key, value in ids do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > n or type(value) ~= "string" or #value < 1 or #value > 32 then
			return false
		end
		keys += 1
	end
	return keys == n
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
		-- The client reveals the returned server result after the reel; an immediate
		-- notice would spoil it before the animation finishes.
		return apply(player, Rewards.OpenBox, boxType, LootService.Rng, EventService.ActiveId())
	end)
	Net.Handle("OpenBoxes", boxBatch, function(player, boxType, count)
		return apply(player, Rewards.OpenBoxes, boxType, count, LootService.Rng, EventService.ActiveId())
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
	Net.Handle("SellRooms", roomBatch, function(player, instanceIds)
		return apply(player, Rewards.SellRooms, instanceIds)
	end)
end

return LootService
