-- Pure helpers for a profile's owned room instances (no Instances, no yielding).

local Balance = require(script.Parent.Parent.Definitions.Balance)

local RoomInventory = {}

-- Storage cap: spare rooms (not placed in the layout). Placed rooms never count.
RoomInventory.MAX_STORED = Balance.Loot.RoomStorage
-- Hard bound on one batch of room ids: a full store plus every grid cell (5x4).
RoomInventory.MAX_BATCH = RoomInventory.MAX_STORED + 20
RoomInventory.MAX_SERIAL = 99999999999

-- Rooms owned but not placed in profile.Layout.
function RoomInventory.StoredCount(profile: any): number
	local placed = {}
	for _, instanceId in profile.Layout or {} do
		placed[instanceId] = true
	end
	local n = 0
	for instanceId in profile.Rooms do
		if not placed[instanceId] then
			n += 1
		end
	end
	return n
end

-- Free storage slots (never negative).
function RoomInventory.StorageLeft(profile: any): number
	return math.max(0, RoomInventory.MAX_STORED - RoomInventory.StoredCount(profile))
end

function RoomInventory.Count(profile: any): number
	local n = 0
	for _ in profile.Rooms do
		n += 1
	end
	return n
end

function RoomInventory.Owns(profile: any, roomId: string): boolean
	for _, room in profile.Rooms do
		if room.Id == roomId then
			return true
		end
	end
	return false
end

function RoomInventory.CanAdd(profile: any, count: number): boolean
	local serial = profile.NextSerial
	if type(serial) ~= "number" or serial < 1 or serial >= RoomInventory.MAX_SERIAL or serial % 1 ~= 0 then return false end
	for _ = 1, count do
		while profile.Rooms["r" .. serial] ~= nil do
			serial += 1
			if serial >= RoomInventory.MAX_SERIAL then return false end
		end
		serial += 1
		if serial > RoomInventory.MAX_SERIAL then return false end
	end
	return true
end

-- Adds a level-1 instance {Id, Level, Modifier?} and returns its id ("r" ..
-- serial). Never reuses an id. Rarity and perks come from the room definition,
-- never from the instance. `modifier` is an event modifier id
-- (Balance.Events.Modifiers), at most one.
function RoomInventory.Add(profile: any, roomId: string, modifier: string?): string
	local serial = profile.NextSerial
	assert(RoomInventory.CanAdd(profile, 1), "Room serial exhausted")
	while profile.Rooms["r" .. serial] ~= nil do
		serial += 1
	end
	local instanceId = "r" .. serial
	profile.NextSerial = serial + 1
	profile.Rooms[instanceId] = { Id = roomId, Level = 1, Modifier = modifier }
	profile.Discovered = profile.Discovered or {}
	profile.Discovered[roomId] = true
	return instanceId
end

-- True if the instance is placed in the layout.
function RoomInventory.IsPlaced(profile: any, instanceId: string): boolean
	for _, placed in profile.Layout do
		if placed == instanceId then
			return true
		end
	end
	return false
end

return RoomInventory
