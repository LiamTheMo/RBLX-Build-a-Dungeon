-- Persisted player profile (docs/ARCHITECTURE.md "Profile"). Pure: no Instances.
-- Default() builds a new profile; Migrate() validates and repairs stored data.
-- The store metadata (profileRevision, sessionLease) rides along but is not part
-- of the gameplay schema.

local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Balance = require(script.Parent.Parent.Definitions.Balance)
local Visitors = require(script.Parent.Parent.Definitions.Visitors)
local Events = require(script.Parent.Events)
local Loot = require(script.Parent.Loot)
local Economy = require(script.Parent.Economy)
local Progression = require(script.Parent.Progression)
local Threat = require(script.Parent.Threat)

local ProfileSchema = {}

-- v2 adds Discovered (collection index). v1 -> v2 fills it from owned rooms and Stats.
-- v3 adds room Rarity/Perks, keeper Xp/Level, Boxes, Blueprints, Permanent and
-- BoxPity. v2 -> v3: rooms become Common; Xp is seeded from Stats.Wins at the
-- Novice rate (levels only, no retroactive level-up boxes).
-- v4 replaces the vault balance with VaultPercent and adds Threat and room
-- Modifier. v3 -> v4: Coins += Vault, Vault dropped, VaultPercent = 0, Threat = 1.
-- v5 (item model of 2026-11-05) moves rarity and perks to the room definitions:
-- a room instance is {Id, Level, Modifier?}. v4 -> v5: instance Rarity/Perks are
-- dropped and Level is clamped to the definition's tier cap; every other field kept.
-- v7 adds Crystal chests; older servers must not overwrite them.
-- v8 adds new chest-specific room identities.
ProfileSchema.VERSION = 8
ProfileSchema.MAX_MONEY = 1e12

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end
ProfileSchema.DeepCopy = deepCopy

function ProfileSchema.Default()
	return {
		Version = ProfileSchema.VERSION,
		Coins = 0,
		VaultPercent = 0, -- 0..100: share of Coins at risk while the Treasure Room is on the route
		Threat = 1, -- selected threat tier (Balance.Threat)
		NextSerial = 3,
		Rooms = {
			r1 = { Id = "SlimeNest", Level = 1 },
			r2 = { Id = "TreasureRoom", Level = 1 }, -- the Coin Cache
		},
		Layout = { ["3,2"] = "r1" },
		Tutorial = { Step = "Welcome", Done = false },
		Settings = { ReducedMotion = false, MusicVolume = 0.5, SfxVolume = 0.4 },
		ChallengerUnlocked = false, -- legacy (the challenger invite was removed in v4); kept, unused
		Stats = { Encounters = 0, Wins = 0, Escapes = 0, Robberies = 0, Earned = 0 },
		Discovered = { SlimeNest = true, TreasureRoom = true },
		Xp = 0,
		Level = 1,
		Boxes = { Dungeon = 0, Rare = 0, Crystal = 0 },
		Blueprints = {}, -- roomId -> count
		Permanent = {}, -- upgradeId -> level (absent = 0)
		BoxPity = 0, -- boxes opened in a row below Balance.Loot.PityRarity
		profileRevision = 0,
	}
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Floors to a whole number in [0, max]; anything that is not a finite number is 0.
local function whole(value: any, max: number): number
	if not isFinite(value) then
		return 0
	end
	return math.clamp(math.floor(value), 0, max)
end

local function fraction(value: any, fallback: number): number
	if not isFinite(value) then
		return fallback
	end
	return math.clamp(value, 0, 1)
end

