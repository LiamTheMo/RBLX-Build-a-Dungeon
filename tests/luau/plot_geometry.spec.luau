local Shared = game:GetService("ReplicatedStorage").Shared
local PlotGeometry = require(Shared.Rules.PlotGeometry)
local Grid = require(Shared.Definitions.Grid)

test("entrance cell is front and centre", function()
	local v = PlotGeometry.CellLocal(3, 1)
	expectEq(v.X, 0, "x")
	expectEq(v.Z, 1.5 * Grid.CellSize, "z")
end)

test("rows run back (-Z) as they increase and columns run +X", function()
	expect(PlotGeometry.CellLocal(3, 4).Z < PlotGeometry.CellLocal(3, 1).Z, "row 4 is behind row 1")
	expect(PlotGeometry.CellLocal(5, 2).X > PlotGeometry.CellLocal(1, 2).X, "column 5 is right of column 1")
end)

test("LocalToCell inverts CellLocal for every cell, including offsets inside the cell", function()
	for c = 1, Grid.Columns do
		for r = 1, Grid.Rows do
			local centre = PlotGeometry.CellLocal(c, r)
			for _, off in { Vector3.new(0, 0, 0), Vector3.new(2.9, 5, -2.9), Vector3.new(-2.9, -1, 2.9) } do
				local col, row = PlotGeometry.LocalToCell(centre + off)
				expectEq(col, c, "column")
				expectEq(row, r, "row")
			end
		end
	end
end)

test("LocalToCell is nil outside the grid and for NaN", function()
	expectEq(PlotGeometry.LocalToCell(Vector3.new(100, 0, 0)), nil, "far right")
	expectEq(PlotGeometry.LocalToCell(Vector3.new(0, 0, 100)), nil, "far front")
	expectEq(PlotGeometry.LocalToCell(Vector3.new(0, 0, -100)), nil, "far back")
	expectEq(PlotGeometry.LocalToCell(Vector3.new(0 / 0, 0, 0)), nil, "nan")
	expectEq(PlotGeometry.LocalToCell(Vector3.new(-2.6 * Grid.CellSize - 0.5, 0, 0)), nil, "just left")
end)

test("spawn is one cell in front of the entrance and outside the grid", function()
	local s = PlotGeometry.SpawnLocal()
	expectEq(s.X, 0, "x")
	expectEq(s.Z, 2.5 * Grid.CellSize, "z")
	expectEq(PlotGeometry.LocalToCell(s), nil, "outside grid")
end)
