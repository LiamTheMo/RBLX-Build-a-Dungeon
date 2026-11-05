-- Hides Door_<Side> pieces on sides that connect to the entrance or another
-- placed room (adjacent rooms always connect). Local-only property changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Grid = require(ReplicatedStorage.Shared.Definitions.Grid)
local Route = require(ReplicatedStorage.Shared.Rules.Route)

local Doors = {}

local entranceKey = Route.Key(Grid.EntranceCell.Column, Grid.EntranceCell.Row)

-- occupied(cellKey) -> boolean for placed rooms (the entrance is added here).
function Doors.Apply(model: Instance, column: number, row: number, occupied: (string) -> boolean)
	for sideName, off in Grid.Sides do
		local door = model:FindFirstChild("Door_" .. sideName, true)
		if door and door:IsA("BasePart") then
			if door:GetAttribute("DoorT") == nil then
				door:SetAttribute("DoorT", door.Transparency)
				door:SetAttribute("DoorC", door.CanCollide)
			end
			local key = Route.Key(column + off.Column, row + off.Row)
			if key == entranceKey or occupied(key) then
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
