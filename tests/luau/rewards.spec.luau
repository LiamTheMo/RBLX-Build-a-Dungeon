-- Profile mutations for loot: drops and XP on a defeat, opening boxes,
-- crafting, scrapping and permanent upgrades.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Rooms = require(Server.Definitions.Rooms)
local Loot = require(Server.Rules.Loot)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RoomInventory = require(Server.Rules.RoomInventory)
local Rewards = require(Server.Rules.Rewards)
local Progression = require(Server.Rules.Progression)

-- A threat-1, no-event reward context with the given bonuses.
local function ctxWith(bonuses)
	local c = Rewards.Context(ProfileSchema.Default())
	c.Bonuses = bonuses
	return c
end
local NO_BONUS = ctxWith({ Coins = 0, Loot = 0, Xp = 0 })

test("exhausted room serials reject batches and crafting without spending", function()
	local p = ProfileSchema.Default()
	p.NextSerial = RoomInventory.MAX_SERIAL - 1
	p.Coins, p.BoxPity, p.Boxes.Dungeon = 123, 4, 2
	p.Blueprints.RestlessCrypt = Loot.CraftCost("RestlessCrypt")
	local rooms = RoomInventory.Count(p)
	local ok, reason = Rewards.OpenBoxes(p, "Dungeon", 2, Random.new(1))
	expectEq(ok, false, "batch refused")
	expectEq(reason, "RoomIdsExhausted", "batch reason")
	expectEq(p.Boxes.Dungeon, 2, "boxes preserved")
	expectEq(p.BoxPity, 4, "pity preserved")
	expectEq(p.Coins, 123, "coins preserved")
	expectEq(RoomInventory.Count(p), rooms, "rooms preserved")
	p.NextSerial = RoomInventory.MAX_SERIAL
	local blueprints = p.Blueprints.RestlessCrypt
	local crafted, craftReason = Rewards.Craft(p, "RestlessCrypt")
	expectEq(crafted, false, "craft refused")
	expectEq(craftReason, "RoomIdsExhausted", "craft reason")
	expectEq(p.Blueprints.RestlessCrypt, blueprints, "blueprints preserved")
end)

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

