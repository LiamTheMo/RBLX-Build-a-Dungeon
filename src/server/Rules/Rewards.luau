-- Profile mutations for loot and progression (GDD "Loot, rarity and
-- progression"). Pure and non-yielding: callers pass the live profile and an
-- RNG (Random.new() on the server, seeded in specs), then call
-- ProfileService.Changed. Each returns (ok, dataOrReason) like a remote handler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(ReplicatedStorage.Shared.Definitions.Balance)
local Loot = require(ReplicatedStorage.Shared.Rules.Loot)
local Progression = require(ReplicatedStorage.Shared.Rules.Progression)
local RoomInventory = require(script.Parent.RoomInventory)

local Rewards = {}

local Rooms = require(ReplicatedStorage.Shared.Definitions.Rooms)

local function isDefender(roomId: string): boolean
	local def = Rooms.Get(roomId)
	return def ~= nil and def.Kind == "Defender"
end

-- Adds one box. At the stack cap the box converts to banked coins instead of
-- being lost; returns true when it was converted (callers send "Box storage full").
local function addBox(profile, boxType: string): boolean
	local held = profile.Boxes[boxType] or 0
	if held >= Balance.Loot.MaxStack then
		profile.Coins += Balance.Loot.BoxOverflowCoins[boxType] or 0
		return true
	end
	profile.Boxes[boxType] = held + 1
	return false
end

local function addBlueprints(profile, roomId: string, n: number)
	profile.Blueprints[roomId] = math.min(Balance.Loot.MaxStack, (profile.Blueprints[roomId] or 0) + n)
end

-- Adds XP and grants one box per level gained. Returns (newLevel?, levelDrops).
function Rewards.GrantXp(profile, amount: number)
	local level, xp, gained = Progression.AddXp(profile.Level, profile.Xp, amount)
	profile.Level, profile.Xp = level, xp
	local drops = {}
	for _, reached in gained do
		local boxType = Progression.LevelReward(reached)
		local overflow = addBox(profile, boxType)
		table.insert(drops, { Kind = "Box", Type = boxType, Source = "LevelUp", Overflow = overflow or nil })
	end
	return if #gained > 0 then level else nil, drops
end

-- A defeated visitor: drop rolls (scaled by the loot bonus) and XP (scaled by
-- the XP bonus). Call exactly once per encounter, in the step that pays out.
-- Returns {Drops = {{Kind, Type?, RoomId?, Source, Overflow?}}, Xp, LevelUp = level?}.
-- Overflow = true: the box stack was full and it was converted to coins.
function Rewards.Defeat(profile, visitorId: string, rng, bonuses)
	local drops = Loot.RollDrops(visitorId, bonuses.Loot, rng, profile.Level)
	for _, drop in drops do
		drop.Source = "Visitor"
		if drop.Kind == "Box" then
			drop.Overflow = addBox(profile, drop.Type) or nil
		elseif drop.RoomId then
			addBlueprints(profile, drop.RoomId, 1)
		end
	end
	local xp = Progression.XpFor(visitorId, bonuses.Xp)
	local levelUp, levelDrops = Rewards.GrantXp(profile, xp)
	table.move(levelDrops, 1, #levelDrops, #drops + 1, drops)
	return { Drops = drops, Xp = xp, LevelUp = levelUp }
end

-- Opens one box: a room of a rolled rarity (pity applies) with rolled perks.
-- A full inventory leaves the box unopened.
function Rewards.OpenBox(profile, boxType: string, rng)
	if Loot.Odds(boxType, 0, profile.Level) == nil then
		return false, "BadArgs"
	end
	if (profile.Boxes[boxType] or 0) < 1 then
		return false, "NoBox"
	end
	if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
		return false, "TooManyRooms"
	end
	-- Same pity-adjusted, gate-filtered lists Loot.Odds shows.
	local rarity = Loot.RollRarity(boxType, profile.BoxPity, rng)
	local roomId = Loot.RollRoom(rng, profile.Level)
	local perks = Loot.RollPerks(rarity, rng)
	profile.Boxes[boxType] -= 1
	profile.BoxPity = Loot.NextPity(profile.BoxPity, rarity)
	local instanceId = RoomInventory.Add(profile, roomId, rarity, perks)
	return true, { InstanceId = instanceId, RoomId = roomId, Rarity = rarity, Perks = table.clone(perks) }
end

-- CraftCost blueprints of a type -> one Common room of that type.
function Rewards.Craft(profile, roomId: string)
	if not Loot.Craftable(roomId) then
		return false, "NotCraftable"
	end
	if (profile.Blueprints[roomId] or 0) < Balance.Loot.CraftCost then
		return false, "NotEnoughBlueprints"
	end
	if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
		return false, "TooManyRooms"
	end
	local left = profile.Blueprints[roomId] - Balance.Loot.CraftCost
	profile.Blueprints[roomId] = if left > 0 then left else nil
	return true, RoomInventory.Add(profile, roomId)
end

-- Scraps an unplaced room instance (any rarity or level, not the Treasure
-- Room) for ScrapReturn blueprints of its type. Returns the new blueprint count.
function Rewards.Scrap(profile, instanceId: string)
	local room = profile.Rooms[instanceId]
	if room == nil then
		return false, "NotOwned"
	end
	if not Loot.Craftable(room.Id) then
		return false, "NotScrappable"
	end
	if RoomInventory.IsPlaced(profile, instanceId) then
		return false, "RoomPlaced"
	end
	if (profile.Blueprints[room.Id] or 0) >= Balance.Loot.MaxStack then
		return false, "BlueprintsFull"
	end
	if isDefender(room.Id) then
		local others = 0
		for id, other in profile.Rooms do
			if id ~= instanceId and isDefender(other.Id) then
				others += 1
			end
		end
		if others == 0 then
			return false, "LastDefender"
		end
	end
	profile.Rooms[instanceId] = nil
	addBlueprints(profile, room.Id, Balance.Loot.ScrapReturn)
	return true, profile.Blueprints[room.Id]
end

-- Buys the next level of a permanent upgrade with banked coins.
function Rewards.BuyPermanent(profile, upgradeId: string)
	local def = Balance.Permanent[upgradeId]
	if type(def) ~= "table" or def.Base == nil then
		return false, "UnknownUpgrade"
	end
	local level = profile.Permanent[upgradeId] or 0
	local cost = Progression.PermanentCost(upgradeId, level)
	if cost == nil then
		return false, "MaxLevel"
	end
	if profile.Coins < cost then
		return false, "NotEnoughCoins"
	end
	profile.Coins -= cost
	profile.Permanent[upgradeId] = level + 1
	return true, level + 1
end

return Rewards
