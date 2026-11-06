-- Loot rules: shown odds (tier, then room inside the tier), rolls with pity,
-- blueprint drops, craft and scrap costs by tier, and drop rates.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local Loot = require(Server.Rules.Loot)

local function sum(list)
	local total = 0
	for _, e in list do
		total += e.Chance
	end
	return total
end

local function chanceOf(list, id)
	for _, e in list do
		if e.Id == id then
			return e.Chance
		end
	end
	return 0
end

-- An rng that returns the given numbers in order (then repeats the last).
local function seq(...)
	local values, i = { ... }, 0
	return {
		NextNumber = function()
			i = math.min(i + 1, #values)
			return values[i]
		end,
	}
end

test("shown odds: tier chances and room chances inside each tier sum to 1", function()
	for _, boxType in Loot.BoxTypes do
		local odds = Loot.Odds(boxType)
		expectNear(sum(odds.Rarities), 1, 1e-9, boxType .. " tiers")
		expectNear(sum(odds.Rooms), 1, 1e-9, boxType .. " rooms overall")
		for _, t in odds.Rarities do
			expectNear(sum(odds.TierRooms[t.Id]), 1, 1e-9, boxType .. " rooms inside " .. t.Id)
			for _, e in odds.TierRooms[t.Id] do
				expectEq(Rooms.Rarity(e.Id), t.Id, e.Id .. " belongs to " .. t.Id)
				expectNear(chanceOf(odds.Rooms, e.Id), t.Chance * e.Chance, 1e-12, e.Id .. " overall = tier * share")
			end
		end
		expectEq(odds.PityAfter, 9, "pity shown")
	end
	local d = Loot.Odds("Dungeon")
	expectNear(chanceOf(d.Rarities, "Common"), 0.60, 1e-9, "common 60%")
	expectNear(chanceOf(d.Rarities, "Mythic"), 0.0028, 1e-9, "mythic 0.28%")
	expectNear(chanceOf(d.Rarities, "Secret"), 0.0002, 1e-9, "secret 0.02%")
	expectNear(chanceOf(d.TierRooms.Common, "SlimeNest"), 1 / 3, 1e-9, "common rooms equally likely")
	expectNear(chanceOf(d.Rooms, "SlimeNest"), 0.20, 1e-9, "slime 20% overall")
	expectEq(chanceOf(d.TierRooms.Rare, "Treasury"), 0, "royal room excluded")
	expectNear(chanceOf(d.TierRooms.Secret, "VoidGate"), 1, 1e-9, "dungeon secret room")
	expectEq(chanceOf(d.Rooms, "TreasureRoom"), 0, "never the starter Coin Cache")
	local r = Loot.Odds("Rare")
	expectEq(chanceOf(r.Rarities, "Common"), 0, "rare box has no Common")
	expectEq(r.TierRooms.Common, nil, "no Common room list")
	expectNear(chanceOf(r.Rarities, "Rare"), 0.32, 1e-9, "rare 32%")
	expectEq(Loot.Odds("Gold"), nil, "unknown box")
	for _, e in d.Rooms do
		expect(Rooms.All[e.Id] and Rooms.All[e.Id].Placeable, e.Id .. " placeable")
	end
end)

test("every tier has rooms; every placeable room but the Coin Cache is in the pool", function()
	for _, t in Balance.Rarities do
		expect(#Loot.TierRooms(t.Id) > 0, t.Id .. " has rooms")
	end
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		if def.Placeable and id ~= "TreasureRoom" then
			expect(Loot.Craftable(id), id .. " in the loot pool")
			local dungeon = chanceOf(Loot.Odds("Dungeon").Rooms, id)
			local royal = chanceOf(Loot.Odds("Rare").Rooms, id)
			expect((dungeon > 0) ~= (royal > 0), id .. " belongs to exactly one chest")
			expect(chanceOf(Loot.BlueprintOdds(nil), id) > 0, id .. " remains craftable via blueprints")
		end
	end
end)

test("each chest rolls only its shown room pool, including pity", function()
	for _, boxType in Loot.BoxTypes do
		for _, pity in { 0, Balance.Loot.PityAfter } do
			local odds = Loot.Odds(boxType, pity, 50)
			local rng = Random.new(501 + pity)
			for _ = 1, 2000 do
				local tier, id = Loot.RollBox(boxType, pity, rng, 50)
				expect(id ~= nil and chanceOf(odds.Rooms, id) > 0, boxType .. " roll is displayed")
				expectEq(Rooms.Rarity(id), tier, "rolled tier matches room")
			end
		end
	end
end)

test("rolls are deterministic for a seed and match the tier", function()
	local a, b = Random.new(42), Random.new(42)
	for _ = 1, 50 do
		local ta, ra = Loot.RollBox("Dungeon", 0, a, 10)
		local tb, rb = Loot.RollBox("Dungeon", 0, b, 10)
		expectEq(ta, tb, "tier")
		expectEq(ra, rb, "room")
		expectEq(Rooms.Rarity(ra), ta, "room of the rolled tier")
	end
	expectEq(Loot.RollBox("Gold", 0, a), nil, "unknown box")
end)

test("tier frequencies roughly match the odds", function()
	local rng, n, counts = Random.new(7), 20000, {}
	for _ = 1, n do
		local r = Loot.RollRarity("Dungeon", 0, rng)
		counts[r] = (counts[r] or 0) + 1
	end
	expectNear(counts.Common / n, 0.60, 0.015, "common")
	expectNear(counts.Uncommon / n, 0.25, 0.015, "uncommon")
	expectNear(counts.Rare / n, 0.10, 0.01, "rare")
	expectNear((counts.Epic or 0) / n, 0.035, 0.006, "epic")
end)

test("room frequencies inside a tier match the shown shares", function()
	local rng, n, counts = Random.new(17), 14000, {}
	for _ = 1, n do
		local id = Loot.RollRoom("Rare", rng, 50, "Dungeon")
		counts[id] = (counts[id] or 0) + 1
	end
	local shown = Loot.Odds("Dungeon", 0, 50).TierRooms.Rare
	for _, e in shown do
		expectNear((counts[e.Id] or 0) / n, e.Chance, 0.015, e.Id)
	end
end)

test("pity: after 9 boxes below Rare the next is at least Rare, then resets", function()
	local rng = Random.new(3)
	for _ = 1, 500 do
		local r = Loot.RollRarity("Dungeon", Balance.Loot.PityAfter, rng)
		expect(Loot.RarityRank(r) >= Loot.RarityRank("Rare"), "guaranteed Rare+, got " .. tostring(r))
	end
	expectEq(Loot.NextPity(0, "Common"), 1, "counts up")
	expectEq(Loot.NextPity(8, "Uncommon"), 9, "reaches pity")
	expectEq(Loot.NextPity(9, "Common"), 9, "never above PityAfter")
	expectEq(Loot.NextPity(9, "Rare"), 0, "Rare resets")
	expectEq(Loot.NextPity(4, "Mythic"), 0, "Mythic resets")
	expectEq(Loot.NextPity(9, "Epic"), 0, "Epic resets")
	-- Simulated streak: no run of 10 below Rare ever happens.
	local pity, streak, worst = 0, 0, 0
	for _ = 1, 5000 do
		local r = Loot.RollRarity("Dungeon", pity, rng)
		pity = Loot.NextPity(pity, r)
		streak = if Loot.RarityRank(r) >= 3 then 0 else streak + 1
		worst = math.max(worst, streak)
	end
	expect(worst <= 9, "longest streak below Rare " .. worst)
end)

test("craft cost and scrap return come from the room's tier", function()
	local expected = {
		Common = { 5, 2 }, Uncommon = { 6, 3 }, Rare = { 8, 4 }, Epic = { 10, 5 },
		Legendary = { 12, 6 }, Mythic = { 15, 8 }, Secret = { 20, 10 },
	}
	for _, t in Balance.Rarities do
		expectEq(t.CraftCost, expected[t.Id][1], t.Id .. " craft")
		expectEq(t.ScrapReturn, expected[t.Id][2], t.Id .. " scrap")
		expect(t.ScrapReturn < t.CraftCost, t.Id .. " scrapping never pays for a craft")
	end
	expectEq(Loot.CraftCost("SlimeNest"), 5, "common room")
	expectEq(Loot.CraftCost("GoblinBarracks"), 10, "epic room")
	expectEq(Loot.ScrapReturn("VoidGate"), 10, "secret room")
	expectEq(Loot.ScrapReturn("Strongbox"), 3, "uncommon treasure")
	expectEq(Loot.CraftCost("TreasureRoom"), nil, "coin cache not craftable")
	expectEq(Loot.ScrapReturn("Entrance"), nil, "entrance")
end)

test("drop rates roughly match over many seeded rolls; loot bonus scales them", function()
	local function rates(visitorId, bonus, seed)
		local rng, n, box, bp, boxType = Random.new(seed), 20000, 0, 0, nil
		for _ = 1, n do
			for _, d in Loot.RollDrops(visitorId, bonus, rng) do
				if d.Kind == "Box" then
					box += 1
					boxType = d.Type
				else
					bp += 1
					expect(Loot.Craftable(d.RoomId), "blueprint is craftable")
				end
			end
		end
		return box / n, bp / n, boxType
	end
	local box, bp = rates("Novice", 0, 5)
	expectNear(box, 0.06, 0.008, "novice box")
	expectNear(bp, 0.12, 0.01, "novice blueprint")
	box, bp = rates("Novice", 1, 6)
	expectNear(box, 0.12, 0.01, "doubled box")
	expectNear(bp, 0.24, 0.012, "doubled blueprint")
	local boxType
	box, bp, boxType = rates("ArmoredChallenger", 0, 8)
	expectNear(box, 0.25, 0.015, "challenger box")
	expectEq(boxType, "Rare", "challenger drops a Rare Box")
	box, bp = rates("Practice", 1, 9)
	expectEq(box + bp, 0, "practice drops nothing")
	expectEq(#Loot.RollDrops("Nobody", 0, Random.new(1)), 0, "unknown visitor")
	expectEq(Loot.DropChances("Scout", 100).Box, 1, "chance capped at 1")
end)

test("blueprint drops: tier by Dungeon weights, then a room of it", function()
	local odds = Loot.BlueprintOdds(nil)
	expectNear(sum(odds), 1, 1e-9, "sums to 1")
	expectNear(chanceOf(odds, "GuardRoom"), 0.60 / 3, 1e-9, "common share")
	expectNear(chanceOf(odds, "VoidGate"), 0.0002 * (1 / 1.5), 1e-12, "secret share")
	local rng, n, rare = Random.new(23), 20000, 0
	for _ = 1, n do
		if Rooms.Rarity(Loot.RollBlueprint(rng, 50)) == "Rare" then
			rare += 1
		end
	end
	expectNear(rare / n, 0.10, 0.01, "rare blueprints ~10%")
end)

test("only rooms in the loot pool are craftable (never the Coin Cache)", function()
	expect(Loot.Craftable("SlimeNest"), "slime")
	expect(Loot.Craftable("RestlessCrypt"), "crypt")
	expect(Loot.Craftable("VoidVault"), "rarer treasures are craftable")
	expect(not Loot.Craftable("TreasureRoom"), "coin cache")
	expect(not Loot.Craftable("Entrance"), "entrance")
	expect(not Loot.Craftable("Hacked"), "unknown")
end)

test("odds honour pity and the shop gates (Common/Uncommon only), and match the rolls", function()
	local fresh = Loot.Odds("Dungeon", 0, 1)
	expectEq(chanceOf(fresh.TierRooms.Uncommon, "BatRoost"), 0, "bat gated at level 1")
	expectEq(chanceOf(fresh.TierRooms.Uncommon, "MushroomCavern"), 1, "lowest-gated Uncommon is the fallback")
	expect(chanceOf(fresh.TierRooms.Rare, "MonsterDen") > 0, "Rare rooms are never gated")
	expectNear(sum(fresh.Rooms), 1, 1e-9, "renormalised")
	local l4 = Loot.Odds("Dungeon", 0, 4)
	expectNear(chanceOf(l4.TierRooms.Uncommon, "BatRoost"), 0.5, 1e-9, "bat at 4 (with the mushroom)")
	expectEq(chanceOf(l4.TierRooms.Uncommon, "Strongbox"), 0, "strongbox still gated")
	local l6 = Loot.Odds("Dungeon", 0, 6)
	expectEq(chanceOf(l6.TierRooms.Uncommon, "Strongbox"), 0, "strongbox belongs to royal")
	local royal = Loot.Odds("Rare", 0, 6)
	expectNear(chanceOf(royal.TierRooms.Uncommon, "Strongbox"), 0.5 / 1.5, 1e-9, "royal strongbox at 6")
	local pity = Loot.Odds("Dungeon", 9, 1)
	expectEq(chanceOf(pity.Rarities, "Common"), 0, "pity removes Common")
	expectEq(chanceOf(pity.Rarities, "Uncommon"), 0, "pity removes Uncommon")
	expectNear(sum(pity.Rarities), 1, 1e-9, "pity renormalised")
	-- Rolls use the same lists: a scripted roll of ~1 lands in the last shown entry.
	local top = seq(0.999999)
	local last = pity.Rarities[#pity.Rarities].Id
	expectEq(Loot.RollRarity("Dungeon", 9, top), last, "roll matches odds")
	expectEq(Loot.RollRoom("Common", top, 1), "GuardRoom", "last common room")
	expectEq(Loot.RollRoom("Uncommon", top, 1), "MushroomCavern", "uncommon gated at 1")
	expectEq(Loot.RollRoom("Uncommon", top, 6), "Strongbox", "uncommon at 6")
	expectEq(Loot.RollBlueprint(seq(0, 0.999999), 1), "GuardRoom", "common blueprint")
	expectEq(Loot.RollBlueprint(seq(0.7, 0), 1), "MushroomCavern", "uncommon blueprint gated at 1")
	expectEq(Loot.RollBlueprint(seq(0.7, 0.999999), 5), "BatRoost", "uncommon blueprint at 5: last unlocked")
end)
