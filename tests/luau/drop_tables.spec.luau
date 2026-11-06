-- The drop tables the player sees (Rewards.Table / State.DropTables, Catalog)
-- against what Rewards.Defeat actually pays and rolls.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Visitors = require(Server.Definitions.Visitors)
local Catalog = require(Server.Rules.Catalog)
local Economy = require(Server.Rules.Economy)
local Rooms = require(game:GetService("ServerScriptService").Server.Definitions.Rooms)
local Loot = require(Server.Rules.Loot)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Rewards = require(Server.Rules.Rewards)

local function veteran()
	local p = ProfileSchema.Default()
	p.Level, p.Threat, p.Tutorial.Done = 30, 4, true
	p.Permanent = { LuckyCharm = 2, GoldenTouch = 2 }
	return p
end

-- Rolls `n` defeats on fresh copies; returns per-drop frequencies keyed "Box:Type" / "Blueprint:RoomId".
local function frequencies(profile, visitorId, ctx, variant, n, seed)
	local rng, counts = Random.new(seed), {}
	for _ = 1, n do
		local copy = ProfileSchema.DeepCopy(profile)
		local r = Rewards.Defeat(copy, visitorId, rng, ctx, 20, variant)
		for _, d in r.Drops do
			if d.Source == "Visitor" and not d.Guaranteed then
				local key = d.Kind .. ":" .. (d.Type or d.RoomId)
				counts[key] = (counts[key] or 0) + 1 / n
			end
		end
	end
	return counts
end

test("every listed chance matches the rolled frequency (threat 4, bonuses, Lucky Stars)", function()
	local p = veteran()
	local ctx = Rewards.Context(p, "LuckyStars")
	local tbl = Rewards.Table(p, "Novice", ctx)
	local freq = frequencies(p, "Novice", ctx, nil, 20000, 4)
	local total = 0
	for _, e in tbl.Drops do
		local key = e.Kind .. ":" .. (e.Type or e.RoomId)
		expectNear(freq[key] or 0, e.Chance, math.max(0.006, e.Chance * 0.1), key)
		total += e.Chance
	end
	-- 6% * 1.75 (tier 4) * 1.1 (Lucky Charm 2) * 2 (event) = 23.1%
	expectNear(tbl.Drops[1].Chance, 0.231, 1e-9, "box chance")
	expect(total > 0, "has drops")
end)

test("Elite doubles drop chances; Shiny and Gilded add a guaranteed box", function()
	local p = veteran()
	local ctx = Rewards.Context(p)
	local base = Rewards.Table(p, "Scout", ctx).Drops[1].Chance
	local elite = frequencies(p, "Scout", ctx, "Elite", 20000, 8)["Box:Dungeon"] or 0
	expectNear(elite, math.min(1, base * 2), 0.012, "elite box rate")
	local r = Rewards.Defeat(ProfileSchema.DeepCopy(p), "Scout", { NextNumber = function() return 0.999 end }, ctx, 20, "Gilded")
	local guaranteed = nil
	for _, d in r.Drops do
		if d.Guaranteed then
			guaranteed = d.Type
		end
	end
	expectEq(guaranteed, "Rare", "gilded rare box")
	local tbl = Rewards.Table(p, "Scout", ctx)
	expectEq(tbl.Variants[2].GuaranteedBox, "Dungeon", "shiny listed with its box")
end)

test("coins paid equal floor(base * multipliers) and stay in the shown range", function()
	local p = veteran()
	local ctx = Rewards.Context(p, "GoldenHour")
	local range = Rewards.CoinRange("Cleric", ctx)
	-- tier 4 x2.5, Golden Touch 2 +10%, Golden Hour x2 = x5.5: 26..36 -> 143..198
	expectEq(range.Min, 143, "min")
	expectEq(range.Max, 198, "max")
	local rng = Random.new(2)
	for _ = 1, 200 do
		local base = Economy.RollReward("Cleric", rng)
		local copy = ProfileSchema.DeepCopy(p)
		local r = Rewards.Defeat(copy, "Cleric", rng, ctx, base)
		expect(r.Amount >= range.Min and r.Amount <= range.Max, "in range")
		expectEq(copy.Coins, p.Coins + r.Amount, "paid to Coins")
	end
	local gilded = Rewards.CoinRange("Cleric", ctx, "Gilded")
	expectEq(gilded.Min, 1430, "gilded x10")
	local tbl = Rewards.Table(p, "Cleric", ctx)
	expectEq(tbl.Variants[1].Coins.Max, Rewards.CoinRange("Cleric", ctx, "Gilded").Max, "variant ranges listed")
end)

test("catalog lists base coin ranges, XP and every possible drop", function()
	local c = Catalog.Build()
	for id in Visitors.All do
		local v = c.Visitors[id]
		local min, max = Economy.RewardRange(id)
		expectEq(v.Reward.Min, min, id .. " min")
		expectEq(v.Reward.Max, max, id .. " max")
		expectEq(v.Theft, Balance.Visitors[id].TheftFraction, id .. " theft")
		local blueprints, sum = 0, 0
		for _, d in v.Drops do
			if d.Kind == "Blueprint" then
				blueprints += 1
				sum += d.Chance
			end
		end
		local base = Loot.DropChances(id, 0)
		local rooms = 0
		for _, id in Rooms.Order do
			if Loot.Craftable(id) then
				rooms += 1
			end
		end
		expectEq(blueprints, rooms, id .. " every blueprint room listed")
		expectNear(sum, base.Blueprint, 1e-9, id .. " blueprint chances add up")
	end
	expectEq(#c.Variants, 3, "variants")
	expectEq(#c.Threat, 6, "tiers")
	expectEq(c.Threat[4].UnlockLevel, 13, "tier 4 level")
	expectEq(#c.Events, #Balance.Events.List, "events")
	expectEq(#c.Modifiers, 3, "modifiers")
end)
