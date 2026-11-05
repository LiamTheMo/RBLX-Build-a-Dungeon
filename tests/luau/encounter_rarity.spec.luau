-- Rarity, room upgrades and Stout Defenders in the encounter simulation.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local EncounterSim = require(game:GetService("ServerScriptService").Server.Rules.EncounterSim)

local function run(visitorId, config)
	config.visitorId = visitorId
	local sim = EncounterSim.new(config)
	for _ = 1, 4000 do
		sim:Step(0.1)
		if sim.Result then
			break
		end
	end
	return sim
end

test("rarity multiplies defender health and damage and trap damage", function()
	local up = Balance.Upgrades
	local mythic = EncounterSim.new({ route = { "GuardRoom" }, rarities = { "Mythic" }, visitorId = "Novice" })
	expectNear(mythic.Defenders[1].MaxHealth, 80 * 1.85, 1e-9, "health")
	expectNear(mythic.Defenders[1].Damage, 12 * 1.85, 1e-9, "damage")
	local rare = EncounterSim.new({ route = { "SpikeHall" }, levels = { 2 }, rarities = { "Rare" }, visitorId = "Novice" })
	expectNear(rare._traps[1].Damage, 15 * (1 + up.DamageBonusPerLevel) * 1.25, 1e-9, "trap")
	local bogus = EncounterSim.new({ route = { "GuardRoom" }, rarities = { "Order" }, visitorId = "Novice" })
	expectEq(bogus.Defenders[1].MaxHealth, 80, "unknown rarity is Common")
end)

test("every tier scales stats by its Balance multiplier and caps levels", function()
	for _, tier in Balance.Rarities do
		local sim = EncounterSim.new({ route = { "GuardRoom" }, levels = { 99 }, rarities = { tier.Id }, visitorId = "Novice" })
		local above = tier.MaxLevel - 1
		expectNear(
			sim.Defenders[1].MaxHealth,
			80 * (1 + above * Balance.Upgrades.HealthBonusPerLevel) * tier.StatMultiplier,
			1e-9,
			tier.Id
		)
	end
end)

test("levels are capped by rarity", function()
	local up = Balance.Upgrades
	local common = EncounterSim.new({ route = { "GuardRoom" }, levels = { 6 }, visitorId = "Novice" })
	expectNear(common.Defenders[1].MaxHealth, 80 * (1 + 2 * up.HealthBonusPerLevel), 1e-9, "common stops at 3")
	local mythic = EncounterSim.new({ route = { "GuardRoom" }, levels = { 6 }, rarities = { "Mythic" }, visitorId = "Novice" })
	expectNear(mythic.Defenders[1].MaxHealth, 80 * (1 + 5 * up.HealthBonusPerLevel) * 1.85, 1e-9, "mythic 6")
	expectNear(EncounterSim.DefenderHealth("GuardRoom", 6, "Common", 0), 80 * (1 + 2 * up.HealthBonusPerLevel), 1e-9, "helper")
	expectEq(EncounterSim.DefenderHealth("SpikeHall", 1), nil, "no defender")
end)

test("Stout Defenders adds to defender health only", function()
	local sim = EncounterSim.new({ route = { "SlimeNest", "SpikeHall" }, healthBonus = 0.25, visitorId = "Novice" })
	expectNear(sim.Defenders[1].MaxHealth, 40 * 1.25, 1e-9, "health")
	expectEq(sim.Defenders[1].Damage, 6, "damage unchanged")
end)

test("upgraded Monster Den and Mushroom Cavern grow their bonus; the strongest Den applies", function()
	local den = Balance.Rooms.MonsterDen
	local sim = EncounterSim.new({ route = { "MonsterDen", "GuardRoom" }, levels = { 3 }, visitorId = "Novice" })
	expectNear(sim.Defenders[2].Damage, 12 * (1 + den.DamageBonus + 2 * den.BonusPerLevel), 1e-9, "den level 3")
	local two =
		EncounterSim.new({ route = { "MonsterDen", "GuardRoom", "MonsterDen" }, levels = { 1, 1, 3 }, visitorId = "Novice" })
	expectNear(two.Defenders[2].MaxHealth, 80 * (1 + den.HealthBonus + 2 * den.BonusPerLevel), 1e-9, "stronger den, once")
	local events = two:Step(0.1)
	expectEq(events[2].Den, 3, "boost credited to the stronger den")
	local mush = Balance.Rooms.MushroomCavern
	local cav =
		EncounterSim.new({ route = { "MushroomCavern" }, levels = { 2 }, rarities = { "Uncommon" }, visitorId = "Novice" })
	expectNear(cav._caverns[1].Bonus, (mush.TrapDamageBonus + mush.TrapDamageBonusPerLevel) * 1.10, 1e-9, "spore bonus")
end)

test("a fully Common, level-1 layout still beats a Novice", function()
	local sim = run("Novice", { route = { "SlimeNest", "SpikeHall" }, levels = { 1, 1 }, rarities = { "Common", "Common" } })
	expectEq(sim.Result, "Defeated", "common starter layout")
end)

test("rarity never helps the visitor", function()
	local route = { "GuardRoom", "SpikeHall", "SlimeNest" }
	local common = run("Cleric", { route = route })
	local mythic = run("Cleric", { route = route, rarities = { "Mythic", "Mythic", "Mythic" } })
	expect(mythic.Result == "Defeated" or mythic.Health <= common.Health, "mythic at least as strong")
end)
