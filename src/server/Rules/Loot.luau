--!strict
-- Box odds and rolls, blueprint drops and craft/scrap costs (GDD "Loot, rarity
-- and progression"). Pure: every roll takes an injected Random
-- (`rng:NextNumber()` in [0, 1)), so specs are deterministic; the server passes
-- Random.new(). Weighted picks walk a fixed order (the Balance.Rarities list /
-- Rooms.Order), never dictionary order. Gameplay-earned only: nothing here is sold.
--
-- Item model (2026-11-05): a room's rarity is fixed by its definition. A box
-- rolls a TIER (tier weights, pity, event boost), then a ROOM from its own
-- tier pool (Balance.Loot.RoomWeights, default 1). Common and Uncommon rooms respect the
-- shop level gates; Rare and rarer rooms are loot-only and never gated.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Progression = require(script.Parent.Progression)

export type Drop = { Kind: string, Type: string?, RoomId: string? }

local Loot = {}

Loot.BoxTypes = table.freeze({ "Dungeon", "Rare", "Crystal" })

-- Rarity functions take an optional ordered tier list (default Balance.Rarities)
-- so specs and events (Events.BoxTiers) can change the weights without touching Balance.
type Tiers = { any }

-- Tiers whose rooms follow the shop level gates.
local GATED = table.freeze({ Common = true, Uncommon = true })

-- 1-based rank (index in the ordered list), nil for an unknown id.
function Loot.RarityRank(rarity: any, tiers: Tiers?): number?
	for i, r in tiers or Balance.Rarities do
		if r.Id == rarity then
			return i
		end
	end
	return nil
end

-- A room's weight inside its tier (0 = never from loot).
local function roomWeight(roomId: string): number
	local w = Balance.Loot.RoomWeights[roomId]
	return if type(w) == "number" then w else 1
end

-- In the loot pool: placeable with a positive room weight. Exactly the rooms
-- boxes and blueprints can give, crafting can make and scrapping accepts (not
-- the starter Coin Cache).
function Loot.Craftable(roomId: any): boolean
	local def = Rooms.Get(roomId)
	return def ~= nil and def.Placeable and roomWeight(def.Id) > 0
end

-- Ordered {Id, Weight} rooms a box of `tier` can give a keeper of `level` (nil =
-- ungated). Common/Uncommon rooms need Progression.ShopLevel <= level; if none
-- qualifies, the tier's lowest-gated rooms are used. Empty for a tier with no rooms.
function Loot.TierRooms(tier: string, level: number?, boxType: string?): { any }
	local all = {}
	for _, id in Rooms.Order do
		local def = Rooms.Get(id) :: any
		local royal = Balance.Loot.RoyalRooms[id] == true
		local crystal = Balance.Loot.CrystalRooms[id] == true
		local included = boxType == nil or (boxType == "Crystal" and crystal) or (boxType == "Rare" and royal) or (boxType == "Dungeon" and not royal and not crystal)
		if included and def.Rarity == tier and Loot.Craftable(id) then
			table.insert(all, { Id = id, Weight = roomWeight(id) })
		end
	end
	if level == nil or not GATED[tier] then
		return all
	end
	local out, lowest, lowestList = {}, math.huge, {}
	for _, e in all do
		local gate = Progression.ShopLevel(e.Id)
		if gate <= level then
			table.insert(out, e)
		end
		if gate < lowest then
			lowest, lowestList = gate, { e }
		elseif gate == lowest then
			table.insert(lowestList, e)
		end
	end
	return if #out > 0 then out else lowestList
end

local function tierField(boxType: string): string?
	return if boxType == "Dungeon" then "Weight" elseif boxType == "Rare" then "RareWeight" elseif boxType == "Crystal" then "CrystalWeight" else nil
end

-- Ordered {Id, Weight} tiers with Weight > 0, at least one room, and rank >= the
-- pity floor, for one box type ("Dungeon" uses Weight, "Rare" uses RareWeight).
local function rarityEntries(boxType: string, pity: number, tiers: Tiers?, blueprint: boolean?): { any }?
	local field = tierField(boxType)
	if field == nil then
		return nil
	end
	local list = tiers or Balance.Rarities
	local minRank = if pity >= Balance.Loot.PityAfter then Loot.RarityRank(Balance.Loot.PityRarity, list) else nil
	local out = {}
	for i, r in list do
		local w = r[field]
		if type(w) == "number" and w > 0 and (minRank == nil or i >= minRank) and #Loot.TierRooms(r.Id, nil, if blueprint then nil else boxType) > 0 then
			table.insert(out, { Id = r.Id, Weight = w })
		end
	end
	return out
end

local function pick(list: { any }, rng: any): string?
	local total = 0
	for _, e in list do
		total += e.Weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, e in list do
		roll -= e.Weight
		if roll < 0 then
			return e.Id
		end
	end
	return list[#list].Id -- float edge
end

local function chances(list: { any }): { any }
	local total = 0
	for _, e in list do
		total += e.Weight
	end
	local out = {}
	for _, e in list do
		table.insert(out, { Id = e.Id, Chance = e.Weight / total })
	end
	return out
end

-- {Rarities = {{Id, Chance}}, TierRooms = {[tier] = {{Id, Chance}}} (chance
-- inside the tier), Rooms = {{Id, Rarity, Chance}} (overall: tier chance * room
-- share)} for a tier list and gate level.
local function distribution(list: { any }, level: number?, boxType: string?): any
	local rarities = chances(list)
	local tierRooms, rooms = {}, {}
	for _, t in rarities do
		local inside = chances(Loot.TierRooms(t.Id, level, boxType))
		tierRooms[t.Id] = inside
		for _, e in inside do
			table.insert(rooms, { Id = e.Id, Rarity = t.Id, Chance = t.Chance * e.Chance })
		end
	end
	return { Rarities = rarities, TierRooms = tierRooms, Rooms = rooms }
end

-- The exact distribution the NEXT open of this box rolls from (pity-adjusted,
-- event-boosted via `tiers`, gate-filtered): {Rarities = {{Id, Chance}},
-- TierRooms = {[tier] = {{Id, Chance}}}, Rooms = {{Id, Rarity, Chance}},
-- PityAfter, PityRarity}. Each Chance list sums to 1. Rolls use the same lists.
function Loot.Odds(boxType: string, pity: number?, level: number?, tiers: Tiers?): any
	local list = rarityEntries(boxType, pity or 0, tiers)
	if list == nil then
		return nil
	end
	local d = distribution(list, level, boxType)
	d.PityAfter = Balance.Loot.PityAfter
	d.PityRarity = Balance.Loot.PityRarity
	return d
end

-- Rolls a box's tier. `pity` = boxes opened in a row below PityRarity; once it
-- reaches PityAfter the roll is restricted to PityRarity or better (renormalised).
function Loot.RollRarity(boxType: string, pity: number, rng: any, tiers: Tiers?): string?
	local list = rarityEntries(boxType, pity, tiers)
	if list == nil then
		return nil
	end
	return pick(list, rng)
end

-- Pity counter after opening a box of `rarity`.
function Loot.NextPity(pity: number, rarity: string, tiers: Tiers?): number
	if (Loot.RarityRank(rarity, tiers) or 0) >= (Loot.RarityRank(Balance.Loot.PityRarity, tiers) :: number) then
		return 0
	end
	return math.min(pity + 1, Balance.Loot.PityAfter)
end

-- A room of `tier` for a keeper of `level` (same list as Odds' TierRooms).
function Loot.RollRoom(tier: string, rng: any, level: number?, boxType: string?): string?
	return pick(Loot.TierRooms(tier, level, boxType), rng)
end

-- One box: (tier, roomId) or nil for an unknown box type.
function Loot.RollBox(boxType: string, pity: number, rng: any, level: number?, tiers: Tiers?): (string?, string?)
	local tier = Loot.RollRarity(boxType, pity, rng, tiers)
	if tier == nil then
		return nil, nil
	end
	return tier, Loot.RollRoom(tier, rng, level, boxType)
end

-- Blueprint drop type: tier by the BlueprintTierBox weights (no pity, no event),
-- then a room of that tier (gated like boxes). {{Id, Rarity, Chance}} overall.
function Loot.BlueprintOdds(level: number?): { any }
	local list = rarityEntries(Balance.Loot.BlueprintTierBox, 0, nil, true) :: { any }
	return distribution(list, level).Rooms
end

function Loot.RollBlueprint(rng: any, level: number?): string?
	local list = rarityEntries(Balance.Loot.BlueprintTierBox, 0, nil, true)
	local tier = list and pick(list, rng)
	return if tier then Loot.RollRoom(tier, rng, level) else nil
end

-- Blueprints of `roomId` needed to craft one (its tier's CraftCost); nil if not craftable.
function Loot.CraftCost(roomId: any): number?
	if not Loot.Craftable(roomId) then
		return nil
	end
	return (Balance.RarityById[Rooms.Rarity(roomId)] or Balance.RarityById.Common).CraftCost
end

-- Blueprints back for scrapping one `roomId` (its tier's ScrapReturn); nil if not scrappable.
function Loot.ScrapReturn(roomId: any): number?
	if not Loot.Craftable(roomId) then
		return nil
	end
	return (Balance.RarityById[Rooms.Rarity(roomId)] or Balance.RarityById.Common).ScrapReturn
end

-- Per-defeat chances: base * (1 + loot bonus) * scale, capped at 1. `scale` is
-- the threat tier, variant and event drop multipliers (Rewards.DropScale).
-- Returns {Box, Blueprint, BoxType} (nil for unknown visitors).
function Loot.DropChances(visitorId: string, lootBonus: number?, scale: number?): any
	local d = Balance.Loot.Drops[visitorId]
	if d == nil then
		return nil
	end
	local m = (1 + math.max(0, lootBonus or 0)) * math.max(0, scale or 1)
	return { Box = math.min(1, d.Box * m), Blueprint = math.min(1, d.Blueprint * m), BoxType = d.BoxType }
end

-- Every possible drop with its chance per defeat, exactly as RollDrops rolls it:
-- {{Kind = "Box", Type, Chance}, {Kind = "Blueprint", RoomId, Rarity, Chance}...}.
-- A blueprint's chance is the blueprint chance times that room's overall share
-- (tier chance * share inside the level-gated tier); `level` nil = ungated.
function Loot.DropTable(visitorId: string, lootBonus: number?, scale: number?, level: number?): { any }
	local out = {}
	local c = Loot.DropChances(visitorId, lootBonus, scale)
	if c == nil then
		return out
	end
	table.insert(out, { Kind = "Box", Type = c.BoxType, Chance = c.Box })
	for _, e in Loot.BlueprintOdds(level) do
		table.insert(out, { Kind = "Blueprint", RoomId = e.Id, Rarity = e.Rarity, Chance = c.Blueprint * e.Chance })
	end
	return out
end

-- Independent box and blueprint rolls for one defeated visitor.
function Loot.RollDrops(visitorId: string, lootBonus: number?, rng: any, level: number?, scale: number?): { Drop }
	local drops: { Drop } = {}
	local c = Loot.DropChances(visitorId, lootBonus, scale)
	if c == nil then
		return drops
	end
	if rng:NextNumber() < c.Box then
		table.insert(drops, { Kind = "Box", Type = c.BoxType })
	end
	if rng:NextNumber() < c.Blueprint then
		table.insert(drops, { Kind = "Blueprint", RoomId = Loot.RollBlueprint(rng, level) })
	end
	return drops
end

return table.freeze(Loot)
