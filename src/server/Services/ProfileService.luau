-- Profile lifecycle: leased load on join, autosave, save + release on leave and
-- shutdown. Other services read the live profile with Get(player), mutate it
-- WITHOUT yielding, then call Changed(player) (marks it dirty, pushes `State`).
-- A failed load never creates or saves a default profile: LoadState is "Failed"
-- and every request is refused (ProfileNotLoaded).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local DataStoreGateway = require(script.Parent.Parent.Infrastructure.DataStoreGateway)
local InMemoryDataStore = require(script.Parent.Parent.Infrastructure.InMemoryDataStore)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local ProfileStore = require(script.Parent.Parent.Infrastructure.ProfileStore)

local ProfileService = {}

-- Studio playtests get their own store so test progress never touches live profiles.
ProfileService.STORE_NAME = if RunService:IsStudio() then "PlayerProfiles_v1_Studio" else "PlayerProfiles_v1"
ProfileService.AUTOSAVE_SECONDS = 60
-- A crashed server's lease lasts SessionLease.DURATION_SECONDS (120); keep waiting a bit longer.
ProfileService.LOAD_WAIT_SECONDS = 130
ProfileService.LOAD_RETRY_SECONDS = 3
ProfileService.SHUTDOWN_BUDGET_SECONDS = 25
ProfileService.SHUTDOWN_DATASTORE_ATTEMPTS = 3

-- Fire (player, profile) once the profile is loaded, and just before the final
-- release save (so services can still apply departure changes).
ProfileService.Loaded = Signal.new()
ProfileService.Removing = Signal.new()
-- Fire (player) on every departure, with or without a live profile. Per-player
-- bookkeeping (plots, queues) must clean up on this, not on Removing.
ProfileService.Left = Signal.new()

local store = nil -- nil when no DataStore could be opened on a live server
local usingMemoryStore = false
local states = {} -- player -> { loadState: string, transient: { [string]: any } }
local rules = nil -- { StateView }, required on first snapshot
local activeGateway = nil
local shuttingDown = false
local loading = {} -- userId -> true while a load/release for that user is running
local pendingLoads = 0

local function createStore()
	local opened, dataStore = pcall(function()
		return DataStoreService:GetDataStore(ProfileService.STORE_NAME)
	end)
	if opened and RunService:IsStudio() then
		-- Studio without "Enable Studio Access to API Services" cannot reach DataStores.
		opened, dataStore = pcall(function()
			dataStore:GetAsync("__probe")
			return dataStore
		end)
	end
	if not opened then
		if not RunService:IsStudio() then
			warn("[ProfileService] Could not open the DataStore; every load will fail: " .. tostring(dataStore))
			return nil
		end
		warn("[ProfileService] DataStores unavailable in Studio; using an in-memory store (not saved).")
		usingMemoryStore = true
		return DataStoreGateway.new({ store = InMemoryDataStore.new() })
	end
	return DataStoreGateway.new({
		store = dataStore,
		waitForBudget = function()
			while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 do
				task.wait(1)
			end
		end,
	})
end

local function getRules()
	if rules == nil then
		local ok, loaded = pcall(function()
			return { StateView = require(script.Parent.Parent.Rules.StateView) }
		end)
		if not ok then
			warn("[ProfileService] Rules unavailable: " .. tostring(loaded))
			return nil
		end
		rules = loaded
	end
	return rules
end

local function snapshot(player: Player)
	local state = states[player]
	local profile = store and store:Get(player.UserId)
	local out = { LoadState = state.loadState }
	if profile and (state.loadState == "Loaded" or state.loadState == "Studio") then
		out.Coins = profile.Coins
		out.Rooms = profile.Rooms
		-- Server-computed display values (Rules/StateView): the client runs no game rules.
		-- The active event is server-set on Workspace (EventService).
		local r = getRules()
		if r then
			local active = workspace:GetAttribute("ActiveEvent")
			local world = { EventId = if active ~= "" then active else nil, UnlockAll = state.transient.ThreatUnlockAll == true }
			local ok, derived = pcall(r.StateView.Derived, profile, world)
			if ok then
				for key, value in derived do
					out[key] = value
				end
			else
				warn("[ProfileService] Snapshot rules failed: " .. tostring(derived))
			end
		end
		out.Layout = profile.Layout
		out.Tutorial = profile.Tutorial
		out.Settings = profile.Settings
		out.Stats = profile.Stats
		out.Discovered = profile.Discovered
		out.Xp = profile.Xp
		out.Level = profile.Level
		out.Boxes = profile.Boxes
		out.Blueprints = profile.Blueprints
		out.Permanent = profile.Permanent
		out.BoxPity = profile.BoxPity
	end
	for key, value in state.transient do
		out[key] = value
	end
	return out
