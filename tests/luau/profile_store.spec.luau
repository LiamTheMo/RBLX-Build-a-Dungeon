-- Profile persistence: leased load, revision-checked save, release, retries, and
-- the rule that a failed load is never written over.

local FakeStores = require(game:GetService("ServerStorage").TestSupport.FakeStores)
local Server = game:GetService("ServerScriptService").Server
local ProfileStore = require(Server.Infrastructure.ProfileStore)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local DataStoreGateway = require(Server.Infrastructure.DataStoreGateway)

local KEY = ProfileStore.KeyFor(1)

test("new player loads defaults, leased, and nothing else is written", function()
	local fake = FakeStores.new("A")
	local profile = fake.store:Load(1)
	expect(profile ~= nil, "loaded")
	expectEq(profile.Coins, 0, "default coins")
	expectEq(fake.backing._data[KEY].sessionLease.jobId, "A", "lease written")
	expectEq(profile.profileRevision, 1, "revision bumped")
end)

test("save persists changes and keeps the lease; release clears it", function()
	local fake = FakeStores.new("A")
	local profile = fake.store:Load(1)
	profile.Coins = 42
	fake.store:MarkDirty(1)
	expect(fake.store:IsDirty(1), "dirty")
	expect(fake.store:Save(1), "save ok")
	expect(not fake.store:IsDirty(1), "clean after save")
	expectEq(fake.backing._data[KEY].Coins, 42, "stored coins")
	expectEq(fake.backing._data[KEY].sessionLease.jobId, "A", "lease kept")
	expect(fake.store:Save(1, true), "release ok")
	expectEq(fake.backing._data[KEY].sessionLease, nil, "lease cleared")
	expect(not fake.store:IsLoaded(1), "forgotten")
end)

test("a lease held by another job blocks the load and writes nothing", function()
	local a = FakeStores.new("A")
	a.store:Load(1)
	local before = a.backing._data[KEY]
	local b = FakeStores.new("B", a)
	local profile, reason = b.store:Load(1)
	expectEq(profile, nil, "no profile")
	expectEq(reason, "LeaseHeld", "reason")
	expectEq(a.backing._data[KEY].profileRevision, before.profileRevision, "untouched")
end)

test("an expired lease can be taken over, and the old server then loses its lease", function()
	local a = FakeStores.new("A")
	local profile = a.store:Load(1)
	profile.Coins = 5
	a.store:MarkDirty(1)
	a.time.now += 10000
	local b = FakeStores.new("B", a)
	expect(b.store:Load(1) ~= nil, "B takes over")
	local ok, reason = a.store:Save(1)
	expect(not ok, "A cannot save")
	expectEq(reason, "LeaseLost", "reason")
	expectEq(a.store:Get(1), nil, "A drops the profile")
	expectEq(b.backing._data[KEY].Coins, 0, "A did not overwrite B's data")
	local again, again2 = a.store:Save(1)
	expect(not again and again2 == "LeaseLost", "A stays locked out")
end)

test("a failed load is never overwritten: newer version and corrupt data", function()
	local fake = FakeStores.new("A")
	fake.backing._data[KEY] = { Version = 99, Coins = 7 }
	local profile, reason = fake.store:Load(1)
	expectEq(profile, nil, "no profile")
	expectEq(reason, "NewerVersion", "reason")
	expectEq(fake.backing._data[KEY].Coins, 7, "stored data untouched")
	expectEq(fake.backing._data[KEY].sessionLease, nil, "no lease taken")
	expect(fake.store:Save(1) == false, "nothing to save")

	fake.backing._data[KEY] = "garbage"
	local _, reason2 = fake.store:Load(1)
	expectEq(reason2, "Corrupt", "corrupt reason")
	expectEq(fake.backing._data[KEY], "garbage", "garbage untouched")
end)

test("a DataStore outage on load fails after retries without writing", function()
	local fake = FakeStores.new("A")
	fake.backing.failNext = 100
	local profile, reason = fake.store:Load(1)
	expectEq(profile, nil, "no profile")
	expect(string.find(reason, "DataStoreError", 1, true) ~= nil, "reason: " .. tostring(reason))
	expectEq(#fake.sleeps, DataStoreGateway.MAX_ATTEMPTS - 1, "backed off between attempts")
	expectEq(fake.sleeps[2], fake.sleeps[1] * 2, "exponential")
	expectEq(fake.backing._data[KEY], nil, "nothing written")
	expect(not fake.store:IsLoaded(1), "not loaded")
end)

test("save retries through transient failures and keeps data on permanent ones", function()
	local fake = FakeStores.new("A")
	local profile = fake.store:Load(1)
	profile.Coins = 9
	fake.store:MarkDirty(1)
	fake.backing.failNext = 2
	expect(fake.store:Save(1), "succeeds on third attempt")
	expectEq(fake.backing._data[KEY].Coins, 9, "stored")

	profile.Coins = 11
	fake.store:MarkDirty(1)
	fake.backing.failNext = 100
	local ok, reason = fake.store:Save(1)
	expect(not ok and string.find(reason, "DataStoreError", 1, true) ~= nil, "reports failure")
	expectEq(fake.store:Get(1).Coins, 11, "live profile kept")
	expect(fake.store:IsDirty(1), "still dirty")
	fake.backing.failNext = 0
	expect(fake.store:Save(1), "later save works")
	expectEq(fake.backing._data[KEY].Coins, 11, "stored later")
end)

test("a release that races a change saves the change too", function()
	local fake = FakeStores.new("A")
	local profile = fake.store:Load(1)
	-- Mutate from inside the write, as a yielding save would allow.
	local real = fake.backing.UpdateAsync
	local mutated = false
	fake.backing.UpdateAsync = function(self, key, transform)
		local result = real(self, key, transform)
		if not mutated then
			mutated = true
			profile.Coins = 77
			fake.store:MarkDirty(1)
		end
		return result
	end
	expect(fake.store:Save(1, true), "release ok")
	expectEq(fake.backing._data[KEY].Coins, 77, "late change saved")
	expectEq(fake.backing._data[KEY].sessionLease, nil, "released")
end)

test("stored data repaired on load is written back with the lease", function()
	local fake = FakeStores.new("A")
	local stored = ProfileSchema.Default()
	stored.Coins = -5.7
	stored.Rooms.r9 = { Id = "Nope", Level = 1 }
	fake.backing._data[KEY] = stored
	local profile = fake.store:Load(1)
	expectEq(profile.Coins, 0, "repaired coins")
	expectEq(profile.Rooms.r9, nil, "unknown room dropped")
	expectEq(fake.backing._data[KEY].Rooms.r9, nil, "repair persisted")
end)

test("release and Forget only clear their own entry, never a newer load", function()
	local fake = FakeStores.new("A")
	local first = fake.store:Load(1)
	local token = fake.store:Peek(1)
	expect(token == first, "peek returns the live table")
	fake.store:Forget(1, {}) -- some other table: ignored
	expect(fake.store:IsLoaded(1), "foreign token does not forget")
	fake.store:Forget(1, token)
	expect(not fake.store:IsLoaded(1), "matching token forgets")

	-- A newer entry for the same user survives a stale entry's release.
	local second = fake.store:Load(1)
	expect(second ~= nil and fake.store:IsLoaded(1), "reloaded")
	fake.store:Forget(1, first)
	expect(fake.store:IsLoaded(1), "stale token leaves the newer entry")
	expect(fake.store:Get(1) == second, "newer profile still live")
end)
