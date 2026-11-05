-- Phase 7 systems depth: Monster Den, Mushroom Cavern, Restless Crypt, visitor
-- traits and the combinations they enable.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local EncounterSim = require(game:GetService("ServerScriptService").Server.Rules.EncounterSim)

local function run(visitorId, route, levels, dt)
	local sim = EncounterSim.new({ route = route, levels = levels, visitorId = visitorId })
	local all = {}
	for _ = 1, 4000 do
		for _, e in sim:Step(dt or 0.1) do
			table.insert(all, e)
		end
		if sim.Result then
			break
		end
	end
	return sim, all
end

local function count(events, kind)
	local n = 0
	for _, e in events do
		if e.Kind == kind then
			n += 1
		end
	end
	return n
end

test("Monster Den boosts each adjacent defender once, not others, and never doubles", function()
	local sim, events = run("Novice", { "SlimeNest", "MonsterDen", "GuardRoom", "SpikeHall" })
	local b = Balance.Rooms.MonsterDen
	expectNear(sim.Defenders[1].MaxHealth, 40 * (1 + b.HealthBonus), 1e-9, "slime health")
	expectNear(sim.Defenders[3].Damage, 12 * (1 + b.DamageBonus), 1e-9, "guard damage")
	expectEq(count(events, "DenBoost"), 2, "two boost events")
	local twin = EncounterSim.new({ route = { "MonsterDen", "GuardRoom", "MonsterDen" }, visitorId = "Novice" })
	expectNear(twin.Defenders[2].MaxHealth, 80 * (1 + b.HealthBonus), 1e-9, "two Dens still one bonus")
	local far = EncounterSim.new({ route = { "MonsterDen", "SpikeHall", "GuardRoom" }, visitorId = "Novice" })
	expectEq(far.Defenders[3].MaxHealth, 80, "not adjacent on the route: no bonus")
	local first = EncounterSim.new({ route = { "GuardRoom", "MonsterDen" }, visitorId = "Novice" }):Step(0.1)
	expectEq(first[1].Kind, "Spawn", "Spawn first")
	expectEq(first[2].Kind, "DenBoost", "boost follows Spawn")
	expectEq(first[2].Index, 1, "boosted index")
end)

test("a Monster Den has no defender and does not stop the visitor", function()
	local sim = run("Novice", { "MonsterDen" })
	expectEq(sim.Result, "Escaped", "result")
	expectEq(sim.Defenders[1], nil, "no defender")
end)

test("Mushroom Cavern spores a passing visitor and it takes +50% trap damage", function()
	local sim = EncounterSim.new({ route = { "MushroomCavern", "SpikeHall" }, visitorId = "Scout" })
	local events = {}
	for _ = 1, 200 do
		for _, e in sim:Step(0.05) do
			table.insert(events, e)
		end
		if sim.Result then
			break
		end
	end
	expectEq(count(events, "Spored"), 1, "once per cavern")
	local hit
	for _, e in events do
		if e.Kind == "Trap" and e.Hit then
			hit = e
		end
	end
	expect(hit ~= nil and hit.Spored == true, "spored strike")
	-- Health lost equals the strikes that landed, spored ones scaled by the bonus.
	local spike, bonus = Balance.Rooms.SpikeHall.Damage, Balance.Rooms.MushroomCavern.TrapDamageBonus
	local expected = 0
	for _, e in events do
		if e.Kind == "Trap" and e.Hit then
			expected += spike * (if e.Spored then 1 + bonus else 1)
		end
	end
	expectNear(sim.MaxHealth - sim.Health, expected, 1e-9, "damage matches")
	local _, bare = run("Scout", { "SpikeHall", "SpikeHall" })
	for _, e in bare do
		expect(e.Kind ~= "Trap" or not e.Spored, "no spores without a cavern")
	end
end)

test("spores wear off after SporeDuration", function()
	local sim = EncounterSim.new({ route = { "MushroomCavern", "SlimeNest" }, visitorId = "Cleric" })
	sim:Step(1)
	expectEq(sim.Spored, true, "spored")
	sim:Step(Balance.Rooms.MushroomCavern.SporeDuration + 0.2)
	expectEq(sim.Spored, false, "expired")
end)

