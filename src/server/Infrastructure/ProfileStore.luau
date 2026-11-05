-- Profile loading and saving with a session lease and revision checks. Pure apart
-- from the injected gateway and clock, so specs drive it with an in-memory store.
-- ProfileService adds the Roblox lifecycle around it.

local ProfileSchema = require(script.Parent.Parent.Rules.ProfileSchema)
local SessionLease = require(script.Parent.Parent.Rules.SessionLease)

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type Options = {
	gateway: any,
	jobId: string,
	clock: () -> number,
}

function ProfileStore.new(options: Options)
	assert(type(options.jobId) == "string" and options.jobId ~= "", "ProfileStore needs a jobId")
	return setmetatable({
		_gateway = options.gateway,
		_jobId = options.jobId,
		_clock = options.clock,
		_entries = {},
	}, ProfileStore)
end

function ProfileStore.KeyFor(userId: number): string
	return "Profile_" .. tostring(userId)
end

-- Loads and leases a profile. Returns (profile) or (nil, reason): "LeaseHeld"
-- (another server owns it), "NewerVersion"/"Corrupt" (stored data is left
-- untouched) or "DataStoreError: ...". A failed load never writes anything.
function ProfileStore:Load(userId: number)
	assert(self._entries[userId] == nil, "Profile already loaded")
	local now = self._clock()
	local reason = nil
	local ok, stored = self._gateway:Update(ProfileStore.KeyFor(userId), function(old)
		local profile, problem = ProfileSchema.Migrate(old)
		if profile == nil then
			reason = problem
			return nil
		end
		if not SessionLease.CanAcquire(profile.sessionLease, self._jobId, now) then
			reason = "LeaseHeld"
			return nil
		end
		profile.sessionLease = SessionLease.New(self._jobId, now)
		profile.profileRevision += 1
		return profile
	end)
	if not ok then
		return nil, "DataStoreError: " .. tostring(stored)
	end
	if stored == nil then
		return nil, reason or "Unknown"
	end
	self._entries[userId] = {
		profile = stored,
		revision = stored.profileRevision,
		changes = 0,
		savedChanges = 0,
		saving = false,
		lost = false,
		released = false,
	}
	return stored, nil
end

-- The live profile, or nil when not loaded or the lease was lost.
function ProfileStore:Get(userId: number)
	local entry = self._entries[userId]
	return entry and not entry.lost and entry.profile or nil
end

function ProfileStore:IsLoaded(userId: number): boolean
	return self._entries[userId] ~= nil
end

function ProfileStore:IsSaving(userId: number): boolean
	local entry = self._entries[userId]
	return entry ~= nil and entry.saving
end

-- True when the live profile has changes that were not written yet.
function ProfileStore:IsDirty(userId: number): boolean
	local entry = self._entries[userId]
	return entry ~= nil and entry.changes ~= entry.savedChanges
end

-- Records that the live profile changed and needs saving.
function ProfileStore:MarkDirty(userId: number)
	local entry = self._entries[userId]
	if entry and not entry.lost then
		entry.changes += 1
	end
end

-- Writes the live profile if this server still holds the lease and nobody else
-- has written since it loaded. `release` clears the lease and forgets the profile.
-- Returns (true) or (false, reason); a failed write keeps the profile loaded.
function ProfileStore:Save(userId: number, release: boolean?)
	local entry = self._entries[userId]
	if entry == nil then
		return false, "NotLoaded"
	end
	if entry.lost then
		return false, "LeaseLost"
	end
	assert(not entry.saving, "Save already in progress")
	entry.saving = true

	local now = self._clock()
	local snapshotChanges = entry.changes
	local payload = ProfileSchema.DeepCopy(entry.profile)
	local reason = nil
	local ok, stored = self._gateway:Update(ProfileStore.KeyFor(userId), function(old)
		if old == nil then
			reason = "Missing"
			return nil
		end
		-- After a release whose snapshot missed later changes the lease is already
		-- clear; the revision check below still proves nobody else loaded since.
		local released = entry.released and old.sessionLease == nil
		if not released and not SessionLease.IsHeldBy(old.sessionLease, self._jobId) then
			reason = "LeaseLost"
			return nil
		end
		if old.profileRevision ~= entry.revision then
			reason = "StaleRevision"
			return nil
		end
		payload.profileRevision = entry.revision + 1
		payload.sessionLease = if release then nil else SessionLease.New(self._jobId, now)
		return payload
	end)
	entry.saving = false

	if not ok then
		return false, "DataStoreError: " .. tostring(stored)
	end
	if stored == nil then
		-- Another server owns or has rewritten this profile: stop writing at once.
		entry.lost = true
		return false, reason or "Unknown"
	end

	entry.revision = stored.profileRevision
	entry.profile.profileRevision = stored.profileRevision
	entry.profile.sessionLease = stored.sessionLease
	entry.released = release == true
	if release and entry.changes ~= snapshotChanges then
		-- Changed while the release was in flight: write again rather than forget.
		if self._entries[userId] ~= entry then
			return true, nil
		end
		return self:Save(userId, true)
	elseif release then
		-- Only clear our own entry: a newer load for this user must survive.
		if self._entries[userId] == entry then
			self._entries[userId] = nil
		end
	else
		entry.savedChanges = snapshotChanges
	end
	return true, nil
end

-- The cached profile table even when the lease was lost (nil when not loaded).
-- Callers keep it as an identity token for Forget.
function ProfileStore:Peek(userId: number)
	local entry = self._entries[userId]
	return entry and entry.profile or nil
end

-- Forgets a profile without writing (used after a lost lease). With `expected`
-- (a table from Peek/Load) it only forgets that same entry, never a newer load.
function ProfileStore:Forget(userId: number, expected: any?)
	local entry = self._entries[userId]
	if entry and (expected == nil or entry.profile == expected) then
		self._entries[userId] = nil
	end
end

function ProfileStore:LoadedUserIds(): { number }
	local ids = {}
	for userId in self._entries do
		table.insert(ids, userId)
	end
	return ids
end

return ProfileStore
