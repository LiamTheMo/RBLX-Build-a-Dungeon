-- Keeper levels, permanent upgrades, bonus aggregation and the economy hooks.

local Shared = game:GetService("ReplicatedStorage").Shared
local Balance = require(Shared.Definitions.Balance)
local Economy = require(Shared.Rules.Economy)
local Progression = require(Shared.Rules.Progression)
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
	expectEq(Progression.ShopLevel("MonsterDen"), 5, "den")
	expectEq(Progression.ShopLevel("RestlessCrypt"), 8, "crypt")
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

local function withRooms(perksByCell, permanent)
	local p = ProfileSchema.Default()
	p.Layout = {}
	local serial = 10
	for cell, room in perksByCell do
		serial += 1
		local id = "r" .. serial
		p.Rooms[id] = { Id = room.Id or "SlimeNest", Level = room.Level or 1, Rarity = "Mythic", Perks = room.Perks or {} }
		if cell ~= "unplaced" then
			p.Layout[cell] = id
		end
	end
	p.Permanent = permanent or {}
	return p
end

test("bonuses sum placed perks only, add permanents, then cap", function()
	local p = withRooms({
		["3,2"] = { Perks = { { Kind = "Coins", Amount = 0.2 }, { Kind = "Loot", Amount = 0.4 } } },
		["3,3"] = { Perks = { { Kind = "Coins", Amount = 0.2 } } },
		unplaced = { Perks = { { Kind = "Xp", Amount = 0.4 } } },
	}, { GoldenTouch = 2, Scholar = 1 })
	local b = Progression.Bonuses(p)
	expectNear(b.Coins, 0.5, 1e-9, "0.2 + 0.2 + 2 * 0.05")
	expectNear(b.Loot, 0.4, 1e-9, "loot")
	expectNear(b.Xp, 0.1, 1e-9, "unplaced perk ignored; Scholar 1")
	local capped = withRooms({
		["3,2"] = { Perks = { { Kind = "Loot", Amount = 0.4 }, { Kind = "Coins", Amount = 0.2 } } },
		["3,3"] = { Perks = { { Kind = "Loot", Amount = 0.4 } } },
		["3,4"] = { Perks = { { Kind = "Loot", Amount = 0.4 } } },
	}, { LuckyCharm = 10 })
	expectNear(Progression.Bonuses(capped).Loot, Balance.Perks.Caps.Loot, 1e-9, "capped at +100%")
	local fresh = Progression.Bonuses(ProfileSchema.Default())
	expectEq(fresh.Coins + fresh.Loot + fresh.Xp, 0, "a new profile has no bonus")
end)

test("permanent effects: Stout, Lure, Deep Vault and the Treasure Room level", function()
	local p = withRooms({ ["3,2"] = { Id = "TreasureRoom", Level = 3 } }, { StoutDefenders = 4, Lure = 5, DeepVault = 2 })
	expectNear(Progression.DefenderHealthBonus(p), 0.20, 1e-9, "stout")
	expectEq(Progression.IntervalReduction(p), 5, "lure")
	expectNear(Progression.VaultCapBonus(p), 2 * 0.05 + 2 * 0.02, 1e-9, "treasure level + deep vault")
	expectEq(Economy.VisitorInterval(false, 5), 25, "lure shortens")
	expectEq(Economy.VisitorInterval(true, 5), 15, "with treasure")
	expectEq(Economy.VisitorInterval(true, 1000), 1, "never below 1 s")
	local unplaced = withRooms({ unplaced = { Id = "TreasureRoom", Level = 3 } })
	expectEq(Progression.VaultCapBonus(unplaced), 0, "only a placed treasure room counts")
end)

test("coin bonus multiplies payouts before the vault bonus; cap can rise", function()
	expectEq((Economy.WinPayout("Novice", 0, false, 0.5)), 30, "20 * 1.5 banked")
	expectEq((Economy.WinPayout("Novice", 1000, true, 0.5)), 33, "20 * 1.5 * 1.10")
	expectEq((Economy.WinPayout("Novice", 1000, true)), 22, "no bonus unchanged")
	expectNear(Economy.VaultBonus(100000), 0.20, 1e-9, "base cap")
	expectNear(Economy.VaultBonus(100000, 0.14), 0.34, 1e-9, "raised cap")
	expectNear(Economy.VaultBonus(500, 0.14), 0.05, 1e-9, "cap does not add bonus by itself")
end)

test("upgrade caps follow rarity", function()
	expectEq(Economy.UpgradeCost(2), 150, "common to 3")
	expectEq(Economy.UpgradeCost(3), nil, "common max 3")
	expectEq(Economy.UpgradeCost(3, "Uncommon"), 350, "uncommon to 4")
	expectEq(Economy.UpgradeCost(4, "Uncommon"), nil, "uncommon max 4")
	expectEq(Economy.UpgradeCost(4, "Rare"), 800, "rare to 5")
	expectEq(Economy.UpgradeCost(5, "Mythic"), 1800, "mythic to 6")
	expectEq(Economy.UpgradeCost(6, "Mythic"), nil, "mythic max 6")
	expectEq(Economy.UpgradeCost(2, "Bogus"), 150, "unknown rarity treated as Common")
	expectEq(Economy.UpgradeCost(3, "Bogus"), nil, "unknown rarity capped as Common")
end)
