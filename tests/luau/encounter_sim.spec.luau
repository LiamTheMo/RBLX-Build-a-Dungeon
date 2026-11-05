local Shared = game:GetService("ReplicatedStorage").Shared
local Balance = require(Shared.Definitions.Balance)
local Grid = require(Shared.Definitions.Grid)
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

test("empty route escapes immediately", function()
	local sim, events = run("Novice", {})
	expectEq(sim.Result, "Escaped", "result")
	expectEq(events[1].Kind, "Spawn", "first event")
	expectEq(events[#events].Kind, "End", "last event")
end)

test("Practice is defeated by a lone Slime Nest", function()
	local sim = run("Practice", { "SlimeNest" })
	expectEq(sim.Result, "Defeated", "result")
	expectEq(sim.Health, 0, "health")
	expectEq(sim.Defenders[1].Down, false, "slime stands")
end)

test("Novice is Defeated by [SlimeNest, SpikeHall]", function()
	expectEq(run("Novice", { "SlimeNest", "SpikeHall" }).Result, "Defeated", "result")
end)

test("Novice Escapes [SpikeHall, SlimeNest]: order matters", function()
	local sim = run("Novice", { "SpikeHall", "SlimeNest" })
	expectEq(sim.Result, "Escaped", "result")
	expect(sim.Health > 0, "alive")
end)

test("Novice reaching [SlimeNest, TreasureRoom] alive robs it", function()
	local sim = run("Novice", { "SlimeNest", "TreasureRoom" })
	expectEq(sim.Result, "Robbed", "result")
	expect(sim.Health > 0, "alive")
end)

test("a defender stops the visitor, then is knocked out and the walk resumes", function()
	local sim, events = run("Novice", { "SlimeNest", "TreasureRoom" })
	expectEq(count(events, "DefenderDown"), 1, "defender down once")
	expectEq(sim.Progress, 2 * Grid.CellSize, "ended at the treasure centre")
	expect(count(events, "Slow") >= 1, "slime slowed the visitor")
	expect(count(events, "End") == 1, "one End event")
end)

test("first attacks land at duel start", function()
	local sim = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Novice" })
	local events = {}
	-- Reach the centre (6 studs at 4 studs/s = 1.5 s), then a hair more.
	for _, e in sim:Step(1.51) do
		table.insert(events, e)
	end
	expectEq(count(events, "Attack"), 2, "one attack each at arrival")
	expectEq(sim.Fighting, 1, "fighting room 1")
	expectEq(sim.Defenders[1].Health, 40 - Balance.Visitors.Novice.AttackDamage, "slime hit")
end)

test("trap strikes follow the cycle from encounter start", function()
	local sim = EncounterSim.new({ route = { "SpikeHall" }, visitorId = "Novice" })
	local strikes = {}
	local t = 0
	-- Single spike hall: the novice reaches its centre at 1.5 s, ending the run.
	while not sim.Result and t < 5 do
		for _, e in sim:Step(0.05) do
			if e.Kind == "Trap" then
				table.insert(strikes, { t = sim.Time, hit = e.Hit })
			end
		end
		t += 0.05
	end
	expectEq(#strikes, 1, "one strike before 1.5 s (the next is at 1.6)")
	expectNear(strikes[1].t, 0.4, 0.06, "first strike")
	expectEq(strikes[1].hit, false, "novice still on the way in at 0.4 s (progress 1.6)")
end)

test("result does not depend on dt, including huge dt", function()
	local routes = {
		{ "SlimeNest", "SpikeHall" },
		{ "SpikeHall", "SlimeNest" },
		{ "SlimeNest", "TreasureRoom" },
		{ "GuardRoom", "SpikeHall", "SlimeNest" },
	}
	for _, route in routes do
		local base = run("Novice", route, nil, 0.05)
		for _, dt in { 0.01, 0.1, 0.37, 1, 30, 1e6 } do
			local sim = run("Novice", route, nil, dt)
			expectEq(sim.Result, base.Result, table.concat(route, ",") .. " at dt " .. dt)
		end
	end
end)

test("Step after the result is a no-op and a bad dt is harmless", function()
	local sim = run("Practice", { "SlimeNest" })
	expectEq(#sim:Step(1), 0, "no events after result")
	local fresh = EncounterSim.new({ route = { "SlimeNest" }, visitorId = "Novice" })
	fresh:Step(0 / 0)
	fresh:Step(-5)
	expectEq(fresh.Result, nil, "still running")
end)

test("levels scale defender health and damage", function()
	local plain = EncounterSim.new({ route = { "GuardRoom" }, visitorId = "Novice" })
	local leveled = EncounterSim.new({ route = { "GuardRoom" }, levels = { 3 }, visitorId = "Novice" })
	local up = Balance.Upgrades
	expectNear(leveled.Defenders[1].MaxHealth, 80 * (1 + 2 * up.HealthBonusPerLevel), 1e-9, "health")
	expectNear(leveled.Defenders[1].Damage, 12 * (1 + 2 * up.DamageBonusPerLevel), 1e-9, "damage")
	expectEq(plain.Defenders[1].MaxHealth, 80, "level 1 unchanged")
end)

test("a higher level can turn a win into a defeat", function()
	local route = { "GuardRoom", "SpikeHall", "SlimeNest" }
	local low = run("Novice", route, { 1, 1, 1 })
	local high = run("Novice", route, { 3, 3, 3 })
	expectEq(high.Result, "Defeated", "upgraded dungeon defeats the novice")
	expect(low.Health >= high.Health, "upgrades never help the visitor")
end)
