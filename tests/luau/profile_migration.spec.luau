-- Profile schema migrations: v1 -> v2 (Discovered) and v2 -> v3 (loot and progression).

local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RoomInventory = require(Server.Rules.RoomInventory)

test("v1 profile migrates to v2: every field kept, Discovered filled from rooms and Stats", function()
	local v1 = ProfileSchema.Default()
	v1.Version = 1
	v1.Discovered = nil
	v1.Coins = 321
	v1.Rooms.r3 = { Id = "GuardRoom", Level = 2 }
	v1.NextSerial = 4
	v1.Stats = { Encounters = 5, Wins = 3, Escapes = 1, Robberies = 1, Earned = 70 }
	v1.ChallengerUnlocked = true
	local p, problem = ProfileSchema.Migrate(v1)
	expect(p ~= nil, "migrates " .. tostring(problem))
	expectEq(p.Version, ProfileSchema.VERSION, "version")
	expectEq(p.Coins, 321, "coins")
	expectEq(p.Rooms.r3.Level, 2, "room level")
	expectEq(p.Layout["3,2"], "r1", "layout")
	expectEq(p.Stats.Wins, 3, "stats")
	expectEq(p.ChallengerUnlocked, true, "flag")
	expectEq(p.Discovered.GuardRoom, true, "owned room")
	expectEq(p.Discovered.SlimeNest, true, "owned room")
	expectEq(p.Discovered.Practice, true, "implied by encounters")
	expectEq(p.Discovered.Novice, true, "implied by encounters")
	expectEq(p.Discovered.Scout, nil, "not implied")
	expectEq(v1.Discovered, nil, "input untouched")
end)

test("v1 with no encounters implies no visitors", function()
	local v1 = ProfileSchema.Default()
	v1.Version = 1
	v1.Discovered = nil
	local p = ProfileSchema.Migrate(v1)
	expectEq(p.Discovered.Practice, nil, "none met")
end)

test("Discovered is sanitised and owned rooms always count", function()
	local stored = ProfileSchema.Default()
	stored.Discovered = { Scout = true, Bogus = true, SpikeHall = "yes", [5] = true, Cleric = false }
	local p = ProfileSchema.Migrate(stored)
	expectEq(p.Discovered.Scout, true, "kept")
	expectEq(p.Discovered.Bogus, nil, "unknown id dropped")
	expectEq(p.Discovered.SpikeHall, nil, "non-true dropped")
	expectEq(p.Discovered.Cleric, nil, "false dropped")
	expectEq(p.Discovered.SlimeNest, true, "owned room restored")
end)

test("adding a room records it as discovered", function()
	local p = ProfileSchema.Default()
	RoomInventory.Add(p, "MonsterDen")
	expectEq(p.Discovered.MonsterDen, true, "den")
end)

local function v2Profile()
	local v2 = ProfileSchema.Default()
	v2.Version = 2
	for _, room in v2.Rooms do
		room.Rarity = nil
		room.Perks = nil
	end
	v2.Xp, v2.Level, v2.Boxes, v2.Blueprints, v2.Permanent, v2.BoxPity = nil, nil, nil, nil, nil, nil
	return v2
end

