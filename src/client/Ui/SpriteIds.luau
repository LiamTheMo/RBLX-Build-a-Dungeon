-- Generated from AI design assistant sprite sheets cut by tools/cut_sheet.py (Assets repo). Origin: owner's AI design assistant account;
-- rights to be confirmed by the owner before release.
local base = {
	Icons = {
		Box = "rbxassetid://86254209003880",
		RareBox = "rbxassetid://112756641645371",
		CrystalBox = "rbxassetid://78896703019278",
		Blueprint = "rbxassetid://91244877353966",
		BlueprintCard = "rbxassetid://99515155889413",
		Collection = "rbxassetid://109550714975325",
		Keeper = "rbxassetid://78289813503783",
		Xp = "rbxassetid://94184215801867",
		Level = "rbxassetid://135476141666868",
		Lock = "rbxassetid://70892206612513",
		Check = "rbxassetid://105346638549617",
		Spores = "rbxassetid://102668667416646",
		Heal = "rbxassetid://114598902375209",
		Trap = "rbxassetid://105608937972302",
		Defender = "rbxassetid://115121131568883",
		Support = "rbxassetid://71337077110235",
		CoinStack = "rbxassetid://121465699018959",
		Trophy = "rbxassetid://101665758125287",
		Map = "rbxassetid://115740889621355",
		SoundOn = "rbxassetid://74397687536975",
		SoundOff = "rbxassetid://133929661621279",
		Music = "rbxassetid://116543446416253",
	},
	Rooms = {
		Entrance = "rbxassetid://72342447219406",
		SlimeNest = "rbxassetid://131021595088904",
		SpikeHall = "rbxassetid://76023786489781",
		GuardRoom = "rbxassetid://103146969089626",
		MonsterDen = "rbxassetid://122987917572025",
		MushroomCavern = "rbxassetid://136141986993498",
		RestlessCrypt = "rbxassetid://130564451106552",
		TreasureRoom = "rbxassetid://98476501812913",
	},
	Portraits = {
		Practice = "rbxassetid://112044234472441",
		Novice = "rbxassetid://128045489477936",
		ArmoredChallenger = "rbxassetid://70492398012883",
		Scout = "rbxassetid://136211470711449",
		Cleric = "rbxassetid://129180967659401",
		Slime = "rbxassetid://87357788574269",
		Guard = "rbxassetid://77532407311750",
		Skeleton = "rbxassetid://89534994406895",
		Keeper = "rbxassetid://112744299318368",
	},
	Rarity = {
		Common = { Gem = "rbxassetid://79690765609745" },
		Uncommon = { Gem = "rbxassetid://97676534001469" },
		Rare = { Gem = "rbxassetid://98204477230967" },
		Epic = { Gem = "rbxassetid://71880120213177" },
		Legendary = { Gem = "rbxassetid://126060381199006" },
		Secret = { Gem = "rbxassetid://123345850137737" },
		Mythic = { Gem = "rbxassetid://114231824191237" },
	},
}

-- Room icons and creature portraits of the 2026-11-05 roster (SpriteIds5) join the base tables.
local Ids5 = require(script.Parent.SpriteIds5)
for _, group in { "Rooms", "Portraits" } do
	for id, asset in Ids5[group] do
		base[group][id] = asset
	end
end
for id, source in { RoyalGuard = "GuardRoom", CrystalGuard = "GuardRoom", CrystalSentry = "EmeraldGuardroom", CrystalBarricade = "ArcaneBarricade", PrismGallery = "StormGallery", PrismSentinel = "CrystalSentinel", PrismSanctum = "SunfireSanctum", PrismBastion = "EclipseBastion" } do
	base.Rooms[id] = base.Rooms[source]
end
return table.freeze(base)
