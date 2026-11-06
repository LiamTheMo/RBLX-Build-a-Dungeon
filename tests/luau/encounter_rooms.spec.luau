-- New room mechanics of the 2026-11-05 roster (Balance.Rooms) and the tier
-- sanity duel. Novice: 60 HP, 10 dmg / 1.0 s, 4 studs/s; rooms are 6 studs, so
-- room i spans (i - 0.5) * 6 .. (i + 0.5) * 6 and a visitor reaches its first
-- defender (room 1's centre) at t = 1.5 s.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local EncounterSim = require(Server.Rules.EncounterSim)

-- Runs to the end; returns the sim and every event (with the sim time it was emitted).
local function run(config, maxSeconds)
	local sim = EncounterSim.new(config)
	local all = {}
	for _ = 1, math.ceil((maxSeconds or 400) / 0.1) do
		for _, e in sim:Step(0.1) do
			e.T = sim.Time
			table.insert(all, e)
		end
		if sim.Result then
			break
		end
	end
	return sim, all
end

local function count(events, kind, filter)
	local n = 0
	for _, e in events do
		if e.Kind == kind and (filter == nil or filter(e)) then
			n += 1
		end
	end
	return n
end

local function first(events, kind)
	for i, e in events do
		if e.Kind == kind then
			return e, i
		end
	end
	return nil, nil
end

local function taken(sim)
	return sim.MaxHealth - sim.Health
end

test("Arrow Gallery: volleys every 0.8 s hit anywhere in the room", function()
	local stats = Balance.Rooms.ArrowGallery
	expectEq(stats.Damage, 8, "8 damage")
	expectEq(stats.Cycle, 0.8, "0.8 s")
	-- In room 1 from t = 0.75 to 2.25: volleys at 1.1 and 1.9 hit (0.3 and 2.7 miss).
	local sim, events = run({ route = { "ArrowGallery", "TreasureRoom" }, visitorId = "Novice" })
	expectEq(count(events, "Trap", function(e) return e.Hit end), 2, "two volleys hit")
	expectNear(sim.Health, 60 - 16, 1e-6, "16 damage")
	expectEq(sim.Result, "Robbed", "reaches the treasure")
end)

test("Bat Roost: 60 HP, 6 damage every 0.4 s", function()
	local sim, events = run({ route = { "BatRoost" }, visitorId = "Novice" })
	expectEq(sim.Defenders[1].MaxHealth, 60, "health")
	-- The Novice needs 6 hits (6 s); ten bites of 6 from 1.5 s fell it first.
	expectEq(count(events, "Attack", function(e) return e.By == "Defender" end), 10, "ten bites")
	expect(sim.Health <= 0, "novice knocked out")
	expectEq(sim.Result, "Defeated", "a lone bat roost beats a Novice")
end)

test("Flame Vent: strike plus Burn ticks (5/s for 3 s); burning blocks Mender", function()
	local route = { "FlameVent", "MonsterDen", "MonsterDen", "TreasureRoom" }
	local sim, events = run({ route = route, visitorId = "Novice" })
	-- Strikes at 0.6 (outside), 2.1 (inside: 10 + burn), 3.6 (outside).
	expectEq(count(events, "Trap", function(e) return e.Hit and e.Burn end), 1, "one burning hit")
	local burns = count(events, "Burn", function(e) return e.Index == 1 and math.abs(e.Damage - 2.5) < 1e-9 end)
	expectEq(burns, 6, "six ticks of 2.5")
	expectNear(sim.Health, 60 - 10 - 15, 1e-6, "10 strike + 15 burn")
	expect(not sim.Burning, "burn over by the end")
	-- Cleric (heals 4/s while walking): no healing while burning (2.1 .. 5.1), then 0.9 s of healing.
	local cleric = run({ route = route, visitorId = "Cleric" })
	expectNear(cleric.Health, 70 - 25 + 0.9 * 4, 0.25, "mender heals only after the burn")
end)

test("Frost Chamber: slows 40% and chills 3/s here and in the next room; Sure-footed only ignores the slow", function()
	local route = { "FrostChamber", "MonsterDen", "TreasureRoom" }
	local sim, events = run({ route = route, visitorId = "Novice" })
	-- 12 studs chilled at 2.4 studs/s = 5 s -> 15 damage; 6.5 s in all.
	expectNear(taken(sim), 15, 0.3, "chill damage over two rooms")
	expectNear(sim.Time, 6.5, 0.1, "slowed through both rooms")
	expectEq(count(events, "Chill"), 1, "one Chill event")
	expectEq(first(events, "Chill").Index, 1, "from the chamber")
	local scout = run({ route = route, visitorId = "Scout" })
	expectNear(taken(scout), 3 * 12 / 6, 0.3, "scout still takes chill damage")
	expectNear(scout.Time, 18 / 6, 0.1, "but walks at full speed")
	-- The strongest slow applies (Slime 75% beats Frost 40%), never both multiplied.
	local mix = EncounterSim.new({ route = { "SlimeNest", "FrostChamber", "TreasureRoom" }, visitorId = "Novice", visitorHealth = 50 })
	-- Slime down at 4.5 s (slow lasts to 10.5 s); the frost room starts at 9 studs.
	while mix.Progress < 10 and mix.Time < 30 do
		mix:Step(0.1)
	end
	expect(mix.Time < 10, "still inside the slime slow")
	local before = mix.Progress
	mix:Step(0.5)
	expectNear(mix.Progress - before, 0.5 * 4 * 0.25, 0.05, "slime slow, not 0.25 * 0.6")
	expect(mix.Slowed and mix.Chilled, "both statuses shown")
end)

test("Goblin Barracks: two goblins, one after the other", function()
	local sim, events = run({ route = { "GoblinBarracks" }, visitorId = "Novice", visitorHealth = 100 })
	local unitEvent = first(events, "Unit")
	expect(unitEvent ~= nil, "second goblin steps in")
	expectEq(unitEvent and unitEvent.Unit, 2, "unit 2")
	expectEq(unitEvent and unitEvent.Name, "Goblin", "a goblin")
	expectEq(count(events, "Unit"), 1, "only two units")
	expectEq(count(events, "DefenderDown"), 1, "down once, after both")
	-- Goblin 1: 1.5 .. 5.5 (5 hits); goblin 2 steps in 0.5 s later: 6.0 .. 10.0 (5 hits).
	expectNear(taken(sim), 90, 1e-6, "ten goblin hits of 9")
	expectEq(sim.Result, "Escaped", "both knocked out")
end)

test("Mimic Room: ambush first strike of 40, then a 70 HP / 10 duel", function()
	local sim, events = run({ route = { "MimicRoom" }, visitorId = "Novice" })
	local ambush, at = first(events, "Ambush")
	expectEq(ambush and ambush.Damage, 40, "ambush damage")
	local firstAttack = first(events, "Attack")
	expect(at ~= nil and firstAttack ~= nil, "events")
	expectEq(sim.Result, "Defeated", "a lone mimic beats a Novice")
	local big, bigEvents = run({ route = { "MimicRoom" }, visitorId = "Novice", visitorHealth = 100 })
	expectEq(count(bigEvents, "Ambush"), 1, "ambush only once")
	-- 40 + bites at 2.5 .. 7.5 (6 x 10) while the visitor needs 7 hits for 70 HP.
	expectNear(taken(big), 100, 1e-6, "ambush plus six bites")
end)

test("Lich Sanctum: summons a skeleton that fights first, then the lich", function()
	local sim, events = run({ route = { "LichSanctum" }, visitorId = "Novice", visitorHealth = 100 })
	local summon, si = first(events, "Summon")
	local unitEvent, ui = first(events, "Unit")
	expectEq(summon and summon.Name, "Skeleton", "summons a skeleton")
	expectEq(unitEvent and unitEvent.Name, "Lich", "then the lich")
	expect(si and ui and si < ui, "skeleton first")
	expectEq(count(events, "Summon"), 1, "one summon")
	expectEq(sim.Defenders[1].Units[1].Health, 40, "skeleton health")
	expectEq(sim.Defenders[1].Units[2].Health, 110, "lich health")
	expectEq(sim.Defenders[1].Name, "Lich", "lich is the last unit")
	expectEq(count(events, "DefenderDown"), 1, "down after the lich")
end)

test("Phoenix Nest: revives the first knocked-out route defender once, at full health", function()
	local sim, events = run({ route = { "GuardRoom", "PhoenixNest" }, visitorId = "Novice", visitorHealth = 100 })
	expectEq(count(events, "Revive"), 1, "exactly one revive")
	local revive = first(events, "Revive")
	expectEq(revive and revive.Index, 1, "the guard (first knocked out)")
	expectEq(revive and revive.By, 2, "by the phoenix")
	expectEq(count(events, "DefenderDown", function(e) return e.Index == 1 end), 1, "guard down for good the second time")
	expectEq(count(events, "DefenderDown", function(e) return e.Index == 2 end), 1, "phoenix not revived again")
	-- The guard took 80 twice: 16 visitor hits before it stays down.
	local hitsOnGuard = count(events, "Attack", function(e) return e.By == "Visitor" and e.Index == 1 end)
	expectEq(hitsOnGuard, 16, "guard fought at full health twice")
	local alone, aloneEvents = run({ route = { "PhoenixNest" }, visitorId = "Novice", visitorHealth = 100 })
	expectEq(count(aloneEvents, "Revive"), 1, "a lone phoenix revives itself once")
	expectEq(first(aloneEvents, "Revive").Index, 1, "itself")
	expectEq(alone.Result, "Escaped", "then stays down")
end)

test("Void Gate: sends the visitor back to the entrance once, keeping its damage; 10/s inside", function()
	local sim, events = run({ route = { "MonsterDen", "VoidGate", "TreasureRoom" }, visitorId = "Novice" })
	expectEq(count(events, "Void"), 1, "once per encounter")
	local void = first(events, "Void")
	expectEq(void and void.Index, 2, "the gate")
	expectNear(void and void.T or 0, 3, 0.06, "at the gate's centre")
	-- 0.75 s inside before the reset, 1.5 s inside on the second pass: 22.5 damage.
	expectNear(taken(sim), 22.5, 0.6, "damage kept across the reset")
	expectNear(sim.Time, 7.5, 0.1, "walked the dungeon twice")
	expectEq(sim.Result, "Robbed", "second pass goes through")
	-- Knocked-out defenders stay down on the second pass.
	local _, again = run({ route = { "BatRoost", "VoidGate", "TreasureRoom" }, visitorId = "Novice", visitorHealth = 3 })
	expectEq(count(again, "DefenderDown"), 1, "bat fought once")
	expectEq(count(again, "Void"), 1, "void once")
end)

test("Dragon Lair: breath hits burn the visitor", function()
	local sim, events = run({ route = { "DragonLair" }, visitorId = "Novice", visitorHealth = 100 }, 60)
	local breath = nil
	for _, e in events do
		if e.Kind == "Attack" and e.By == "Defender" then
			breath = e
			break
		end
	end
	expectEq(breath and breath.Damage, 30, "breath damage")
	expectEq(breath and breath.Burn, true, "breath burns")
	expect(count(events, "Burn", function(e) return e.Index == 1 end) > 0, "burn ticks from the dragon")
	local breaths = count(events, "Attack", function(e) return e.By == "Defender" end)
	local ticks = count(events, "Burn")
	expectNear(taken(sim), breaths * 30 + ticks * 2.5, 1e-6, "damage = breaths + burn ticks")
end)

test("spores raise trap strikes and zones, not burn ticks", function()
	local plain = run({ route = { "MonsterDen", "FrostChamber", "MonsterDen", "TreasureRoom" }, visitorId = "Novice" })
	local spored = run({ route = { "MushroomCavern", "FrostChamber", "MonsterDen", "TreasureRoom" }, visitorId = "Novice" })
	expect(taken(spored) > taken(plain) * 1.2, "chill raised while spored")
end)

-- Standard duel: one room at its tier's max level, then a treasure (so a trap's
-- room is crossed fully), against an unkillable T1 Armored Challenger (14 dmg/s,
-- 3.5 studs/s). Score = damage dealt to the visitor.
local function duelScore(roomId)
	local cap = Balance.RarityById[Rooms.Rarity(roomId)].MaxLevel
	local sim = run({ route = { roomId, "TreasureRoom" }, levels = { cap, 1 }, visitorId = "ArmoredChallenger", visitorHealth = 1000 })
	return taken(sim)
end

test("standard duel: each tier's best room outperforms the tier below (known exceptions printed)", function()
	local best, bestId = {}, {}
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		if def.Placeable then
			local s = duelScore(id)
			if best[def.Rarity] == nil or s > best[def.Rarity] then
				best[def.Rarity], bestId[def.Rarity] = s, id
			end
		end
	end
	local line = {}
	for _, t in Balance.Rarities do
		table.insert(line, string.format("%s %s %.0f", t.Id, bestId[t.Id], best[t.Id]))
	end
	print("    duel scores (max level): " .. table.concat(line, " | "))
	-- Secret has no duelling room (Void Gate is a route effect), so it is skipped.
	local KNOWN = { Secret = true }
	for i = 2, #Balance.Rarities do
		local hi, lo = Balance.Rarities[i].Id, Balance.Rarities[i - 1].Id
		if not KNOWN[hi] then
			expect(best[hi] > best[lo], string.format("%s (%s %.0f) beats %s (%s %.0f)", hi, bestId[hi], best[hi], lo, bestId[lo], best[lo]))
		end
	end
	expect(best.Rare > best.Common, "Rare beats Common too")
	expectEq(bestId.Mythic, "SunfireSanctum", "royal Mythic leads the duel tier")
end)
