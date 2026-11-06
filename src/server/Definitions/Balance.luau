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

Balance.Version = 5

Balance.Economy = table.freeze({
	StartingCoins = 0,
})

Balance.Timing = table.freeze({
	-- Seconds after the previous encounter ends before the next automatic visitor
	-- (before Lure, the vault bonus and events).
	VisitorInterval = 30,
	-- No modifier (vault bonus, Lure, Swarm) brings the interval below this.
	MinVisitorInterval = 5,
})

-- Treasure vault allocation (owner-approved 2026-11-05). The player picks
-- VaultPercent (0..100); while a treasure-kind room is on the route,
-- floor(Coins * pct / 100) coins count as vaulted: visitors who reach the
-- treasure steal TheftFraction of them (times the treasure's TheftScale). In
-- exchange: bonus % = LogBonus * log10(1 + vaulted coins / CoinScale) * rate,
-- where rate = RatePerPercent * the
-- treasure room's Exchange (Balance.Rooms) * (1 + LevelBonus * (level - 1) +
-- DeepVault PerLevel * Deep Vault level). The bonus shortens the visitor interval
-- (interval / (1 + bonus / 100)) and multiplies rare-variant chances by
-- (1 + VariantPerBonus * bonus / 100).
Balance.Vault = table.freeze({
	RatePerPercent = 1.0,
	CoinScale = 100,
	LogBonus = 25,
	LevelBonus = 0.1,
	VariantPerBonus = 0.5,
})

-- Threat levels: the attackers a keeper unlocks for better loot. Tier t unlocks at
-- keeper level UnlockLevels[t]; the player picks the active tier (the tutorial
-- always uses tier 1). Per tier above 1 each stat multiplier grows by PerTier:
-- multiplier = 1 + PerTier * (t - 1). Roster[t] = visitor weights at that tier
-- (ordered; Practice is tutorial-only and never rostered).
local function roster(...)
	local list = {}
	for i = 1, select("#", ...), 2 do
		local id, weight = select(i, ...)
		table.insert(list, table.freeze({ Id = id, Weight = weight }))
	end
	return table.freeze(list)
end
Balance.Threat = table.freeze({
	UnlockLevels = table.freeze({ 1, 4, 8, 13, 19, 26 }),
	PerTier = table.freeze({ Health = 0.35, Damage = 0.35, Coins = 0.5, Xp = 0.4, Drops = 0.25 }),
	Roster = table.freeze({
		roster("Novice", 100),
		roster("Novice", 70, "Scout", 30),
		roster("Novice", 50, "Scout", 30, "Cleric", 20),
		roster("Novice", 35, "Scout", 30, "Cleric", 25, "ArmoredChallenger", 10),
		roster("Novice", 20, "Scout", 30, "Cleric", 30, "ArmoredChallenger", 20),
		roster("Novice", 10, "Scout", 25, "Cleric", 35, "ArmoredChallenger", 30),
	}),
})

-- Rare visitor variants, rolled once at spawn (never for Practice). Ordered
-- rarest first; Chance is the base chance per visitor, multiplied by the vault
-- bonus and events. Health/Coins/Drops multiply the visitor's health, coin
-- reward and drop chances; GuaranteedBox is an extra box on defeat.
local function variant(id: string, chance: number, health: number, coins: number, drops: number, box: string?)
	return table.freeze({ Id = id, Chance = chance, Health = health, Coins = coins, Drops = drops, GuaranteedBox = box })
end
Balance.Variants = table.freeze({
	variant("Gilded", 0.002, 2.0, 10, 1, "Rare"),
	variant("Shiny", 0.01, 1.2, 3, 1, "Dungeon"),
	variant("Elite", 0.05, 1.5, 2, 2, nil),
})

-- Server events (one at a time). Effects multiply: Coins (win coins), Drops (drop
-- chances), Variants (rare-variant chances), BoxRarity (box weights of
-- BoxRarityFrom and rarer), Interval (visitor interval, still >= the minimum).
-- While an event runs, a room from a box gets a Modifier with ModifierChance.
local function event(id: string, name: string, text: string, effects)
	return table.freeze({ Id = id, Name = name, Text = text, Effects = table.freeze(effects) })
