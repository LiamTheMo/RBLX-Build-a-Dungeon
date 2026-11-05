-- Persisted player profile (docs/ARCHITECTURE.md "Profile"). Pure: no Instances.
-- Default() builds a new profile; Migrate() validates and repairs stored data.
-- The store metadata (profileRevision, sessionLease) rides along but is not part
-- of the gameplay schema.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rooms = require(ReplicatedStorage.Shared.Definitions.Rooms)
local Balance = require(ReplicatedStorage.Shared.Definitions.Balance)
local Visitors = require(ReplicatedStorage.Shared.Definitions.Visitors)
local Loot = require(ReplicatedStorage.Shared.Rules.Loot)
local Progression = require(ReplicatedStorage.Shared.Rules.Progression)

local ProfileSchema = {}

-- v2 adds Discovered (collection index). v1 -> v2 fills it from owned rooms and Stats.
-- v3 adds room Rarity/Perks, keeper Xp/Level, Boxes, Blueprints, Permanent and
-- BoxPity. v2 -> v3: rooms become Common; Xp is seeded from Stats.Wins at the
-- Novice rate (levels only, no retroactive level-up boxes).
ProfileSchema.VERSION = 3
ProfileSchema.MAX_MONEY = 1e12
ProfileSchema.MAX_LEVEL = Balance.Upgrades.MaxLevel

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
		Vault = 0,
		NextSerial = 3,
		Rooms = {
			r1 = { Id = "SlimeNest", Level = 1, Rarity = "Common", Perks = {} },
			r2 = { Id = "TreasureRoom", Level = 1, Rarity = "Common", Perks = {} },
		},
		Layout = { ["3,2"] = "r1" },
		Tutorial = { Step = "Welcome", Done = false },
		Settings = { ReducedMotion = false, MusicVolume = 0.5, SfxVolume = 0.8 },
		ChallengerUnlocked = false,
		Stats = { Encounters = 0, Wins = 0, Escapes = 0, Robberies = 0, Earned = 0 },
		Discovered = { SlimeNest = true, TreasureRoom = true },
		Xp = 0,
		Level = 1,
		Boxes = { Dungeon = 0, Rare = 0 },
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
	local profile = {
		Version = ProfileSchema.VERSION,
		Coins = whole(stored.Coins, ProfileSchema.MAX_MONEY),
		Vault = whole(stored.Vault, ProfileSchema.MAX_MONEY),
		profileRevision = whole(stored.profileRevision, 2 ^ 52),
		ChallengerUnlocked = boolOr(stored.ChallengerUnlocked, false),
	}

	-- Store metadata: keep a well-formed lease so a held lease is honoured.
	local lease = stored.sessionLease
	if type(lease) == "table" and type(lease.jobId) == "string" and isFinite(lease.expiresAt) then
		profile.sessionLease = { jobId = lease.jobId, expiresAt = lease.expiresAt }
	end

	-- Rooms: only known, player-placeable room ids with a sane rarity and a level
	-- within that rarity's cap. Perks: known, distinct kinds, at most the
	-- rarity's count; Amount is re-derived from Balance (never trusted).
	local rooms = {}
	local highestSerial = 0
	for instanceId, room in asTable(stored.Rooms) do
		local serial = serialOf(instanceId)
		local def = type(room) == "table" and type(room.Id) == "string" and Rooms.All[room.Id] or nil
		if serial and def and def.Placeable then
			local rarity = if Loot.RarityRank(room.Rarity) then room.Rarity else "Common"
			local maxLevel = Balance.Rarities[rarity].MaxLevel
			local level = isFinite(room.Level) and math.clamp(math.floor(room.Level), 1, maxLevel) or 1
			local perks, seen = {}, {}
			for _, perk in asTable(room.Perks) do
				local kind = type(perk) == "table" and perk.Kind or nil
				local amount = Loot.PerkAmount(rarity, kind)
				if amount and not seen[kind] and #perks < Balance.Rarities[rarity].PerkCount then
					seen[kind] = true
					table.insert(perks, { Kind = kind, Amount = amount })
				end
			end
			rooms[instanceId] = { Id = room.Id, Level = level, Rarity = rarity, Perks = perks }
			highestSerial = math.max(highestSerial, serial)
		end
	end
	profile.Rooms = rooms
	-- NextSerial must stay above every existing id, or a purchase could reuse one.
	local nextSerial = isFinite(stored.NextSerial) and math.floor(stored.NextSerial) or 0
	profile.NextSerial = math.max(nextSerial, highestSerial + 1, 1)

	-- Layout: drop entries pointing at missing or duplicate instances (in key
	-- order so the repair is deterministic), then require a valid route.
	local storedLayout = asTable(stored.Layout)
	local keys = {}
	for key, instanceId in storedLayout do
		if type(key) == "string" and type(instanceId) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local layout, used, cells = {}, {}, {}
	for _, key in keys do
		local instanceId = storedLayout[key]
		if rooms[instanceId] and not used[instanceId] then
			layout[key] = instanceId
			cells[key] = rooms[instanceId].Id
			used[instanceId] = true
		end
	end
	local Route = require(ReplicatedStorage.Shared.Rules.Route)
	local routeOk = Route.Build(cells)
	profile.Layout = if routeOk then layout else {}

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
