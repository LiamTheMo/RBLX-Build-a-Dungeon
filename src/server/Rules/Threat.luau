--!strict
-- Threat levels and rare visitor variants (GDD "Threat levels"). Pure: rolls take
-- an injected rng with NextNumber() in [0, 1); weighted picks walk the ordered
-- Balance lists, never dictionary order.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Economy = require(script.Parent.Economy)

local Threat = {}

local T = Balance.Threat

function Threat.Count(): number
	return #T.UnlockLevels
end

-- Highest tier a keeper of `level` has unlocked (`all` = admin override).
function Threat.Unlocked(level: number, all: boolean?): number
	if all then
		return #T.UnlockLevels
	end
	local best = 1
	for tier, needed in T.UnlockLevels do
		if type(level) == "number" and level >= needed then
			best = tier
		end
	end
	return best
end

-- True for a whole tier in 1..Count.
function Threat.Valid(tier: any): boolean
	return type(tier) == "number" and tier % 1 == 0 and tier >= 1 and tier <= #T.UnlockLevels
end

-- Multipliers at `tier`: {Health, Damage, Coins, Xp, Drops} = 1 + PerTier * (tier - 1).
function Threat.Scale(tier: number): { [string]: number }
	local t = if Threat.Valid(tier) then tier else 1
	local out = {}
	for stat, per in T.PerTier do
		out[stat] = 1 + per * (t - 1)
	end
	return out
end

local function pick(list: { any }, rng: any, weightOf: (any) -> number): any
	local total = 0
	for _, e in list do
		total += weightOf(e)
	end
	local roll = rng:NextNumber() * total
	for _, e in list do
		roll -= weightOf(e)
		if roll < 0 then
			return e
		end
	end
	return list[#list]
end

-- {{Id, Chance}} of the visitors at `tier` (chances sum to 1).
function Threat.Roster(tier: number): { any }
	local list = T.Roster[if Threat.Valid(tier) then tier else 1]
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

function Threat.PickVisitor(tier: number, rng: any): string
	return pick(T.Roster[if Threat.Valid(tier) then tier else 1], rng, function(e)
		return e.Weight
	end).Id
end

-- Variant multiplier from the vault bonus (in percent), the event's Variants
-- effect and the treasure room's VariantBonus (a fraction, e.g. Dragon Hoard 0.25).
function Threat.VariantMultiplier(vaultBonus: number?, eventMult: number?, treasureBonus: number?): number
	return Economy.VaultLuckMultiplier(vaultBonus)
		* math.max(0, eventMult or 1)
		* (1 + math.max(0, treasureBonus or 0))
end

-- {{Id, Chance}} rarest first, each base chance times `mult`; the running total
-- never exceeds 1 (a later entry is cut short). Practice never gets a variant.
function Threat.VariantChances(visitorId: string, mult: number): { any }
	local out, left = {}, 1
	for _, v in Balance.Variants do
		local chance = if visitorId == "Practice" then 0 else math.min(left, v.Chance * math.max(0, mult))
		left -= chance
		table.insert(out, { Id = v.Id, Chance = chance })
	end
	return out
end

-- One roll: the variant id or nil (normal). Uses exactly VariantChances.
function Threat.RollVariant(visitorId: string, mult: number, rng: any): string?
	local roll = rng:NextNumber()
	for _, v in Threat.VariantChances(visitorId, mult) do
		if roll < v.Chance then
			return v.Id
		end
		roll -= v.Chance
	end
	return nil
end

local byId = {}
for _, v in Balance.Variants do
	byId[v.Id] = v
end

-- The Balance entry of a variant id (nil for "" / unknown).
function Threat.Variant(id: any): any
	return byId[id]
end

return table.freeze(Threat)