end

local function push(player: Player)
	if states[player] and player.Parent then
		Net.Fire("State", player, snapshot(player))
	end
end

local function notice(player: Player, text: string, kind: string)
	if player.Parent then
		Net.Fire("Notice", player, { Text = text, Kind = kind })
	end
end

local function waitForSaveSlot(userId: number)
	while store and store:IsSaving(userId) do
		task.wait(0.1)
	end
end

-- True while a connected player (other than `except`) holds a state for this user,
-- e.g. a rejoin on this server while an earlier release is still queued.
local function hasLivePlayer(userId: number, except: Player?): boolean
	for other in states do
		if other ~= except and other.UserId == userId and other.Parent ~= nil then
			return true
		end
	end
	return false
end

-- Sleeps up to `seconds`, waking early when the player leaves or the server closes.
local function sleepWhileHere(player: Player, seconds: number)
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime and player.Parent ~= nil and not shuttingDown do
		task.wait(math.min(0.5, untilTime - os.clock()))
	end
end

-- Saves one cached profile; `player` is nil once they left (a release that failed
-- earlier is retried by the autosave loop).
local function saveUser(userId: number, release: boolean?, player: Player?)
	waitForSaveSlot(userId)
	if store == nil or not store:IsLoaded(userId) then
		return false, "NotLoaded"
	end
	if release and not shuttingDown and hasLivePlayer(userId, player) then
		release = false -- they rejoined meanwhile: keep the entry for the new session
	end
	local token = store:Peek(userId)
	local ok, reason = store:Save(userId, release)
	if not ok then
		warn(("[ProfileService] Save for %d failed: %s"):format(userId, tostring(reason)))
		if reason == "LeaseLost" or reason == "StaleRevision" then
			-- Another server owns this profile now; never write from here again.
			store:Forget(userId, token)
			local state = player and states[player]
			if state then
				state.loadState = "Failed"
				notice(player, "Your data was opened on another server. Please rejoin.", "Bad")
				push(player)
			end
		end
	end
	return ok, reason
end

-- Leases and loads the profile; returns (profile) or (nil, reason). Runs while
-- loading[userId] is set so a rejoin cannot interleave with it.
local function loadBody(player: Player, userId: number)
	waitForSaveSlot(userId)
	local profile = store and store:Get(userId)
	local reason = if store then nil else "DataStoreUnavailable"
	if store and profile == nil then
		store:Forget(userId) -- a lost-lease copy is never reused
		local deadline = os.clock() + ProfileService.LOAD_WAIT_SECONDS
		local delay = ProfileService.LOAD_RETRY_SECONDS
		local told = false
		while true do
			if not player.Parent then
				return nil, "Left"
			end
			profile, reason = store:Load(userId)
			if profile or reason ~= "LeaseHeld" or shuttingDown or os.clock() + delay > deadline then
				break
			end
			if not told then
				told = true
				notice(player, "Waiting for your save from another server...", "Info")
			end
			sleepWhileHere(player, delay)
			delay = math.min(delay * 1.5, 10)
		end
	end
	if profile and (not player.Parent or shuttingDown) then
		saveUser(userId, true, nil) -- left (or server closing) while loading: hand the lease back
		return nil, "Left"
	end
	return profile, reason
end

local function loadPlayer(player: Player)
	local userId = player.UserId
	local state = { loadState = "Loading", transient = {} }
	states[player] = state
	push(player)

	-- A load or release for this user from an earlier session is still running:
	-- wait for it so it cannot delete this session's entry.
	while loading[userId] do
		task.wait(0.1)
	end
	if not player.Parent or states[player] ~= state then
		return
	end
	loading[userId] = true
	pendingLoads += 1
	local ran, profile, reason = pcall(loadBody, player, userId)
	loading[userId] = nil
	pendingLoads -= 1
	if not ran then
		reason = profile
		profile = nil
		warn("[ProfileService] Load crashed: " .. tostring(reason))
	end

	if reason == "Left" or not player.Parent or states[player] ~= state then
		return
	end
	if profile == nil then
		warn(("[ProfileService] Could not load profile %d: %s"):format(userId, tostring(reason)))
		state.loadState = "Failed"
		notice(
			player,
			if reason == "LeaseHeld"
				then "Your data is still open on another server. Please rejoin in a minute."
				else "Could not load your data safely. Nothing was changed. Please rejoin.",
			"Bad"
		)
		push(player)
		return
	end
	state.loadState = if usingMemoryStore then "Studio" else "Loaded"
	push(player)
	ProfileService.Loaded:Fire(player, profile)
