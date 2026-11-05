--!strict
-- Payout, theft and timing rules (docs/PHASE0.md assumptions): everything rounds
-- down to whole coins. The epsilon only absorbs float error like 100 * 1.07.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local Economy = {}

local EPS = 1e-9

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- `extraCap` raises the cap (an upgraded Treasure Room, Deep Vault; Progression.VaultCapBonus).
function Economy.VaultBonus(vault: number, extraCap: number?): number
	if not isCount(vault) then
		return 0
	end
	local e = Balance.Economy
	return math.min(e.VaultBonusCap + math.max(0, extraCap or 0), math.floor(vault / 100) * e.VaultBonusPer100)
end

-- Win reward: banked directly, or into the vault (plus the bonus) when a
-- treasure room exists. The bonus applies only with a treasure room.
-- `coinBonus` (Progression.Bonuses().Coins) multiplies the reward first.
function Economy.WinPayout(
	visitorId: string,
	vault: number,
	hasTreasure: boolean,
	coinBonus: number?,
	extraCap: number?
): (number, string)
	local stats = Balance.Visitors[visitorId]
	if stats == nil then
		return 0, "Bank"
	end
	local base = stats.Reward * (1 + math.max(0, coinBonus or 0))
	if not hasTreasure then
		return math.floor(base + EPS), "Bank"
	end
	return math.floor(base * (1 + Economy.VaultBonus(vault, extraCap)) + EPS), "Vault"
end

function Economy.Theft(visitorId: string, vault: number): number
	local stats = Balance.Visitors[visitorId]
	if stats == nil or not isCount(vault) then
		return 0
	end
	return math.min(vault, math.floor(vault * stats.TheftFraction + EPS))
end

-- Most levels a room of `rarity` (default Common) can reach.
function Economy.MaxLevel(rarity: string?): number
	local r = Balance.Rarities[rarity or "Common"]
	return if type(r) == "table" and r.MaxLevel then r.MaxLevel else Balance.Rarities.Common.MaxLevel
end

-- Cost to go from currentLevel to the next; nil at the rarity's max level or for bad input.
function Economy.UpgradeCost(currentLevel: number, rarity: string?): number?
	if type(currentLevel) ~= "number" or currentLevel % 1 ~= 0 or currentLevel < 1 then
		return nil
	end
	if currentLevel >= Economy.MaxLevel(rarity) then
		return nil
	end
	return Balance.Upgrades.Costs[currentLevel]
end

-- `reduction` (Lure, Progression.IntervalReduction) shortens it, never below 1 s.
function Economy.VisitorInterval(hasTreasure: boolean, reduction: number?): number
	local base = if hasTreasure then Balance.Timing.VisitorIntervalWithTreasure else Balance.Timing.VisitorInterval
	return math.max(1, base - math.max(0, reduction or 0))
end

return Economy
