local Server = game:GetService("ServerScriptService").Server
local Route = require(Server.Rules.Route)
local Grid = require(Server.Definitions.Grid)

local ENTRANCE = Route.Key(Grid.EntranceCell.Column, Grid.EntranceCell.Row)

local function expectFail(cells, reason, key, label)
	local ok, r, k = Route.Build(cells)
	expect(not ok, label .. ": should fail")
	expectEq(r, reason, label .. " reason")
	if key ~= nil then
		expectEq(k, key, label .. " cell")
	end
end

local function build(cells, label)
	local ok, route, off = Route.Build(cells)
	expect(ok, label .. ": should be valid, got " .. tostring(route))
	return route or {}, off or {}
end

local function joined(list)
	return table.concat(list, "|")
end

local function adjacent(a, b)
	local ac, ar = Route.Parse(a)
	local bc, br = Route.Parse(b)
	return math.abs(ac - bc) + math.abs(ar - br) == 1
end

-- Every route must be a simple path of placed rooms starting next to the
-- entrance; on + off route must partition the placed cells.
local function checkShape(cells, route, off, label)
	local seen = {}
	for i, key in route do
		expect(cells[key] ~= nil, label .. ": route cell placed " .. key)
		expect(not seen[key], label .. ": route repeats " .. key)
		seen[key] = true
		expect(adjacent(key, if i == 1 then ENTRANCE else route[i - 1]), label .. ": step " .. i .. " adjacent")
	end
	for _, key in off do
		expect(not seen[key], label .. ": off-route cell also on route " .. key)
		seen[key] = true
	end
	local count = 0
	for key in cells do
		count += 1
		expect(seen[key], label .. ": placed cell accounted " .. key)
	end
	expectEq(#route + #off, count, label .. ": partition size")
end

-- Exhaustive reference: every simple path from the entrance, no pruning; the
-- treasure (when reachable) ends the path; the first strictly longest path in
-- key order wins. Used on small layouts only.
local function reference(cells)
	local keys = {}
	for key in cells do
		table.insert(keys, key)
	end
	table.sort(keys)
	local treasure
	for _, key in keys do
		if cells[key] == "TreasureRoom" then
			treasure = key
		end
	end
	local function neighbours(key)
		local c, r = Route.Parse(key)
		local out = {}
		for _, side in Grid.Sides do
			local k = Route.Key(c + side.Column, r + side.Row)
			if cells[k] then
				table.insert(out, k)
			end
		end
		table.sort(out)
		return out
	end
	-- Reachability of the treasure.
	local reach, queue = { [ENTRANCE] = true }, { ENTRANCE }
	local head = 1
	while head <= #queue do
		for _, n in neighbours(queue[head]) do
			if not reach[n] then
				reach[n] = true
				table.insert(queue, n)
			end
		end
		head += 1
	end
	local mustEnd = treasure ~= nil and reach[treasure] == true
	local best, path, on = {}, {}, { [ENTRANCE] = true }
	local function dfs(key)
		if mustEnd then
			if key == treasure then
				if #path > #best then
					best = table.clone(path)
				end
				return
			end
		elseif #path > #best then
			best = table.clone(path)
		end
		for _, n in neighbours(key) do
			if not on[n] then
				on[n] = true
				table.insert(path, n)
				dfs(n)
				table.remove(path)
				on[n] = nil
			end
		end
	end
	dfs(ENTRANCE)
	return best
end

local ALL_CELLS = {}
for column = 1, Grid.Columns do
	for row = 1, Grid.Rows do
		local key = Route.Key(column, row)
		if key ~= ENTRANCE then
			table.insert(ALL_CELLS, key)
		end
	end
end
table.sort(ALL_CELLS)

local function fullGrid(treasureAt)
	local cells = {}
	for _, key in ALL_CELLS do
		cells[key] = "SlimeNest"
	end
	if treasureAt then
		cells[treasureAt] = "TreasureRoom"
	end
	return cells
end

local function randomLayout(rng, count, withTreasure)
	local pool = table.clone(ALL_CELLS)
	local cells = {}
	for i = 1, count do
		local key = table.remove(pool, rng:NextInteger(1, #pool))
		cells[key] = if withTreasure and i == 1 then "TreasureRoom" else "SlimeNest"
	end
	return cells
end

test("Key and Parse round-trip and reject garbage", function()
	expectEq(Route.Key(3, 2), "3,2", "key")
	local c, r = Route.Parse("3,2")
	expectEq(c, 3, "c")
	expectEq(r, 2, "r")
	for _, bad in { "", "3", "3,", ",2", "a,b", "03,2", "3,2,1", "-1,2", "1.5,2", " 3,2", 5, true, "99999999999999999999,1" } do
		expectEq(Route.Parse(bad), nil, "parse " .. tostring(bad))
	end
end)

test("empty layout is valid with an empty route", function()
	local route, off = build({}, "empty")
	expectEq(#route, 0, "length")
	expectEq(#off, 0, "no idle rooms")
end)

test("single room next to the entrance", function()
	local route, off = build({ ["3,2"] = "SlimeNest" }, "single")
	expectEq(joined(route), "3,2", "route")
	expectEq(#off, 0, "no idle rooms")
end)

test("a chain is its own route, in visiting order", function()
	local cells = {
		["2,1"] = "SlimeNest",
		["1,1"] = "SpikeHall",
		["1,2"] = "SlimeNest",
		["1,3"] = "SpikeHall",
		["2,3"] = "SlimeNest",
		["3,3"] = "GuardRoom",
		["3,4"] = "TreasureRoom",
	}
	local route, off = build(cells, "snake")
	expectEq(joined(route), "2,1|1,1|1,2|1,3|2,3|3,3|3,4", "order")
	expectEq(#off, 0, "nothing idle")
end)

test("branches are allowed: the longer arm is the route, the rest is idle", function()
	-- 3,2 forks into a one-room west arm and a two-room east arm.
	local cells = { ["3,2"] = "SlimeNest", ["2,2"] = "SpikeHall", ["4,2"] = "GuardRoom", ["5,2"] = "SlimeNest" }
	local route, off = build(cells, "fork")
	expectEq(joined(route), "3,2|4,2|5,2", "longest arm")
	expectEq(joined(off), "2,2", "short arm idle")
	checkShape(cells, route, off, "fork")
end)

test("equal arms tie-break on cell keys, every time", function()
	local cells = { ["3,2"] = "SlimeNest", ["2,2"] = "SpikeHall", ["4,2"] = "GuardRoom" }
	local route, off = build(cells, "tie")
	expectEq(joined(route), "3,2|2,2", "smaller key first")
	expectEq(joined(off), "4,2", "other arm idle")
	-- Two rooms touching the entrance: the smaller key starts the route.
	route, off = build({ ["2,1"] = "SlimeNest", ["4,1"] = "SlimeNest" }, "two starts")
	expectEq(joined(route), "2,1", "first start")
	expectEq(joined(off), "4,1", "other idle")
	-- Same answer regardless of table insertion order.
	for _ = 1, 20 do
		local a = {}
		a["4,2"] = "GuardRoom"
		a["2,2"] = "SpikeHall"
		a["3,2"] = "SlimeNest"
		local r2 = build(a, "insertion order")
		expectEq(joined(r2), "3,2|2,2", "stable")
	end
end)

test("loops are allowed: the route walks around them", function()
	-- A 2x2 block next to the entrance: the route takes all four rooms.
	local cells = { ["3,2"] = "SlimeNest", ["4,2"] = "SpikeHall", ["3,3"] = "GuardRoom", ["4,3"] = "SlimeNest" }
	local route, off = build(cells, "square")
	expectEq(#route, 4, "all four")
	expectEq(joined(route), "3,2|3,3|4,3|4,2", "deterministic loop walk")
	checkShape(cells, route, off, "square")
	-- The old "loop through the entrance" case.
	cells = { ["3,2"] = "SlimeNest", ["4,2"] = "SpikeHall", ["4,1"] = "GuardRoom" }
	route, off = build(cells, "entrance loop")
	expectEq(#route, 3, "uses every room")
	expectEq(joined(route), "3,2|4,2|4,1", "key order start")
end)

test("disconnected islands stay placed but idle", function()
	local route, off = build({ ["3,2"] = "SlimeNest", ["1,4"] = "SpikeHall" }, "island")
	expectEq(joined(route), "3,2", "route")
	expectEq(joined(off), "1,4", "island idle")
	route, off = build({ ["1,3"] = "SlimeNest" }, "nothing touches the entrance")
	expectEq(#route, 0, "empty route")
	expectEq(joined(off), "1,3", "idle")
	-- Diagonal cells do not touch.
	route, off = build({ ["3,2"] = "SlimeNest", ["4,3"] = "SpikeHall" }, "diagonal")
	expectEq(joined(route), "3,2", "route")
	expectEq(joined(off), "4,3", "diagonal idle")
end)

test("a reachable treasure always ends the route", function()
	-- Treasure first in a line: the route stops there, rooms behind it are idle.
	local route, off = build({ ["3,2"] = "TreasureRoom", ["3,3"] = "SlimeNest" }, "treasure first")
	expectEq(joined(route), "3,2", "ends at treasure")
	expectEq(joined(off), "3,3", "behind the treasure idle")
	-- A longer path that avoids the treasure loses to one that ends at it.
	local cells = {
		["3,2"] = "SlimeNest",
		["3,3"] = "TreasureRoom",
		["4,2"] = "SpikeHall",
		["5,2"] = "SlimeNest",
		["5,3"] = "GuardRoom",
		["5,4"] = "SlimeNest",
	}
	route, off = build(cells, "detour")
	expectEq(route[#route], "3,3", "treasure last")
	expectEq(joined(route), "3,2|3,3", "only path to the treasure")
	expectEq(joined(off), "4,2|5,2|5,3|5,4", "rest idle")
	-- Longest path that ends at the treasure is preferred over shorter ones.
	cells = {
		["3,2"] = "SlimeNest",
		["4,2"] = "SpikeHall",
		["4,3"] = "GuardRoom",
		["3,3"] = "TreasureRoom",
	}
	route = build(cells, "around")
	expectEq(joined(route), "3,2|4,2|4,3|3,3", "walks around to the treasure")
	expect(Route.Build({ ["3,2"] = "TreasureRoom" }), "treasure alone is fine")
end)

test("an unreachable treasure is off route and the route is the longest path", function()
	local cells = { ["3,2"] = "SlimeNest", ["3,3"] = "SpikeHall", ["1,4"] = "TreasureRoom" }
	local route, off = build(cells, "far treasure")
	expectEq(joined(route), "3,2|3,3", "longest path")
	expectEq(joined(off), "1,4", "treasure idle")
end)

test("one treasure only; entrance cell, bounds and unplaceable rooms", function()
	expectFail({ ["3,2"] = "TreasureRoom", ["5,4"] = "TreasureRoom" }, "TooManyOfRoom", "5,4", "two treasures")
	expectFail({ ["3,1"] = "SlimeNest" }, "OnEntrance", "3,1", "entrance cell")
	expectFail({ ["6,1"] = "SlimeNest" }, "OutOfBounds", "6,1", "column 6")
	expectFail({ ["3,5"] = "SlimeNest" }, "OutOfBounds", "3,5", "row 5")
	expectFail({ ["0,2"] = "SlimeNest" }, "OutOfBounds", "0,2", "column 0")
	expectFail({ ["3,2"] = "Entrance" }, "NotPlaceable", "3,2", "entrance room")
end)

test("old shape reason codes are never produced", function()
	local rng = Random.new(7)
	for _ = 1, 200 do
		local cells = randomLayout(rng, rng:NextInteger(1, 19), rng:NextNumber() < 0.5)
		local ok, reason = Route.Build(cells)
		expect(ok, "random layout valid: " .. tostring(reason))
	end
end)

test("garbage input is refused, never thrown", function()
	expectFail(nil, "BadCell", nil, "nil")
	expectFail("x", "BadCell", nil, "string")
	expectFail({ [1] = "SlimeNest" }, "BadCell", nil, "numeric key")
	expectFail({ ["x"] = "SlimeNest" }, "BadCell", "x", "bad key")
	expectFail({ ["3,2"] = 5 }, "UnknownRoom", "3,2", "number value")
	expectFail({ ["3,2"] = true }, "UnknownRoom", "3,2", "bool value")
	expectFail({ ["3,2"] = {} }, "UnknownRoom", "3,2", "table value")
	expectFail({ ["3,2"] = "Dragon" }, "UnknownRoom", "3,2", "unknown id")
	expectFail({ ["03,2"] = "SlimeNest" }, "BadCell", "03,2", "non-canonical key")
end)

test("full grid: every room on one route", function()
	local cells = fullGrid(nil)
	local route, off = build(cells, "full")
	expectEq(#route, 19, "hamiltonian route")
	expectEq(#off, 0, "nothing idle")
	checkShape(cells, route, off, "full")
	-- The treasure on a cell of the start colour can end a 19-room route; on the
	-- other colour the grid's parity caps it at 18.
	route, off = build(fullGrid("1,2"), "full, treasure 1,2")
	expectEq(#route, 19, "19 rooms to 1,2")
	expectEq(route[#route], "1,2", "treasure last")
	checkShape(fullGrid("1,2"), route, off, "full t12")
	route, off = build(fullGrid("1,1"), "full, treasure 1,1")
	expectEq(#route, 18, "18 rooms to 1,1")
	expectEq(route[#route], "1,1", "treasure last")
	checkShape(fullGrid("1,1"), route, off, "full t11")
end)

test("matches an exhaustive search on random small layouts", function()
	local rng = Random.new(20261105)
	for n = 1, 300 do
		local cells = randomLayout(rng, rng:NextInteger(1, 12), rng:NextNumber() < 0.5)
		local route, off = build(cells, "random " .. n)
		checkShape(cells, route, off, "random " .. n)
		local want = reference(cells)
		if joined(route) ~= joined(want) then
			expectEq(joined(route), joined(want), "random " .. n)
			break
		end
	end
end)

test("performance: worst cases stay well under the visit cap and a few ms", function()
	local cases = { { name = "full", cells = fullGrid(nil) } }
	for _, key in ALL_CELLS do
		table.insert(cases, { name = "full+T" .. key, cells = fullGrid(key) })
	end
	local rng = Random.new(99)
	for i = 1, 400 do
		table.insert(cases, { name = "rand" .. i, cells = randomLayout(rng, rng:NextInteger(12, 19), i % 2 == 0) })
	end
	-- Combs (dead-end teeth) are the hardest shape for the bound.
	table.insert(cases, {
		name = "comb",
		cells = {
			["1,1"] = "SlimeNest", ["2,1"] = "SlimeNest", ["4,1"] = "SlimeNest", ["5,1"] = "SlimeNest",
			["1,2"] = "SlimeNest", ["2,2"] = "SlimeNest", ["3,2"] = "SlimeNest", ["4,2"] = "SlimeNest", ["5,2"] = "SlimeNest",
			["1,3"] = "SlimeNest", ["3,3"] = "SlimeNest", ["5,3"] = "SlimeNest",
			["1,4"] = "SlimeNest", ["3,4"] = "SlimeNest", ["5,4"] = "SlimeNest",
		},
	})
	local worstVisits, worstName, worstTime, total, calls = 0, "", 0, 0, 0
	for _, case in cases do
		local t0 = os.clock()
		local ok = Route.Build(case.cells)
		local dt = os.clock() - t0
		expect(ok, case.name .. " valid")
		calls += 1
		total += dt
		worstTime = math.max(worstTime, dt)
		if Route.LastVisits > worstVisits then
			worstVisits, worstName = Route.LastVisits, case.name
		end
	end
	-- Repeat the full grid to time it without first-call noise.
	local full = fullGrid(nil)
	local t0 = os.clock()
	for _ = 1, 200 do
		Route.Build(full)
	end
	local fullMs = (os.clock() - t0) / 200 * 1000
	print(
		("    perf: %d layouts, avg %.3f ms, worst %.3f ms, full grid %.3f ms, max visits %d (%s), cap %d"):format(
			calls,
			total / calls * 1000,
			worstTime * 1000,
			fullMs,
			worstVisits,
			worstName,
			Route.MaxVisits
		)
	)
	expect(worstVisits <= Route.MaxVisits, "cap never hit on the sample")
	expect(fullMs < 2, "full grid under 2 ms")
	expect(worstTime * 1000 < 10, "worst call under 10 ms")
end)

test("hitting the visit cap still returns a deterministic valid route", function()
	local saved = Route.MaxVisits
	Route.MaxVisits = 5
	local cells = fullGrid("1,1")
	local okA, a, offA = Route.Build(cells)
	local okB, b = Route.Build(cells)
	Route.MaxVisits = saved
	expect(okA and okB, "valid")
	expectEq(joined(a), joined(b), "same answer twice")
	expectEq(a[#a], "1,1", "still ends at the treasure")
	checkShape(cells, a, offA, "capped")
end)
