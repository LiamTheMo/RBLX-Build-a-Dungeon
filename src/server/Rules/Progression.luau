--!strict
-- Keeper XP and levels, level rewards, shop level gates, permanent upgrades and
-- the effective bonuses of a profile (GDD "Loot, rarity and progression"). Pure.
--
-- Bonus order: perks of every PLACED room (profile.Layout) are summed, the
-- matching permanent upgrade is added, then each total is capped by
-- Balance.Perks.Caps. Coins multiplies win rewards before the vault bonus.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local Progression = {}

local EPS = 1e-9
local P = Balance.Progression

function Progression.XpToNext(level: number): number
	return P.XpBase + P.XpPerLevel * (level - 1)
end

-- XP for defeating `visitorId`, after the XP bonus (whole, rounded down).
function Progression.XpFor(visitorId: string, xpBonus: number?): number
	local base = P.Xp[visitorId]
	if base == nil then
		return 0
	end
	return math.floor(base * (1 + math.max(0, xpBonus or 0)) + EPS)
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

-- Iterates the room instances placed in the layout.
local function placed(profile: any): { any }
	local out = {}
	for _, instanceId in profile.Layout or {} do
		local room = profile.Rooms[instanceId]
		if room then
			table.insert(out, room)
		end
	end
	return out
end

-- Effective {Coins, Loot, Xp} fractions: placed-room perks + permanents, capped.
function Progression.Bonuses(profile: any): { Coins: number, Loot: number, Xp: number }
	local sum = { Coins = 0, Loot = 0, Xp = 0 }
	for _, room in placed(profile) do
		for _, perk in room.Perks or {} do
			if sum[perk.Kind] ~= nil and type(perk.Amount) == "number" then
				sum[perk.Kind] += perk.Amount
			end
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

-- Extra vault-bonus cap: the placed Treasure Room's level plus Deep Vault.
function Progression.VaultCapBonus(profile: any): number
	local extra = Progression.PermanentEffect(profile, "VaultBonusCap")
	for _, room in placed(profile) do
		if room.Id == "TreasureRoom" then
			extra += (room.Level - 1) * Balance.Rooms.TreasureRoom.VaultBonusCapPerLevel
		end
	end
	return extra
end

return table.freeze(Progression)
