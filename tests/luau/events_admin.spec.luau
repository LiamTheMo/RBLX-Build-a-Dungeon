-- Server event effects, room modifier rolls, admin authorization and command parsing.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Events = require(Server.Rules.Events)
local Admin = require(Server.Rules.Admin)
local Admins = require(Server.Config.Admins)
local Loot = require(Server.Rules.Loot)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local Rewards = require(Server.Rules.Rewards)

test("event effects: neutral without an event, one multiplier each", function()
	local none = Events.Effects(nil)
	for _, k in { "Coins", "Drops", "Variants", "BoxRarity", "Xp" } do
		expectEq(none[k], 1, "neutral " .. k)
	end
	expectEq(Events.Effects("Bogus").Coins, 1, "unknown id is neutral")
	expectEq(Events.Effects("GoldenHour").Coins, 2, "golden hour")
	expectEq(Events.Effects("LuckyStars").Drops, 2, "lucky stars")
	expectEq(Events.Effects("RareInvasion").Variants, 3, "rare invasion")
	expectEq(Events.Effects("BlessedBoxes").BoxRarity, 2, "blessed boxes")
	expectEq(Events.Effects("Swarm").Xp, 2, "swarm: double XP")
	expectEq(Events.Effects("Swarm").Coins, 1, "other effects stay neutral")
end)

test("Blessed Boxes doubles Epic and rarer weights only; odds and rolls agree", function()
	expectEq(Events.BoxTiers(Events.Effects(nil)), nil, "no boost without the event")
	local tiers = Events.BoxTiers(Events.Effects("BlessedBoxes"))
	for i, r in Balance.Rarities do
		local boosted = (Loot.RarityRank(r.Id) :: number) >= (Loot.RarityRank("Epic") :: number)
		expectNear(tiers[i].Weight, r.Weight * (if boosted then 2 else 1), 1e-9, r.Id)
		expectNear(tiers[i].RareWeight, r.RareWeight * (if boosted then 2 else 1), 1e-9, r.Id .. " rare box")
	end
	local odds = Loot.Odds("Dungeon", 0, 1, tiers)
	local rng, n, epicPlus = Random.new(21), 50000, 0
	for _ = 1, n do
		local rank = Loot.RarityRank(Loot.RollRarity("Dungeon", 0, rng, tiers)) :: number
		if rank >= (Loot.RarityRank("Epic") :: number) then
			epicPlus += 1
		end
	end
	local expected = 0
	for _, e in odds.Rarities do
		if (Loot.RarityRank(e.Id) :: number) >= (Loot.RarityRank("Epic") :: number) then
			expected += e.Chance
		end
	end
	expectNear(epicPlus / n, expected, 0.004, "rolled Epic+ share matches the shown odds")
	expectNear(expected, 2 * 5 / (100 + 5), 1e-9, "Epic+ weight 5 doubled")
end)

test("modifiers roll only during events, at 25%, at most one per room", function()
	expectEq(Events.RollModifier(nil, { NextNumber = function() return 0 end }), nil, "no event, no modifier")
	local rng, n, hits, kinds = Random.new(5), 20000, 0, {}
	for _ = 1, n do
		local m = Events.RollModifier("GoldenHour", rng)
		if m then
			hits += 1
			kinds[m] = true
			expect(Events.Modifier(m) ~= nil, "known modifier")
		end
	end
	expectNear(hits / n, Balance.Events.ModifierChance, 0.01, "25%")
	expect(kinds.Blazing and kinds.Lucky and kinds.Golden, "every modifier possible")
	-- Through OpenBox: stored on the instance, Golden/Lucky count only when placed.
	local p = ProfileSchema.Default()
	p.Boxes.Dungeon = 1
	local seq = { 0.5, 0.5, 0.1, 0.99 } -- rarity (Common: no perk rolls), room, modifier chance, pick last
	local i = 0
	local ok, data = Rewards.OpenBox(p, "Dungeon", { NextNumber = function() i += 1 return seq[i] or 0.5 end }, "LuckyStars")
	expect(ok, "opened")
	expectEq(data.Modifier, "Golden", "modifier returned")
	expectEq(p.Rooms[data.InstanceId].Modifier, "Golden", "stored on the room")
	expectEq(Progression.Bonuses(p).Coins, 0, "unplaced modifier ignored")
	p.Layout["3,3"] = data.InstanceId
	expectNear(Progression.Bonuses(p).Coins, 0.10, 1e-9, "placed Golden +10% coins")
	local saved = ProfileSchema.Migrate(p)
	expectEq(saved.Rooms[data.InstanceId].Modifier, "Golden", "survives a save")
	p.Rooms[data.InstanceId].Modifier = "Hacked"
	expectEq(ProfileSchema.Migrate(p).Rooms[data.InstanceId].Modifier, nil, "unknown modifier dropped")
end)

