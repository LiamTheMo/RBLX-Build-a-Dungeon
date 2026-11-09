-- Threat tiers (unlocks, scaling, rosters) and rare visitor variants.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Threat = require(Server.Rules.Threat)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local EncounterSim = require(Server.Rules.EncounterSim)

test("tiers unlock at keeper levels 1, 4, 8, 13, 19, 26", function()
	expectEq(Threat.Count(), 6, "six tiers")
	local cases = { { 1, 1 }, { 3, 1 }, { 4, 2 }, { 7, 2 }, { 8, 3 }, { 13, 4 }, { 19, 5 }, { 25, 5 }, { 26, 6 }, { 100, 6 } }
	for _, c in cases do
		expectEq(Threat.Unlocked(c[1]), c[2], "level " .. c[1])
	end
	expectEq(Threat.Unlocked(1, true), 6, "admin override")
	expect(Threat.Valid(3) and not Threat.Valid(0) and not Threat.Valid(7) and not Threat.Valid(2.5), "valid tiers")
	expect(not Threat.Valid("2") and not Threat.Valid(0 / 0), "non-numbers")
end)

test("scaling per tier: health/damage +35%, coins +50%, XP +40%, drops +25%", function()
	local t1, t4 = Threat.Scale(1), Threat.Scale(4)
	for _, k in { "Health", "Damage", "Coins", "Xp", "Drops" } do
		expectEq(t1[k], 1, "tier 1 " .. k)
	end
	expectNear(t4.Health, 2.05, 1e-9, "health")
	expectNear(t4.Damage, 2.05, 1e-9, "damage")
	expectNear(t4.Coins, 2.5, 1e-9, "coins")
	expectNear(t4.Xp, 2.2, 1e-9, "xp")
	expectNear(t4.Drops, 1.75, 1e-9, "drops")
	expectEq(Threat.Scale(99).Coins, 1, "invalid tier = tier 1")
end)

test("rosters: T1 Novice only, Scout from T2, Cleric from T3, Challenger from T4", function()
	local function ids(tier)
		local out, total = {}, 0
		for _, e in Threat.Roster(tier) do
			out[e.Id] = e.Chance
			total += e.Chance
		end
		expectNear(total, 1, 1e-9, "tier " .. tier .. " sums to 1")
		return out
	end
	expectEq(ids(1).Novice, 1, "T1")
	expect(ids(2).Scout and not ids(2).Cleric, "T2")
	expect(ids(3).Cleric and not ids(3).ArmoredChallenger, "T3")
	expect(ids(4).ArmoredChallenger, "T4")
	expect(ids(6).ArmoredChallenger > ids(4).ArmoredChallenger, "higher tiers shift to tougher visitors")
	expect(ids(6).Novice < ids(2).Novice, "fewer novices")
	for tier = 1, Threat.Count() do
		expect(ids(tier).Practice == nil, "practice never rostered")
	end
	-- Seeded picks follow the weights.
	local rng, n, counts = Random.new(11), 20000, {}
	for _ = 1, n do
		local id = Threat.PickVisitor(4, rng)
		counts[id] = (counts[id] or 0) + 1
	end
	for id, chance in ids(4) do
		expectNear((counts[id] or 0) / n, chance, 0.015, "T4 " .. id)
	end
end)

test("active threat: tier 1 during the tutorial, then the selection clamped to unlocks", function()
	local p = ProfileSchema.Default()
	p.Level, p.Threat = 30, 6
	expectEq(Progression.ActiveThreat(p), 1, "tutorial")
	p.Tutorial.Done = true
	expectEq(Progression.ActiveThreat(p), 6, "selected")
	p.Level = 9
	expectEq(Progression.ActiveThreat(p), 3, "clamped to unlocked")
	expectEq(Progression.ActiveThreat(p, true), 6, "admin override")
end)

test("variant chances: base 5% / 1% / 0.2%, scaled, capped, never Practice", function()
	local base = Threat.VariantChances("Novice", 1)
	expectEq(base[1].Id, "Gilded", "rarest first")
	expectNear(base[1].Chance, 0.002, 1e-12, "gilded")
	expectNear(base[2].Chance, 0.01, 1e-12, "shiny")
	expectNear(base[3].Chance, 0.05, 1e-12, "elite")
	-- Vault bonus 100% (x2 luck) and Rare Invasion (x3).
	local mult = Threat.VariantMultiplier(100, 3)
	expectNear(mult, 6, 1e-9, "multiplier")
	expectNear(Threat.VariantMultiplier(0, 1, 0.25), 1.25, 1e-9, "Dragon Hoard +25%")
	expectNear(Threat.VariantMultiplier(100, 3, 0.25), 6 * 1.25, 1e-9, "stacks")
	expectNear(Threat.VariantMultiplier(0, 1, 0, 0.5), 1.5, 1e-9, "Rare Lure +50%")
	expectNear(Threat.VariantChances("Novice", mult)[3].Chance, 0.30, 1e-9, "elite scaled")
	local huge = Threat.VariantChances("Novice", 1e6)
	expectNear(huge[1].Chance + huge[2].Chance + huge[3].Chance, 1, 1e-9, "never above 1 in total")
	for _, v in Threat.VariantChances("Practice", 100) do
		expectEq(v.Chance, 0, "practice " .. v.Id)
	end
	expectEq(Threat.RollVariant("Practice", 100, { NextNumber = function() return 0 end }), nil, "practice roll")
end)

test("variant rolls match their chances (seeded)", function()
	local mult = Threat.VariantMultiplier(50, 1)
	local rng, n, counts = Random.new(3), 200000, {}
	for _ = 1, n do
		local v = Threat.RollVariant("Scout", mult, rng) or "None"
		counts[v] = (counts[v] or 0) + 1
	end
	for _, v in Threat.VariantChances("Scout", mult) do
		expectNear((counts[v.Id] or 0) / n, v.Chance, math.max(0.002, v.Chance * 0.1), v.Id)
	end
	local edge = { NextNumber = function() return 0.0019 end }
	expectEq(Threat.RollVariant("Novice", 1, edge), "Gilded", "low roll is Gilded")
	expectEq(Threat.RollVariant("Novice", 1, { NextNumber = function() return 0.011 end }), "Shiny", "next band")
	expectEq(Threat.RollVariant("Novice", 1, { NextNumber = function() return 0.5 end }), nil, "normal")
end)

test("variant and threat stats reach the simulation", function()
	local plain = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Novice" })
	local strong = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Novice", visitorHealth = 2.05 * 1.5, visitorDamage = 2.05 })
	expectNear(strong.MaxHealth, plain.MaxHealth * 2.05 * 1.5, 1e-9, "health scaled")
	expectEq(strong.Health, strong.MaxHealth, "starts full")
	local blazing = EncounterSim.new({ route = { "SlimeNest" }, modifiers = { "Blazing" }, visitorId = "Novice" })
	expectNear(blazing.Defenders[1].Damage, plain.Defenders[1].Damage * 1.15, 1e-9, "Blazing +15% damage")
	expectEq(Balance.Variants[1].GuaranteedBox, "Rare", "gilded guarantees a Rare Box")
end)
