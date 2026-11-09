--!strict
-- Server-computed fields of the private State snapshot (docs/ARCHITECTURE.md,
-- "Remotes"). Pure: reads a profile, never mutates it. The client shows these
-- values instead of running game rules itself.

local Definitions = script.Parent.Parent.Definitions
local Rooms = require(Definitions.Rooms)
local Visitors = require(Definitions.Visitors)
local Balance = require(Definitions.Balance)
local Economy = require(script.Parent.Economy)
local Events = require(script.Parent.Events)
local Loot = require(script.Parent.Loot)
local Progression = require(script.Parent.Progression)
local Rewards = require(script.Parent.Rewards)
local Threat = require(script.Parent.Threat)

local StateView = {}

-- Snapshot copy of each owned room {Id, Level, Modifier?} plus, from its
-- definition, Rarity, Perks (copies) and MaxLevel, and NextUpgradeCost (nil at the
-- tier's max or for rooms that cannot be upgraded). The profile's own tables are
-- never touched.
local function rooms(profile: any): { [string]: any }
	local out = {}
	for instanceId, room in profile.Rooms or {} do
		local copy = table.clone(room)
		local def = Rooms.Get(room.Id)
		local rarity = Rooms.Rarity(room.Id)
		copy.Rarity = rarity
		copy.MaxLevel = Economy.MaxLevel(rarity)
		local perks, defPerks: { any } = {}, if def then def.Perks else {}
		for i, perk in defPerks do
			perks[i] = { Kind = perk.Kind, Amount = perk.Amount }
		end
		copy.Perks = perks
		copy.NextUpgradeCost = if def and def.Upgradable then Economy.UpgradeCost(room.Level, rarity) else nil
		out[instanceId] = copy
	end
	return out
end

-- The next goals for the HUD: the next threat tier, the next level-gated shop
-- room and the cheapest permanent upgrade not yet maxed (each nil when none).
local function nextUnlocks(profile: any, unlocked: number): any
	local out = {}
	local tier = unlocked + 1
	if tier <= Threat.Count() then
		out.Threat = { Tier = tier, Level = Balance.Threat.UnlockLevels[tier] }
	end
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		local level = Progression.ShopLevel(id)
		if def and def.Source == "Shop" and level > profile.Level and (out.ShopRoom == nil or level < out.ShopRoom.Level) then
			out.ShopRoom = { RoomId = id, Level = level }
		end
	end
	for _, id in Balance.Permanent.Order do
		local cost = Progression.PermanentCost(id, (profile.Permanent or {})[id] or 0)
		if cost and (out.Permanent == nil or cost < out.Permanent.Cost) then
			out.Permanent = { Id = id, Cost = cost, Affordable = profile.Coins >= cost }
		end
	end
	return out
end

-- `world` = {EventId?, UnlockAll?}: the active server event and the admin threat
-- override. Returns the derived snapshot fields (see docs/ARCHITECTURE.md).
function StateView.Derived(profile: any, world: any?): any
	local w = world or {}
	local ctx = Rewards.Context(profile, w.EventId, w.UnlockAll)
	local tiers = Events.BoxTiers(ctx.Effects, ctx.LuckMult)

	local boxOdds = {}
	for _, boxType in Loot.BoxTypes do
		-- Exactly the distribution the next open of that box rolls from: tier
		-- chances, then room chances inside each tier (Loot.Odds).
		boxOdds[boxType] = Loot.Odds(boxType, profile.BoxPity, profile.Level, tiers)
	end

	local permanentNext = {}
	for _, id in Balance.Permanent.Order do
		permanentNext[id] = Progression.PermanentCost(id, (profile.Permanent or {})[id] or 0) -- nil at max
	end

	local drops, tables = {}, {}
	for id in Visitors.All do
		drops[id] = Loot.DropChances(id, ctx.Bonuses.Loot, Rewards.DropScale(ctx)) -- {Box, Blueprint, BoxType}
		tables[id] = Rewards.Table(profile, id, ctx)
	end

	local unlocked = Progression.ThreatUnlocked(profile, w.UnlockAll)
	local vaulted, risk = Progression.Vaulted(profile), 0
	for _, visitor in Threat.Roster(ctx.Threat) do
		risk = math.max(risk, Economy.Theft(visitor.Id, vaulted, nil, Progression.TheftScale(profile)))
	end
	return {
		VaultPercent = profile.VaultPercent,
		Vaulted = vaulted,
		VaultRisk = risk,
		VaultRate = Progression.VaultRate(profile),
		VaultBonus = Progression.VaultBonus(profile), -- percent
		VaultLuck = ctx.LuckMult,
		VariantChance = ctx.VariantMult, -- all rare-visitor boosts combined (x1 with none)
		Threat = profile.Threat,
		ThreatActive = ctx.Threat,
		ThreatUnlocked = unlocked,
		ActiveEvent = ctx.EventId,
		XpToNext = Progression.XpToNext(profile.Level),
		Bonuses = ctx.Bonuses,
		Rooms = rooms(profile),
		BoxOdds = boxOdds,
		PermanentNextCost = permanentNext,
		DropChances = drops,
		DropTables = tables,
		NextUnlocks = nextUnlocks(profile, unlocked),
	}
end

return table.freeze(StateView)
