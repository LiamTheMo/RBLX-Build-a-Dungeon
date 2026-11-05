-- Profile mutations for loot: drops and XP on a defeat, opening boxes,
-- crafting, scrapping and permanent upgrades.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Loot = require(Server.Rules.Loot)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RoomInventory = require(Server.Rules.RoomInventory)
local Rewards = require(Server.Rules.Rewards)

local NO_BONUS = { Coins = 0, Loot = 0, Xp = 0 }

-- An RNG that returns the given numbers in turn (then 0.5).
local function scripted(values)
	local i = 0
	return {
		NextNumber = function()
			i += 1
			return values[i] or 0.5
		end,
	}
end

test("a defeat grants XP and drops; level-ups grant boxes (Rare every 5th)", function()
	local p = ProfileSchema.Default()
	local r = Rewards.Defeat(p, "Novice", scripted({ 0.01, 0.01, 0 }), NO_BONUS)
	expectEq(r.Xp, 10, "xp")
	expectEq(p.Xp, 10, "stored")
	expectEq(#r.Drops, 2, "box and blueprint")
	expectEq(p.Boxes.Dungeon, 1, "box added")
	local bp = r.Drops[2].RoomId
	expectEq(p.Blueprints[bp], 1, "blueprint added")
	expectEq(r.LevelUp, nil, "no level")
	local miss = Rewards.Defeat(p, "Novice", scripted({ 0.99, 0.99 }), NO_BONUS)
	expectEq(#miss.Drops, 0, "nothing dropped")
	p.Level, p.Xp = 4, 0
	local up = Rewards.Defeat(p, "ArmoredChallenger", scripted({ 0.99, 0.99 }), { Coins = 0, Loot = 0, Xp = 4 })
	-- 30 * 5 = 150 xp from level 4: 125 to reach 5, 25 left.
	expectEq(up.LevelUp, 5, "level 5")
	expectEq(p.Xp, 25, "leftover")
	expectEq(p.Boxes.Rare, 1, "rare box at level 5")
	expectEq(up.Drops[1].Source, "LevelUp", "level drop listed")
	expectEq(up.Drops[1].Type, "Rare", "type")
	local practice = Rewards.Defeat(ProfileSchema.Default(), "Practice", scripted({ 0, 0 }), NO_BONUS)
	expectEq(#practice.Drops, 0, "practice never drops")
	expectEq(practice.Xp, 5, "practice xp")
end)

test("opening a box adds a rolled room and spends the box", function()
	local p = ProfileSchema.Default()
	expectEq(select(2, Rewards.OpenBox(p, "Dungeon", Random.new(1))), "NoBox", "no box")
	expectEq(select(2, Rewards.OpenBox(p, "Gold", Random.new(1))), "BadArgs", "unknown type")
	p.Boxes.Rare = 2
	local ok, data = Rewards.OpenBox(p, "Rare", Random.new(1))
	expect(ok, "opened")
	expectEq(p.Boxes.Rare, 1, "spent")
	local room = p.Rooms[data.InstanceId]
	expectEq(room.Id, data.RoomId, "room stored")
	expectEq(room.Rarity, data.Rarity, "rarity stored")
	expect(data.Rarity ~= "Common", "a Rare Box is never Common")
	expectEq(#room.Perks, Balance.RarityById[data.Rarity].PerkCount, "perks rolled")
	expectEq(room.Level, 1, "level 1")
	expectEq(p.Discovered[data.RoomId], true, "discovered")
	expect(data.Perks ~= room.Perks, "returned perks are a copy")
end)

test("a full inventory leaves the box unopened", function()
	local p = ProfileSchema.Default()
	p.Boxes.Dungeon = 1
	while RoomInventory.Count(p) < RoomInventory.MAX_ROOMS do
		RoomInventory.Add(p, "SlimeNest")
	end
	local ok, reason = Rewards.OpenBox(p, "Dungeon", Random.new(1))
	expectEq(ok, false, "refused")
	expectEq(reason, "TooManyRooms", "reason")
	expectEq(p.Boxes.Dungeon, 1, "box kept")
	expectEq(p.BoxPity, 0, "pity untouched")
end)

test("pity through OpenBox: the 10th box after nine low ones is Rare or better", function()
	local p = ProfileSchema.Default()
	p.Boxes.Dungeon = 10
	-- 0.0 rolls Common every time (first weight), until pity forces Rare+.
	local rng = { NextNumber = function()
		return 0
	end }
	for i = 1, 9 do
		local _, data = Rewards.OpenBox(p, "Dungeon", rng)
		expectEq(data.Rarity, "Common", "box " .. i)
	end
	expectEq(p.BoxPity, 9, "pity counter")
	local _, tenth = Rewards.OpenBox(p, "Dungeon", rng)
	expect(Loot.RarityRank(tenth.Rarity) >= Loot.RarityRank("Rare"), "tenth is Rare+")
	expectEq(p.BoxPity, 0, "reset")
end)

test("crafting needs 5 blueprints, gives a Common room and respects the cap", function()
	local p = ProfileSchema.Default()
	p.Blueprints.GuardRoom = 4
	expectEq(select(2, Rewards.Craft(p, "GuardRoom")), "NotEnoughBlueprints", "4 is not enough")
	p.Blueprints.GuardRoom = 7
	local ok, id = Rewards.Craft(p, "GuardRoom")
	expect(ok, "crafted")
	expectEq(p.Rooms[id].Rarity, "Common", "common")
	expectEq(#p.Rooms[id].Perks, 0, "no perks")
	expectEq(p.Blueprints.GuardRoom, 2, "spent 5")
	p.Blueprints.SpikeHall = 5
	Rewards.Craft(p, "SpikeHall")
	expectEq(p.Blueprints.SpikeHall, nil, "empty stack removed")
	expectEq(select(2, Rewards.Craft(p, "TreasureRoom")), "NotCraftable", "treasure")
	expectEq(select(2, Rewards.Craft(p, "Entrance")), "NotCraftable", "entrance")
	expectEq(select(2, Rewards.Craft(p, "Hacked")), "NotCraftable", "unknown")
	p.Blueprints.MonsterDen = 5
	while RoomInventory.Count(p) < RoomInventory.MAX_ROOMS do
		RoomInventory.Add(p, "SlimeNest")
	end
	expectEq(select(2, Rewards.Craft(p, "MonsterDen")), "TooManyRooms", "full")
	expectEq(p.Blueprints.MonsterDen, 5, "blueprints kept")
end)

test("scrapping: unplaced only, never the Treasure Room, +2 blueprints", function()
	local p = ProfileSchema.Default() -- r1 SlimeNest placed, r2 TreasureRoom unplaced
	expectEq(select(2, Rewards.Scrap(p, "r1")), "RoomPlaced", "placed")
	expectEq(select(2, Rewards.Scrap(p, "r2")), "NotScrappable", "treasure")
	expectEq(select(2, Rewards.Scrap(p, "r99")), "NotOwned", "missing")
	local id = RoomInventory.Add(p, "RestlessCrypt", "Mythic", {})
	local ok, count = Rewards.Scrap(p, id)
	expect(ok, "scrapped")
	expectEq(count, 2, "two blueprints")
	expectEq(p.Rooms[id], nil, "room gone")
	expectEq(p.Blueprints.RestlessCrypt, 2, "stored")
	expectEq(p.Discovered.RestlessCrypt, true, "still discovered")
	expectEq(select(2, Rewards.Scrap(p, id)), "NotOwned", "replayed scrap refused")
end)

test("permanent upgrades: cost, coins, max level", function()
	local p = ProfileSchema.Default()
	expectEq(select(2, Rewards.BuyPermanent(p, "GoldenTouch")), "NotEnoughCoins", "broke")
	expectEq(select(2, Rewards.BuyPermanent(p, "Bogus")), "UnknownUpgrade", "unknown")
	expectEq(select(2, Rewards.BuyPermanent(p, "Order")), "UnknownUpgrade", "not an upgrade")
	p.Coins = 520
	expectEq(select(2, Rewards.BuyPermanent(p, "GoldenTouch")), 1, "level 1")
	expectEq(select(2, Rewards.BuyPermanent(p, "GoldenTouch")), 2, "level 2")
	expectEq(p.Coins, 0, "200 + 320 spent")
	p.Coins = 1e9
	p.Permanent.Scholar = 5
	expectEq(select(2, Rewards.BuyPermanent(p, "Scholar")), "MaxLevel", "max")
	expectEq(p.Coins, 1e9, "nothing charged at max")
end)

test("scrap refuses the last Defender and a full blueprint stack", function()
	local p = ProfileSchema.Default() -- r1 SlimeNest is the only Defender
	p.Layout = {}
	local spike = RoomInventory.Add(p, "SpikeHall")
	expectEq(select(2, Rewards.Scrap(p, "r1")), "LastDefender", "last defender kept")
	expect(p.Rooms.r1 ~= nil, "still owned")
	expect(Rewards.Scrap(p, spike), "a trap room can be scrapped")
	local guard = RoomInventory.Add(p, "GuardRoom")
	expect(Rewards.Scrap(p, "r1"), "scrap one of two defenders")
	expectEq(select(2, Rewards.Scrap(p, guard)), "LastDefender", "now the last one")
	local q = ProfileSchema.Default()
	q.Layout = {}
	RoomInventory.Add(q, "GuardRoom")
	local extra = RoomInventory.Add(q, "GuardRoom")
	q.Blueprints.GuardRoom = Balance.Loot.MaxStack
	expectEq(select(2, Rewards.Scrap(q, extra)), "BlueprintsFull", "cap refuses")
	expect(q.Rooms[extra] ~= nil, "room kept")
end)

test("boxes past the stack cap convert to coins and are flagged", function()
	local p = ProfileSchema.Default()
	p.Boxes.Dungeon = Balance.Loot.MaxStack
	local coins = p.Coins
	local r = Rewards.Defeat(p, "Novice", scripted({ 0.01, 0.99 }), NO_BONUS)
	expectEq(p.Boxes.Dungeon, Balance.Loot.MaxStack, "stack unchanged")
	expectEq(r.Drops[1].Overflow, true, "flagged")
	expectEq(p.Coins, coins + Balance.Loot.BoxOverflowCoins.Dungeon, "converted to coins")
end)

test("box and blueprint drops respect the shop level gates", function()
	local p = ProfileSchema.Default() -- level 1
	local top = scripted({ 0.001, 0.001, 0.999999 })
	local r = Rewards.Defeat(p, "Novice", top, NO_BONUS)
	expectEq(r.Drops[2].RoomId, "GuardRoom", "level 1 blueprint is ungated")
	p.Boxes.Dungeon = 1
	local ok, data = Rewards.OpenBox(p, "Dungeon", { NextNumber = function() return 0.999999 end })
	expect(ok and data.RoomId == "GuardRoom", "box room gated at level 1")
end)
