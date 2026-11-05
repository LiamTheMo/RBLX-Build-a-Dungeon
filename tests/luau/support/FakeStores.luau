--!nocheck
-- A ProfileStore wired to an in-memory DataStore, with backoff sleeps recorded
-- instead of waited. Specs poke `backing._data[key]` and `backing.failNext`, and
-- advance `time.now` to expire leases.
--
--     local FakeStores = require(game:GetService("ServerStorage").TestSupport.FakeStores)
--     local fake = FakeStores.new("JobA")  -- fake.store, fake.backing, fake.sleeps, fake.time

local FakeStores = {}

local Infrastructure = game:GetService("ServerScriptService").Server.Infrastructure

-- `shared` (from a previous FakeStores.new) lets a second "server" use the same data.
function FakeStores.new(jobId: string, shared)
	local DataStoreGateway = require(Infrastructure.DataStoreGateway)
	local InMemoryDataStore = require(Infrastructure.InMemoryDataStore)
	local ProfileStore = require(Infrastructure.ProfileStore)

	local fake = {
		backing = shared and shared.backing or InMemoryDataStore.new(),
		time = shared and shared.time or { now = 1000 },
		sleeps = {},
	}
	fake.gateway = DataStoreGateway.new({
		store = fake.backing,
		sleep = function(seconds)
			table.insert(fake.sleeps, seconds)
		end,
	})
	fake.store = ProfileStore.new({
		gateway = fake.gateway,
		jobId = jobId,
		clock = function()
			return fake.time.now
		end,
	})
	return fake
end

return FakeStores
