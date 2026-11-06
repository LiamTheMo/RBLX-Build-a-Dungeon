-- Pure helpers for a profile's owned room instances (no Instances, no yielding).

local RoomInventory = {}

RoomInventory.MAX_ROOMS = 30

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

-- Adds a level-1 instance {Id, Level, Modifier?} and returns its id ("r" ..
-- serial). Never reuses an id. Rarity and perks come from the room definition,
-- never from the instance. `modifier` is an event modifier id
-- (Balance.Events.Modifiers), at most one.
function RoomInventory.Add(profile: any, roomId: string, modifier: string?): string
	local serial = profile.NextSerial
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
