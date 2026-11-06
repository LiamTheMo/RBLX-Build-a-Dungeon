-- Creator Store audio picked by name/creator/duration only; listen and confirm before release.
-- Volume is the slot's loudness before the player's SFX setting. Combat sounds repeat a lot, so
-- they are much quieter than the UI ones and carry a longer Cooldown (seconds between plays).
return table.freeze({
	Click = { Id = "rbxassetid://15675059323", Volume = 0.3 },
	Place = { Id = "rbxassetid://9119998434", Volume = 0.3 },
	Commit = { Id = "rbxassetid://103516326607012", Volume = 0.3 },
	Error = { Id = "rbxassetid://91501650514390", Volume = 0.25 },
	CoinGain = { Id = "rbxassetid://135483737426662", Volume = 0.2, Cooldown = 0.12 },
	Bank = { Id = "rbxassetid://133570405319995", Volume = 0.25 },
	SpikeStrike = { Id = "rbxassetid://18686538327", Volume = 0.1, Cooldown = 0.18 },
	GuardAttack = { Id = "rbxassetid://127083126906441", Volume = 0.1, Cooldown = 0.18 },
	Hit = { Id = "rbxassetid://109495438839139", Volume = 0.08, Cooldown = 0.15 },
	VisitorDefeated = { Id = "rbxassetid://9116406610", Volume = 0.12, Cooldown = 0.3 },
	VisitorArrive = { Id = "rbxassetid://125209584906878", Volume = 0.12, Cooldown = 0.3 },
	Rise = { Id = "rbxassetid://4262181447", Volume = 0.1, Cooldown = 0.3 },
	Spores = { Id = "rbxassetid://9125640290", Volume = 0.08, Cooldown = 0.25 },
	Heal = { Id = "rbxassetid://4612374393", Volume = 0.1, Cooldown = 0.25 },
	Purchase = { Id = "rbxassetid://120891770644830", Volume = 0.25 },
	UpgradePurchase = { Id = "rbxassetid://103516326607012", Volume = 0.25 },
	LootCollect = { Id = "rbxassetid://4262181447", Volume = 0.14, Cooldown = 0.2 },
})
