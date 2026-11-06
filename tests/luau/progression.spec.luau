-- Keeper levels, permanent upgrades, bonus aggregation and the economy hooks.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Economy = require(Server.Rules.Economy)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(game:GetService("ServerScriptService").Server.Rules.ProfileSchema)

test("level curve: 50 + 25 * (level - 1)", function()
	expectEq(Progression.XpToNext(1), 50, "1 -> 2")
	expectEq(Progression.XpToNext(2), 75, "2 -> 3")
	expectEq(Progression.XpToNext(10), 275, "10 -> 11")
	local level, xp, gained = Progression.AddXp(1, 40, 10)
	expectEq(level, 2, "exactly levels")
	expectEq(xp, 0, "no leftover")
	expectEq(#gained, 1, "one level")
	level, xp, gained = Progression.AddXp(1, 0, 50 + 75 + 10)
	expectEq(level, 3, "two levels at once")
	expectEq(xp, 10, "leftover")
	expectEq(gained[2], 3, "levels listed")
	level, xp = Progression.AddXp(Balance.Progression.MaxLevel, 0, 1e6)
	expectEq(level, Balance.Progression.MaxLevel, "max level holds")
	expectEq(xp, 0, "no xp at max")
	expectEq(select(2, Progression.AddXp(1, 0, -5)), 0, "negative ignored")
end)

test("XP per visitor with bonus, rounded down", function()
	expectEq(Progression.XpFor("Novice", 0), 10, "novice")
	expectEq(Progression.XpFor("ArmoredChallenger", 0), 30, "challenger")
	expectEq(Progression.XpFor("Scout", 0.5), 18, "12 * 1.5")
	expectEq(Progression.XpFor("Cleric", 0.1), 15, "14 * 1.1 = 15.4")
	expectEq(Progression.XpFor("Nobody", 1), 0, "unknown")
end)

test("level rewards and shop gates", function()
	expectEq(Progression.LevelReward(2), "Dungeon", "2")
	expectEq(Progression.LevelReward(5), "Rare", "5")
	expectEq(Progression.LevelReward(10), "Rare", "10")
	expectEq(Progression.ShopLevel("GuardRoom"), 1, "guard ungated")
	expectEq(Progression.ShopLevel("MushroomCavern"), 3, "mushroom")
	expectEq(Progression.ShopLevel("BatRoost"), 4, "bat roost")
	expectEq(Progression.ShopLevel("ArrowGallery"), 5, "arrow gallery")
	expectEq(Progression.ShopLevel("Strongbox"), 6, "strongbox")
	expectEq(Progression.ShopLevel("MonsterDen"), 1, "den: loot-only now, no shop gate")
end)

test("permanent upgrade costs: round(base * 1.6^level), nil at max", function()
	expectEq(Progression.PermanentCost("GoldenTouch", 0), 200, "first")
	expectEq(Progression.PermanentCost("GoldenTouch", 1), 320, "second")
	expectEq(Progression.PermanentCost("GoldenTouch", 2), 512, "third")
	expectEq(Progression.PermanentCost("Scholar", 0), 250, "scholar base")
	expectEq(Progression.PermanentCost("Lure", 3), 1638, "400 * 4.096 = 1638.4")
	expectEq(Progression.PermanentCost("DeepVault", 1), 480, "deep vault")
	expectEq(Progression.PermanentCost("Scholar", 5), nil, "scholar max 5")
	expectEq(Progression.PermanentCost("GoldenTouch", 10), nil, "max 10")
	expectEq(Progression.PermanentCost("GoldenTouch", 1.5), nil, "fraction")
	expectEq(Progression.PermanentCost("Order", 0), nil, "not an upgrade")
	expectEq(Progression.PermanentCost("CostGrowth", 0), nil, "not an upgrade")
	expectEq(Progression.PermanentCost("Bogus", 0), nil, "unknown")
end)

-- Rooms by cell ("unplaced" = owned, not placed); perks come from the definitions.
local function withRooms(byCell, permanent)
	local p = ProfileSchema.Default()
	p.Layout = {}
	local serial = 10
	for cell, room in byCell do
		serial += 1
		local id = "r" .. serial
		p.Rooms[id] = { Id = room.Id, Level = room.Level or 1, Modifier = room.Modifier }
		if string.sub(cell, 1, 8) ~= "unplaced" then
			p.Layout[cell] = id
		end
	end
	p.Permanent = permanent or {}
	return p
end

test("bonuses sum the route rooms' built-in perks, add permanents, then cap", function()
	local p = withRooms({
		["3,2"] = { Id = "DragonLair" }, -- Coins, Loot, Xp +10%
		["3,3"] = { Id = "GolemForge" }, -- Coins, Xp +10%
		unplaced = { Id = "VoidGate" },
	}, { GoldenTouch = 2, Scholar = 1 })
	local b = Progression.Bonuses(p)
	expectNear(b.Coins, 0.3, 1e-9, "0.1 + 0.1 + 2 * 0.05")
	expectNear(b.Loot, 0.1, 1e-9, "loot")
	expectNear(b.Xp, 0.3, 1e-9, "unplaced perks ignored; Scholar 1")
	local stored = withRooms({ ["3,2"] = { Id = "SlimeNest" } })
	stored.Rooms.r11.Perks = { { Kind = "Coins", Amount = 5 } } -- stale saved perks are never trusted
	expectEq(Progression.Bonuses(stored).Coins, 0, "perks only from the definition")
	local capped = withRooms({
		["3,2"] = { Id = "VoidGate" },
		["3,3"] = { Id = "VoidGate" },
		["3,4"] = { Id = "VoidGate" },
		["2,4"] = { Id = "VoidGate" },
	}, { LuckyCharm = 10 })
	expectNear(Progression.Bonuses(capped).Loot, Balance.Perks.Caps.Loot, 1e-9, "capped at +100%")
	local fresh = Progression.Bonuses(ProfileSchema.Default())
	expectEq(fresh.Coins + fresh.Loot + fresh.Xp, 0, "a new profile has no bonus")
end)

test("permanent effects: Stout, Lure, Deep Vault and the treasure room", function()
	local p = withRooms({ ["3,2"] = { Id = "DragonHoard", Level = 3 } }, { StoutDefenders = 4, Lure = 5, DeepVault = 2 })
	p.Rooms.r2 = nil -- the starter Coin Cache (unplaced) is not needed here
	expectNear(Progression.DefenderHealthBonus(p), 0.20, 1e-9, "stout")
	expectEq(Progression.IntervalReduction(p), 5, "lure")
	-- Dragon Hoard (exchange 2.0) level 3, Deep Vault 2: 2.0 * (1 + 0.1 * 2 + 0.05 * 2) = 2.6
	expectNear(Progression.VaultRate(p), 2.0 * 1.3, 1e-9, "exchange, treasure level and deep vault")
	expectNear(Progression.VariantBonus(p), 0.25, 1e-9, "hoard: +25% rare variants")
	expectEq(Progression.TheftScale(p), 1, "normal theft")
	local void = withRooms({ ["3,2"] = { Id = "VoidVault" } })
	expectEq(Progression.TheftScale(void), 0.5, "void vault halves thefts")
	expectEq(Progression.VariantBonus(void), 0, "no variant bonus")
	expectEq(Economy.VisitorInterval(0, 5), 25, "lure shortens")
	expectEq(Economy.VisitorInterval(0, 1000), 5, "never below 5 s")
	local unplaced = withRooms({ unplaced = { Id = "DragonHoard", Level = 3 } })
	expectEq(Progression.VaultRate(unplaced), 0, "only a treasure on the route counts")
	expectEq(Progression.VariantBonus(unplaced), 0, "idle hoard gives nothing")
end)

test("coin multipliers stack: threat, variant, coin bonus, event", function()
	expectEq(Economy.WinPayout(20, Economy.CoinMultiplier({ CoinBonus = 0.5 })), 30, "20 * 1.5")
	expectEq(Economy.WinPayout(20, Economy.CoinMultiplier({})), 20, "no bonus unchanged")
	local m = Economy.CoinMultiplier({ ThreatCoins = 2, VariantCoins = 3, CoinBonus = 0.1, EventCoins = 2 })
	expectEq(Economy.WinPayout(21, m), 277, "21 * 2 * 3 * 1.1 * 2 = 277.2")
	expectEq(Economy.WinPayout(-5, 2), 0, "bad base")
end)

test("upgrade caps follow rarity", function()
	expectEq(Economy.UpgradeCost(2), 150, "common to 3")
	expectEq(Economy.UpgradeCost(3), nil, "common max 3")
	expectEq(Economy.UpgradeCost(3, "Uncommon"), 350, "uncommon to 4")
	expectEq(Economy.UpgradeCost(4, "Uncommon"), nil, "uncommon max 4")
	expectEq(Economy.UpgradeCost(4, "Rare"), 800, "rare to 5")
	expectEq(Economy.UpgradeCost(5, "Epic"), 1800, "epic to 6")
	expectEq(Economy.UpgradeCost(6, "Epic"), nil, "epic max 6")
	expectEq(Economy.UpgradeCost(6, "Legendary"), 3500, "legendary to 7")
	expectEq(Economy.UpgradeCost(7, "Legendary"), nil, "legendary max 7")
	expectEq(Economy.UpgradeCost(7, "Mythic"), 6000, "mythic to 8")
	expectEq(Economy.UpgradeCost(8, "Mythic"), nil, "mythic max 8")
	expectEq(Economy.UpgradeCost(8, "Secret"), 10000, "secret to 9")
	expectEq(Economy.UpgradeCost(9, "Secret"), 16000, "secret to 10")
	expectEq(Economy.UpgradeCost(10, "Secret"), nil, "secret max 10")
	expectEq(Economy.UpgradeCost(2, "Bogus"), 150, "unknown rarity treated as Common")
	expectEq(Economy.UpgradeCost(3, "Bogus"), nil, "unknown rarity capped as Common")
end)
