--!strict
-- Every tunable number, kept apart from rules and logic (AGENTS.md). All values
-- are Phase 0 placeholders: hypotheses to test, not final balance. The reasons
-- behind them are in docs/PHASE0.md ("Placeholder values"). Record meaningful
-- changes there.
--
-- Units: health and damage are hit points, times are seconds, speeds are studs
-- per second at miniature scale (one grid cell is Grid.CellSize studs), and
-- fractions are 0..1.

local Balance = {}

Balance.Version = 3

Balance.Economy = table.freeze({
	StartingCoins = 0,
	-- Only while a Treasure Room is placed: each full 100 unbanked vault gold
	-- adds this much to win rewards, up to the cap.
	VaultBonusPer100 = 0.01,
	VaultBonusCap = 0.20,
})

Balance.Timing = table.freeze({
	-- Seconds after the previous encounter ends before the next automatic visitor.
	VisitorInterval = 30,
	-- A placed Treasure Room attracts visitors more often.
	VisitorIntervalWithTreasure = 20,
})

-- Visitors stop to fight a room's defender until it is knocked out (it recovers
-- after the encounter). Traps hit them as they pass.
Balance.Visitors = table.freeze({
	Practice = table.freeze({
		Health = 20,
		AttackDamage = 5,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = 10,
		TheftFraction = 0,
	}),
	Novice = table.freeze({
		Health = 60,
		AttackDamage = 10,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = 20,
		TheftFraction = 0.10,
	}),
	ArmoredChallenger = table.freeze({
		Health = 160,
		AttackDamage = 14,
		AttackInterval = 1.0,
		WalkSpeed = 3.5,
		Reward = 50,
		TheftFraction = 0.25,
	}),
	-- Phase 7 visitors with visible traits (docs/GDD.md). Traits are named in
	-- Visitors.luau; their numbers are here.
	Scout = table.freeze({
		Health = 50,
		AttackDamage = 8,
		AttackInterval = 1.0,
		WalkSpeed = 6,
		Reward = 25,
		TheftFraction = 0.10,
	}),
	Cleric = table.freeze({
		Health = 70,
		AttackDamage = 8,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = 30,
		TheftFraction = 0.10,
		-- Mender: HP regained per second while walking (not while duelling).
		HealPerSecond = 4,
	}),
})

