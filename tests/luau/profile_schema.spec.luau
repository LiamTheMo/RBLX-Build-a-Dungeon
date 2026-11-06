-- Profile schema: defaults and repair of stored data.

local Server = game:GetService("ServerScriptService").Server
local ProfileSchema = require(Server.Rules.ProfileSchema)
local SessionLease = require(Server.Rules.SessionLease)

local function migrated(mutate)
	local stored = ProfileSchema.Default()
	mutate(stored)
	local profile, problem = ProfileSchema.Migrate(stored)
	expect(profile ~= nil, "migrates: " .. tostring(problem))
	return profile or ProfileSchema.Default()
end

test("default profile matches the contract", function()
	local p = ProfileSchema.Default()
	expectEq(p.Version, ProfileSchema.VERSION, "version")
	expectEq(p.VaultPercent, 0, "vault percent")
	expectEq(p.Threat, 1, "threat")
	expectEq(p.Vault, nil, "no vault balance")
	expectEq(p.NextSerial, 3, "NextSerial")
	expectEq(p.Rooms.r1.Id, "SlimeNest", "r1")
	expectEq(p.Rooms.r2.Id, "TreasureRoom", "r2")
	expectEq(p.Layout["3,2"], "r1", "layout")
	expectEq(p.Layout["3,3"], nil, "only one placed room")
	expectEq(p.Settings.MusicVolume, 0.5, "music")
	expectEq(p.Settings.SfxVolume, 0.4, "sfx")
	expectEq(p.Tutorial.Step, "Welcome", "tutorial")
	expect(ProfileSchema.Default() ~= p and ProfileSchema.Default().Rooms ~= p.Rooms, "fresh tables")
end)

test("nil stored data is a new player; default survives Migrate unchanged", function()
	local fresh = ProfileSchema.Migrate(nil)
	expectEq(fresh.Coins, 0, "coins")
	local again = ProfileSchema.Migrate(ProfileSchema.Default())
	expectEq(again.Layout["3,2"], "r1", "layout kept")
	expectEq(again.Rooms.r2.Id, "TreasureRoom", "rooms kept")
	expectEq(again.NextSerial, 3, "serial kept")
end)

test("a newer schema version is rejected, garbage is corrupt, input untouched", function()
	local newer = { Version = ProfileSchema.VERSION + 1, Coins = 5 }
	local profile, problem = ProfileSchema.Migrate(newer)
	expectEq(profile, nil, "no profile")
	expectEq(problem, "NewerVersion", "problem")
	expectEq(newer.Coins, 5, "untouched")
	expectEq(select(2, ProfileSchema.Migrate("x")), "Corrupt", "string")
	expectEq(select(2, ProfileSchema.Migrate({})), "Corrupt", "no version")
	expectEq(select(2, ProfileSchema.Migrate({ Version = 0 })), "Corrupt", "version 0")
end)

test("money is clamped to whole numbers >= 0", function()
	local p = migrated(function(s)
		s.Coins = 12.9
		s.VaultPercent = 55.5
		s.Stats.Earned = 0 / 0
	end)
	expectEq(p.Coins, 12, "fractional floored")
	expectEq(p.VaultPercent, 55, "percent floored")
	expectEq(p.Stats.Earned, 0, "nan")
	local q = migrated(function(s)
		s.Coins = math.huge
		s.VaultPercent = 900
		s.Threat = 2.5
	end)
	expectEq(q.Coins, 0, "inf")
	expectEq(q.VaultPercent, 100, "percent clamped")
	expectEq(q.Threat, 1, "fractional threat reset")
	expectEq(migrated(function(s) s.Coins = -50 end).Coins, 0, "negative")
	expectEq(migrated(function(s) s.VaultPercent = "100" end).VaultPercent, 0, "string percent")
end)

test("unknown and unplaceable room ids and bad instance ids are dropped", function()
	local p = migrated(function(s)
		s.Rooms.r3 = { Id = "Hacked", Level = 1 }
		s.Rooms.r4 = { Id = "Entrance", Level = 1 }
		s.Rooms.evil = { Id = "SlimeNest", Level = 1 }
		s.Rooms.r5 = "SlimeNest"
		s.Layout["3,3"] = "r3"
	end)
	expectEq(p.Rooms.r3, nil, "unknown id")
	expectEq(p.Rooms.r4, nil, "entrance")
	expectEq(p.Rooms.evil, nil, "bad instance key")
	expectEq(p.Rooms.r5, nil, "not a table")
	expectEq(p.Layout["3,3"], nil, "layout pointing at dropped room")
	expectEq(p.Layout["3,2"], "r1", "valid layout kept")
end)