end

local function removePlayer(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	local profile = store and store:Get(player.UserId)
	if profile then
		ProfileService.Removing:Fire(player, profile)
	end
	-- Always fires, even when there is no profile (failed load, lost lease).
	ProfileService.Left:Fire(player)
	if profile then
		saveUser(player.UserId, true, player)
	end
	if states[player] == state then
		states[player] = nil
	end
end

local function validSettings(settings: any): boolean
	if type(settings) ~= "table" then
		return false
	end
	local count = 0
	for key, value in settings do
		count += 1
		if key == "ReducedMotion" then
			if type(value) ~= "boolean" then
				return false
			end
		elseif key == "MusicVolume" or key == "SfxVolume" then
			if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
				return false
			end
		else
			return false
		end
	end
	return count == 3
end

function ProfileService.Init()
	store = nil
	local gateway = createStore()
	activeGateway = gateway
	if gateway then
		local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
		store = ProfileStore.new({ gateway = gateway, jobId = jobId, clock = os.time })
	end
	Net.SetReadyCheck(function(player)
		return ProfileService.Get(player) ~= nil
	end)
	Net.Handle("SaveSettings", validSettings, function(player, settings)
		local profile = ProfileService.Get(player)
		if profile == nil then
			return false, "ProfileNotLoaded"
		end
		profile.Settings.ReducedMotion = settings.ReducedMotion
		profile.Settings.MusicVolume = settings.MusicVolume
		profile.Settings.SfxVolume = settings.SfxVolume
		ProfileService.Changed(player)
		return true, nil
	end)
end

function ProfileService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(removePlayer)

	-- Autosave renews every lease; profiles whose player left (a release that
	-- failed earlier) are released again.
	task.spawn(function()
		while true do
			task.wait(ProfileService.AUTOSAVE_SECONDS)
			if store then
				for _, userId in store:LoadedUserIds() do
					local player = Players:GetPlayerByUserId(userId)
					task.spawn(saveUser, userId, player == nil, player)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		if store == nil then
			return
		end
		activeGateway:SetMaxAttempts(ProfileService.SHUTDOWN_DATASTORE_ATTEMPTS)
		local remaining = 0
		for _, player in Players:GetPlayers() do
			local profile = store:Get(player.UserId)
			if profile then
				pcall(function()
					ProfileService.Removing:Fire(player, profile)
				end)
			end
		end
		for _, userId in store:LoadedUserIds() do
			remaining += 1
			task.spawn(function()
				saveUser(userId, true, Players:GetPlayerByUserId(userId))
				remaining -= 1
			end)
		end
		local deadline = os.clock() + ProfileService.SHUTDOWN_BUDGET_SECONDS
		while (remaining > 0 or pendingLoads > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- The live profile, or nil while loading, after a failed load or lost lease.
function ProfileService.Get(player: Player)
	local state = states[player]
	if state == nil or store == nil then
		return nil
	end
	if state.loadState ~= "Loaded" and state.loadState ~= "Studio" then
		return nil
	end
	return store:Get(player.UserId)
end

-- "Loading" | "Loaded" | "Studio" | "Failed" (nil for an unknown player).
function ProfileService.LoadState(player: Player): string?
	local state = states[player]
	return state and state.loadState
end

-- Call after mutating the profile (without yielding in between): marks it for
-- saving and pushes the new State snapshot to the owner.
function ProfileService.Changed(player: Player)
	if ProfileService.Get(player) == nil then
		return
	end
	store:MarkDirty(player.UserId)
	push(player)
end

-- Non-persistent state shown in the snapshot (e.g. Building, ThreatUnlockAll).
function ProfileService.SetTransient(player: Player, key: string, value: any)
	local state = states[player]
	if state == nil then
		return
	end
	if state.transient[key] ~= value then
		state.transient[key] = value
		push(player)
	end
end

function ProfileService.GetTransient(player: Player, key: string): any
	local state = states[player]
	return state and state.transient[key]
end

function ProfileService.SaveNow(player: Player)
	return saveUser(player.UserId, false, player)
end

return ProfileService
