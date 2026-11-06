local LayoutRules = require(game:GetService("ServerScriptService").Server.Rules.LayoutRules)

local function profile()
	return {
		Rooms = {
			r1 = { Id = "SlimeNest", Level = 1 },
			r2 = { Id = "TreasureRoom", Level = 1 },
			r3 = { Id = "SpikeHall", Level = 1 },
			r4 = { Id = "GuardRoom", Level = 1 },
			r5 = { Id = "TreasureRoom", Level = 1 },
		},
	}
end

test("valid layout returns route order, cellKey -> roomId and idle cells", function()
	local ok, route, cells, off = LayoutRules.Validate(profile(), { ["3,2"] = "r1", ["3,3"] = "r3", ["3,4"] = "r2" })
	expect(ok, "ok: " .. tostring(route))
	expectEq(table.concat(route, "|"), "3,2|3,3|3,4", "route")
	expectEq(cells["3,3"], "SpikeHall", "cells")
	expectEq(#off, 0, "nothing idle")
end)

test("empty layout is valid", function()
	local ok, route, cells, off = LayoutRules.Validate(profile(), {})
	expect(ok, "ok")
	expectEq(#route, 0, "empty route")
	expectEq(next(cells), nil, "no cells")
	expectEq(#off, 0, "no idle")
end)

test("any shape is accepted; off-route rooms come back as idle cells", function()
	-- Branch at 3,2, an island at 1,4 and the treasure in front of a room.
	local ok, route, cells, off = LayoutRules.Validate(profile(), {
		["3,2"] = "r1",
		["2,2"] = "r3",
		["4,2"] = "r4",
		["1,4"] = "r2",
	})
	expect(ok, "branch + island accepted: " .. tostring(route))
	expectEq(table.concat(route, "|"), "3,2|2,2", "route (tie on key order)")
	expectEq(table.concat(off, "|"), "1,4|4,2", "idle cells")
	expectEq(cells["1,4"], "TreasureRoom", "idle rooms still in cells")
	ok, route, cells, off = LayoutRules.Validate(profile(), { ["3,2"] = "r2", ["3,3"] = "r1" })
	expect(ok, "treasure first accepted")
	expectEq(table.concat(route, "|"), "3,2", "route ends at the treasure")
	expectEq(table.concat(off, "|"), "3,3", "room behind it idle")
	ok, route, cells, off = LayoutRules.Validate(profile(), { ["5,4"] = "r1" })
	expect(ok, "disconnected accepted")
	expectEq(#route, 0, "no route")
	expectEq(table.concat(off, "|"), "5,4", "idle")
end)

test("unowned instance is refused", function()
	local ok, reason, cell = LayoutRules.Validate(profile(), { ["3,2"] = "r9" })
	expect(not ok, "refused")
	expectEq(reason, "NotOwned", "reason")
	expectEq(cell, "3,2", "cell")
end)

test("an instance used twice is refused", function()
	local ok, reason = LayoutRules.Validate(profile(), { ["3,2"] = "r1", ["3,3"] = "r1" })
	expect(not ok, "refused")
	expectEq(reason, "DuplicateInstance", "reason")
end)

test("a second Treasure Room, the entrance cell and out of bounds are refused", function()
	local ok, reason, cell = LayoutRules.Validate(profile(), { ["3,2"] = "r2", ["5,4"] = "r5" })
	expect(not ok, "two treasures refused")
	expectEq(reason, "TooManyOfRoom", "reason")
	expectEq(cell, "5,4", "cell")
	ok, reason = LayoutRules.Validate(profile(), { ["3,1"] = "r1" })
	expect(not ok and reason == "OnEntrance", "entrance")
	ok, reason = LayoutRules.Validate(profile(), { ["6,4"] = "r1" })
	expect(not ok and reason == "OutOfBounds", "bounds")
end)

test("more than 19 entries is refused", function()
	local layout = {}
	for i = 1, 20 do
		layout["x" .. i] = "r1"
	end
	local ok, reason = LayoutRules.Validate(profile(), layout)
	expect(not ok, "refused")
	expectEq(reason, "TooManyRooms", "reason")
end)

test("garbage layouts are refused with BadArgs", function()
	for _, bad in { "x", 5, true, { 1, 2 }, { ["3,2"] = 5 }, { ["3,2"] = {} } } do
		local ok, reason = LayoutRules.Validate(profile(), bad)
		expect(not ok, "refused " .. tostring(bad))
		expectEq(reason, "BadArgs", "reason")
	end
	local ok, reason = LayoutRules.Validate(profile(), nil)
	expect(not ok and reason == "BadArgs", "nil refused")
end)

test("only one treasure room of any tier may be placed", function()
	local Route = require(game:GetService("ServerScriptService").Server.Rules.Route)
	local ok, reason, key = Route.Build({ ["3,2"] = "TreasureRoom", ["2,2"] = "Strongbox" })
	expectEq(ok, false, "two treasures refused")
	expectEq(reason, "TooManyOfRoom", "reason")
	expectEq(key, "3,2", "second in key order")
	expect((Route.Build({ ["3,2"] = "SlimeNest", ["3,3"] = "VoidVault" })), "one rarer treasure is fine")
end)