end
local function modifier(id: string, effect: string, amount: number, text: string)
	return table.freeze({ Id = id, Effect = effect, Amount = amount, Text = text })
end
Balance.Events = table.freeze({
	List = table.freeze({
		event("GoldenHour", "Golden Hour", "Double coins from defeated adventurers.", { Coins = 2 }),
		event("LuckyStars", "Lucky Stars", "Double drop chances.", { Drops = 2 }),
		event("RareInvasion", "Rare Invasion", "Triple chance of Elite, Shiny and Gilded adventurers.", { Variants = 3 }),
		event("BlessedBoxes", "Blessed Boxes", "Epic and rarer rooms are twice as likely in boxes.", { BoxRarity = 2 }),
		event("Swarm", "Swarm", "Adventurers arrive twice as often.", { Interval = 0.5 }),
	}),
	BoxRarityFrom = "Epic",
	-- Automatic schedule: a random event every MinGap..MaxGap seconds after the
	-- previous one ends (or the server starts), lasting Duration. Off in Studio
	-- unless RunInStudio (admins can still start one with /event start).
	MinGap = 35 * 60,
	MaxGap = 50 * 60,
	Duration = 10 * 60,
	MaxAdminMinutes = 240,
	RunInStudio = false,
	-- Room modifiers: at most one per room. Damage scales that room's defender
	-- and trap damage; Loot and Coins add to the bonuses like perks (capped).
	ModifierChance = 0.25,
	Modifiers = table.freeze({
		modifier("Blazing", "Damage", 0.15, "+15% damage"),
		modifier("Lucky", "Loot", 0.10, "+10% loot chance"),
		modifier("Golden", "Coins", 0.10, "+10% coins"),
	}),
})

-- Visitors stop to fight a room's defender until it is knocked out (it recovers
-- after the encounter). Traps hit them as they pass.
Balance.Visitors = table.freeze({
	Practice = table.freeze({
		Health = 20,
		AttackDamage = 5,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = table.freeze({ Min = 8, Max = 12 }),
		TheftFraction = 0,
	}),
	Novice = table.freeze({
		Health = 60,
		AttackDamage = 10,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = table.freeze({ Min = 18, Max = 26 }),
		TheftFraction = 0.10,
	}),
	ArmoredChallenger = table.freeze({
		Health = 160,
		AttackDamage = 14,
		AttackInterval = 1.0,
		WalkSpeed = 3.5,
		Reward = table.freeze({ Min = 45, Max = 65 }),
		TheftFraction = 0.25,
	}),
	-- Phase 7 visitors with visible traits (docs/GDD.md). Traits are named in
	-- Visitors.luau; their numbers are here.
	Scout = table.freeze({
		Health = 50,
		AttackDamage = 8,
		AttackInterval = 1.0,
		WalkSpeed = 6,
		Reward = table.freeze({ Min = 22, Max = 32 }),
		TheftFraction = 0.10,
	}),
	Cleric = table.freeze({
		Health = 70,
		AttackDamage = 8,
		AttackInterval = 1.0,
		WalkSpeed = 4,
		Reward = table.freeze({ Min = 26, Max = 36 }),
		TheftFraction = 0.10,
		-- Mender: HP regained per second while walking (not while duelling or burning).
		HealPerSecond = 4,
	}),
})

-- Shared status effects. Burn: DamagePerSecond (before the source room's level
-- and Blazing scaling) dealt in ticks every Tick seconds for Duration seconds;
-- a new burn refreshes the duration and keeps the stronger damage. Burning
-- visitors cannot heal (Mender). Burn ticks are not trap strikes: Spored does
-- not raise them.
Balance.Status = table.freeze({
	Burn = table.freeze({ DamagePerSecond = 5, Duration = 3, Tick = 0.5 }),
})

