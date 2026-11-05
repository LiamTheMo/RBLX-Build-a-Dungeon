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

Balance.Version = 1

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
})

Balance.Rooms = table.freeze({
	SlimeNest = table.freeze({
		DefenderHealth = 40,
		AttackDamage = 6,
		AttackInterval = 1.0,
		-- Each hit slows the visitor's walk speed by this fraction for SlowDuration.
		SlowFraction = 0.5,
		SlowDuration = 3,
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
})

Balance.Upgrades = table.freeze({
	-- The MVP's first room upgrade. Its effect is decided in Phase 3.
	FirstUpgradeCost = 60,
})

return table.freeze(Balance)
