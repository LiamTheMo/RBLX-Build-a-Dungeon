local Server = game:GetService("ServerScriptService").Server
local Route = require(Server.Rules.Route)

local function expectFail(cells, reason, key, label)
	local ok, r, k = Route.Build(cells)
	expect(not ok, label .. ": should fail")
	expectEq(r, reason, label .. " reason")
	if key ~= nil then
		expectEq(k, key, label .. " cell")
	end
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
	local ok, route = Route.Build({})
	expect(ok, "ok")
	expectEq(#route, 0, "length")
end)

test("single room next to the entrance", function()
	local ok, route = Route.Build({ ["3,2"] = "SlimeNest" })
	expect(ok, "ok")
	expectEq(route[1], "3,2", "first")
end)

test("valid snake returns cells in route order", function()
	local ok, route = Route.Build({
		["2,1"] = "SlimeNest",
		["1,1"] = "SpikeHall",
		["1,2"] = "SlimeNest",
		["1,3"] = "SpikeHall",
		["2,3"] = "SlimeNest",
		["3,3"] = "GuardRoom",
		["3,4"] = "TreasureRoom",
	})
	expect(ok, "snake should be valid, got " .. tostring(route))
	if ok then
		expectEq(table.concat(route, "|"), "2,1|1,1|1,2|1,3|2,3|3,3|3,4", "order")
	end
end)

test("loop is rejected", function()
	local ok, reason = Route.Build({ ["3,2"] = "SlimeNest", ["4,2"] = "SpikeHall", ["4,1"] = "GuardRoom" })
	expect(not ok, "should fail")
	expectEq(reason, "Loop", "reason")
end)

test("branch is rejected", function()
	expectFail({ ["3,2"] = "SlimeNest", ["2,2"] = "SpikeHall", ["4,2"] = "GuardRoom" }, "Branch", "3,2", "branch")
end)

test("entrance touching two rooms is a branch", function()
	local ok, reason = Route.Build({ ["2,1"] = "SlimeNest", ["4,1"] = "SlimeNest" })
	expect(not ok, "should fail")
	expectEq(reason, "Branch", "reason")
end)

test("disconnected room is rejected with its cell", function()
	expectFail({ ["3,2"] = "SlimeNest", ["1,4"] = "SpikeHall" }, "Disconnected", "1,4", "far room")
	expectFail({ ["1,3"] = "SlimeNest" }, "Disconnected", "1,3", "none touches entrance")
	-- Diagonal cells do not touch.
	expectFail({ ["3,2"] = "SlimeNest", ["4,3"] = "SpikeHall" }, "Disconnected", "4,3", "diagonal")
end)

test("treasure must be last; one treasure only", function()
	expectFail({ ["3,2"] = "TreasureRoom", ["3,3"] = "SlimeNest" }, "TreasureNotLast", "3,2", "treasure first")
	expectFail({ ["3,2"] = "TreasureRoom", ["3,3"] = "TreasureRoom" }, "TooManyOfRoom", nil, "two treasures")
	expect(Route.Build({ ["3,2"] = "SlimeNest", ["3,3"] = "TreasureRoom" }), "treasure last is fine")
	expect(Route.Build({ ["3,2"] = "TreasureRoom" }), "treasure alone is fine")
end)

test("entrance cell, out of bounds and unplaceable rooms", function()
	expectFail({ ["3,1"] = "SlimeNest" }, "OnEntrance", "3,1", "entrance cell")
	expectFail({ ["6,1"] = "SlimeNest" }, "OutOfBounds", "6,1", "column 6")
	expectFail({ ["3,5"] = "SlimeNest" }, "OutOfBounds", "3,5", "row 5")
	expectFail({ ["0,2"] = "SlimeNest" }, "OutOfBounds", "0,2", "column 0")
	expectFail({ ["3,2"] = "Entrance" }, "NotPlaceable", "3,2", "entrance room")
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
