--!strict
-- Plot grid shape (GDD "Building"; values from docs/PHASE0.md). Data only: the
-- server's route validation arrives in Phase 1.
--
-- Cells are addressed { Column, Row }, both 1-based. Row 1 is the front edge,
-- where visitors arrive. Every room is a small open square (about player
-- height) with a doorway on all four sides, so orthogonally adjacent rooms
-- always connect. A valid layout is therefore one unbranched chain that starts
-- at the entrance: each room touches only the rooms before and after it on the
-- route. The route ends at its last room, or at the Treasure Room if one is
-- placed (it must be the last room).

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
