--!strict
-- Server events and room modifiers (GDD "Server events"). Pure: EventService owns
-- which event is active; rules take its effects table.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local Events = {}

local E = Balance.Events
local NEUTRAL = table.freeze({ Coins = 1, Drops = 1, Variants = 1, BoxRarity = 1, Interval = 1 })

local events, modifiers = {}, {}
for _, def in E.List do
	events[def.Id] = def
end
for _, def in E.Modifiers do
	modifiers[def.Id] = def
end

-- The event definition for an id (nil for "" / unknown).
function Events.Get(id: any): any
	return events[id]
end

function Events.Modifier(id: any): any
	return modifiers[id]
end

-- {Coins, Drops, Variants, BoxRarity, Interval} multipliers of the active event
-- (all 1 with no event).
function Events.Effects(id: any): { [string]: number }
	local def = events[id]
	if def == nil then
		return NEUTRAL
	end
	local out = table.clone(NEUTRAL)
	for k, v in def.Effects do
		out[k] = v
	end
	return table.freeze(out)
end

-- Rarity tier list for box rolls under `effects`: Weight and RareWeight of
-- BoxRarityFrom and rarer tiers multiplied by BoxRarity. Nil when unboosted, so
-- callers fall back to Balance.Rarities. Loot.Odds/RollRarity take this list.
function Events.BoxTiers(effects: { [string]: number }, luck: number?): { any }?
	local boost = (effects.BoxRarity or 1) * (luck or 1)
	if boost == nil or boost == 1 then
		return nil
	end
	local out, boosted = {}, false
	for _, r in Balance.Rarities do
		boosted = boosted or r.Id == E.BoxRarityFrom
		local copy = table.clone(r)
		if boosted then
			copy.Weight *= boost
			copy.RareWeight *= boost
			copy.CrystalWeight *= boost
		end
		table.insert(out, copy)
	end
	return out
end

-- A modifier id for a room opened from a box while `eventId` runs, or nil.
-- Rolls the chance first, then one modifier uniformly.
function Events.RollModifier(eventId: any, rng: any): string?
	if events[eventId] == nil or rng:NextNumber() >= E.ModifierChance then
		return nil
	end
	local list = E.Modifiers
	return list[math.min(#list, math.floor(rng:NextNumber() * #list) + 1)].Id
end

-- Seconds until the next automatic event (MinGap..MaxGap).
function Events.NextGap(rng: any): number
	return E.MinGap + rng:NextNumber() * (E.MaxGap - E.MinGap)
end

-- A random event id (uniform over the list).
function Events.RollEvent(rng: any): string
	local list = E.List
	return list[math.min(#list, math.floor(rng:NextNumber() * #list) + 1)].Id
end

return table.freeze(Events)
