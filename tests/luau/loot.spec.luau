-- Loot rules: shown odds, rarity rolls with pity, perks and drop rates.

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

test("shown odds sum to 1 and match the tables", function()
	for _, boxType in Loot.BoxTypes do
		local odds = Loot.Odds(boxType)
		expectNear(sum(odds.Rooms), 1, 1e-9, boxType .. " rooms")
		expectNear(sum(odds.Rarities), 1, 1e-9, boxType .. " rarities")
		expectEq(odds.PityAfter, 9, "pity shown")
	end
	local d = Loot.Odds("Dungeon")
	expectNear(chanceOf(d.Rarities, "Common"), 0.60, 1e-9, "common 60%")
	expectNear(chanceOf(d.Rarities, "Mythic"), 0.0028, 1e-9, "mythic 0.28%")
	expectNear(chanceOf(d.Rarities, "Secret"), 0.0002, 1e-9, "secret 0.02%")
	expectNear(chanceOf(d.Rooms, "SlimeNest"), 0.25, 1e-9, "slime 25%")
	expectNear(chanceOf(d.Rooms, "RestlessCrypt"), 0.08, 1e-9, "crypt 8%")
	expectEq(chanceOf(d.Rooms, "TreasureRoom"), 0, "never a treasure room")
	local r = Loot.Odds("Rare")
	expectEq(chanceOf(r.Rarities, "Common"), 0, "rare box has no Common")
	expectNear(chanceOf(r.Rarities, "Rare"), 0.32, 1e-9, "rare 32%")
	expectEq(Loot.Odds("Gold"), nil, "unknown box")
	for _, e in d.Rooms do
		expect(Rooms.All[e.Id] and Rooms.All[e.Id].Placeable, e.Id .. " placeable")
	end
end)

test("rolls are deterministic for a seed", function()
	local a, b = Random.new(42), Random.new(42)
	for _ = 1, 50 do
		expectEq(Loot.RollRarity("Dungeon", 0, a), Loot.RollRarity("Dungeon", 0, b), "rarity")
		expectEq(Loot.RollRoom(a), Loot.RollRoom(b), "room")
	end
end)

test("rarity frequencies roughly match the odds", function()
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

test("perks: count, size and distinct kinds follow the rarity", function()
	local rng = Random.new(11)
	expectEq(#Loot.RollPerks("Common", rng), 0, "Common has none")
	for _ = 1, 100 do
		local u = Loot.RollPerks("Uncommon", rng)
		expectEq(#u, 1, "Uncommon one")
		expectEq(u[1].Amount, Balance.Perks.Small[u[1].Kind], "small")
		local r = Loot.RollPerks("Rare", rng)
		expectEq(r[1].Amount, Balance.Perks.Medium[r[1].Kind], "medium")
		local e = Loot.RollPerks("Epic", rng)
		expectEq(#e, 2, "Epic two")
		expect(e[1].Kind ~= e[2].Kind, "different kinds")
		expectEq(e[2].Amount, Balance.Perks.Medium[e[2].Kind], "medium")
		local g = Loot.RollPerks("Legendary", rng)
		expectEq(#g, 2, "Legendary two")
		expectEq(g[2].Amount, Balance.Perks.Large[g[2].Kind], "large")
		for id, size in { Mythic = "Large", Secret = "Huge" } do
			local m = Loot.RollPerks(id, rng)
			expectEq(#m, 3, id .. " three")
			local kinds = {}
			for _, perk in m do
				kinds[perk.Kind] = true
				expectEq(perk.Amount, Balance.Perks[size][perk.Kind], id .. " size")
			end
			expectEq(#Balance.Perks.Kinds, 3, "three kinds exist")
			expect(kinds.Coins and kinds.Loot and kinds.Xp, id .. " one of each kind")
		end
	end
	expectEq(Loot.PerkAmount("Common", "Coins"), nil, "no common perk")
	expectEq(Loot.PerkAmount("Mythic", "Loot"), 0.40, "large loot")
	expectEq(Loot.PerkAmount("Secret", "Coins"), 0.30, "huge coins")
	expectEq(Loot.PerkAmount("Secret", "Xp"), 0.60, "huge xp")
	expectEq(Loot.PerkAmount("Rare", "Bogus"), nil, "unknown kind")
	expectEq(Loot.PerkAmount("Order", "Coins"), nil, "not a rarity")
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
					expect(Balance.Loot.BlueprintRooms[d.RoomId] ~= nil, "blueprint is a shop room")
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

test("only placeable non-treasure rooms are craftable", function()
	expect(Loot.Craftable("SlimeNest"), "slime")
	expect(Loot.Craftable("RestlessCrypt"), "crypt")
	expect(not Loot.Craftable("TreasureRoom"), "treasure")
	expect(not Loot.Craftable("Entrance"), "entrance")
	expect(not Loot.Craftable("Hacked"), "unknown")
end)

test("odds honour pity and the shop level gates, and match the rolls", function()
	local fresh = Loot.Odds("Dungeon", 0, 1)
	expectEq(chanceOf(fresh.Rooms, "MushroomCavern"), 0, "gated at level 1")
	expectEq(chanceOf(fresh.Rooms, "RestlessCrypt"), 0, "crypt gated")
	expectNear(sum(fresh.Rooms), 1, 1e-9, "renormalised")
	expectNear(chanceOf(fresh.Rooms, "SlimeNest"), 25 / 70, 1e-9, "slime share")
	local l3 = Loot.Odds("Dungeon", 0, 3)
	expect(chanceOf(l3.Rooms, "MushroomCavern") > 0, "unlocked at 3")
	expectEq(chanceOf(l3.Rooms, "MonsterDen"), 0, "den still gated")
	expect(chanceOf(Loot.Odds("Dungeon", 0, 8).Rooms, "RestlessCrypt") > 0, "crypt at 8")
	local pity = Loot.Odds("Dungeon", 9, 1)
	expectEq(chanceOf(pity.Rarities, "Common"), 0, "pity removes Common")
	expectEq(chanceOf(pity.Rarities, "Uncommon"), 0, "pity removes Uncommon")
	expectNear(sum(pity.Rarities), 1, 1e-9, "pity renormalised")
	-- Rolls use the same list: a scripted roll of ~1 lands in the last shown entry.
	local top = { NextNumber = function() return 0.999999 end }
	local last = pity.Rarities[#pity.Rarities].Id
	expectEq(Loot.RollRarity("Dungeon", 9, top), last, "roll matches odds")
	expectEq(Loot.RollRoom(top, 1), "GuardRoom", "last gated room")
	expectEq(Loot.RollBlueprint(top, 1), "GuardRoom", "blueprint gated at 1")
	expectEq(Loot.RollBlueprint(top, 8), "RestlessCrypt", "blueprint at 8")
end)