-- Room stats, keyed by room Id (rarity, kind and texts are in Rooms.luau). Each
-- level above 1 scales defender damage and health, trap, zone and burn damage
-- and the Den / Mushroom bonuses (Balance.Upgrades). Cost = shop price in coins
-- (only Common and Uncommon rooms are sold; level gates in
-- Balance.Progression.ShopLevel).
-- Defenders: DefenderHealth / AttackDamage / AttackInterval, or Units = an ordered
-- list fought one after another (the next unit steps in when one is knocked out).
-- Strike traps: Damage every Cycle seconds, the first strike Telegraph seconds
-- after the encounter starts. Zone traps: ZoneDamage per second while inside.
local function unit(name: string, health: number, damage: number, interval: number)
	return table.freeze({ Name = name, Health = health, Damage = damage, Interval = interval })
end
Balance.Rooms = table.freeze({
	-- Common ------------------------------------------------------------------
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
	-- Treasure line. Exchange replaces the old rarity multiplier in the vault rate;
	-- VariantBonus multiplies rare-variant chances by (1 + VariantBonus); TheftScale
	-- multiplies what a visitor steals. Coin bonuses are perks (RoomPerks).
	TreasureRoom = table.freeze({ Exchange = 1.0 }), -- "Coin Cache", the starter treasure
	-- Uncommon ----------------------------------------------------------------
	-- A visitor entering the cell is Spored for SporeDuration seconds and takes
	-- TrapDamageBonus more trap damage (+TrapDamageBonusPerLevel per level above 1).
	MushroomCavern = table.freeze({
		SporeDuration = 5,
		TrapDamageBonus = 0.50,
		TrapDamageBonusPerLevel = 0.10,
		Cost = 200,
	}),
	-- Arrow volleys hit anywhere in the room.
	ArrowGallery = table.freeze({
		Damage = 8,
		Cycle = 0.8,
		Telegraph = 0.3,
		Cost = 250,
	}),
	BatRoost = table.freeze({
		-- Doubled from 30/4 so the Uncommon defender out-duels the Common Guard Room.
		DefenderHealth = 60,
		AttackDamage = 6,
		AttackInterval = 0.4,
		Cost = 220,
	}),
	Strongbox = table.freeze({ Exchange = 1.15, Cost = 600 }),
	-- Rare --------------------------------------------------------------------
	-- Support room: no defender, no stop. Each Defender room next to it on the
	-- route gets these bonuses (once per defender: the strongest adjacent Den).
	-- Each level above 1 adds BonusPerLevel to both bonuses.
	MonsterDen = table.freeze({
		DamageBonus = 0.20,
		HealthBonus = 0.20,
		BonusPerLevel = 0.05,
	}),
	-- Skeleton defender: the first time it is knocked out it rises once with
	-- ReviveFraction of its max health.
	RestlessCrypt = table.freeze({
		DefenderHealth = 60,
		AttackDamage = 8,
		AttackInterval = 1.0,
		ReviveFraction = 0.5,
	}),
	-- Strike trap; a hit also sets the visitor on fire (Balance.Status.Burn).
	FlameVent = table.freeze({
		Damage = 10,
		Cycle = 1.5,
		Telegraph = 0.6,
		Burn = true,
	}),
	Treasury = table.freeze({ Exchange = 1.3 }),
	-- Epic --------------------------------------------------------------------
	-- Zone: while the visitor is inside, or in the NEXT room on the route, it is
	-- Chilled: SlowFraction slower (Sure-footed visitors ignore the slow) and
	-- ZoneDamage per second.
	FrostChamber = table.freeze({
		ZoneDamage = 3,
		SlowFraction = 0.40,
		ChillsNextRoom = true,
	}),
	GoblinBarracks = table.freeze({
		Units = table.freeze({ unit("Goblin", 50, 9, 1.0), unit("Goblin", 50, 9, 1.0) }),
	}),
	-- Looks like a chest: AmbushDamage lands the moment the visitor arrives, then
	-- a normal duel (its first regular attack one AttackInterval later).
	MimicRoom = table.freeze({
		DefenderHealth = 70,
		AttackDamage = 10,
		AttackInterval = 1.0,
		AmbushDamage = 40,
	}),
	RoyalVault = table.freeze({ Exchange = 1.6 }),
	-- Legendary ---------------------------------------------------------------
	GolemForge = table.freeze({
		DefenderHealth = 220,
		AttackDamage = 18,
		AttackInterval = 1.6,
	}),
	-- The lich summons a skeleton (the first unit) when the visitor arrives, then
	-- fights itself once the skeleton is knocked out.
	LichSanctum = table.freeze({
		Units = table.freeze({ unit("Skeleton", 40, 8, 1.0), unit("Lich", 110, 15, 1.4) }),
		Summon = true,
	}),
	DragonHoard = table.freeze({ Exchange = 2.0, VariantBonus = 0.25 }),
	-- Mythic ------------------------------------------------------------------
	-- Breath: every hit also burns (Balance.Status.Burn).
	DragonLair = table.freeze({
		DefenderHealth = 300,
		AttackDamage = 30,
		AttackInterval = 2.0,
		Burn = true,
	}),
	-- Revives = route defenders it brings back per encounter: the first one knocked
	-- out (the phoenix itself included) stands up again at full health.
	PhoenixNest = table.freeze({
		DefenderHealth = 150,
		AttackDamage = 16,
		AttackInterval = 1.2,
		Revives = 1,
	}),
	CelestialCoffer = table.freeze({ Exchange = 2.6 }),
	-- Secret ------------------------------------------------------------------
	-- Zone: ZoneDamage per second inside. Once per encounter, a visitor reaching
	-- the room's centre is sent back to the entrance (progress 0), keeping its damage.
	VoidGate = table.freeze({
		ZoneDamage = 10,
		SendsBack = true,
	}),
	VoidVault = table.freeze({ Exchange = 3.5, TheftScale = 0.5 }),
	RoyalGuard = table.freeze({ DefenderHealth = 84, AttackDamage = 12.3, AttackInterval = 1.2 }),
	CrystalGuard = table.freeze({ DefenderHealth = 88, AttackDamage = 12.6, AttackInterval = 1.2 }),
	CrystalSentry = table.freeze({ DefenderHealth = 72, AttackDamage = 11, AttackInterval = 1.0, SlowFraction = 0.3, SlowDuration = 2 }),
	CrystalBarricade = table.freeze({ Damage = 19, Cycle = 1.1, Telegraph = 0.35 }),
	PrismGallery = table.freeze({ Damage = 17, Cycle = 0.9, Telegraph = 0.3 }),
	PrismSentinel = table.freeze({ DefenderHealth = 264, AttackDamage = 22, AttackInterval = 1.6 }),
	PrismSanctum = table.freeze({ DefenderHealth = 187, AttackDamage = 20, AttackInterval = 1.2, Burn = true, Revives = 1 }),
	PrismBastion = table.freeze({ DefenderHealth = 374, AttackDamage = 35, AttackInterval = 1.6, ReviveFraction = 0.4 }),
	EmeraldGuardroom = table.freeze({ DefenderHealth = 65, AttackDamage = 10, AttackInterval = 1.0, SlowFraction = 0.3, SlowDuration = 2 }),
	ArcaneBarricade = table.freeze({ Damage = 17, Cycle = 1.1, Telegraph = 0.35 }),
	StormGallery = table.freeze({ Damage = 15, Cycle = 0.9, Telegraph = 0.3 }),
	CrystalSentinel = table.freeze({ DefenderHealth = 240, AttackDamage = 20, AttackInterval = 1.6 }),
	SunfireSanctum = table.freeze({ DefenderHealth = 170, AttackDamage = 18, AttackInterval = 1.2, Burn = true, Revives = 1 }),
	EclipseBastion = table.freeze({ DefenderHealth = 340, AttackDamage = 32, AttackInterval = 1.6, ReviveFraction = 0.4 }),
})

