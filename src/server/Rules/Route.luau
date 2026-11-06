--!strict
-- Layout checks and the visitors' route (docs/PHASE0.md, "Grid and route";
-- owner-approved rule of 2026-11-05). Rooms may sit in any cell but the
-- entrance; a layout is never refused for its shape. The route is the LONGEST
-- simple path (most rooms) through orthogonally adjacent rooms, starting at a
-- room next to the entrance. If a room with EndsRoute (the Treasure Room) is
-- reachable, the route is the longest path that ENDS at it; otherwise it is the
-- longest path overall and the treasure is off the route. Ties go to the path
-- whose cell-key sequence sorts first, so preview, commit and every later
-- recomputation agree. Rooms not on the route are idle.
--
-- Input may come from clients, so it is checked defensively and refusals are
-- reason codes, never errors.

local Grid = require(script.Parent.Parent.Definitions.Grid)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)

local Route = {}

-- Hard cap on DFS node visits per Build. The grid has at most 19 rooms and the
-- parity bound below keeps real layouts far under this (see route.spec); if it
-- is ever hit, the best path found so far is used (deterministic, since the
-- search order is fixed).
Route.MaxVisits = 4000
-- Diagnostics only (specs): DFS visits of the last Build that searched.
Route.LastVisits = 0

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

-- Why one cell entry cannot be placed, or nil. MaxPlaced is not checked here
-- (it depends on the other entries).
function Route.CellProblem(key: any, roomId: any): string?
	local column, row = Route.Parse(key)
	if column == nil or row == nil then
		return "BadCell"
	end
	if column < 1 or column > Grid.Columns or row < 1 or row > Grid.Rows then
		return "OutOfBounds"
	end
	if key == entranceKey then
		return "OnEntrance"
	end
	local def = if type(roomId) == "string" then Rooms.Get(roomId) else nil
	if def == nil then
		return "UnknownRoom"
	end
	if not def.Placeable then
		return "NotPlaceable"
	end
	return nil
end

