-- Levels (capped by the room definition's rarity), Stout Defenders, Monster Den
-- and Mushroom Cavern scaling in the encounter simulation. Since the 2026-11-05
-- item model there is no per-instance rarity multiplier.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local EncounterSim = require(Server.Rules.EncounterSim)

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

test("stats come from the definition: a passed rarity changes nothing", function()
	local plain = EncounterSim.new({ route = { "GuardRoom" }, visitorId = "Novice" })
	local hacked = EncounterSim.new({ route = { "GuardRoom" }, rarities = { "Secret" }, visitorId = "Novice" } :: any)
	expectEq(plain.Defenders[1].MaxHealth, 80, "guard health")
	expectEq(hacked.Defenders[1].MaxHealth, 80, "rarity ignored")
	expectEq(hacked.Defenders[1].Damage, 12, "damage")
end)

test("levels scale damage and health, capped by the room's tier", function()
	local up = Balance.Upgrades
	for _, id in { "GuardRoom", "BatRoost", "RestlessCrypt", "MimicRoom", "GolemForge", "DragonLair" } do
		local cap = Balance.RarityById[Rooms.Rarity(id)].MaxLevel
		local sim = EncounterSim.new({ route = { id }, levels = { 99 }, visitorId = "Novice" })
		local base = Balance.Rooms[id].DefenderHealth
		expectNear(sim.Defenders[1].MaxHealth, base * (1 + (cap - 1) * up.HealthBonusPerLevel), 1e-9, id .. " health at cap")
		expectNear(
			sim.Defenders[1].Damage,
			Balance.Rooms[id].AttackDamage * (1 + (cap - 1) * up.DamageBonusPerLevel),
			1e-9,
			id .. " damage at cap"
		)
	end
	local spike = EncounterSim.new({ route = { "SpikeHall" }, levels = { 2 }, visitorId = "Novice" })
	expectNear(spike._traps[1].Damage, 15 * (1 + up.DamageBonusPerLevel), 1e-9, "trap")
	expectNear(EncounterSim.DefenderHealth("GuardRoom", 6, 0), 80 * (1 + 2 * up.HealthBonusPerLevel), 1e-9, "common stops at 3")
	expectNear(EncounterSim.DefenderHealth("GoblinBarracks", 1, 0), 50, 1e-9, "first unit")
	expectEq(EncounterSim.DefenderHealth("SpikeHall", 1), nil, "no defender")
	expectEq(EncounterSim.DefenderHealth("TreasureRoom", 1), nil, "treasure has none")
end)

test("Stout Defenders adds to defender health only, for every unit", function()
	local sim = EncounterSim.new({ route = { "SlimeNest", "SpikeHall" }, healthBonus = 0.25, visitorId = "Novice" })
	expectNear(sim.Defenders[1].MaxHealth, 40 * 1.25, 1e-9, "health")
	expectEq(sim.Defenders[1].Damage, 6, "damage unchanged")
	local lich = EncounterSim.new({ route = { "LichSanctum" }, healthBonus = 0.5, visitorId = "Novice" })
	expectNear(lich.Defenders[1].Units[2].Health, 110 * 1.5, 1e-9, "second unit too")
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
	local goblins = EncounterSim.new({ route = { "MonsterDen", "GoblinBarracks" }, visitorId = "Novice" })
	expectNear(goblins.Defenders[2].Units[2].Damage, 9 * (1 + den.DamageBonus), 1e-9, "every unit boosted")
	local mush = Balance.Rooms.MushroomCavern
	local cav = EncounterSim.new({ route = { "MushroomCavern" }, levels = { 2 }, visitorId = "Novice" })
	expectNear(cav._caverns[1].Bonus, mush.TrapDamageBonus + mush.TrapDamageBonusPerLevel, 1e-9, "spore bonus")
end)

test("a fully Common, level-1 layout still beats a T1 Novice", function()
	local sim = run("Novice", { route = { "SlimeNest", "SpikeHall" }, levels = { 1, 1 } })
	expectEq(sim.Result, "Defeated", "common starter layout")
	local guard = run("Novice", { route = { "SlimeNest", "SpikeHall", "GuardRoom" } })
	expectEq(guard.Result, "Defeated", "common layout with a guard")
end)