-- Which automatic visitor comes next (Rules/VisitorRotation). Before the
-- tutorial is done and Wins reaches MixMinWins it is always a Novice. After that
-- the visitor is Pattern[Stats.Encounters % #Pattern + 1]: fixed, so the
-- player can plan, and Novice-heavy.
Balance.Rotation = table.freeze({
	MixMinWins = 8,
	Pattern = table.freeze({ "Novice", "Novice", "Scout", "Novice", "Cleric" }),
})

Balance.Rooms = table.freeze({
	SlimeNest = table.freeze({
		DefenderHealth = 40,
		AttackDamage = 6,
		AttackInterval = 1.0,
		-- Each hit slows the visitor's walk speed by this fraction for SlowDuration.
		SlowFraction = 0.75,
		SlowDuration = 6,
	}),
	SpikeHall = table.freeze({
		Damage = 15,
		-- One full trap cycle; the warning flash takes the first Telegraph seconds.
		Cycle = 1.2,
		Telegraph = 0.4,
	}),
	GuardRoom = table.freeze({
		DefenderHealth = 80,
		AttackDamage = 12,
		AttackInterval = 1.2,
		Cost = 100,
	}),
	-- Support room: no defender, no stop. Each Defender room next to it on the
	-- route gets these bonuses (once per defender: the strongest adjacent Den).
	-- Each level above 1 adds BonusPerLevel to both bonuses.
	MonsterDen = table.freeze({
		DamageBonus = 0.20,
		HealthBonus = 0.20,
		BonusPerLevel = 0.05,
		Cost = 250,
	}),
	-- Trap-like: a visitor entering the cell is Spored for SporeDuration seconds
	-- and takes TrapDamageBonus more from traps (+TrapDamageBonusPerLevel per level above 1).
	MushroomCavern = table.freeze({
		SporeDuration = 5,
		TrapDamageBonus = 0.50,
		TrapDamageBonusPerLevel = 0.10,
		Cost = 200,
	}),
	-- Skeleton defender: the first time it is knocked out it rises once with
	-- ReviveFraction of its max health.
	RestlessCrypt = table.freeze({
		DefenderHealth = 60,
		AttackDamage = 8,
		AttackInterval = 1.0,
		ReviveFraction = 0.5,
		Cost = 300,
	}),
	-- Each level above 1 raises the vault-bonus cap (only while placed).
	TreasureRoom = table.freeze({
		VaultBonusCapPerLevel = 0.05,
	}),
})

Balance.Upgrades = table.freeze({
	-- Coins to reach level 2, 3, 4, 5 and 6. A room stops at its rarity's MaxLevel.
	Costs = table.freeze({ 60, 150, 350, 800, 1800 }),
	MaxLevel = 6, -- the highest any rarity allows
	-- Per level above 1: scales defender damage and health, and trap damage.
	DamageBonusPerLevel = 0.25,
	HealthBonusPerLevel = 0.25,
})

-- Room rarity (GDD "Loot, rarity and progression"). Weight is the Dungeon Box
-- odds. StatMultiplier scales defender health and damage, trap damage, the
-- Monster Den boost and the Mushroom spore bonus. Perks: PerkCount different
-- kinds, each of PerkSize. Shop, starter, tutorial and crafted rooms are Common.
Balance.Rarities = table.freeze({
	Order = table.freeze({ "Common", "Uncommon", "Rare", "Mythic" }),
	Common = table.freeze({ Weight = 70, StatMultiplier = 1.00, MaxLevel = 3, PerkCount = 0, PerkSize = "Small" }),
	Uncommon = table.freeze({ Weight = 22, StatMultiplier = 1.10, MaxLevel = 4, PerkCount = 1, PerkSize = "Small" }),
	Rare = table.freeze({ Weight = 7, StatMultiplier = 1.25, MaxLevel = 5, PerkCount = 1, PerkSize = "Medium" }),
	Mythic = table.freeze({ Weight = 1, StatMultiplier = 1.45, MaxLevel = 6, PerkCount = 2, PerkSize = "Large" }),
})

-- Room perks, as fractions. Perks of every PLACED room add up with the
-- permanent upgrades, then each total is capped (Progression.Bonuses).
Balance.Perks = table.freeze({
	Kinds = table.freeze({ "Coins", "Loot", "Xp" }),
	Small = table.freeze({ Coins = 0.05, Loot = 0.10, Xp = 0.10 }),
	Medium = table.freeze({ Coins = 0.10, Loot = 0.20, Xp = 0.20 }),
	Large = table.freeze({ Coins = 0.20, Loot = 0.40, Xp = 0.40 }),
	Caps = table.freeze({ Coins = 1.00, Loot = 1.00, Xp = 1.00 }),
})

-- Gameplay-earned loot only; never sold. Chances are per defeated visitor and
-- multiplied by (1 + loot bonus), rolled independently.
Balance.Loot = table.freeze({
	Drops = table.freeze({
		Practice = table.freeze({ Box = 0, Blueprint = 0, BoxType = "Dungeon" }),
		Novice = table.freeze({ Box = 0.06, Blueprint = 0.12, BoxType = "Dungeon" }),
		Scout = table.freeze({ Box = 0.09, Blueprint = 0.15, BoxType = "Dungeon" }),
		Cleric = table.freeze({ Box = 0.09, Blueprint = 0.15, BoxType = "Dungeon" }),
		ArmoredChallenger = table.freeze({ Box = 0.25, Blueprint = 0.35, BoxType = "Rare" }),
	}),
	-- Which room a box holds (both box types).
	BoxRooms = table.freeze({
		SlimeNest = 25,
		SpikeHall = 25,
		GuardRoom = 20,
		MushroomCavern = 12,
		MonsterDen = 10,
		RestlessCrypt = 8,
	}),
	-- Rarity odds of a Rare Box (a Dungeon Box uses Rarities[*].Weight).
	RareBoxRarity = table.freeze({ Uncommon = 60, Rare = 32, Mythic = 8 }),
	-- After PityAfter boxes in a row below PityRarity, the next is at least PityRarity.
	PityAfter = 9,
	PityRarity = "Rare",
	-- Blueprint drop type: a shop room, weighted toward common roles.
	BlueprintRooms = table.freeze({ GuardRoom = 40, MushroomCavern = 25, MonsterDen = 20, RestlessCrypt = 15 }),
	CraftCost = 5, -- blueprints of one type -> one Common room of that type
	ScrapReturn = 2, -- blueprints back for scrapping an unplaced room
	MaxStack = 999, -- most boxes of one type or blueprints of one room held
	-- A box earned while its stack is full converts to this many coins (banked).
	BoxOverflowCoins = table.freeze({ Dungeon = 100, Rare = 300 }),
	ChallengerCooldown = 120, -- seconds after a challenger encounter ends before another invite
})

-- Keeper XP and levels. XP to go from level L to L + 1 is XpBase + XpPerLevel * (L - 1).
Balance.Progression = table.freeze({
	Xp = table.freeze({ Practice = 5, Novice = 10, Scout = 12, Cleric = 14, ArmoredChallenger = 30 }),
	XpBase = 50,
	XpPerLevel = 25,
	MaxLevel = 100,
	-- Each level-up gives a Dungeon Box; every RareBoxEvery-th level a Rare Box instead.
	RareBoxEvery = 5,
	-- Keeper level needed to buy a shop room.
	ShopLevel = table.freeze({ MushroomCavern = 3, MonsterDen = 5, RestlessCrypt = 8 }),
})

-- Account-wide keeper upgrades bought with banked coins; never reset. Cost to
-- go from level L to L + 1 is round(Base * CostGrowth ^ L). Each level adds
-- PerLevel to Effect.
Balance.Permanent = table.freeze({
	Order = table.freeze({ "GoldenTouch", "LuckyCharm", "Scholar", "StoutDefenders", "Lure", "DeepVault" }),
	CostGrowth = 1.6,
	GoldenTouch = table.freeze({ Effect = "Coins", PerLevel = 0.05, MaxLevel = 10, Base = 200 }),
	LuckyCharm = table.freeze({ Effect = "Loot", PerLevel = 0.05, MaxLevel = 10, Base = 200 }),
	Scholar = table.freeze({ Effect = "Xp", PerLevel = 0.10, MaxLevel = 5, Base = 250 }),
	StoutDefenders = table.freeze({ Effect = "DefenderHealth", PerLevel = 0.05, MaxLevel = 10, Base = 200 }),
	Lure = table.freeze({ Effect = "VisitorInterval", PerLevel = 1, MaxLevel = 5, Base = 400 }), -- seconds shorter
	DeepVault = table.freeze({ Effect = "VaultBonusCap", PerLevel = 0.02, MaxLevel = 5, Base = 300 }),
})

Balance.Server = table.freeze({
	MaxPlots = 6,
})

return table.freeze(Balance)
