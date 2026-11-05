--!strict
-- Layout validation: a valid dungeon is one unbranched chain from the entrance
-- (docs/PHASE0.md, "Grid and route"). Input may come from clients, so it is
-- checked defensively and refusals are reason codes, never errors.

local Grid = require(script.Parent.Parent.Definitions.Grid)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)

local Route = {}

function Route.Key(column: number, row: number): string
	return column .. "," .. row
end

function Route.Parse(key: any): (number?, number?)
	if type(key) ~= "string" or #key > 8 then
		return nil, nil
	end
	local c, r = string.match(key, "^(%d+),(%d+)$")
	local column, row = tonumber(c), tonumber(r)
	-- Canonical form only, so "03,2" cannot alias "3,2".
	if column == nil or row == nil or Route.Key(column, row) ~= key then
		return nil, nil
	end
	return column, row
end

local entranceKey = Route.Key(Grid.EntranceCell.Column, Grid.EntranceCell.Row)

local function neighbours(node: { Column: number, Row: number }, nodes: { [string]: any }): { string }
	local found = {}
	for _, side in Grid.Sides do
		local k = Route.Key(node.Column + side.Column, node.Row + side.Row)
		if nodes[k] then
			table.insert(found, k)
		end
	end
	table.sort(found)
	return found
end

function Route.Build(cells: any): (boolean, any, string?)
	if type(cells) ~= "table" then
		return false, "BadCell", nil
	end

	-- Per-cell checks in key order, so the offending cell is deterministic.
	local keys: { string } = {}
	for key in cells do
		if type(key) ~= "string" then
			return false, "BadCell", nil
		end
		table.insert(keys, key)
	end
	table.sort(keys)

	local counts: { [string]: number } = {}
	local nodes: { [string]: { Column: number, Row: number } } = {
		[entranceKey] = { Column = Grid.EntranceCell.Column, Row = Grid.EntranceCell.Row },
	}
	for _, key in keys do
		local column, row = Route.Parse(key)
		if column == nil or row == nil then
			return false, "BadCell", key
		end
		if column < 1 or column > Grid.Columns or row < 1 or row > Grid.Rows then
			return false, "OutOfBounds", key
		end
		if key == entranceKey then
			return false, "OnEntrance", key
		end
		local roomId = cells[key]
		local def = if type(roomId) == "string" then Rooms.Get(roomId) else nil
		if def == nil then
			return false, "UnknownRoom", key
		end
		if not def.Placeable then
			return false, "NotPlaceable", key
		end
		counts[roomId] = (counts[roomId] or 0) + 1
		if def.MaxPlaced and counts[roomId] > def.MaxPlaced then
			return false, "TooManyOfRoom", key
		end
		nodes[key] = { Column = column, Row = row }
	end

	if #keys == 0 then
		return true, {}
	end

	-- Walk outwards from the entrance; any cycle or fork is rejected.
	local order: { string } = {}
	local parent: { [string]: string | boolean } = { [entranceKey] = false }
	local queue = { entranceKey }
	local head = 1
	local branchAt: string? = nil -- reported after the walk, so a cycle is named a Loop first
	while head <= #queue do
		local key = queue[head]
		head += 1
		local children = {}
		for _, n in neighbours(nodes[key], nodes) do
			if n ~= parent[key] then
				if parent[n] ~= nil then
					return false, "Loop", if key == entranceKey then n else key
				end
				table.insert(children, n)
			end
		end
		if #children > 1 and branchAt == nil then
			branchAt = if key == entranceKey then children[2] else key
		end
		for _, n in children do
			parent[n] = key
			table.insert(queue, n)
			table.insert(order, n)
		end
	end

	if branchAt then
		return false, "Branch", branchAt
	end

	if #order < #keys then
		for _, key in keys do
			if parent[key] == nil then
				return false, "Disconnected", key
			end
		end
	end

	for i, key in order do
		local def = Rooms.Get(cells[key])
		if def and def.EndsRoute and i < #order then
			return false, "TreasureNotLast", key
		end
	end
	return true, order
end

return Route
