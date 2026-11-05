--!strict
-- Server-side check of a client-submitted layout (cellKey -> room instance id)
-- against the player's profile, then the shared route rules.

local Definitions = script.Parent.Parent.Definitions
local Grid = require(Definitions.Grid)
local Route = require(script.Parent.Route)

local MAX_CELLS = Grid.Columns * Grid.Rows - 1 -- every cell but the entrance

local LayoutRules = {}

-- Returns (true, routeCells, cells) with cells = cellKey -> roomId, or (false, reason, cellKey?).
function LayoutRules.Validate(profile: any, layout: any): (boolean, any, any)
	if type(layout) ~= "table" then
		return false, "BadArgs", nil
	end

	local keys: { string } = {}
	for key, instanceId in layout do
		if type(key) ~= "string" or type(instanceId) ~= "string" then
			return false, "BadArgs", nil
		end
		table.insert(keys, key)
		if #keys > MAX_CELLS then
			return false, "TooManyRooms", nil
		end
	end
	table.sort(keys)

	local cells: { [string]: string } = {}
	local used: { [string]: boolean } = {}
	for _, key in keys do
		local instanceId = layout[key]
		local owned = profile.Rooms[instanceId]
		if type(owned) ~= "table" then
			return false, "NotOwned", key
		end
		if used[instanceId] then
			return false, "DuplicateInstance", key
		end
		used[instanceId] = true
		cells[key] = owned.Id
	end

	local ok, routeOrReason, offender = Route.Build(cells)
	if not ok then
		return false, routeOrReason, offender
	end
	return true, routeOrReason, cells
end

return LayoutRules
