--!strict
-- Plot grid shape (GDD "Building"; values from docs/PHASE0.md). Data only: the
-- route itself is computed by Rules/Route.
--
-- Cells are addressed { Column, Row }, both 1-based. Row 1 is the front edge,
-- where visitors arrive. Every room is a small open square (about player
-- height) with a doorway on all four sides, so orthogonally adjacent rooms
-- always connect. Rooms may go in any cell but the entrance (rule of
-- 2026-11-05); the server picks the route as the longest simple path of
-- adjacent rooms from the entrance, ending at the Treasure Room when it is
-- reachable. Rooms off that route are idle.

export type Cell = { Column: number, Row: number }

local Grid = {}

Grid.Version = 1

Grid.Columns = 5
Grid.Rows = 4

-- Studs. Rooms are miniature: visitors are scaled-down adventurers.
Grid.CellSize = 6
Grid.WallHeight = 5

-- Fixed for every plot; the route always starts here.
Grid.EntranceCell = table.freeze({ Column = 3, Row = 1 }) :: Cell

-- Doorway sides, as column/row offsets.
Grid.Sides = table.freeze({
	North = table.freeze({ Column = 0, Row = 1 }),
	East = table.freeze({ Column = 1, Row = 0 }),
	South = table.freeze({ Column = 0, Row = -1 }),
	West = table.freeze({ Column = -1, Row = 0 }),
})

return table.freeze(Grid)