local function boolOr(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function serialOf(instanceId: any): number?
	if type(instanceId) ~= "string" or #instanceId > 12 then
		return nil
	end
	local digits = string.match(instanceId, "^r(%d+)$")
	return digits and tonumber(digits) or nil
end

local function asTable(value: any): { [any]: any }
	return if type(value) == "table" then value else {}
end

-- Returns (profile) or (nil, problem). Problems: "Corrupt", "NewerVersion". A nil
-- `stored` is a brand-new player and yields Default(). Never mutates `stored`.
function ProfileSchema.Migrate(stored: any)
	if stored == nil then
		return ProfileSchema.Default()
	end
	if type(stored) ~= "table" or type(stored.Version) ~= "number" or stored.Version < 1 then
		return nil, "Corrupt"
	end
	if stored.Version > ProfileSchema.VERSION then
		return nil, "NewerVersion"
	end

	local default = ProfileSchema.Default()
	local coins = whole(stored.Coins, ProfileSchema.MAX_MONEY)
	if stored.Version < 4 then
		coins = math.min(ProfileSchema.MAX_MONEY, coins + whole(stored.Vault, ProfileSchema.MAX_MONEY))
	end
	local profile = {
		Version = ProfileSchema.VERSION,
		Coins = coins,
		VaultPercent = if stored.Version < 4 then 0 else whole(stored.VaultPercent, 100),
		Threat = if Threat.Valid(stored.Threat) then stored.Threat else 1,
		profileRevision = whole(stored.profileRevision, 2 ^ 52),
		ChallengerUnlocked = boolOr(stored.ChallengerUnlocked, false),
	}

	-- Store metadata: keep a well-formed lease so a held lease is honoured.
	local lease = stored.sessionLease
	if type(lease) == "table" and type(lease.jobId) == "string" and isFinite(lease.expiresAt) then
		profile.sessionLease = { jobId = lease.jobId, expiresAt = lease.expiresAt }
	end

	-- Rooms: only known, player-placeable room ids, as {Id, Level, Modifier?}.
	-- Rarity and perks belong to the definition (v5): any saved Rarity/Perks are
	-- dropped. Level is clamped to the definition's tier cap.
	local rooms = {}
	local highestSerial = 0
	for instanceId, room in asTable(stored.Rooms) do
		local serial = serialOf(instanceId)
		local def = type(room) == "table" and type(room.Id) == "string" and Rooms.All[room.Id] or nil
		if serial and def and def.Placeable then
			local maxLevel = Economy.MaxLevel(def.Rarity)
			local level = isFinite(room.Level) and math.clamp(math.floor(room.Level), 1, maxLevel) or 1
			local modifier = if Events.Modifier(room.Modifier) then room.Modifier else nil
			rooms[instanceId] = { Id = room.Id, Level = level, Modifier = modifier }
			highestSerial = math.max(highestSerial, serial)
		end
	end
	profile.Rooms = rooms
	-- NextSerial must stay above every existing id, or a purchase could reuse one.
	local nextSerial = isFinite(stored.NextSerial) and math.floor(stored.NextSerial) or 0
	profile.NextSerial = math.max(nextSerial, highestSerial + 1, 1)

	-- Layout: drop, entry by entry in key order (so the repair is deterministic),
	-- cells that are malformed, out of bounds or on the entrance, entries pointing
	-- at missing or duplicate instances or unplaceable rooms, and rooms over their
	-- MaxPlaced or their Kind's limit (Rooms.KindLimit: one treasure of any tier).
	-- The shape is never repaired: any shape is valid since 2026-11-05
	-- (Route.Build only picks the route; other rooms are idle).
	local Route = require(script.Parent.Route)
	local storedLayout = asTable(stored.Layout)
	local keys = {}
	for key, instanceId in storedLayout do
		if type(key) == "string" and type(instanceId) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local layout, used, counts, kinds = {}, {}, {}, {}
	for _, key in keys do
		local instanceId = storedLayout[key]
		local room = rooms[instanceId]
		if room and not used[instanceId] and Route.CellProblem(key, room.Id) == nil then
			local def = Rooms.Get(room.Id) :: any
			local count = (counts[room.Id] or 0) + 1
			local kindCount = (kinds[def.Kind] or 0) + 1
			local kindLimit = Rooms.KindLimit[def.Kind]
			if not (def.MaxPlaced and count > def.MaxPlaced) and not (kindLimit and kindCount > kindLimit) then
				layout[key] = instanceId
				used[instanceId] = true
				counts[room.Id] = count
				kinds[def.Kind] = kindCount
			end
		end
	end
	profile.Layout = layout

	local tutorial = asTable(stored.Tutorial)
	profile.Tutorial = {
		Step = if type(tutorial.Step) == "string" and #tutorial.Step >= 1 and #tutorial.Step <= 32
			then tutorial.Step
			else default.Tutorial.Step,
		Done = boolOr(tutorial.Done, false),
	}

	local settings = asTable(stored.Settings)
	profile.Settings = {
		ReducedMotion = boolOr(settings.ReducedMotion, false),
		MusicVolume = fraction(settings.MusicVolume, default.Settings.MusicVolume),
		SfxVolume = fraction(settings.SfxVolume, default.Settings.SfxVolume),
	}

	local stats = asTable(stored.Stats)
	profile.Stats = {}
	for name in default.Stats do
		profile.Stats[name] = whole(stats[name], ProfileSchema.MAX_MONEY)
	end

	-- Collection index (v2). Stored ids are kept only if they are real rooms or
	-- visitors; owned rooms always count. A v1 profile has none, so visitors are
	-- implied by Stats: the practice visitor by one encounter, a Novice by two.
	local discovered = {}
	for id, flag in asTable(stored.Discovered) do
		if flag == true and type(id) == "string" and (Rooms.All[id] or Visitors.All[id]) then
			discovered[id] = true
		end
	end
	for _, room in rooms do
		discovered[room.Id] = true
	end
	if stored.Version < 2 then
		if profile.Stats.Encounters >= 1 then
			discovered.Practice = true
		end
		if profile.Stats.Encounters >= 2 then
			discovered.Novice = true
		end
	end
	profile.Discovered = discovered

	-- Keeper progression (v3).
	local P = Balance.Progression
	local level = isFinite(stored.Level) and math.clamp(math.floor(stored.Level), 1, P.MaxLevel) or 1
	local xp = whole(stored.Xp, ProfileSchema.MAX_MONEY)
	if stored.Version < 3 then
		level, xp = Progression.AddXp(1, 0, profile.Stats.Wins * P.Xp.Novice)
	end
	profile.Level = level
	profile.Xp = if level >= P.MaxLevel then 0 else math.min(xp, Progression.XpToNext(level) - 1)
	profile.Threat = math.min(profile.Threat, Threat.Unlocked(level))

	local cap = Balance.Loot.MaxStack
	local boxes = asTable(stored.Boxes)
	profile.Boxes = {}
	for _, boxType in Loot.BoxTypes do
		profile.Boxes[boxType] = whole(boxes[boxType], cap)
	end
	profile.Blueprints = {}
	for roomId, count in asTable(stored.Blueprints) do
		local n = whole(count, cap)
		if Loot.Craftable(roomId) and n > 0 then
			profile.Blueprints[roomId] = n
		end
	end
	profile.Permanent = {}
	for _, id in Balance.Permanent.Order do
		local n = whole(asTable(stored.Permanent)[id], Balance.Permanent[id].MaxLevel)
		if n > 0 then
			profile.Permanent[id] = n
		end
	end
	profile.BoxPity = whole(stored.BoxPity, Balance.Loot.PityAfter)

	return profile
end

return ProfileSchema
