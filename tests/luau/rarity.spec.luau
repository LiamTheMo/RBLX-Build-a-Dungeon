-- The rarity table: one ordered, data-driven list in Balance.Rarities.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
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
		expect(Balance.Perks[r.PerkSize] ~= nil, "perk size exists for " .. r.Id)
		expect(r.PerkCount <= #Balance.Perks.Kinds, "perk kinds suffice for " .. r.Id)
		expect(r.MaxLevel - 1 <= #Balance.Upgrades.Costs, "upgrade costs cover " .. r.Id)
		expect(RarityColors.Fill[r.Id] ~= nil, "colour for " .. r.Id)
		if i > 1 then
			local lo = list[i - 1]
			expect(r.StatMultiplier > lo.StatMultiplier, "stat rises at " .. r.Id)
			expect(r.MaxLevel > lo.MaxLevel, "max level rises at " .. r.Id)
			expect(r.Weight < lo.Weight, "rarer drops less often at " .. r.Id)
			expect(r.PerkCount >= lo.PerkCount, "perks never shrink at " .. r.Id)
		end
	end
	for i = 2, #Balance.Upgrades.Costs do
		expect(Balance.Upgrades.Costs[i] > Balance.Upgrades.Costs[i - 1], "costs rise")
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

test("an extra tier in an injected table needs no code changes", function()
	local tiers = table.clone(Balance.Rarities)
	table.insert(tiers, {
		Id = "Cosmic", Weight = 0.01, RareWeight = 0.2, StatMultiplier = 3, MaxLevel = 12, PerkCount = 3, PerkSize = "Huge",
	})
	expectEq(Loot.RarityRank("Cosmic", tiers), 8, "ranked last")
	expectEq(Loot.RarityRank("Cosmic"), nil, "real table untouched")
	for _, box in Loot.BoxTypes do
		local odds = Loot.Odds(box, 0, nil, tiers)
		expect(chanceOf(odds.Rarities, "Cosmic") > 0, box .. " lists it")
		local total = 0
		for _, e in odds.Rarities do
			total += e.Chance
		end
		expectNear(total, 1, 1e-9, box .. " renormalised")
		expectEq(Loot.RollRarity(box, 0, TOP, tiers), "Cosmic", box .. " rolls it")
	end
	expectEq(Loot.NextPity(5, "Cosmic", tiers), 0, "counts as Rare+ for pity")
	expectEq(Loot.NextPity(5, "Cosmic"), 6, "unknown without the table")
	local perks = Loot.RollPerks("Cosmic", Random.new(1), tiers)
	expectEq(#perks, 3, "perks")
	expectEq(perks[1].Amount, Balance.Perks.Huge[perks[1].Kind], "size")
end)

test("saved rarities validate against the list; unknown ones become Common", function()
	local s = ProfileSchema.Default()
	local n = 2
	for _, tier in Balance.Rarities do
		n += 1
		s.Rooms["r" .. n] = { Id = "SlimeNest", Level = 99, Rarity = tier.Id, Perks = {} }
	end
	s.Rooms.r90 = { Id = "SlimeNest", Level = 99, Rarity = "Cosmic", Perks = {} }
	s.NextSerial = 100
	local p = ProfileSchema.Migrate(s)
	n = 2
	for _, tier in Balance.Rarities do
		n += 1
		expectEq(p.Rooms["r" .. n].Rarity, tier.Id, "kept " .. tier.Id)
		expectEq(p.Rooms["r" .. n].Level, tier.MaxLevel, "capped " .. tier.Id)
	end
	expectEq(p.Rooms.r90.Rarity, "Common", "unknown")
	expectEq(p.Rooms.r90.Level, 3, "unknown capped as Common")
end)
