local LayoutRules = require(game:GetService("ServerScriptService").Server.Rules.LayoutRules)

local function profile()
	return {
		Rooms = {
			r1 = { Id = "SlimeNest", Level = 1 },
			r2 = { Id = "TreasureRoom", Level = 1 },
			r3 = { Id = "SpikeHall", Level = 1 },
		},
	}
end

test("valid layout returns route order and cellKey -> roomId", function()
	local ok, route, cells = LayoutRules.Validate(profile(), { ["3,2"] = "r1", ["3,3"] = "r3", ["3,4"] = "r2" })
	expect(ok, "ok: " .. tostring(route))
	expectEq(table.concat(route, "|"), "3,2|3,3|3,4", "route")
	expectEq(cells["3,3"], "SpikeHall", "cells")
end)

test("empty layout is valid", function()
	local ok, route = LayoutRules.Validate(profile(), {})
	expect(ok, "ok")
	expectEq(#route, 0, "empty route")
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

test("route rules are applied after ownership", function()
	local ok, reason, cell = LayoutRules.Validate(profile(), { ["3,2"] = "r2", ["3,3"] = "r1" })
	expect(not ok, "refused")
	expectEq(reason, "TreasureNotLast", "reason")
	expectEq(cell, "3,2", "cell")
	ok, reason = LayoutRules.Validate(profile(), { ["5,4"] = "r1" })
	expect(not ok and reason == "Disconnected", "disconnected")
end)
