-- The rarity table: one ordered, data-driven list in Balance.Rarities. Since the
-- 2026-11-05 item model each room DEFINITION has one fixed rarity.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local Loot = require(Server.Rules.Loot)
local RarityColors = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui.RarityColors)
local ProfileSchema = require(Server.Rules.ProfileSchema)

local TOP = { NextNumber = function() return 0.999999 end }

local function chanceOf(list, id)
	for _, e in list do
		if e.Id == id then
			return e.Chance
		end
	end
	return 0
end

test("both boxes' weights sum to 100", function()
	local dungeon, rare = 0, 0
	for _, r in Balance.Rarities do
		dungeon += r.Weight
		rare += r.RareWeight
	end
	expectNear(dungeon, 100, 1e-9, "dungeon")
	expectNear(rare, 100, 1e-9, "rare box")
end)

test("tiers are strictly ordered and well formed", function()
	local list = Balance.Rarities
	expectEq(list[1].Id, "Common", "Common first")
	expectEq(list[#list].Id, "Secret", "Secret last")
	local seen = {}
	for i, r in list do
		expect(not seen[r.Id], "unique id " .. r.Id)
		seen[r.Id] = true
		expectEq(Balance.RarityById[r.Id], r, "lookup " .. r.Id)
		expectEq(Loot.RarityRank(r.Id), i, "rank " .. r.Id)
		expectEq(r.StatMultiplier, nil, "no stat multiplier any more " .. r.Id)
		expect(r.MaxLevel - 1 <= #Balance.Upgrades.Costs, "upgrade costs cover " .. r.Id)
		expect(RarityColors.Fill[r.Id] ~= nil, "colour for " .. r.Id)
		if i > 1 then
			local lo = list[i - 1]
			expect(r.MaxLevel > lo.MaxLevel, "max level rises at " .. r.Id)
			expect(r.Weight < lo.Weight, "rarer drops less often at " .. r.Id)
			expect(r.CraftCost > lo.CraftCost, "crafting costs more at " .. r.Id)
			expect(r.ScrapReturn >= lo.ScrapReturn, "scrap never shrinks at " .. r.Id)
		end
	end
	for i = 2, #Balance.Upgrades.Costs do
		expect(Balance.Upgrades.Costs[i] > Balance.Upgrades.Costs[i - 1], "costs rise")
	end
end)

test("every room has one known rarity; perks are fixed and grow with the tier", function()
	local maxPerks = {}
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		expect(Balance.RarityById[def.Rarity] ~= nil, id .. " rarity known")
		local kinds = {}
		for _, perk in def.Perks do
			expect(table.find(Balance.Perks.Kinds, perk.Kind) ~= nil, id .. " perk kind")
			expect(perk.Amount > 0 and perk.Amount <= 0.25, id .. " perk modest")
			expect(not kinds[perk.Kind], id .. " distinct kinds")
			kinds[perk.Kind] = true
		end
		local rank = Loot.RarityRank(def.Rarity)
		if rank <= 2 then
			expectEq(#def.Perks, 0, id .. ": Common/Uncommon have no perks")
		end
		maxPerks[rank] = math.max(maxPerks[rank] or 0, #def.Perks)
	end
	expectEq(maxPerks[3], 1, "Rare: one kind")
	expectEq(maxPerks[4], 1, "Epic: one kind")
	expectEq(maxPerks[5], 2, "Legendary: two kinds")
	expectEq(maxPerks[6], 3, "Mythic: three kinds")
	expectEq(maxPerks[7], 3, "Secret: three kinds")
	expect(Balance.RoomPerks.Hacked == nil and Rooms.Get("Hacked") == nil, "no stray ids")
	for id in Balance.RoomPerks do
		expect(Rooms.Get(id) ~= nil, "perks for a real room " .. id)
	end
end)

test("Secret is reachable from both boxes and survives pity", function()
	expect(chanceOf(Loot.Odds("Dungeon").Rarities, "Secret") > 0, "dungeon odds")
	expect(chanceOf(Loot.Odds("Rare").Rarities, "Secret") > 0, "rare box odds")
	expectEq(Loot.RollRarity("Dungeon", 0, TOP), "Secret", "top roll")
	expectEq(Loot.RollRarity("Rare", 0, TOP), "Secret", "top roll, rare box")
	local pity = Loot.Odds("Dungeon", Balance.Loot.PityAfter).Rarities
	expect(chanceOf(pity, "Secret") > 0, "still possible under pity")
	for _, id in { "Common", "Uncommon" } do
		expectEq(chanceOf(pity, id), 0, "pity removes " .. id)
	end
	local rng = Random.new(5)
	for _ = 1, 300 do
		expect(Loot.RarityRank(Loot.RollRarity("Dungeon", 9, rng)) >= Loot.RarityRank("Rare"), "pity is Rare+")
	end
end)

test("an extra tier in an injected table is ranked; a tier without rooms is never rolled", function()
	local tiers = table.clone(Balance.Rarities)
	table.insert(tiers, { Id = "Cosmic", Weight = 0.01, RareWeight = 0.2, MaxLevel = 12, CraftCost = 30, ScrapReturn = 12 })
	expectEq(Loot.RarityRank("Cosmic", tiers), 8, "ranked last")
	expectEq(Loot.RarityRank("Cosmic"), nil, "real table untouched")
	for _, box in Loot.BoxTypes do
		local odds = Loot.Odds(box, 0, nil, tiers)
		expectEq(chanceOf(odds.Rarities, "Cosmic"), 0, box .. ": no room has it, so it is not offered")
		local total = 0
		for _, e in odds.Rarities do
			total += e.Chance
		end
		expectNear(total, 1, 1e-9, box .. " renormalised")
		expectEq(Loot.RollRarity(box, 0, TOP, tiers), "Secret", box .. " rolls only offered tiers")
	end
	expectEq(Loot.NextPity(5, "Cosmic", tiers), 0, "counts as Rare+ for pity")
	expectEq(Loot.NextPity(5, "Cosmic"), 6, "unknown without the table")
end)

test("saved levels are clamped to the definition's tier cap; saved rarity is ignored", function()
	local s = ProfileSchema.Default()
	s.Version = 4
	local n = 2
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		if def.Placeable then
			n += 1
			s.Rooms["r" .. n] = { Id = id, Level = 99, Rarity = "Secret", Perks = { { Kind = "Coins", Amount = 9 } } }
		end
	end
	s.NextSerial = 100
	local p = ProfileSchema.Migrate(s)
	for key, room in p.Rooms do
		local cap = Balance.RarityById[Rooms.Rarity(room.Id)].MaxLevel
		if key ~= "r1" and key ~= "r2" then
			expectEq(room.Level, cap, room.Id .. " capped at its tier")
		end
		expectEq(room.Rarity, nil, room.Id .. " no instance rarity")
		expectEq(room.Perks, nil, room.Id .. " no instance perks")
	end
end)
