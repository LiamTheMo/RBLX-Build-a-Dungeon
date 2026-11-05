--!strict
-- Plot-local grid maths (docs/ARCHITECTURE.md, "Plot geometry"). Local -Z is the
-- back of the plot, +Z the front where row 1 and the entrance are.

local Grid = require(script.Parent.Parent.Definitions.Grid)

local PlotGeometry = {}

local centreColumn = (Grid.Columns + 1) / 2
local centreRow = (Grid.Rows + 1) / 2

function PlotGeometry.CellLocal(column: number, row: number): Vector3
	return Vector3.new((column - centreColumn) * Grid.CellSize, 0, (centreRow - row) * Grid.CellSize)
end

function PlotGeometry.LocalToCell(localPos: Vector3): (number?, number?)
	local column = math.floor(localPos.X / Grid.CellSize + centreColumn + 0.5)
	local row = math.floor(centreRow - localPos.Z / Grid.CellSize + 0.5)
	-- NaN fails every comparison below, so it also lands outside.
	if not (column >= 1 and column <= Grid.Columns and row >= 1 and row <= Grid.Rows) then
		return nil, nil
	end
	return column, row
end

function PlotGeometry.SpawnLocal(): Vector3
	local entrance = Grid.EntranceCell
	return PlotGeometry.CellLocal(entrance.Column, entrance.Row) + Vector3.new(0, 0, Grid.CellSize)
end

return PlotGeometry