Balance.Upgrades = table.freeze({
	-- Coins to reach level 2, 3, ... A room stops at its rarity's MaxLevel (the
	-- list must have MaxLevel - 1 entries for the highest tier).
	Costs = table.freeze({ 60, 150, 350, 800, 1800, 3500, 6000, 10000, 16000 }),
	-- Per level above 1: scales defender damage and health, and trap damage.
	DamageBonusPerLevel = 0.25,
	HealthBonusPerLevel = 0.25,
})

-- Room rarity (GDD "Loot, rarity and progression"). THE ordered list: index is
-- rank (lowest first), and every rule and UI iterates it, so a new tier is one
-- new entry here (plus its colour in the client's Ui/RarityColors). Since the
-- 2026-11-05 item model a rarity belongs to a room DEFINITION (Rooms.luau), not
-- to an instance. Weight = Dungeon Box tier odds, RareWeight = Rare Box tier
-- odds (each column sums to 100); a box rolls a tier, then a room of that tier.
-- MaxLevel = upgrade cap of the tier's rooms. CraftCost = blueprints of one room
-- to craft it; ScrapReturn = blueprints back for scrapping one (always below
-- CraftCost). Keep Common first and never rename an Id.
local function tier(id: string, weight: number, rareWeight: number, crystalWeight: number, maxLevel: number, craft: number, scrap: number)
	return table.freeze({
		Id = id,
		Weight = weight,
		RareWeight = rareWeight,
		CrystalWeight = crystalWeight,
		MaxLevel = maxLevel,
		CraftCost = craft,
		ScrapReturn = scrap,
	})
end
Balance.Rarities = table.freeze({
	tier("Common", 60, 25, 15, 3, 5, 2),
	tier("Uncommon", 25, 35, 25, 4, 6, 3),
	tier("Rare", 10, 25, 35, 5, 8, 4),
	tier("Epic", 3.5, 10, 15, 6, 10, 5),
	tier("Legendary", 1.2, 3.5, 7, 7, 12, 6),
	tier("Mythic", 0.28, 1.2, 2.5, 8, 15, 8),
	tier("Secret", 0.02, 0.3, 0.5, 10, 20, 10),
})
local byId = {}
for _, r in Balance.Rarities do
	byId[r.Id] = r
end
Balance.RarityById = table.freeze(byId)

-- Room perks, as fractions, fixed by the room definition (RoomPerks, keyed by
-- room Id; rooms not listed have none). Perks of every room ON THE ROUTE add up
-- with the permanent upgrades, then each total is capped (Progression.Bonuses).
-- Rare: one kind +5%; Epic: one kind +10%; Legendary: two kinds; Mythic and
-- Secret: all three.
local function perks(...)
	local list = {}
	for i = 1, select("#", ...), 2 do
		local kind, amount = select(i, ...)
		table.insert(list, table.freeze({ Kind = kind, Amount = amount }))
	end
	return table.freeze(list)
end
Balance.Perks = table.freeze({
	Kinds = table.freeze({ "Coins", "Loot", "Xp" }),
	Caps = table.freeze({ Coins = 1.00, Loot = 1.00, Xp = 1.00 }),
})
Balance.RoomPerks = table.freeze({
	MonsterDen = perks("Xp", 0.05),
	RestlessCrypt = perks("Loot", 0.05),
	FlameVent = perks("Coins", 0.05),
	Treasury = perks("Coins", 0.05),
	FrostChamber = perks("Xp", 0.10),
	GoblinBarracks = perks("Loot", 0.10),
	MimicRoom = perks("Coins", 0.10),
	RoyalVault = perks("Coins", 0.10),
	GolemForge = perks("Coins", 0.10, "Xp", 0.10),
	LichSanctum = perks("Loot", 0.10, "Xp", 0.10),
	DragonHoard = perks("Coins", 0.10, "Loot", 0.10),
	DragonLair = perks("Coins", 0.10, "Loot", 0.10, "Xp", 0.10),
	PhoenixNest = perks("Coins", 0.10, "Loot", 0.10, "Xp", 0.10),
	-- Includes its "+10% coins" ability (+10% Mythic base, +10% ability).
	CelestialCoffer = perks("Coins", 0.20, "Loot", 0.10, "Xp", 0.10),
	VoidGate = perks("Coins", 0.15, "Loot", 0.15, "Xp", 0.15),
	VoidVault = perks("Coins", 0.15, "Loot", 0.15, "Xp", 0.15),
	CrystalBarricade = perks("Xp", 0.05),
	PrismGallery = perks("Loot", 0.10),
	PrismSentinel = perks("Coins", 0.10, "Xp", 0.10),
	PrismSanctum = perks("Coins", 0.10, "Loot", 0.10, "Xp", 0.10),
	PrismBastion = perks("Coins", 0.15, "Loot", 0.15, "Xp", 0.15),
	ArcaneBarricade = perks("Xp", 0.05),
	StormGallery = perks("Loot", 0.10),
	CrystalSentinel = perks("Coins", 0.10, "Xp", 0.10),
	SunfireSanctum = perks("Coins", 0.10, "Loot", 0.10, "Xp", 0.10),
	EclipseBastion = perks("Coins", 0.15, "Loot", 0.15, "Xp", 0.15),
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
	-- A box (and a blueprint drop) rolls a tier, then a room OF THAT TIER by these
	-- weights; rooms not listed weigh 1, so a tier's rooms are equally likely.
	-- 0 = never from loot and not craftable (the starter Coin Cache). The other
	-- treasure rooms weigh less: only one treasure can be placed.
	-- Royal and Dungeon chests have disjoint room pools; unlisted rooms belong to Dungeon.
	RoyalRooms = table.freeze({
		RoyalGuard = true, EmeraldGuardroom = true, ArcaneBarricade = true, StormGallery = true,
		CrystalSentinel = true, SunfireSanctum = true, EclipseBastion = true,
	}),
	CrystalRooms = table.freeze({
		CrystalGuard = true, CrystalSentry = true, CrystalBarricade = true, PrismGallery = true,
		PrismSentinel = true, PrismSanctum = true, PrismBastion = true,
	}),
	RoomWeights = table.freeze({
		TreasureRoom = 0,
		Strongbox = 0.5,
		Treasury = 0.5,
		RoyalVault = 0.5,
		DragonHoard = 0.5,
		CelestialCoffer = 0.5,
		VoidVault = 0.5,
	}),
	-- After PityAfter boxes in a row below PityRarity, the next is at least PityRarity.
	PityAfter = 9,
	PityRarity = "Rare",
	-- Blueprint drops roll their tier with this box type's tier weights (no pity,
	-- no event boost), then a room of that tier like a box.
	BlueprintTierBox = "Dungeon",
	MaxStack = 999, -- most boxes of one type or blueprints of one room held
	-- A box earned while its stack is full converts to this many coins (banked).
	BoxOverflowCoins = table.freeze({ Dungeon = 100, Rare = 300, Crystal = 600 }),
})

-- Keeper XP and levels. XP to go from level L to L + 1 is XpBase + XpPerLevel * (L - 1).
Balance.Progression = table.freeze({
	Xp = table.freeze({ Practice = 5, Novice = 10, Scout = 12, Cleric = 14, ArmoredChallenger = 30 }),
	XpBase = 50,
	XpPerLevel = 25,
	MaxLevel = 100,
	-- Each level-up gives a Dungeon Box; every RareBoxEvery-th level a Rare Box instead.
	RareBoxEvery = 5,
	CrystalBoxEvery = 10,
	-- Keeper level needed to buy a shop room (1 when absent). Boxes and blueprints
	-- respect the same gates, for Common and Uncommon rooms only.
	ShopLevel = table.freeze({ MushroomCavern = 3, BatRoost = 4, ArrowGallery = 5, Strongbox = 6 }),
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
	DeepVault = table.freeze({ Effect = "VaultRate", PerLevel = 0.05, MaxLevel = 5, Base = 300 }), -- vault exchange rate
})

Balance.Server = table.freeze({
	MaxPlots = 6,
})

return table.freeze(Balance)
