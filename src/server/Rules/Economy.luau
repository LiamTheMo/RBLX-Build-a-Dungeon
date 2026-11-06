--!strict
-- Coin rewards, the treasure vault exchange, theft and timing (docs/PHASE0.md).
-- Everything rounds down to whole coins. The epsilon only absorbs float error
-- like 100 * 1.07.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local Economy = {}

local EPS = 1e-9

local function isCount(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- A visitor's base coin range {Min, Max}; nil for an unknown visitor.
function Economy.RewardRange(visitorId: string): (number?, number?)
	local stats = Balance.Visitors[visitorId]
	if stats == nil then
		return nil, nil
	end
	return stats.Reward.Min, stats.Reward.Max
end

-- Rolls the base reward once per encounter: a whole number in [Min, Max].
function Economy.RollReward(visitorId: string, rng: any): number
	local min, max = Economy.RewardRange(visitorId)
	if min == nil or max == nil then
		return 0
	end
	return math.clamp(min + math.floor(rng:NextNumber() * (max - min + 1)), min, max)
end

-- What multiplies a base reward: threat tier, variant, the capped coin bonus and
-- the event. `ctx` = {ThreatCoins?, VariantCoins?, CoinBonus?, EventCoins?}.
function Economy.CoinMultiplier(ctx: any): number
	return (ctx.ThreatCoins or 1) * (ctx.VariantCoins or 1) * (1 + math.max(0, ctx.CoinBonus or 0)) * (ctx.EventCoins or 1)
end

-- Coins paid for a defeat (straight to Coins).
function Economy.WinPayout(base: number, multiplier: number): number
	if not isCount(base) or not isCount(multiplier) then
		return 0
	end
	return math.floor(base * multiplier + EPS)
end

-- Coins at risk: floor(coins * percent / 100), only while the Treasure Room is on the route.
function Economy.Vaulted(coins: number, percent: number, hasTreasure: boolean): number
	if not hasTreasure or not isCount(coins) or not isCount(percent) then
		return 0
	end
	return math.floor(coins * math.min(percent, 100) / 100 + EPS)
end

-- Vault exchange rate of a placed treasure room `roomId` at `level`, with
-- `deepVault` permanent levels: RatePerPercent * Exchange (Balance.Rooms, 1 if
-- absent) * (1 + LevelBonus * (level - 1) + DeepVault PerLevel * deepVault).
function Economy.VaultRate(roomId: string?, level: number?, deepVault: number?): number
	local stats = roomId and Balance.Rooms[roomId]
	local exchange = if stats and isCount(stats.Exchange) then stats.Exchange else 1
	local lv = if isCount(level) then math.max(1, level :: number) else 1
	local deep = if isCount(deepVault) then deepVault :: number else 0
	local v = Balance.Vault
	return v.RatePerPercent * exchange * (1 + v.LevelBonus * (lv - 1) + Balance.Permanent.DeepVault.PerLevel * deep)
end

-- Spawn-rate bonus in percent: VaultPercent * rate.
function Economy.VaultBonus(percent: number, rate: number): number
	if not isCount(percent) or not isCount(rate) then
		return 0
	end
	return math.min(percent, 100) * rate
end

-- Visitor interval: (base - Lure) / (1 + bonus / 100) * the event's Interval
-- effect, never below MinVisitorInterval.
function Economy.VisitorInterval(bonus: number?, reduction: number?, eventMult: number?): number
	local t = Balance.Timing
	local base = math.max(t.MinVisitorInterval, t.VisitorInterval - math.max(0, reduction or 0))
	local seconds = base / (1 + math.max(0, bonus or 0) / 100) * math.max(0, eventMult or 1)
	return math.max(t.MinVisitorInterval, seconds)
end

-- Stolen by a visitor that reaches the treasure: TheftFraction of the vaulted coins, times `scale` (the
-- treasure's TheftScale, default 1). `snapshot` is the vaulted amount when the visitor spawned: the
-- theft uses min(snapshot, vaulted), so depositing coins mid-encounter cannot raise it and spending
-- them cannot hide them (it only ever lowers the base).
function Economy.Theft(visitorId: string, vaulted: number, snapshot: number?, scale: number?): number
	local stats = Balance.Visitors[visitorId]
	if stats == nil or not isCount(vaulted) then
		return 0
	end
	if snapshot ~= nil then
		if not isCount(snapshot) then
			return 0
		end
		vaulted = math.min(vaulted, snapshot)
	end
	local s = if isCount(scale) then scale :: number else 1
	return math.min(vaulted, math.floor(vaulted * stats.TheftFraction * s + EPS))
end

-- Most levels a room of `rarity` (default Common) can reach. Callers pass the
-- room definition's rarity (Rooms.Rarity(roomId)).
function Economy.MaxLevel(rarity: string?): number
	return (Balance.RarityById[rarity or "Common"] or Balance.RarityById.Common).MaxLevel
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

return table.freeze(Economy)