test("Restless Crypt rises once at half health, then falls for good", function()
	local sim = EncounterSim.new({ route = { "RestlessCrypt" }, visitorId = "ArmoredChallenger" })
	local risen, downAfterRise = 0, false
	for _ = 1, 400 do
		for _, e in sim:Step(0.05) do
			if e.Kind == "Rise" then
				risen += 1
				expectNear(sim.Defenders[1].Health, sim.Defenders[1].MaxHealth * 0.5, 1e-6, "half health")
			elseif e.Kind == "DefenderDown" then
				downAfterRise = risen == 1
			end
		end
		if sim.Result then
			break
		end
	end
	expectEq(risen, 1, "one Rise")
	expectEq(downAfterRise, true, "Down only after the Rise")
end)

test("Scout is SureFooted and faster than a Novice", function()
	local sim, events = run("Scout", { "SlimeNest" })
	expectEq(count(events, "Slow"), 0, "no slow events")
	expectEq(sim.Slowed, false, "not slowed")
	local novice = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Novice" })
	local scout = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Scout" })
	novice:Step(1)
	scout:Step(1)
	expect(scout.Progress > novice.Progress, "faster")
	expect(count(select(2, run("Novice", { "SlimeNest" })), "Slow") >= 1, "slows still work on a Novice")
end)

test("Cleric heals while walking but not while duelling", function()
	local sim = EncounterSim.new({ route = { "SpikeHall", "SpikeHall", "SlimeNest" }, visitorId = "Cleric" })
	local healed, last = false, sim.Health
	for _ = 1, 400 do
		sim:Step(0.05)
		if sim.Fighting == 0 and sim.Health > last then
			healed = true
		end
		if sim.Fighting > 0 then
			expect(sim.Health <= last + 1e-9, "no healing while duelling")
		end
		expect(sim.Health <= sim.MaxHealth, "never above max")
		last = sim.Health
		if sim.Result then
			break
		end
	end
	expect(healed, "healed while walking")
end)

test("combo: a Den between two slimes turns a Cleric escape into a defeat", function()
	expectEq(run("Cleric", { "SlimeNest", "SlimeNest", "SpikeHall" }).Result, "Escaped", "plain layout loses")
	expectEq(run("Cleric", { "SlimeNest", "MonsterDen", "SlimeNest", "SpikeHall" }).Result, "Defeated", "Den layout wins")
end)

test("combo: Mushroom before spikes defeats a Scout that spikes alone do not", function()
	expectEq(run("Scout", { "SpikeHall", "SpikeHall", "SpikeHall" }).Result, "Escaped", "spikes alone lose")
	expectEq(run("Scout", { "MushroomCavern", "SpikeHall", "SpikeHall", "SpikeHall" }).Result, "Defeated", "with mushroom")
	expectEq(run("Scout", { "SpikeHall", "SpikeHall", "SpikeHall", "MushroomCavern" }).Result, "Escaped", "order matters")
end)

test("combo: a Den between Crypt and Guard defeats the Armored Challenger", function()
	expectEq(run("ArmoredChallenger", { "RestlessCrypt", "GuardRoom" }).Result, "Escaped", "without the Den")
	expectEq(run("ArmoredChallenger", { "RestlessCrypt", "MonsterDen", "GuardRoom" }).Result, "Defeated", "with the Den")
end)

test("no rare room needed: starter and tutorial rooms beat every automatic visitor", function()
	expectEq(run("Novice", { "SlimeNest", "SpikeHall" }).Result, "Defeated", "starter layout beats a Novice")
	for _, v in { "Novice", "Scout", "Cleric" } do
		expectEq(run(v, { "SlimeNest", "SpikeHall", "SlimeNest" }).Result, "Defeated", v)
	end
end)

test("new mechanics do not depend on dt", function()
	for _, case in {
		{ "Scout", { "MushroomCavern", "SpikeHall", "SpikeHall", "SpikeHall" } },
		{ "Cleric", { "SlimeNest", "MonsterDen", "SlimeNest", "SpikeHall" } },
		{ "ArmoredChallenger", { "RestlessCrypt", "MonsterDen", "GuardRoom" } },
	} do
		local base = run(case[1], case[2], nil, 0.05).Result
		for _, dt in { 0.1, 0.5, 1e6 } do
			expectEq(run(case[1], case[2], nil, dt).Result, base, case[1] .. " dt " .. dt)
		end
	end
end)
