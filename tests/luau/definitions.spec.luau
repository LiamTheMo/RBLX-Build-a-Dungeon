-- Consistency checks for the shared definitions: every id resolves, every room
-- or visitor that needs numbers has them, and values sit in sane ranges.

local Server = game:GetService("ServerScriptService").Server
local Grid = require(Server.Definitions.Grid)
local Rooms = require(Server.Definitions.Rooms)
local Visitors = require(Server.Definitions.Visitors)
local Balance = require(Server.Definitions.Balance)

local function isPositive(n)
	return type(n) == "number" and n > 0
end

local function isFraction(n)
	return type(n) == "number" and n >= 0 and n <= 1
end

test("room sale values cover every rarity", function()
	for _, rarity in Balance.Rarities do
		expect(isPositive(Balance.Loot.SaleCoins[rarity.Id]), rarity.Id .. " sale value")
	end
end)

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
			if stats and stats.Units then
				expect(#stats.Units >= 2, id .. " Units lists several")
				for _, u in stats.Units do
					expect(isPositive(u.Health) and isPositive(u.Damage) and isPositive(u.Interval), id .. " unit stats")
				end
			elseif stats then
				expect(isPositive(stats.DefenderHealth), id .. " DefenderHealth")
				expect(isPositive(stats.AttackDamage), id .. " AttackDamage")
				expect(isPositive(stats.AttackInterval), id .. " AttackInterval")
			end
		elseif def.Kind == "Trap" then
			expect(stats ~= nil, id .. " has no balance")
			if stats and stats.SporeDuration then
				expect(isPositive(stats.SporeDuration), id .. " SporeDuration")
				expect(isPositive(stats.TrapDamageBonus), id .. " TrapDamageBonus")
			elseif stats and stats.ZoneDamage then
				expect(isPositive(stats.ZoneDamage), id .. " ZoneDamage")
			elseif stats then
				expect(isPositive(stats.Damage), id .. " Damage")
				expect(isPositive(stats.Cycle), id .. " Cycle")
				expect(stats.Telegraph > 0 and stats.Telegraph < stats.Cycle, id .. " telegraph fits in the cycle")
			end
		end
		if def.Source == "Shop" then
			expect(stats and isPositive(stats.Cost) and stats.Cost % 1 == 0, id .. " needs a whole-number Cost")
			expect(def.Rarity == "Common" or def.Rarity == "Uncommon", id .. " only Common/Uncommon are sold")
		elseif stats and stats.Cost ~= nil then
			expect(false, id .. " has a Cost but is not sold")
		end
		if def.Kind == "Treasure" then
			expect(stats ~= nil and isPositive(stats.Exchange), id .. " Exchange")
		end
		expect(Balance.RarityById[def.Rarity] ~= nil, id .. " known rarity")
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
			local r = stats.Reward
			expect(
				type(r) == "table" and isPositive(r.Min) and r.Min % 1 == 0 and r.Max % 1 == 0 and r.Max >= r.Min,
				id .. " whole-number Reward range"
			)
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
	local t = Balance.Timing
	expect(isPositive(t.MinVisitorInterval) and t.MinVisitorInterval <= t.VisitorInterval, "interval floor")
	expect(isPositive(Balance.Vault.RatePerPercent), "vault rate")
end)

test("definitions are frozen", function()
	expect(table.isfrozen(Rooms.All.SlimeNest), "room defs frozen")
	expect(table.isfrozen(Balance.Visitors.Novice), "balance frozen")
	expect(table.isfrozen(Grid.EntranceCell), "grid frozen")
end)
