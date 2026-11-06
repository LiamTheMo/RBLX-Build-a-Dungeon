-- Server-computed State snapshot fields (Rules/StateView): the client shows these
-- instead of running Loot, Economy or Progression itself.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local Visitors = require(Server.Definitions.Visitors)
local Economy = require(Server.Rules.Economy)
local Loot = require(Server.Rules.Loot)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RoomInventory = require(Server.Rules.RoomInventory)
local StateView = require(Server.Rules.StateView)

local function deepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function profileWith(level, pity)
	local p = ProfileSchema.Default()
	p.Level, p.BoxPity = level, pity
	return p
end

test("BoxOdds equals Loot.Odds(box, pity, level) for that player", function()
	for _, case in { { 1, 0 }, { 3, 4 }, { 5, 9 }, { 8, 0 }, { 100, 9 } } do
		local profile = profileWith(case[1], case[2])
		local view = StateView.Derived(profile)
		for _, box in Loot.BoxTypes do
			local expected = Loot.Odds(box, case[2], case[1])
			expect(deepEqual(view.BoxOdds[box], expected), ("%s box at level %d, pity %d"):format(box, case[1], case[2]))
		end
	end
end)

test("pity changes the odds the snapshot shows", function()
	local fresh = StateView.Derived(profileWith(1, 0)).BoxOdds.Dungeon
	local pity = StateView.Derived(profileWith(1, Balance.Loot.PityAfter)).BoxOdds.Dungeon
	expectEq(fresh.Rarities[1].Id, "Common", "common possible without pity")
	expect(pity.Rarities[1].Id ~= "Common", "pity removes tiers below " .. Balance.Loot.PityRarity)
end)

