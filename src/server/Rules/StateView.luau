--!strict
-- Server-computed fields of the private State snapshot (docs/ARCHITECTURE.md,
-- "Remotes"). Pure: reads a profile, never mutates it. The client shows these
-- values instead of running game rules itself.

local Definitions = script.Parent.Parent.Definitions
local Rooms = require(Definitions.Rooms)
local Visitors = require(Definitions.Visitors)
local Balance = require(Definitions.Balance)
local Economy = require(script.Parent.Economy)
local Loot = require(script.Parent.Loot)
local Progression = require(script.Parent.Progression)

local StateView = {}

-- Snapshot copy of each owned room plus NextUpgradeCost (nil at the rarity's max
-- or for rooms that cannot be upgraded). The profile's own tables are never touched.
local function rooms(profile: any): { [string]: any }
	local out = {}
	for instanceId, room in profile.Rooms or {} do
		local copy = table.clone(room)
		local def = Rooms.Get(room.Id)
		copy.NextUpgradeCost = if def and def.Upgradable then Economy.UpgradeCost(room.Level, room.Rarity) else nil
		out[instanceId] = copy
	end
	return out
end

-- Returns { VaultBonus, VaultBonusCap, XpToNext, Bonuses, Rooms, BoxOdds,
-- PermanentNextCost, DropChances } for the snapshot.
function StateView.Derived(profile: any): any
	local extraCap = Progression.VaultCapBonus(profile)
	local bonuses = Progression.Bonuses(profile)

	local boxOdds = {}
	for _, boxType in Loot.BoxTypes do
		-- Exactly the distribution the next open of that box rolls from.
		boxOdds[boxType] = Loot.Odds(boxType, profile.BoxPity, profile.Level)
	end

	local permanentNext = {}
	for _, id in Balance.Permanent.Order do
		permanentNext[id] = Progression.PermanentCost(id, (profile.Permanent or {})[id] or 0) -- nil at max
	end

	local drops = {}
	for id in Visitors.All do
		drops[id] = Loot.DropChances(id, bonuses.Loot) -- {Box, Blueprint, BoxType}, with the loot bonus
	end

	return {
		VaultBonus = Economy.VaultBonus(profile.Vault, extraCap),
		VaultBonusCap = Economy.VaultBonus(1e12, extraCap), -- the effective cap
		XpToNext = Progression.XpToNext(profile.Level),
		Bonuses = bonuses,
		Rooms = rooms(profile),
		BoxOdds = boxOdds,
		PermanentNextCost = permanentNext,
		DropChances = drops,
	}
end

return table.freeze(StateView)
