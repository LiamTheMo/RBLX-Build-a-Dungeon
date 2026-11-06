--!strict
-- Keeper XP and levels, level rewards, shop level gates, permanent upgrades and
-- the effective bonuses of a profile (GDD "Loot, rarity and progression"). Pure.
--
-- Bonus order: the built-in perks (fixed by each room's definition) and event
-- modifiers (Lucky, Golden) of every room ON THE ROUTE (Route.Build over
-- profile.Layout; idle rooms count for nothing) are summed, the matching
-- permanent upgrade is added, then each total is capped by Balance.Perks.Caps.
-- The vault (Treasure, VaultRate, Vaulted, VariantBonus, TheftScale) likewise
-- needs a treasure-kind room on the route.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Economy = require(script.Parent.Economy)
local Events = require(script.Parent.Events)
local LayoutRules = require(script.Parent.LayoutRules)
local Threat = require(script.Parent.Threat)

local Progression = {}

local EPS = 1e-9
local P = Balance.Progression

function Progression.XpToNext(level: number): number
	return P.XpBase + P.XpPerLevel * (level - 1)
end

-- XP for defeating `visitorId`, after the threat tier's Xp multiplier and the
-- XP bonus (whole, rounded down).
function Progression.XpFor(visitorId: string, xpBonus: number?, threatXp: number?): number
	local base = P.Xp[visitorId]
	if base == nil then
		return 0
	end
	return math.floor(base * (threatXp or 1) * (1 + math.max(0, xpBonus or 0)) + EPS)
end

-- Adds XP: returns (level, xp, levelsGained: {number}). XP stops at MaxLevel.
function Progression.AddXp(level: number, xp: number, amount: number): (number, number, { number })
	local gained = {}
	xp += math.max(0, amount)
	while level < P.MaxLevel and xp >= Progression.XpToNext(level) do
		xp -= Progression.XpToNext(level)
		level += 1
		table.insert(gained, level)
	end
	if level >= P.MaxLevel then
		xp = 0
	end
	return level, xp, gained
end

-- The box granted on reaching `level`.
function Progression.LevelReward(level: number): string
	return if level % P.RareBoxEvery == 0 then "Rare" else "Dungeon"
end

-- Keeper level needed to buy `roomId` in the shop (1 = no gate).
function Progression.ShopLevel(roomId: string): number
	return P.ShopLevel[roomId] or 1
end

-- Coins to go from `level` to level + 1; nil at max or for an unknown upgrade.
function Progression.PermanentCost(upgradeId: any, level: any): number?
	local def = Balance.Permanent[upgradeId]
	if type(upgradeId) ~= "string" or type(def) ~= "table" or def.Base == nil then
		return nil
	end
	if type(level) ~= "number" or level % 1 ~= 0 or level < 0 or level >= def.MaxLevel then
		return nil
	end
	return math.floor(def.Base * Balance.Permanent.CostGrowth ^ level + 0.5)
end

-- Total effect of a permanent upgrade, keyed by Effect name ("Coins", "Loot", ...).
function Progression.PermanentEffect(profile: any, effect: string): number
	local total = 0
	for _, id in Balance.Permanent.Order do
		local def = Balance.Permanent[id]
		if def.Effect == effect then
			total += (profile.Permanent and profile.Permanent[id] or 0) * def.PerLevel
		end
	end
	return total
end

-- The room instances ON THE ROUTE (idle, off-route rooms give no perks,
-- modifiers or vault effects; rule of 2026-11-05). An invalid layout counts as empty.
local function routeRooms(profile: any): { any }
	local out = {}
	local layout = profile.Layout or {}
	local ok, routeCells = LayoutRules.Validate(profile, layout)
	if not ok then
		return out
	end
	for _, key in routeCells do
		local room = profile.Rooms[layout[key]]
		if room then
			table.insert(out, room)
		end
	end
	return out
end

-- Effective {Coins, Loot, Xp} fractions: route-room perks (from the room
-- definitions, never from saved data) and modifiers + permanents, capped.
function Progression.Bonuses(profile: any): { Coins: number, Loot: number, Xp: number }
	local sum = { Coins = 0, Loot = 0, Xp = 0 }
	for _, room in routeRooms(profile) do
		local def = Rooms.Get(room.Id)
		local perks: { any } = if def then def.Perks else {}
		for _, perk in perks do
			if sum[perk.Kind] ~= nil and type(perk.Amount) == "number" then
				sum[perk.Kind] += perk.Amount
			end
		end
		local mod = Events.Modifier(room.Modifier)
		if mod and sum[mod.Effect] ~= nil then
			sum[mod.Effect] += mod.Amount
		end
	end
	local out = {}
	for kind, value in sum do
		out[kind] = math.min(Balance.Perks.Caps[kind], value + Progression.PermanentEffect(profile, kind))
	end
	return out :: any
end

-- Stout Defenders: fraction added to defender health.
function Progression.DefenderHealthBonus(profile: any): number
	return Progression.PermanentEffect(profile, "DefenderHealth")
end

-- Lure: seconds removed from the visitor interval.
function Progression.IntervalReduction(profile: any): number
	return Progression.PermanentEffect(profile, "VisitorInterval")
end

-- The treasure-kind room instance on the route (any tier), or nil (an off-route
-- treasure has no vault effect).
function Progression.Treasure(profile: any): any
	for _, room in routeRooms(profile) do
		if Rooms.IsTreasure(room.Id) then
			return room
		end
	end
	return nil
end

-- Vault exchange rate: 0 without the Treasure Room on the route.
function Progression.VaultRate(profile: any): number
	local room = Progression.Treasure(profile)
	if room == nil then
		return 0
	end
	return Economy.VaultRate(room.Id, room.Level, (profile.Permanent or {}).DeepVault or 0)
end

-- The route treasure's rare-variant bonus (a fraction; Dragon Hoard), 0 without one.
function Progression.VariantBonus(profile: any): number
	local room = Progression.Treasure(profile)
	local stats = room and Balance.Rooms[room.Id]
	return stats and stats.VariantBonus or 0
end

-- What a theft is multiplied by: the route treasure's TheftScale (Void Vault 0.5), else 1.
function Progression.TheftScale(profile: any): number
	local room = Progression.Treasure(profile)
	local stats = room and Balance.Rooms[room.Id]
	return stats and stats.TheftScale or 1
end

-- Spawn-rate bonus in percent from the coins actually at risk.
function Progression.VaultBonus(profile: any): number
	return Economy.VaultBonus(Economy.Vaulted(profile.Coins, profile.VaultPercent or 0, Progression.Treasure(profile) ~= nil), Progression.VaultRate(profile))
end

-- Coins currently at risk (0 without a treasure room on the route).
function Progression.Vaulted(profile: any): number
	return Economy.Vaulted(profile.Coins, profile.VaultPercent or 0, Progression.Treasure(profile) ~= nil)
end

-- Seconds between visitors right now (vault bonus, Lure and the event's Interval effect).
function Progression.VisitorInterval(profile: any, eventEffects: any): number
	return Economy.VisitorInterval(Progression.VaultBonus(profile), Progression.IntervalReduction(profile), eventEffects and eventEffects.Interval)
end

-- Highest unlocked threat tier (`all` = admin override).
function Progression.ThreatUnlocked(profile: any, all: boolean?): number
	return Threat.Unlocked(profile.Level, all)
end

-- The tier visitors use: tier 1 until the tutorial is done, else the selected
-- tier clamped to what is unlocked.
function Progression.ActiveThreat(profile: any, all: boolean?): number
	if not (profile.Tutorial and profile.Tutorial.Done) then
		return 1
	end
	local selected = if Threat.Valid(profile.Threat) then profile.Threat else 1
	return math.min(selected, Progression.ThreatUnlocked(profile, all))
end

return table.freeze(Progression)