test("room levels are repaired", function()
	local p = migrated(function(s)
		s.Rooms.r1.Level = -3
		s.Rooms.r2.Level = 2.7
	end)
	expectEq(p.Rooms.r1.Level, 1, "negative")
	expectEq(p.Rooms.r2.Level, 2, "fractional")
end)

test("duplicate and missing instances in the layout are dropped", function()
	local p = migrated(function(s)
		s.Layout["3,2"] = "r1"
		s.Layout["3,3"] = "r1" -- the same instance twice
		s.Layout["2,2"] = "r99" -- missing instance
	end)
	expectEq(p.Layout["3,2"], "r1", "first (by key order) kept... ")
	expectEq(p.Layout["3,3"], nil, "duplicate dropped")
	expectEq(p.Layout["2,2"], nil, "missing dropped")
end)

test("any layout shape is kept; only bad entries are dropped", function()
	local p = migrated(function(s)
		s.Layout = { ["3,2"] = "r1", ["5,4"] = "r2" } -- disconnected treasure: idle, still valid
	end)
	expectEq(p.Layout["3,2"], "r1", "route room kept")
	expectEq(p.Layout["5,4"], "r2", "disconnected room kept")
	local q = migrated(function(s)
		s.Rooms.r3 = { Id = "SpikeHall", Level = 1, Rarity = "Common", Perks = {} }
		s.Rooms.r4 = { Id = "TreasureRoom", Level = 1, Rarity = "Common", Perks = {} }
		s.Layout = {
			["3,2"] = "r1",
			["bad"] = "r3", -- malformed key
			["3,1"] = "r3", -- on the entrance
			["6,2"] = "r3", -- out of bounds
			["1,1"] = "r2",
			["2,2"] = "r4", -- second Treasure Room (key order: 1,1 came first)
		}
	end)
	expectEq(q.Layout["3,2"], "r1", "valid entry kept")
	expectEq(q.Layout["1,1"], "r2", "first treasure kept")
	expectEq(q.Layout["2,2"], nil, "second treasure dropped")
	expectEq(q.Layout["bad"], nil, "bad cell key")
	expectEq(q.Layout["3,1"], nil, "entrance cell")
	expectEq(q.Layout["6,2"], nil, "out of bounds")
	expectEq(q.Rooms.r3.Id, "SpikeHall", "rooms kept")
	expectEq(q.Rooms.r4.Id, "TreasureRoom", "rooms kept")
end)

test("NextSerial always stays above existing instance ids", function()
	local p = migrated(function(s)
		s.NextSerial = 1
		s.Rooms.r7 = { Id = "SlimeNest", Level = 1 }
	end)
	expectEq(p.NextSerial, 8, "above r7")
	local q = migrated(function(s)
		s.NextSerial = "x"
	end)
	expectEq(q.NextSerial, 3, "bad value repaired")
end)

test("settings and tutorial are repaired", function()
	local p = migrated(function(s)
		s.Settings = { ReducedMotion = "yes", MusicVolume = 5, SfxVolume = -1 }
		s.Tutorial = { Step = 12, Done = "no" }
	end)
	expectEq(p.Settings.ReducedMotion, false, "bool")
	expectEq(p.Settings.MusicVolume, 1, "clamped high")
	expectEq(p.Settings.SfxVolume, 0, "clamped low")
	expectEq(p.Tutorial.Step, "Welcome", "step")
	expectEq(p.Tutorial.Done, false, "done")
end)

test("store metadata survives Migrate, malformed lease is dropped", function()
	local lease = SessionLease.New("job", 100)
	local p = migrated(function(s)
		s.profileRevision = 4
		s.sessionLease = lease
	end)
	expectEq(p.profileRevision, 4, "revision")
	expectEq(p.sessionLease.jobId, "job", "lease")
	local q = migrated(function(s)
		s.sessionLease = { jobId = 5 }
	end)
	expectEq(q.sessionLease, nil, "bad lease dropped")
end)
