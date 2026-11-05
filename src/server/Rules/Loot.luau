--!strict
-- Box odds, rarity, perk and drop rolls (GDD "Loot, rarity and progression").
-- Pure: every roll takes an injected Random (`rng:NextNumber()` in [0, 1)), so
-- specs are deterministic; the server passes Random.new(). Weighted picks walk
-- a fixed order (the Balance.Rarities list / Rooms.Order), never dictionary order.
-- Gameplay-earned only: nothing here is sold.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Progression = require(script.Parent.Progression)

export type Perk = { Kind: string, Amount: number }
export type Drop = { Kind: string, Type: string?, RoomId: string? }

local Loot = {}

Loot.BoxTypes = table.freeze({ "Dungeon", "Rare" })

-- Rarity functions take an optional ordered tier list (default Balance.Rarities)
-- so specs can try an extra tier without touching Balance.
type Tiers = { any }

-- 1-based rank (index in the ordered list), nil for an unknown id.
function Loot.RarityRank(rarity: any, tiers: Tiers?): number?
	for i, r in tiers or Balance.Rarities do
		if r.Id == rarity then
			return i
		end
	end
	return nil
end

-- Ordered {Id, Weight} entries with Weight > 0 and rank >= minRank, for one box
-- type ("Dungeon" uses Weight, "Rare" uses RareWeight).
local function rarityEntries(boxType: string, pity: number, tiers: Tiers?): { any }?
	local field = if boxType == "Dungeon" then "Weight" elseif boxType == "Rare" then "RareWeight" else nil
	if field == nil then
		return nil
	end
	local list = tiers or Balance.Rarities
	local minRank = if pity >= Balance.Loot.PityAfter then Loot.RarityRank(Balance.Loot.PityRarity, list) else nil
	local out = {}
	for i, r in list do
		local w = r[field]
		if type(w) == "number" and w > 0 and (minRank == nil or i >= minRank) then
			table.insert(out, { Id = r.Id, Weight = w })
		end
	end
	return out
end

-- Ordered {Id, Weight} entries of a room-weight table with Weight > 0.
local function entries(weights: { [string]: number }, order: { string }): { any }
	local out = {}
	for _, id in order do
		local w = weights[id]
		if type(w) == "number" and w > 0 then
			table.insert(out, { Id = id, Weight = w })
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

-- Room entries a keeper of `level` may roll: only rooms whose shop level gate is
-- <= level (no bypassing progression via loot). If none qualify, the rooms with
-- the lowest gate are used.
local function gatedRooms(weights: { [string]: number }, level: number?): { any }
	local all = entries(weights, Rooms.Order)
	if level == nil then
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

-- The exact distribution the NEXT open of this box rolls from (pity-adjusted and
-- gate-filtered): {Rooms = {{Id, Chance}}, Rarities = {{Id, Chance}}, PityAfter,
-- PityRarity}. Chances are fractions summing to 1. Rolls use the same lists.
function Loot.Odds(boxType: string, pity: number?, level: number?, tiers: Tiers?): any
	local list = rarityEntries(boxType, pity or 0, tiers)
	if list == nil then
		return nil
	end
	return {
		Rooms = chances(gatedRooms(Balance.Loot.BoxRooms, level)),
		Rarities = chances(list),
		PityAfter = Balance.Loot.PityAfter,
		PityRarity = Balance.Loot.PityRarity,
	}
end

-- Rolls a box's rarity. `pity` = boxes opened in a row below PityRarity; once it
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

function Loot.RollRoom(rng: any, level: number?): string?
	return pick(gatedRooms(Balance.Loot.BoxRooms, level), rng)
end

function Loot.RollBlueprint(rng: any, level: number?): string?
	return pick(gatedRooms(Balance.Loot.BlueprintRooms, level), rng)
end

-- The tier entry for an id (nil if unknown).
local function tierOf(rarity: any, tiers: Tiers?): any
	local i = Loot.RarityRank(rarity, tiers)
	return if i then (tiers or Balance.Rarities)[i] else nil
end

-- The configured amount of a `kind` perk on a `rarity` room; nil if it has none.
function Loot.PerkAmount(rarity: any, kind: any, tiers: Tiers?): number?
	local r = tierOf(rarity, tiers)
	if r == nil or r.PerkCount < 1 then
		return nil
	end
	local size = Balance.Perks[r.PerkSize]
	return size and size[kind]
end

-- PerkCount different kinds (at most one of each), each at the tier's size.
function Loot.RollPerks(rarity: string, rng: any, tiers: Tiers?): { Perk }
	local r = tierOf(rarity, tiers)
	local perks = {}
	if r == nil then
		return perks
	end
	local pool = table.clone(Balance.Perks.Kinds)
	for _ = 1, math.min(r.PerkCount, #pool) do
		local kind = table.remove(pool, math.floor(rng:NextNumber() * #pool) + 1) :: string
		table.insert(perks, { Kind = kind, Amount = Loot.PerkAmount(rarity, kind, tiers) :: number })
	end
	return perks
end

-- Rooms a blueprint stack can craft and scrapping can return: placeable, not the Treasure Room.
function Loot.Craftable(roomId: any): boolean
	local def = Rooms.All[roomId]
	return def ~= nil and def.Placeable and def.Kind ~= "Treasure"
end

-- Per-defeat chances after the loot bonus: {Box, Blueprint, BoxType} (nil for unknown visitors).
function Loot.DropChances(visitorId: string, lootBonus: number?): any
	local d = Balance.Loot.Drops[visitorId]
	if d == nil then
		return nil
	end
	local scale = 1 + math.max(0, lootBonus or 0)
	return { Box = math.min(1, d.Box * scale), Blueprint = math.min(1, d.Blueprint * scale), BoxType = d.BoxType }
end

-- Independent box and blueprint rolls for one defeated visitor.
function Loot.RollDrops(visitorId: string, lootBonus: number?, rng: any, level: number?): { Drop }
	local drops: { Drop } = {}
	local c = Loot.DropChances(visitorId, lootBonus)
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
