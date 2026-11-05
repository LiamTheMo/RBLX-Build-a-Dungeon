-- Hides Door_<Side> pieces on sides that connect to the entrance or another
-- placed room (adjacent rooms always connect). Local-only property changes.
local Catalog = require(script.Parent.Catalog)

local Doors = {}

-- Which neighbouring cell each art door piece faces (column/row offsets; row 1
-- is the front of the plot, so North is row + 1).
local SIDES = {
	North = { 0, 1 },
	East = { 1, 0 },
	South = { 0, -1 },
	West = { -1, 0 },
}

-- `key` is the model's cell key ("c,r"); occupied(cellKey) -> boolean for placed
-- rooms (the entrance is added here). Needs the catalog (Catalog.Wait()).
function Doors.Apply(model: Instance, key: string, occupied: (string) -> boolean)
	local c, r = string.match(key, "^(%d+),(%d+)$")
	local column, row = tonumber(c), tonumber(r)
	if column == nil or row == nil then
		return
	end
	local entranceKey = Catalog.Current and Catalog.Current.Grid.EntranceKey
	for sideName, off in SIDES do
		local door = model:FindFirstChild("Door_" .. sideName, true)
		if door and door:IsA("BasePart") then
			if door:GetAttribute("DoorT") == nil then
				door:SetAttribute("DoorT", door.Transparency)
				door:SetAttribute("DoorC", door.CanCollide)
			end
			local neighbour = (column + off[1]) .. "," .. (row + off[2])
			if neighbour == entranceKey or occupied(neighbour) then
				door.Transparency = 1
				door.CanCollide = false
			else
				door.Transparency = door:GetAttribute("DoorT")
				door.CanCollide = door:GetAttribute("DoorC")
			end
		end
	end
end

return Doors