test("event gaps are 35..50 minutes and every event can be rolled", function()
	local rng, seen = Random.new(9), {}
	for _ = 1, 500 do
		local gap = Events.NextGap(rng)
		expect(gap >= 35 * 60 and gap <= 50 * 60, "gap in range")
		seen[Events.RollEvent(rng)] = true
	end
	for _, e in Balance.Events.List do
		expect(seen[e.Id], "rolled " .. e.Id)
	end
end)

test("admin check: listed UserId or group rank >= 254", function()
	expect(table.find(Admins.UserIds, 855002824) ~= nil, "owner listed")
	expectEq(Admins.GroupId, 33284082, "group")
	expect(Admin.IsAdmin(855002824, Admins, nil), "listed user, rank unknown")
	expect(Admin.IsAdmin(1, Admins, 254), "rank 254")
	expect(Admin.IsAdmin(1, Admins, 255), "owner rank")
	expect(not Admin.IsAdmin(1, Admins, 253), "rank 253")
	expect(not Admin.IsAdmin(1, Admins, nil), "lookup failed")
	expect(not Admin.IsAdmin("855002824", Admins, 255), "string id")
	expect(not Admin.IsAdmin(1, nil, 255), "no config")
end)

test("admin command parsing validates every argument", function()
	local c = Admin.Parse("/event start goldenhour 15")
	expectEq(c.Action, "EventStart", "start")
	expectEq(c.Event, "GoldenHour", "case-insensitive id")
	expectEq(c.Minutes, 15, "minutes")
	expectEq(Admin.Parse("/event start Swarm").Minutes, nil, "default duration")
	expectEq(Admin.Parse("/event start Bogus"), nil, "unknown event")
	expectEq(Admin.Parse("/event start Swarm 0"), nil, "zero minutes")
	expectEq(Admin.Parse("/event start Swarm 9999"), nil, "too long")
	expectEq(Admin.Parse("/event stop").Action, "EventStop", "stop")
	expectEq(Admin.Parse("/event list").Action, "EventList", "list")
	local g = Admin.Parse("/give coins 500 Bob")
	expectEq(g.Action, "GiveCoins", "coins")
	expectEq(g.Amount, 500, "amount")
	expectEq(g.Target, "Bob", "target")
	expectEq(Admin.Parse("/give coins 500").Target, nil, "self")
	expectEq(Admin.Parse("/give coins -5"), nil, "negative")
	expectEq(Admin.Parse("/give coins 1.5"), nil, "fraction")
	expectEq(Admin.Parse("/give coins 1e12"), nil, "too many")
	expectEq(Admin.Parse("/give coins nan"), nil, "nan")
	local b = Admin.Parse("/give box rare 3")
	expectEq(b.Box, "Rare", "box type")
	expectEq(b.Amount, 3, "box count")
	expectEq(Admin.Parse("/give box gold 3"), nil, "unknown box")
	expectEq(Admin.Parse("/give box Dungeon 1000"), nil, "over the stack")
	expectEq(Admin.Parse("/give xp 250").Action, "GiveXp", "xp")
	expectEq(Admin.Parse("/threat unlockall").Action, "UnlockThreat", "unlock")
	expectEq(Admin.Parse("/threat unlockall Bob extra"), nil, "extra words")
	expectEq(Admin.Parse(string.rep("a", 300)), nil, "too long")
	expectEq(Admin.Parse(42), nil, "not text")
end)


test("panel events validate ids, duration and malformed requests", function()
	local c = Admin.PanelEvent("EventStart", "GoldenHour", 10, "Server")
	expect(c ~= nil and c.Event == "GoldenHour" and c.Minutes == 10 and c.Scope == "Server", "valid event")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 5, "Global").Scope, "Global", "global scope")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 5, "World"), nil, "unknown scope rejected")
	expectEq(Admin.PanelEvent("EventStop", "Server", 0, "Global").Scope, "Global", "global stop")
	expectEq(Admin.PanelEvent("EventStart", "Unknown", 10, "Server"), nil, "unknown event")
	expectEq(Admin.PanelEvent("EventStart", "Swarm extra", 10, "Server"), nil, "injected words")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 0, "Server"), nil, "zero minutes")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 241, "Server"), nil, "over maximum")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 1.5, "Server"), nil, "fraction")
	expectEq(Admin.PanelEvent("EventStart", "Swarm", 0/0, "Server"), nil, "nan")
	expectEq(Admin.PanelEvent("EventStop", "Server", 0, "Server").Action, "EventStop", "valid stop")
	expectEq(Admin.PanelEvent("EventStop", "Swarm", 0, "Server"), nil, "invalid stop")
end)