test("coin rewards and overflow conversions respect the saved balance cap", function()
	local p = ProfileSchema.Default()
	p.Coins = ProfileSchema.MAX_MONEY - 5
	local result = Rewards.Defeat(p, "Novice", scripted({ 0.99, 0.99 }), NO_BONUS, 20)
	expectEq(result.Amount, 5, "actual reward")
	expectEq(result.Capped, true, "cap reported")
	expectEq(p.Coins, ProfileSchema.MAX_MONEY, "balance capped")
	expectEq(ProfileSchema.Migrate(p).Coins, p.Coins, "rejoin keeps balance")
	expectEq(Rewards.Defeat(p, "Novice", scripted({ 0.99, 0.99 }), NO_BONUS, 20).Amount, 0, "full wallet")

	local q = ProfileSchema.Default()
	q.Coins, q.Boxes.Dungeon = ProfileSchema.MAX_MONEY - 150, Balance.Loot.MaxStack
	local converted, credited = Rewards.GiveBoxes(q, "Dungeon", 2)
	expectEq(converted, 2, "both stacks overflowed")
	expectEq(credited, 150, "actual converted coins")
	expectEq(q.Coins, ProfileSchema.MAX_MONEY, "conversion capped")

	local level = ProfileSchema.Default()
	level.Level, level.Xp = 9, Progression.XpToNext(9) - 1
	level.Coins = ProfileSchema.MAX_MONEY - 50
	level.Boxes.Rare, level.Boxes.Crystal = Balance.Loot.MaxStack, Balance.Loot.MaxStack
	local _, drops = Rewards.GrantXp(level, 1)
	expectEq(#drops, 2, "level and crystal rewards")
	expectEq(drops[1].OverflowCoins + drops[2].OverflowCoins, 50, "actual level conversions")
	expectEq(level.Coins, ProfileSchema.MAX_MONEY, "level conversions capped")
end)

test("a defeat grants XP and drops; level-ups grant boxes (Rare every 5th)", function()
	local p = ProfileSchema.Default()
	local r = Rewards.Defeat(p, "Novice", scripted({ 0.01, 0.01, 0 }), NO_BONUS, 20)
	expectEq(r.Xp, 10, "xp")
	expectEq(r.Amount, 20, "base coins at threat 1")
	expectEq(p.Coins, 20, "coins paid straight to Coins")
	expectEq(p.Xp, 10, "stored")
	expectEq(#r.Drops, 2, "box and blueprint")
	expectEq(p.Boxes.Dungeon, 1, "box added")
	local bp = r.Drops[2].RoomId
	expectEq(p.Blueprints[bp], 1, "blueprint added")
	expectEq(r.LevelUp, nil, "no level")
	local miss = Rewards.Defeat(p, "Novice", scripted({ 0.99, 0.99 }), NO_BONUS, 20)
	expectEq(#miss.Drops, 0, "nothing dropped")
	p.Level, p.Xp = 4, 0
	local up = Rewards.Defeat(p, "ArmoredChallenger", scripted({ 0.99, 0.99 }), ctxWith({ Coins = 0, Loot = 0, Xp = 4 }), 50)
	-- 30 * 5 = 150 xp from level 4: 125 to reach 5, 25 left.
	expectEq(up.LevelUp, 5, "level 5")
	expectEq(p.Xp, 25, "leftover")
	expectEq(p.Boxes.Rare, 1, "rare box at level 5")
	expectEq(up.Drops[1].Source, "LevelUp", "level drop listed")
	expectEq(up.Drops[1].Type, "Rare", "type")
	local practice = Rewards.Defeat(ProfileSchema.Default(), "Practice", scripted({ 0, 0 }), NO_BONUS, 10)
	expectEq(#practice.Drops, 0, "practice never drops")
	expectEq(practice.Xp, 5, "practice xp")
end)

test("crystal milestone awards, saves and opens without replacing the royal chest", function()
	local p = ProfileSchema.Default()
	p.Level, p.Xp = 9, 0
	local _, drops = Rewards.GrantXp(p, 10000)
	expect(p.Boxes.Rare > 0 and p.Boxes.Crystal > 0, "both rewards")
	local loaded = ProfileSchema.Migrate(p)
	expectEq(loaded.Boxes.Crystal, p.Boxes.Crystal, "saved crystal count")
	local before = loaded.Boxes.Crystal
	local ok = Rewards.OpenBox(loaded, "Crystal", Random.new(1))
	expect(ok, "opened")
	expectEq(loaded.Boxes.Crystal, before - 1, "spent once")
end)

test("opening a box adds a room of the rolled tier and spends the box", function()
	local p = ProfileSchema.Default()
	expectEq(select(2, Rewards.OpenBox(p, "Dungeon", Random.new(1))), "NoBox", "no box")
	expectEq(select(2, Rewards.OpenBox(p, "Gold", Random.new(1))), "BadArgs", "unknown type")
	p.Boxes.Rare = 2
	local ok, data = Rewards.OpenBox(p, "Rare", Random.new(1))
	expect(ok, "opened")
	expectEq(p.Boxes.Rare, 1, "spent")
	local room = p.Rooms[data.InstanceId]
	expectEq(room.Id, data.RoomId, "room stored")
	expectEq(Rooms.Rarity(room.Id), data.Rarity, "room of the rolled tier")
	expect(Loot.Odds("Rare").TierRooms[data.Rarity] ~= nil, "rolled tier is offered")
	expectEq(room.Rarity, nil, "instance stores no rarity")
	expectEq(room.Perks, nil, "instance stores no perks")
	expectEq(#data.Perks, #Rooms.Get(room.Id).Perks, "returned perks are the definition's")
	expect(data.Perks ~= Rooms.Get(room.Id).Perks, "a copy")
	expectEq(room.Level, 1, "level 1")
	expectEq(p.Discovered[data.RoomId], true, "discovered")
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

test("bulk box opening is bounded, all-or-nothing, and advances pity per box", function()
	local p = ProfileSchema.Default()
	p.Boxes.Dungeon = 3
	local rng = { NextNumber = function() return 0 end }
	local ok, opened = Rewards.OpenBoxes(p, "Dungeon", 2, rng)
	expect(ok, "opened batch")
	expectEq(#opened, 2, "result count")
	expectEq(p.Boxes.Dungeon, 1, "spent exactly two")
	expectEq(p.BoxPity, 2, "pity advanced for each")
	local boxes, pity, rooms = p.Boxes.Dungeon, p.BoxPity, RoomInventory.Count(p)
	expectEq(select(2, Rewards.OpenBoxes(p, "Dungeon", 2, rng)), "NoBox", "insufficient stock")
	expectEq(p.Boxes.Dungeon, boxes, "stock unchanged")
	expectEq(p.BoxPity, pity, "pity unchanged")
	expectEq(RoomInventory.Count(p), rooms, "rooms unchanged")
	expectEq(select(2, Rewards.OpenBoxes(p, "Dungeon", 31, rng)), "BadArgs", "request cap")
	p.Boxes.Dungeon = 1
	while RoomInventory.Count(p) < RoomInventory.MAX_ROOMS do RoomInventory.Add(p, "SpikeHall") end
	local pityBeforeFull, boxesBeforeFull = p.BoxPity, p.Boxes.Dungeon
	expectEq(select(2, Rewards.OpenBoxes(p, "Dungeon", 1, rng)), "TooManyRooms", "capacity checked")
	expectEq(p.BoxPity, pityBeforeFull, "full capacity leaves pity unchanged")
	expectEq(p.Boxes.Dungeon, boxesBeforeFull, "full capacity leaves box")
end)

test("bulk room sale is all-or-nothing, pays rarity values, and keeps one defender", function()
	local p = ProfileSchema.Default()
	p.Layout = {}
	local common = RoomInventory.Add(p, "SpikeHall")
	local rare = RoomInventory.Add(p, "RestlessCrypt")
	local coins = p.Coins
	local ok, receipt = Rewards.SellRooms(p, { common, rare })
	expect(ok, "sold batch")
	expectEq(receipt.Coins, 125, "Common plus Rare provisional sale values")
	expectEq(p.Coins, coins + 125, "coins credited")
	expectEq(p.Rooms[common], nil, "common removed")
	expectEq(p.Rooms[rare], nil, "rare removed")
	expectEq(p.Rooms.r1 ~= nil, true, "last defender retained")
	local guard = RoomInventory.Add(p, "GuardRoom")
	local before = p.Coins
	expectEq(select(2, Rewards.SellRooms(p, { guard, "missing" })), "NotOwned", "invalid batch refused")
	expectEq(p.Rooms[guard] ~= nil, true, "valid entry retained on refusal")
	expectEq(p.Coins, before, "no partial payout")
	expectEq(select(2, Rewards.SellRooms(p, { "r1", guard })), "LastDefender", "last defender protected")
	expectEq(select(2, Rewards.SellRooms(p, { guard, guard })), "BadArgs", "duplicate rejected")
end)

test("crafting costs the tier's blueprints and respects the cap", function()
	local p = ProfileSchema.Default()
	p.Blueprints.GuardRoom = 4
	expectEq(select(2, Rewards.Craft(p, "GuardRoom")), "NotEnoughBlueprints", "4 is not enough")
	p.Blueprints.GuardRoom = 7
	local ok, id = Rewards.Craft(p, "GuardRoom")
	expect(ok, "crafted")
	expectEq(p.Rooms[id].Id, "GuardRoom", "room")
	expectEq(p.Rooms[id].Rarity, nil, "no instance rarity")
	expectEq(p.Blueprints.GuardRoom, 2, "spent 5 (Common)")
	p.Blueprints.GoblinBarracks = 9
	expectEq(select(2, Rewards.Craft(p, "GoblinBarracks")), "NotEnoughBlueprints", "Epic needs 10")
	p.Blueprints.GoblinBarracks = 10
	expect(Rewards.Craft(p, "GoblinBarracks"), "Epic crafted with 10")
	expectEq(p.Blueprints.GoblinBarracks, nil, "spent 10")
	p.Blueprints.SpikeHall = 5
	Rewards.Craft(p, "SpikeHall")
	expectEq(p.Blueprints.SpikeHall, nil, "empty stack removed")
	expectEq(select(2, Rewards.Craft(p, "TreasureRoom")), "NotCraftable", "coin cache")
	expectEq(select(2, Rewards.Craft(p, "Entrance")), "NotCraftable", "entrance")
	expectEq(select(2, Rewards.Craft(p, "Hacked")), "NotCraftable", "unknown")
	p.Blueprints.MonsterDen = 8
	while RoomInventory.Count(p) < RoomInventory.MAX_ROOMS do
		RoomInventory.Add(p, "SlimeNest")
	end
	expectEq(select(2, Rewards.Craft(p, "MonsterDen")), "TooManyRooms", "full")
	expectEq(p.Blueprints.MonsterDen, 8, "blueprints kept")
end)

test("scrapping: unplaced only, never the Coin Cache, the tier's ScrapReturn", function()
	local p = ProfileSchema.Default() -- r1 SlimeNest placed, r2 TreasureRoom unplaced
	expectEq(select(2, Rewards.Scrap(p, "r1")), "RoomPlaced", "placed")
	expectEq(select(2, Rewards.Scrap(p, "r2")), "NotScrappable", "treasure")
	expectEq(select(2, Rewards.Scrap(p, "r99")), "NotOwned", "missing")
	local id = RoomInventory.Add(p, "RestlessCrypt")
	local ok, count = Rewards.Scrap(p, id)
	expect(ok, "scrapped")
	expectEq(count, 4, "four blueprints (Rare)")
	expectEq(p.Rooms[id], nil, "room gone")
	expectEq(p.Blueprints.RestlessCrypt, 4, "stored")
	local spike = RoomInventory.Add(p, "SpikeHall")
	expectEq(select(2, Rewards.Scrap(p, spike)), 2, "Common returns 2")
	local vault = RoomInventory.Add(p, "VoidVault")
	expectEq(select(2, Rewards.Scrap(p, vault)), 10, "Secret treasure returns 10")
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

test("box and blueprint drops respect the shop level gates (Common/Uncommon only)", function()
	local p = ProfileSchema.Default() -- level 1
	-- Box roll 0.001, blueprint roll 0.001, blueprint tier 0.7 (Uncommon), room 0.999999.
	local r = Rewards.Defeat(p, "Novice", scripted({ 0.001, 0.001, 0.7, 0.999999 }), NO_BONUS)
	expectEq(r.Drops[2].RoomId, "EmeraldGuardroom", "level 1 Uncommon blueprint follows the unlocked pool")
	p.Boxes.Dungeon = 2
	local ok, data = Rewards.OpenBox(p, "Dungeon", scripted({ 0.7, 0.999999, 0.5 }))
	expect(ok and data.RoomId == "MushroomCavern", "Uncommon box room gated at level 1")
	-- 0.9 lands in Rare (85..95% of the Dungeon weights); Rare rooms are never gated.
	local ok2, rare = Rewards.OpenBox(p, "Dungeon", scripted({ 0.9, 0.999999, 0.5 }))
	expect(ok2 and rare.Rarity == "Rare" and rare.RoomId == "Treasury", "Rare room at level 1")
end)

test("Swarm doubles defeat XP; Rare Lure raises the variant multiplier through the context", function()
	local p = ProfileSchema.Default()
	local plain = Rewards.Context(p, nil)
	local swarm = Rewards.Context(p, "Swarm")
	expectEq(swarm.Effects.Xp, 2, "Swarm XP effect")
	expectEq(swarm.Effects.Coins, 1, "Swarm leaves coins alone")
	local a = Rewards.Defeat(ProfileSchema.Default(), "Novice", scripted({ 0.99, 0.99 }), plain, 50)
	local b = Rewards.Defeat(ProfileSchema.Default(), "Novice", scripted({ 0.99, 0.99 }), swarm, 50)
	expectEq(b.Xp, a.Xp * 2, "double XP under Swarm")
	p.Permanent = { Lure = 5 }
	expectNear(Rewards.Context(p, nil).VariantMult, plain.VariantMult * 1.5, 1e-9, "Lure 5: +50% variant chances")
	expectEq(Rewards.Context(p, nil).LuckMult, plain.LuckMult, "Lure does not touch drop luck")
end)