test("rooms are copies with the definition's Rarity, Perks, MaxLevel and NextUpgradeCost; the profile is untouched", function()
	local profile = ProfileSchema.Default()
	local crypt = RoomInventory.Add(profile, "RestlessCrypt")
	profile.Rooms[crypt].Level = 5 -- Rare max
	local lair = RoomInventory.Add(profile, "DragonLair")
	local view = StateView.Derived(profile)
	for id, room in profile.Rooms do
		local copy = view.Rooms[id]
		local def = Rooms.Get(room.Id)
		expect(copy ~= nil and copy ~= room, "copied " .. id)
		expectEq(copy.Id, room.Id, "same room " .. id)
		expectEq(copy.Rarity, def.Rarity, "definition rarity " .. id)
		expectEq(copy.MaxLevel, Economy.MaxLevel(def.Rarity), "max level " .. id)
		expectEq(#copy.Perks, #def.Perks, "definition perks " .. id)
		expectEq(copy.NextUpgradeCost, Economy.UpgradeCost(room.Level, def.Rarity), "cost " .. id)
		expectEq(room.NextUpgradeCost, nil, "profile not modified " .. id)
		expectEq(room.Rarity, nil, "profile room has no rarity " .. id)
	end
	expectEq(view.Rooms[crypt].NextUpgradeCost, nil, "nil at the tier's max")
	expectEq(view.Rooms[lair].Rarity, "Mythic", "mythic lair")
	expectEq(#view.Rooms[lair].Perks, 3, "three perks")
	expectEq(view.Rooms.r1.NextUpgradeCost, 60, "common slime level 1")
end)

test("BoxOdds lists the rooms inside each tier", function()
	local odds = StateView.Derived(profileWith(10, 0)).BoxOdds.Dungeon
	for _, t in odds.Rarities do
		expect(odds.TierRooms[t.Id] ~= nil and #odds.TierRooms[t.Id] > 0, t.Id .. " rooms listed")
	end
end)

test("permanent next costs match Progression.PermanentCost, nil at max", function()
	local profile = ProfileSchema.Default()
	profile.Permanent = { GoldenTouch = 3, Scholar = Balance.Permanent.Scholar.MaxLevel }
	local view = StateView.Derived(profile)
	for _, id in Balance.Permanent.Order do
		expectEq(view.PermanentNextCost[id], Progression.PermanentCost(id, profile.Permanent[id] or 0), id)
	end
	expectEq(view.PermanentNextCost.Scholar, nil, "max")
end)

test("drop chances include the player's loot bonus", function()
	local profile = ProfileSchema.Default()
	profile.Permanent = { LuckyCharm = 4 }
	local view = StateView.Derived(profile)
	local bonus = Progression.Bonuses(profile).Loot
	expect(bonus > 0, "has a loot bonus")
	for id in Visitors.All do
		expect(deepEqual(view.DropChances[id], Loot.DropChances(id, bonus)), id)
	end
end)

test("vault fields, XP and bonuses match the rules", function()
	local profile = ProfileSchema.Default()
	profile.Coins, profile.VaultPercent, profile.Level = 1234, 50, 4
	profile.Layout["3,3"] = "r2"
	profile.Permanent = { DeepVault = 2 }
	local view = StateView.Derived(profile)
	expectEq(view.VaultPercent, 50, "percent")
	expectEq(view.Vaulted, 617, "vaulted")
	expectEq(view.VaultRisk, 61, "maximum theft from the active roster")
	profile.Rooms.r2.Id = "VoidVault"
	local protected = StateView.Derived(profile)
	expectEq(protected.VaultRisk, 30, "void vault halves the maximum theft")
	profile.Rooms.r2.Id = "TreasureRoom"
	expectNear(view.VaultRate, 1.1, 1e-9, "rate with Deep Vault 2")
	local expectedBonus = 25 * math.log(1 + 617 / 100) / math.log(10) * 1.1
	expectNear(view.VaultBonus, expectedBonus, 1e-9, "bonus percent")
	expectNear(view.VisitorInterval, 30 / (1 + expectedBonus / 100), 1e-9, "interval")
	expectEq(view.XpToNext, Progression.XpToNext(4), "xp to next")
	expect(deepEqual(view.Bonuses, Progression.Bonuses(profile)), "bonuses")
end)

test("threat fields and next unlocks", function()
	local profile = ProfileSchema.Default()
	profile.Level, profile.Threat, profile.Coins = 9, 3, 250
	local view = StateView.Derived(profile)
	expectEq(view.ThreatUnlocked, 3, "level 9 unlocks tier 3")
	expectEq(view.ThreatActive, 1, "tutorial uses tier 1")
	profile.Tutorial.Done = true
	view = StateView.Derived(profile)
	expectEq(view.ThreatActive, 3, "selected tier after the tutorial")
	expectEq(view.NextUnlocks.Threat.Tier, 4, "next tier")
	expectEq(view.NextUnlocks.Threat.Level, 13, "at level 13")
	expect(view.NextUnlocks.ShopRoom == nil, "every shop room unlocked by level 9")
	expectEq(view.NextUnlocks.Permanent.Id, "GoldenTouch", "cheapest permanent (first on a tie)")
	expectEq(view.NextUnlocks.Permanent.Affordable, true, "250 >= 200")
	profile.Level = 1
	view = StateView.Derived(profile, { UnlockAll = true })
	expectEq(view.ThreatUnlocked, 6, "admin override")
	expectEq(view.NextUnlocks.Threat, nil, "nothing left")
	expectEq(view.NextUnlocks.ShopRoom.RoomId, "MushroomCavern", "next shop room")
	expectEq(view.NextUnlocks.ShopRoom.Level, 3, "at level 3")
end)

test("drop tables follow the threat tier and the event; box odds follow Blessed Boxes", function()
	local profile = ProfileSchema.Default()
	profile.Level, profile.Threat, profile.Tutorial.Done = 30, 5, true
	local plain = StateView.Derived(profile)
	local lucky = StateView.Derived(profile, { EventId = "LuckyStars" })
	local novice, luckyNovice = plain.DropTables.Novice, lucky.DropTables.Novice
	expectNear(novice.Drops[1].Chance, 0.06 * 2, 1e-9, "tier 5 box chance (x2)")
	expectNear(luckyNovice.Drops[1].Chance, 0.06 * 4, 1e-9, "Lucky Stars doubles it")
	expectEq(novice.Coins.Min, 54, "18 * 3")
	expectEq(novice.Coins.Max, 78, "26 * 3")
	expectEq(novice.Xp, 26, "10 * 2.6")
	expectEq(lucky.ActiveEvent, "LuckyStars", "event id")
	local blessed = StateView.Derived(profile, { EventId = "BlessedBoxes" })
	local function chance(odds, id)
		for _, e in odds.Rarities do
			if e.Id == id then
				return e.Chance
			end
		end
		return 0
	end
	expect(chance(blessed.BoxOdds.Dungeon, "Epic") > chance(plain.BoxOdds.Dungeon, "Epic") * 1.9, "Epic boosted")
	expect(chance(blessed.BoxOdds.Dungeon, "Common") < chance(plain.BoxOdds.Dungeon, "Common"), "Common lower")
end)
