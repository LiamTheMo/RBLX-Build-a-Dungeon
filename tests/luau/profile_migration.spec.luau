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

test("v2 profile migrates to v5: every field kept, progression added, vault banked", function()
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
	expectEq(p.Version, ProfileSchema.VERSION, "version")
	expectEq(p.Coins, 940, "vault banked into coins")
	expectEq(p.Vault, nil, "vault dropped")
	expectEq(p.VaultPercent, 0, "vault percent")
	expectEq(p.Rooms.r3.Level, 3, "level kept (Common cap 3)")
	expectEq(p.Rooms.r3.Rarity, nil, "no instance rarity (definition's)")
	expectEq(p.Rooms.r3.Perks, nil, "no instance perks")
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
	expectEq(v2.Rooms.r3.Level, 3, "input untouched")
end)

test("v3 fields are validated and clamped", function()
	local s = ProfileSchema.Default()
	s.Rooms.r3 = {
		Id = "GuardRoom",
		Level = 9,
		Rarity = "Rare",
		Perks = { { Kind = "Coins", Amount = 50 }, { Kind = "Loot", Amount = 0.2 } },
	}
	s.Rooms.r4 = { Id = "SlimeNest", Level = 6, Rarity = "Bogus", Perks = { { Kind = "Coins", Amount = 0.2 } } }
	s.Rooms.r5 = { Id = "MonsterDen", Level = 6, Rarity = "Mythic", Perks = { { Kind = "Xp" } } }
	s.NextSerial = 6
	s.Level = 1e9
	s.Xp = -4
	s.Boxes = { Dungeon = 3.7, Rare = -1, Gold = 50 }
	s.Blueprints = { GuardRoom = 4, TreasureRoom = 9, Entrance = 3, Hacked = 1, SpikeHall = 0, SlimeNest = 1e9 }
	s.Permanent = { GoldenTouch = 99, Scholar = 2.5, Bogus = 3, Lure = -2 }
	s.BoxPity = 50
	local p = ProfileSchema.Migrate(s)
	expectEq(p.Rooms.r3.Level, 3, "guard is Common: cap 3 (saved rarity ignored)")
	expectEq(p.Rooms.r3.Rarity, nil, "rarity dropped")
	expectEq(p.Rooms.r3.Perks, nil, "perks dropped, never trusted")
	expectEq(p.Rooms.r4.Level, 3, "common cap 3")
	expectEq(p.Rooms.r5.Level, 5, "monster den is Rare: cap 5")
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

test("a v5 profile round-trips unchanged and newer versions are rejected", function()
	local s = ProfileSchema.Default()
	RoomInventory.Add(s, "RestlessCrypt", "Lucky")
	s.Rooms.r3.Level = 4
	s.Level, s.Xp, s.BoxPity = 7, 30, 4
	s.Boxes.Rare = 2
	s.Blueprints.GuardRoom = 3
	s.Permanent.Lure = 2
	local p = ProfileSchema.Migrate(s)
	expectEq(p.Rooms.r3.Id, "RestlessCrypt", "room")
	expectEq(p.Rooms.r3.Level, 4, "level")
	expectEq(p.Rooms.r3.Modifier, "Lucky", "modifier")
	expectEq(p.Level, 7, "level")
	expectEq(p.Xp, 30, "xp")
	expectEq(p.BoxPity, 4, "pity")
	expectEq(p.Boxes.Rare, 2, "boxes")
	expectEq(p.Blueprints.GuardRoom, 3, "blueprints")
	expectEq(p.Permanent.Lure, 2, "permanent")
	expectEq(select(2, ProfileSchema.Migrate({ Version = ProfileSchema.VERSION + 1, Coins = 1 })), "NewerVersion", "v6 rejected")
end)

test("v4 profile migrates to v5: instance rarity and perks dropped, levels clamped to the definition's tier", function()
	local v4 = ProfileSchema.Default()
	v4.Version = 4
	v4.Coins, v4.VaultPercent, v4.Threat = 1234, 40, 2
	v4.Level, v4.Xp = 9, 12
	v4.Rooms.r1 = { Id = "SlimeNest", Level = 7, Rarity = "Epic", Perks = { { Kind = "Coins", Amount = 0.1 } } }
	v4.Rooms.r2 = { Id = "TreasureRoom", Level = 5, Rarity = "Legendary", Perks = {} }
	v4.Rooms.r3 = { Id = "RestlessCrypt", Level = 4, Rarity = "Common", Perks = {}, Modifier = "Blazing" }
	v4.Rooms.r4 = { Id = "MushroomCavern", Level = 2, Rarity = "Secret", Perks = { { Kind = "Xp", Amount = 0.6 } } }
	v4.NextSerial = 5
	v4.Layout = { ["3,2"] = "r1", ["3,3"] = "r3", ["3,4"] = "r2" }
	v4.Blueprints = { GuardRoom = 7, RestlessCrypt = 2 }
	v4.Boxes = { Dungeon = 4, Rare = 1 }
	v4.BoxPity = 3
	v4.Permanent = { DeepVault = 2 }
	v4.Discovered.RestlessCrypt = true
	v4.Stats.Wins = 40
	local p, problem = ProfileSchema.Migrate(v4)
	expect(p ~= nil, "migrates " .. tostring(problem))
	expectEq(p.Version, ProfileSchema.VERSION, "version")
	for id, room in p.Rooms do
		expectEq(room.Rarity, nil, id .. " rarity dropped")
		expectEq(room.Perks, nil, id .. " perks dropped")
	end
	expectEq(p.Rooms.r1.Level, 3, "Epic slime clamped to the Common cap")
	expectEq(p.Rooms.r2.Level, 3, "coin cache clamped to 3")
	expectEq(p.Rooms.r3.Level, 4, "crypt (Rare, cap 5) keeps level 4")
	expectEq(p.Rooms.r3.Modifier, "Blazing", "modifier kept")
	expectEq(p.Rooms.r4.Level, 2, "mushroom level kept")
	expectEq(p.Coins, 1234, "coins")
	expectEq(p.VaultPercent, 40, "vault percent")
	expectEq(p.Threat, 2, "threat")
	expectEq(p.Level, 9, "keeper level")
	expectEq(p.Xp, 12, "xp")
	expectEq(p.Layout["3,4"], "r2", "layout kept")
	expectEq(p.Blueprints.GuardRoom, 7, "blueprints kept")
	expectEq(p.Boxes.Dungeon, 4, "boxes kept")
	expectEq(p.BoxPity, 3, "pity kept")
	expectEq(p.Permanent.DeepVault, 2, "permanent kept")
	expectEq(p.Discovered.RestlessCrypt, true, "discovered kept")
	expectEq(p.Stats.Wins, 40, "stats kept")
	expectEq(p.NextSerial, 5, "serial")
	expectEq(v4.Rooms.r1.Rarity, "Epic", "input untouched")
	-- Two treasures saved in a layout: only the first (key order) is kept.
	local two = ProfileSchema.Default()
	RoomInventory.Add(two, "Strongbox")
	two.Layout = { ["3,2"] = "r1", ["3,3"] = "r2", ["2,2"] = "r3" }
	local q = ProfileSchema.Migrate(two)
	expectEq(q.Layout["2,2"], "r3", "first treasure in key order kept")
	expectEq(q.Layout["3,3"], nil, "second treasure dropped")
end)

test("v3 profile migrates to v4: vault banked into Coins, every other field kept", function()
	local v3 = ProfileSchema.Default()
	v3.Version = 3
	v3.VaultPercent, v3.Threat = nil, nil
	v3.Coins, v3.Vault = 500, 120
	v3.Level, v3.Xp = 6, 30
	v3.Boxes = { Dungeon = 2, Rare = 1 }
	v3.Permanent = { DeepVault = 3 }
	v3.ChallengerUnlocked = true
	v3.Rooms.r2.Level = 2
	local p, problem = ProfileSchema.Migrate(v3)
	expect(p ~= nil, "migrates " .. tostring(problem))
	expectEq(p.Version, ProfileSchema.VERSION, "version")
	expectEq(p.Coins, 620, "Coins += Vault")
	expectEq(p.Vault, nil, "Vault dropped")
	expectEq(p.VaultPercent, 0, "nothing at risk after the update")
	expectEq(p.Threat, 1, "threat 1")
	expectEq(p.Level, 6, "level kept")
	expectEq(p.Xp, 30, "xp kept")
	expectEq(p.Boxes.Rare, 1, "boxes kept")
	expectEq(p.Permanent.DeepVault, 3, "deep vault level kept")
	expectEq(p.Rooms.r2.Level, 2, "treasure level kept")
	expectEq(p.ChallengerUnlocked, true, "legacy flag kept")
	expectEq(v3.Vault, 120, "input untouched")
	-- A v4 profile never re-adds a stray Vault field.
	local again = ProfileSchema.Migrate({ Version = 4, Coins = 10, Vault = 999, VaultPercent = 30, Threat = 2 })
	expectEq(again.Coins, 10, "v4 ignores Vault")
	expectEq(again.VaultPercent, 30, "percent kept")
	expectEq(again.Threat, 1, "threat clamped to the level-1 unlock")
end)


test("version 5 profiles migrate and new royal rooms survive a round trip", function()
	local old = ProfileSchema.Default()
	old.Version = 5
	old.Coins = 4321
	local migrated = ProfileSchema.Migrate(old)
	expectEq(migrated.Coins, 4321, "coins retained")
	expectEq(migrated.Version, ProfileSchema.VERSION, "upgraded version")
	migrated.Rooms.r99 = { Id = "EclipseBastion", Level = 1 }
	migrated.Blueprints.EmeraldGuardroom = 3
	local roundtrip = ProfileSchema.Migrate(migrated)
	expectEq(roundtrip.Rooms.r99.Id, "EclipseBastion", "new room retained")
	expectEq(roundtrip.Blueprints.EmeraldGuardroom, 3, "new blueprints retained")
end)


test("new chest room identities survive a profile round trip", function()
	local saved = ProfileSchema.Default()
	saved.Rooms.r99 = { Id = "CrystalBarricade", Level = 1 }
	saved.NextSerial = 100
	local restored = ProfileSchema.Migrate(saved)
	expectEq(restored.Rooms.r99.Id, "CrystalBarricade", "crystal room retained")
	expectEq(restored.Version, ProfileSchema.VERSION, "current schema")
end)
