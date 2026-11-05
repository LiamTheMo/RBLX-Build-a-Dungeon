-- Consistency checks for the shared definitions: every id resolves, every room
-- or visitor that needs numbers has them, and values sit in sane ranges.

local Shared = game:GetService("ReplicatedStorage").Shared
local Grid = require(Shared.Definitions.Grid)
local Rooms = require(Shared.Definitions.Rooms)
local Visitors = require(Shared.Definitions.Visitors)
local Balance = require(Shared.Definitions.Balance)

local function isPositive(n)
	return type(n) == "number" and n > 0
end

local function isFraction(n)
	return type(n) == "number" and n >= 0 and n <= 1
end

test("room ids match their keys and appear once in Order", function()
	local seen = {}
	for _, id in Rooms.Order do
		expect(Rooms.All[id] ~= nil, "Order lists unknown room " .. id)
		expect(not seen[id], "Order repeats " .. id)
		seen[id] = true
	end
	for key, def in Rooms.All do
		expectEq(def.Id, key, "room id")
		expect(seen[key], key .. " missing from Rooms.Order")
	end
end)

test("exactly one fixed entrance and at most one treasure room", function()
	local entrances = 0
	for _, def in Rooms.All do
		if def.Kind == "Entrance" then
			entrances += 1
			expect(not def.Placeable, "entrance must be fixed")
		end
		if def.Kind == "Treasure" then
			expectEq(def.MaxPlaced, 1, "treasure MaxPlaced")
			expect(def.EndsRoute, "treasure must end the route")
			expect(def.Placeable, "treasure is optional, so it must be placeable")
		end
	end
	expectEq(entrances, 1, "entrance count")
end)

test("defenders and traps have balance entries", function()
	for id, def in Rooms.All do
		local stats = Balance.Rooms[id]
		if def.Kind == "Defender" then
			expect(stats ~= nil, id .. " has no balance")
			if stats then
				expect(isPositive(stats.DefenderHealth), id .. " DefenderHealth")
				expect(isPositive(stats.AttackDamage), id .. " AttackDamage")
				expect(isPositive(stats.AttackInterval), id .. " AttackInterval")
			end
		elseif def.Kind == "Trap" then
			expect(stats ~= nil, id .. " has no balance")
			if stats then
				expect(isPositive(stats.Damage), id .. " Damage")
				expect(isPositive(stats.Cycle), id .. " Cycle")
				expect(stats.Telegraph > 0 and stats.Telegraph < stats.Cycle, id .. " telegraph fits in the cycle")
			end
		end
		if def.Source == "Shop" then
			expect(stats and isPositive(stats.Cost) and stats.Cost % 1 == 0, id .. " needs a whole-number Cost")
		end
	end
	for id in Balance.Rooms do
		expect(Rooms.All[id] ~= nil, "balance for unknown room " .. id)
	end
end)

test("every visitor has stats and balance has no unknown visitors", function()
	for id, def in Visitors.All do
		expectEq(def.Id, id, "visitor id")
		local stats = Balance.Visitors[id]
		expect(stats ~= nil, id .. " has no balance")
		if stats then
			expect(isPositive(stats.Health), id .. " Health")
			expect(isPositive(stats.AttackInterval), id .. " AttackInterval")
			expect(isPositive(stats.WalkSpeed), id .. " WalkSpeed")
			expect(isPositive(stats.Reward) and stats.Reward % 1 == 0, id .. " whole-number Reward")
			expect(isFraction(stats.TheftFraction), id .. " TheftFraction")
		end
	end
	for id in Balance.Visitors do
		expect(Visitors.All[id] ~= nil, "balance for unknown visitor " .. id)
	end
end)

test("grid and economy values are in range", function()
	expect(Grid.Columns >= 2 and Grid.Rows >= 2, "grid too small")
	local e = Grid.EntranceCell
	expect(e.Column >= 1 and e.Column <= Grid.Columns and e.Row >= 1 and e.Row <= Grid.Rows, "entrance inside grid")
	expect(isFraction(Balance.Economy.VaultBonusPer100), "VaultBonusPer100")
	expect(isFraction(Balance.Economy.VaultBonusCap), "VaultBonusCap")
	expect(
		Balance.Timing.VisitorIntervalWithTreasure < Balance.Timing.VisitorInterval,
		"a treasure room must attract visitors more often"
	)
end)

test("definitions are frozen", function()
	expect(table.isfrozen(Rooms.All.SlimeNest), "room defs frozen")
	expect(table.isfrozen(Balance.Visitors.Novice), "balance frozen")
	expect(table.isfrozen(Grid.EntranceCell), "grid frozen")
end)