-- Longest simple path. Node 0 is the entrance (not part of the route); nodes
-- 1..n are the rooms in key order, so adjacency lists in index order are in key
-- order and the DFS meets paths in lexicographic key order. Only a strictly
-- longer path replaces the best one, so the first longest path found wins ties.
local function longestPath(keys: { string }, cells: { [string]: string }): { number }
	local n = #keys
	local col, row, colour = {}, {}, {}
	local index: { [string]: number } = { [entranceKey] = 0 }
	col[0], row[0] = Grid.EntranceCell.Column, Grid.EntranceCell.Row
	local treasure: number? = nil
	for i, key in keys do
		local c, r = Route.Parse(key)
		col[i], row[i] = c :: number, r :: number
		index[key] = i
		local def = Rooms.Get(cells[key])
		if def and def.EndsRoute then
			treasure = i
		end
	end
	local adj: { [number]: { number } } = {}
	for i = 0, n do
		colour[i] = (col[i] + row[i]) % 2
		local list = {}
		for _, side in Grid.Sides do
			local j = index[Route.Key(col[i] + side.Column, row[i] + side.Row)]
			if j and j ~= 0 then
				table.insert(list, j)
			end
		end
		table.sort(list)
		adj[i] = list
	end

	local onPath: { [number]: boolean } = { [0] = true }
	local seen: { [number]: number } = {}
	local stamp = 0
	local queue: { number } = {}

	-- Rooms reachable from `from` without using rooms already on the path; the
	-- treasure (when it ends the route) is never walked through. Returns the
	-- count of rooms coloured unlike / like `from`, and whether the treasure is
	-- among them.
	local function reach(from: number, stopAtTreasure: boolean): (number, number, boolean)
		stamp += 1
		local head, tail = 1, 0
		for _, j in adj[from] do
			if not onPath[j] and seen[j] ~= stamp then
				seen[j] = stamp
				tail += 1
				queue[tail] = j
			end
		end
		local unlike, like, found = 0, 0, false
		while head <= tail do
			local v = queue[head]
			head += 1
			if colour[v] == colour[from] then
				like += 1
			else
				unlike += 1
			end
			if v == treasure then
				found = true
				if stopAtTreasure then
					continue
				end
			end
			for _, j in adj[v] do
				if not onPath[j] and seen[j] ~= stamp then
					seen[j] = stamp
					tail += 1
					queue[tail] = j
				end
			end
		end
		return unlike, like, found
	end

	local _, _, treasureReachable = reach(0, false)
	local mustEnd = treasure ~= nil and treasureReachable

	local path: { number } = {}
	local best: { number } = {}
	local visits = 0
	local aborted = false
	Route.LastVisits = 0

	local function dfs(v: number, depth: number)
		visits += 1
		if visits > Route.MaxVisits then
			aborted = true
			return
		end
		if mustEnd then
			if v == treasure then
				if depth > #best then
					best = table.clone(path)
				end
				return
			end
		elseif depth > #best then
			best = table.clone(path)
		end
		-- Upper bound: the path alternates colours (grid is bipartite), so with
		-- `unlike` / `like` rooms still reachable it can add at most
		-- min(2 * unlike, 2 * like + 1) more; ending at the treasure also fixes
		-- the parity of that count.
		local unlike, like, found = reach(v, mustEnd)
		if mustEnd and not found then
			return
		end
		local extra = math.min(2 * unlike, 2 * like + 1)
		if mustEnd then
			local odd = colour[treasure :: number] ~= colour[v]
			if (extra % 2 == 1) ~= odd then
				extra -= 1
			end
		end
		if depth + extra <= #best then
			return
		end
		for _, j in adj[v] do
			if not onPath[j] then
				onPath[j] = true
				path[depth + 1] = j
				dfs(j, depth + 1)
				path[depth + 1] = nil
				onPath[j] = nil
				if aborted then
					return
				end
			end
		end
	end
	dfs(0, 0)
	Route.LastVisits = visits
	if mustEnd and #best == 0 then
		-- Only reachable if the cap stopped the search before any path reached
		-- the treasure: fall back to the first shortest path to it (BFS in key order).
		local parent: { [number]: number } = { [0] = -1 }
		local q, head = { 0 }, 1
		while head <= #q do
			local v = q[head]
			head += 1
			if v == treasure then
				break
			end
			for _, j in adj[v] do
				if parent[j] == nil then
					parent[j] = v
					table.insert(q, j)
				end
			end
		end
		local v = treasure :: number
		while v ~= 0 do
			table.insert(best, 1, v)
			v = parent[v]
		end
	end
	return best
end

-- Returns (true, routeCells, offRouteCells): routeCells in visiting order,
-- offRouteCells (idle rooms) in key order. Or (false, reason, cellKey?).
function Route.Build(cells: any): (boolean, any, any)
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
	local kindCounts: { [string]: number } = {}
	for _, key in keys do
		local problem = Route.CellProblem(key, cells[key])
		if problem then
			return false, problem, key
		end
		local roomId = cells[key]
		local def = Rooms.Get(roomId)
		counts[roomId] = (counts[roomId] or 0) + 1
		if def and def.MaxPlaced and counts[roomId] > def.MaxPlaced then
			return false, "TooManyOfRoom", key
		end
		-- Kind limits (Rooms.KindLimit): one treasure of any tier per plot.
		local kindLimit = def and Rooms.KindLimit[def.Kind]
		if def and kindLimit then
			kindCounts[def.Kind] = (kindCounts[def.Kind] or 0) + 1
			if kindCounts[def.Kind] > kindLimit then
				return false, "TooManyOfRoom", key
			end
		end
	end

	local route: { string } = {}
	local onRoute: { [string]: boolean } = {}
	for _, i in longestPath(keys, cells) do
		table.insert(route, keys[i])
		onRoute[keys[i]] = true
	end
	local offRoute: { string } = {}
	for _, key in keys do
		if not onRoute[key] then
			table.insert(offRoute, key)
		end
	end
	return true, route, offRoute
end

return Route
