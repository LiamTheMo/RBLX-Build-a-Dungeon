-- Coin ranges, the treasure vault exchange (vaulted coins, rate, bonus, interval)
-- and theft.

local Server = game:GetService("ServerScriptService").Server
local Economy = require(Server.Rules.Economy)
local Balance = require(Server.Definitions.Balance)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(Server.Rules.ProfileSchema)

test("coin ranges match the owner's numbers and rolls stay inside them", function()
	local expected = {
		Practice = { 8, 12 },
		Novice = { 18, 26 },
		Scout = { 22, 32 },
		Cleric = { 26, 36 },
		ArmoredChallenger = { 45, 65 },
	}
	for id, range in expected do
		local min, max = Economy.RewardRange(id)
		expectEq(min, range[1], id .. " min")
		expectEq(max, range[2], id .. " max")
		local rng, seen = Random.new(7), {}
		for _ = 1, 2000 do
			local v = Economy.RollReward(id, rng)
			expect(v >= min and v <= max and v % 1 == 0, id .. " roll in range")
			seen[v] = true
		end
		expect(seen[min] and seen[max], id .. " both ends reachable")
	end
	expectEq(Economy.RollReward("Nobody", Random.new(1)), 0, "unknown visitor")
	local top = { NextNumber = function() return 0.9999999 end }
	expectEq(Economy.RollReward("Novice", top), 26, "top of the range")
end)

test("vaulted coins: floor(coins * percent / 100), only with a treasure room", function()
	expectEq(Economy.Vaulted(1000, 25, true), 250, "25%")
	expectEq(Economy.Vaulted(999, 33, true), 329, "rounds down (329.67)")
	expectEq(Economy.Vaulted(1000, 100, true), 1000, "all")
	expectEq(Economy.Vaulted(1000, 50, false), 0, "no treasure room")
	expectEq(Economy.Vaulted(1000, 0, true), 0, "0%")
	expectEq(Economy.Vaulted(-5, 50, true), 0, "bad coins")
	expectEq(Economy.Vaulted(100, 0 / 0, true), 0, "nan percent")
end)

test("vault rate and bonus follow the treasure's Exchange, level and Deep Vault", function()
	expectNear(Economy.VaultRate("TreasureRoom", 1, 0), 1.0, 1e-9, "coin cache level 1")
	expectNear(Economy.VaultRate("Strongbox", 1, 0), 1.15, 1e-9, "strongbox")
	expectNear(Economy.VaultRate("DragonHoard", 7, 0), 2.0 * 1.6, 1e-9, "dragon hoard level 7")
	expectNear(Economy.VaultRate("VoidVault", 1, 0), 3.5, 1e-9, "void vault")
	expectNear(Economy.VaultRate("TreasureRoom", 1, 5), 1.25, 1e-9, "deep vault 5")
	expectNear(Economy.VaultRate("Bogus", 1, 0), 1.0, 1e-9, "unknown room has exchange 1")
	expectNear(Economy.VaultBonus(100, 1.0), 100, 1e-9, "100% at rate 1")
	expectNear(Economy.VaultBonus(40, 2.56), 102.4, 1e-9, "40% at 2.56")
	expectEq(Economy.VaultBonus(-1, 1), 0, "bad percent")
	-- Treasure exchange rises with the tier.
	local last = 0
	for _, id in { "TreasureRoom", "Strongbox", "Treasury", "RoyalVault", "DragonHoard", "CelestialCoffer", "VoidVault" } do
		local rate = Economy.VaultRate(id, 1, 0)
		expect(rate > last, id .. " exchange rises")
		last = rate
	end
end)

test("Void Vault halves a theft (TheftScale)", function()
	expectEq(Economy.Theft("Novice", 1000, nil, 0.5), 50, "10% of 1000, halved")
	expectEq(Economy.Theft("ArmoredChallenger", 999, 999, 0.5), 124, "floor(999 * 0.25 * 0.5)")
	expectEq(Economy.Theft("Novice", 1000, nil, nil), 100, "default scale 1")
end)

test("visitor interval: base / (1 + bonus / 100), Lure, Swarm, floored at 5 s", function()
	local t = Balance.Timing
	expectEq(Economy.VisitorInterval(0), t.VisitorInterval, "plain")
	expectNear(Economy.VisitorInterval(100), 15, 1e-9, "+100% halves it")
	expectNear(Economy.VisitorInterval(50, 5), 25 / 1.5, 1e-9, "Lure then bonus")
	expectEq(Economy.VisitorInterval(1000), t.MinVisitorInterval, "floored")
	expectNear(Economy.VisitorInterval(0, 0, 0.5), 15, 1e-9, "Swarm halves")
	expectNear(Economy.VisitorInterval(100, 0, 0.5), 7.5, 1e-9, "Swarm stacks with the bonus")
	expectEq(Economy.VisitorInterval(300, 0, 0.5), t.MinVisitorInterval, "Swarm still floored")
end)

test("theft takes TheftFraction of the vaulted coins, rounded down", function()
	expectEq(Economy.Theft("Novice", 0), 0, "empty vault")
	expectEq(Economy.Theft("Novice", 99), 9, "9.9 rounds down")
	expectEq(Economy.Theft("ArmoredChallenger", 101), 25, "25.25")
	expectEq(Economy.Theft("Practice", 500), 0, "practice steals nothing")
	expectEq(Economy.Theft("Novice", -50), 0, "negative")
	expectEq(Economy.Theft("Nobody", 100), 0, "unknown visitor")
	-- Spawn snapshot: spending lowers the theft, depositing mid-encounter cannot raise it.
	expectEq(Economy.Theft("ArmoredChallenger", 400, 400), 100, "unchanged vault")
	expectEq(Economy.Theft("ArmoredChallenger", 100, 400), 25, "spent down to 100 after spawn")
	expectEq(Economy.Theft("ArmoredChallenger", 4000, 400), 100, "deposit after spawn is not at risk")
	expectEq(Economy.Theft("ArmoredChallenger", 400, 0), 0, "nothing vaulted at spawn")
end)

test("profile vault: only a placed treasure room puts coins at risk", function()
	local p = ProfileSchema.Default()
	p.Coins, p.VaultPercent = 1000, 40
	expectEq(Progression.Vaulted(p), 0, "treasure not placed")
	expectEq(Progression.VaultBonus(p), 0, "no bonus without it")
	p.Layout["3,3"] = "r2" -- Treasure Room after the slime
	expectEq(Progression.Vaulted(p), 400, "40% vaulted")
	expectNear(Progression.VaultBonus(p), 40, 1e-9, "40% bonus at rate 1")
	expectNear(Progression.VisitorInterval(p), 30 / 1.4, 1e-9, "faster visitors")
	expectEq(Economy.Theft("Novice", Progression.Vaulted(p)), 40, "a novice steals 10% of it")
	expectNear(Progression.VisitorInterval(p, { Interval = 0.5 }), 15 / 1.4, 1e-9, "with Swarm")
end)

test("upgrade costs end at the max level", function()
	expectEq(Economy.UpgradeCost(1), Balance.Upgrades.Costs[1], "to level 2")
	expectEq(Economy.UpgradeCost(Economy.MaxLevel()), nil, "max")
	expectEq(Economy.UpgradeCost(0), nil, "zero")
	expectEq(Economy.UpgradeCost(1.5), nil, "fraction")
	expectEq(Economy.UpgradeCost("1"), nil, "string")
end)