test("v2 profile migrates to v3: every field kept, rooms Common, progression added", function()
	local v2 = v2Profile()
	v2.Coins = 900
	v2.Vault = 40
	v2.Rooms.r3 = { Id = "GuardRoom", Level = 3 }
	v2.NextSerial = 4
	v2.Stats = { Encounters = 20, Wins = 13, Escapes = 5, Robberies = 2, Earned = 300 }
	v2.Discovered.Scout = true
	v2.ChallengerUnlocked = true
	v2.Tutorial = { Step = "Done", Done = true }
	local p, problem = ProfileSchema.Migrate(v2)
	expect(p ~= nil, "migrates " .. tostring(problem))
	expectEq(p.Version, 3, "version")
	expectEq(p.Coins, 900, "coins")
	expectEq(p.Vault, 40, "vault")
	expectEq(p.Rooms.r3.Level, 3, "level kept (Common cap 3)")
	expectEq(p.Rooms.r3.Rarity, "Common", "common")
	expectEq(#p.Rooms.r3.Perks, 0, "no perks")
	expectEq(p.Rooms.r1.Rarity, "Common", "starter common")
	expectEq(p.Layout["3,2"], "r1", "layout")
	expectEq(p.NextSerial, 4, "serial")
	expectEq(p.Stats.Wins, 13, "stats")
	expectEq(p.Discovered.Scout, true, "discovered")
	expectEq(p.ChallengerUnlocked, true, "flag")
	expectEq(p.Tutorial.Done, true, "tutorial")
	-- 13 wins * 10 xp = 130: level 2 at 50, level 3 at 125, 5 left.
	expectEq(p.Level, 3, "level seeded from wins")
	expectEq(p.Xp, 5, "xp seeded")
	expectEq(p.Boxes.Dungeon, 0, "no retroactive boxes")
	expectEq(p.Boxes.Rare, 0, "no retroactive boxes")
	expectEq(next(p.Blueprints), nil, "no blueprints")
	expectEq(next(p.Permanent), nil, "no permanents")
	expectEq(p.BoxPity, 0, "pity")
	expectEq(v2.Rooms.r3.Rarity, nil, "input untouched")
end)

test("v3 fields are validated and clamped", function()
	local s = ProfileSchema.Default()
	s.Rooms.r3 = {
		Id = "GuardRoom",
		Level = 9,
		Rarity = "Rare",
		Perks = { { Kind = "Coins", Amount = 50 }, { Kind = "Loot", Amount = 0.2 } },
	}
	s.Rooms.r4 = { Id = "SlimeNest", Level = 6, Rarity = "Legendary", Perks = { { Kind = "Coins", Amount = 0.2 } } }
	s.Rooms.r5 = {
		Id = "MonsterDen",
		Level = 6,
		Rarity = "Mythic",
		Perks = { { Kind = "Xp" }, { Kind = "Xp" }, { Kind = "Hax", Amount = 9 }, "x", { Kind = "Loot" } },
	}
	s.NextSerial = 6
	s.Level = 1e9
	s.Xp = -4
	s.Boxes = { Dungeon = 3.7, Rare = -1, Gold = 50 }
	s.Blueprints = { GuardRoom = 4, TreasureRoom = 9, Entrance = 3, Hacked = 1, SpikeHall = 0, SlimeNest = 1e9 }
	s.Permanent = { GoldenTouch = 99, Scholar = 2.5, Bogus = 3, Lure = -2 }
	s.BoxPity = 50
	local p = ProfileSchema.Migrate(s)
	local r3 = p.Rooms.r3
	expectEq(r3.Level, 5, "rare cap 5")
	expectEq(#r3.Perks, 1, "rare has one perk")
	expectEq(r3.Perks[1].Kind, "Coins", "first valid kept")
	expectEq(r3.Perks[1].Amount, 0.10, "amount re-derived, not trusted")
	expectEq(p.Rooms.r4.Rarity, "Common", "unknown rarity -> Common")
	expectEq(p.Rooms.r4.Level, 3, "common cap 3")
	expectEq(#p.Rooms.r4.Perks, 0, "common has no perks")
	local r5 = p.Rooms.r5
	expectEq(r5.Level, 6, "mythic 6")
	expectEq(#r5.Perks, 2, "two distinct")
	expectEq(r5.Perks[1].Kind, "Xp", "xp")
	expectEq(r5.Perks[2].Kind, "Loot", "loot, duplicates and junk skipped")
	expectEq(r5.Perks[2].Amount, 0.40, "large loot")
	expectEq(p.Level, 100, "level clamped")
	expectEq(p.Xp, 0, "xp at max level")
	expectEq(p.Boxes.Dungeon, 3, "floored")
	expectEq(p.Boxes.Rare, 0, "negative")
	expectEq(p.Boxes.Gold, nil, "unknown box type dropped")
	expectEq(p.Blueprints.GuardRoom, 4, "kept")
	expectEq(p.Blueprints.TreasureRoom, nil, "not craftable")
	expectEq(p.Blueprints.Entrance, nil, "entrance")
	expectEq(p.Blueprints.Hacked, nil, "unknown")
	expectEq(p.Blueprints.SpikeHall, nil, "zero dropped")
	expectEq(p.Blueprints.SlimeNest, 999, "stack capped")
	expectEq(p.Permanent.GoldenTouch, 10, "max level")
	expectEq(p.Permanent.Scholar, 2, "floored")
	expectEq(p.Permanent.Bogus, nil, "unknown")
	expectEq(p.Permanent.Lure, nil, "negative dropped")
	expectEq(p.BoxPity, 9, "pity clamped")
	local t = ProfileSchema.Default()
	t.Level, t.Xp = 2, 500
	expectEq(ProfileSchema.Migrate(t).Xp, 74, "xp kept below the next level")
end)

test("a v3 profile round-trips unchanged and newer versions are still rejected", function()
	local s = ProfileSchema.Default()
	RoomInventory.Add(s, "RestlessCrypt", "Mythic", { { Kind = "Coins", Amount = 0.2 }, { Kind = "Xp", Amount = 0.4 } })
	s.Level, s.Xp, s.BoxPity = 7, 30, 4
	s.Boxes.Rare = 2
	s.Blueprints.GuardRoom = 3
	s.Permanent.Lure = 2
	local p = ProfileSchema.Migrate(s)
	expectEq(p.Rooms.r3.Rarity, "Mythic", "rarity")
	expectEq(#p.Rooms.r3.Perks, 2, "perks")
	expectEq(p.Level, 7, "level")
	expectEq(p.Xp, 30, "xp")
	expectEq(p.BoxPity, 4, "pity")
	expectEq(p.Boxes.Rare, 2, "boxes")
	expectEq(p.Blueprints.GuardRoom, 3, "blueprints")
	expectEq(p.Permanent.Lure, 2, "permanent")
	expectEq(select(2, ProfileSchema.Migrate({ Version = 4, Coins = 1 })), "NewerVersion", "v4 rejected")
end)
