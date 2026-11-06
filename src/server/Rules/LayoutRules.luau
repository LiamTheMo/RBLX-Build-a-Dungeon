--!strict
-- Server-side check of a client-submitted layout (cellKey -> room instance id)
-- against the player's profile, then the route rules (Route.Build). Any shape is
-- accepted; rooms the route does not use are idle (offRouteCells).

local Definitions = script.Parent.Parent.Definitions
local Grid = require(Definitions.Grid)
local Route = require(script.Parent.Route)

local MAX_CELLS = Grid.Columns * Grid.Rows - 1 -- every cell but the entrance

local LayoutRules = {}

-- Returns (true, routeCells, cells, offRouteCells) with cells = cellKey -> roomId
-- (every placed room, on the route or not), or (false, reason, cellKey?).
function LayoutRules.Validate(profile: any, layout: any): (boolean, any, any, any)
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

	local ok, routeOrReason, offRouteOrKey = Route.Build(cells)
	if not ok then
		return false, routeOrReason, offRouteOrKey
	end
	return true, routeOrReason, cells, offRouteOrKey
end

return LayoutRules
