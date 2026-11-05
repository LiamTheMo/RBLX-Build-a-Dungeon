local Server = game:GetService("ServerScriptService").Server
local VisitorRotation = require(Server.Rules.VisitorRotation)
local Visitors = require(Server.Definitions.Visitors)
local Balance = require(Server.Definitions.Balance)

test("Novice only until the tutorial is done and Wins reaches the threshold", function()
	for encounters = 0, 12 do
		expectEq(VisitorRotation.Pick(false, 99, encounters), "Novice", "tutorial not done")
		expectEq(VisitorRotation.Pick(true, Balance.Rotation.MixMinWins - 1, encounters), "Novice", "too few wins")
	end
end)

test("after unlock the rotation is deterministic, Novice-heavy and uses every visitor", function()
	local seen, novices, n = {}, 0, #Balance.Rotation.Pattern
	for e = 0, n - 1 do
		local id = VisitorRotation.Pick(true, 8, e)
		expectEq(VisitorRotation.Pick(true, 8, e), id, "repeatable")
		expectEq(VisitorRotation.Pick(true, 8, e + n * 7), id, "cycles")
		seen[id] = true
		if id == "Novice" then
			novices += 1
		end
		expectEq(Visitors.Get(id).Arrival, "Automatic", "automatic visitors only")
	end
	expect(seen.Scout and seen.Cleric and seen.Novice, "all three appear")
	expect(novices * 2 > n, "Novice is the most common")
end)

test("bad input is harmless", function()
	expectEq(VisitorRotation.Pick(true, 8, -3), VisitorRotation.Pick(true, 8, 0), "negative encounters")
	expectEq(VisitorRotation.Pick(true, 8, 0 / 0), VisitorRotation.Pick(true, 8, 0), "nan encounters")
	expectEq(VisitorRotation.Pick(true, "x" :: any, 3), "Novice", "bad wins")
end)

test("traits are defined and described", function()
	expectEq(Visitors.Get("Scout").Traits[1], "SureFooted", "scout")
	expectEq(Visitors.Get("Cleric").Traits[1], "Mender", "cleric")
	for _, v in { "Scout", "Cleric" } do
		expect(Visitors.TraitText[Visitors.Get(v).Traits[1]] ~= nil, v .. " trait text")
	end
end)
