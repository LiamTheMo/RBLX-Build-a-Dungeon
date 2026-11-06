--!strict
-- Room identities and placement rules (GDD "Room roster"). Tunable numbers
-- (costs, damage, timings, perks) live in Balance.luau, keyed by the same Id.
-- Ids are persisted in profiles: never rename or reuse one.
--
-- Item model (owner-approved 2026-11-05): every room DEFINITION has one fixed
-- Rarity (a Balance.Rarities Id) and fixed Perks (Balance.RoomPerks); a saved
-- room instance is only {Id, Level, Modifier?}. The rarity sets the upgrade cap,
-- loot odds and craft/scrap costs. Only Common and Uncommon rooms are sold.

local Balance = require(script.Parent.Balance)

export type Kind = "Entrance" | "Defender" | "Trap" | "Treasure" | "Support"
-- Permanent: part of every plot. Starter: owned from the first join.
-- Tutorial: granted by onboarding. Shop: bought with coins (also in boxes).
-- Loot: boxes and blueprints only (Rare and rarer).
export type Source = "Permanent" | "Starter" | "Tutorial" | "Shop" | "Loot"

export type Perk = { Kind: string, Amount: number }

export type RoomDef = {
	Id: string,
	DisplayName: string,
	Kind: Kind,
	Source: Source,
	Rarity: string,
	Description: string,
	-- One short line for cards: what makes this room special.
	Ability: string,
	-- Whether the player can place, move and remove it.
	Placeable: boolean,
	-- Most copies on one plot at a time; nil means no limit beyond grid space.
	-- Kinds may also be limited as a whole (Rooms.KindLimit).
	MaxPlaced: number?,
	-- Whether the player can pay to level it up (up to its rarity's MaxLevel).
	Upgradable: boolean,
	-- Must be the last room on the route when placed.
	EndsRoute: boolean,
	-- Built-in perks (from Balance.RoomPerks); empty for most rooms.
	Perks: { Perk },
	ArtSource: string?,
}

local Rooms = {}

Rooms.Version = 4

-- Most rooms of one Kind on a plot at a time: only one treasure of any tier.
Rooms.KindLimit = table.freeze({ Treasure = 1 })

local function room(
	id: string,
	name: string,
	kind: Kind,
	source: Source,
	rarity: string,
	ability: string,
	description: string,
	artSource: string?
): any
	local treasure = kind == "Treasure"
	return {
		Id = id,
		DisplayName = name,
		Kind = kind,
		Source = source,
		Rarity = rarity,
		Ability = ability,
		Description = description,
		Placeable = true,
		MaxPlaced = if treasure then 1 else nil,
		Upgradable = true,
		EndsRoute = treasure,
		ArtSource = artSource,
	}
end

local list = {
	{
		Id = "Entrance",
		DisplayName = "Entrance",
		Kind = "Entrance",
		Source = "Permanent",
		Rarity = "Common",
		Ability = "Where adventurers arrive.",
		Description = "Where adventurers arrive. Fixed in place.",
		Placeable = false,
		MaxPlaced = 1,
		Upgradable = false,
		EndsRoute = false,
	},
	-- Common
	room("SlimeNest", "Slime Nest", "Defender", "Starter", "Common", "Hits slow the adventurer.",
		"A slime fights each adventurer and slows them for a few seconds."),
	room("SpikeHall", "Spike Hall", "Trap", "Tutorial", "Common", "Strikes after a warning flash.",
		"Spikes flash, then strike anyone standing on them. Slowed adventurers get hit more."),
	room("GuardRoom", "Guard Room", "Defender", "Shop", "Common", "Steady, heavy hits.",
		"A sturdy guard with steady, heavy hits."),
	room("TreasureRoom", "Coin Cache", "Treasure", "Starter", "Common", "Basic vault exchange.",
		"Optional. Attracts adventurers more often and grows a vault bonus, "
			.. "but an adventurer who reaches it steals part of the vaulted coins."),
	-- Uncommon
	room("MushroomCavern", "Mushroom Cavern", "Trap", "Shop", "Uncommon", "Spored adventurers take more trap damage.",
		"Spores cloud adventurers passing through. Spored adventurers take extra trap damage."),
	room("ArrowGallery", "Arrow Gallery", "Trap", "Shop", "Uncommon", "Fast volleys hit anywhere in the room.",
		"Archers' slits line the walls. Quick arrow volleys hit adventurers anywhere in the room."),
	room("BatRoost", "Bat Roost", "Defender", "Shop", "Uncommon", "Fragile, but bites very fast.",
		"A swarm of bats nips at each adventurer with very fast, light bites."),
	room("Strongbox", "Strongbox", "Treasure", "Shop", "Uncommon", "Better vault exchange.",
		"A locked strongbox: a better vault exchange than the Coin Cache. Only one treasure can be placed."),
	-- Rare
	room("MonsterDen", "Monster Den", "Support", "Loot", "Rare", "Boosts defenders next to it.",
		"No monster of its own. Defender rooms next to it on the route hit harder and are tougher."),
	room("RestlessCrypt", "Restless Crypt", "Defender", "Loot", "Rare", "Rises once at half health.",
		"A skeleton that rises once, at half health, the first time it is knocked out."),
	room("FlameVent", "Flame Vent", "Trap", "Loot", "Rare", "Strikes and sets adventurers on fire.",
		"Vents blast fire on a slow cycle. A hit sets the adventurer burning for a few seconds."),
	room("Treasury", "Treasury", "Treasure", "Loot", "Rare", "Good vault exchange, +coins.",
		"A guarded treasury with a good vault exchange. Only one treasure can be placed."),
	-- Epic
	room("FrostChamber", "Frost Chamber", "Trap", "Loot", "Epic", "Chills: slows and hurts here and in the next room.",
		"Freezing air chills adventurers inside and in the next room: slower, and taking steady cold damage."),
	room("GoblinBarracks", "Goblin Barracks", "Defender", "Loot", "Epic", "Two goblins, one after the other.",
		"Two goblins fight each adventurer. When the first is knocked out, the second steps in."),
	room("MimicRoom", "Mimic Room", "Defender", "Loot", "Epic", "Ambush: a big first bite.",
		"Looks like a treasure chest. It bites hard the moment an adventurer arrives, then keeps fighting."),
	room("RoyalVault", "Royal Vault", "Treasure", "Loot", "Epic", "Great vault exchange, +coins.",
		"A royal vault with a great vault exchange. Only one treasure can be placed."),
	-- Legendary
	room("GolemForge", "Golem Forge", "Defender", "Loot", "Legendary", "A very tough, slow-hitting tank.",
		"A stone golem with huge health and slow, crushing blows."),
	room("LichSanctum", "Lich Sanctum", "Defender", "Loot", "Legendary", "Summons a skeleton, then fights.",
		"The lich summons a skeleton to fight first, then fights the adventurer itself."),
	room("DragonHoard", "Dragon Hoard", "Treasure", "Loot", "Legendary", "Huge exchange, rarer adventurers.",
		"A dragon's hoard: a huge vault exchange, and rare adventurer variants are more likely. "
			.. "Only one treasure can be placed."),
	-- Mythic
	room("DragonLair", "Dragon Lair", "Defender", "Loot", "Mythic", "Fire breath burns.",
		"A dragon with enormous health whose fire breath sets adventurers burning."),
	room("PhoenixNest", "Phoenix Nest", "Defender", "Loot", "Mythic", "Revives the first defender knocked out.",
		"A phoenix that fights, and once per adventurer revives the first defender on the route that is "
			.. "knocked out, at full health (itself included)."),
	room("CelestialCoffer", "Celestial Coffer", "Treasure", "Loot", "Mythic", "Enormous exchange, +coins.",
		"A coffer of starlight: an enormous vault exchange and extra coins. Only one treasure can be placed."),
	-- Secret
	room("VoidGate", "Void Gate", "Trap", "Loot", "Secret", "Sends the adventurer back to the start once.",
		"The void hurts anyone inside. The first time an adventurer reaches its centre, it is sent back to "
			.. "the entrance, keeping its wounds, and must walk the whole dungeon again."),
	room("VoidVault", "Void Vault", "Treasure", "Loot", "Secret", "Best exchange; thieves take half.",
		"A vault in the void: the best exchange, and thieves who reach it take only half as much. "
			.. "Only one treasure can be placed."),
	-- Chest-specific rooms reuse existing models until distinct art is authored.
	room("RoyalGuard", "Royal Guard", "Defender", "Loot", "Common", "A stronger guard.", "A royal guard with steady, heavy hits.", "GuardRoom"),
	room("CrystalGuard", "Crystal Guard", "Defender", "Loot", "Common", "A crystal-armoured guard.", "A crystal-armoured guard with steady, heavy hits.", "GuardRoom"),
	room("CrystalSentry", "Crystal Sentry", "Defender", "Loot", "Uncommon", "A nimble guard slows its target.", "A crystal sentry slows visitors with every strike.", "GuardRoom"),
	room("CrystalBarricade", "Crystal Barricade", "Trap", "Loot", "Rare", "Quick crystal spikes.", "A crystal spike trap strikes in quick cycles.", "SpikeHall"),
	room("PrismGallery", "Prism Gallery", "Trap", "Loot", "Epic", "Rapid crystal volleys.", "Crystal bolts strike visitors throughout the gallery.", "ArrowGallery"),
	room("PrismSentinel", "Prism Sentinel", "Defender", "Loot", "Legendary", "A durable crystal guardian.", "A prism guardian holds the line with heavy, steady blows.", "GolemForge"),
	room("PrismSanctum", "Prism Sanctum", "Defender", "Loot", "Mythic", "Burns and revives a defender once.", "A prism guardian burns visitors and revives the first fallen defender once.", "PhoenixNest"),
	room("PrismBastion", "Prism Bastion", "Defender", "Loot", "Secret", "A guardian rises once after defeat.", "A prism guardian fights hard and rises once with partial health.", "DragonLair"),
	room("EmeraldGuardroom", "Emerald Guardroom", "Defender", "Loot", "Uncommon", "A nimble guard slows its target.",
		"An emerald guard slows visitors with every strike.", "GuardRoom"),
	room("ArcaneBarricade", "Arcane Barricade", "Trap", "Loot", "Rare", "Quick arcane spikes.",
		"An arcane spike trap strikes in quick cycles.", "SpikeHall"),
	room("StormGallery", "Storm Gallery", "Trap", "Loot", "Epic", "Rapid storm volleys.",
		"Storm bolts strike visitors throughout the gallery.", "ArrowGallery"),
	room("CrystalSentinel", "Crystal Sentinel", "Defender", "Loot", "Legendary", "A durable crystal guardian.",
		"A crystal guardian holds the line with heavy, steady blows.", "GolemForge"),
	room("SunfireSanctum", "Sunfire Sanctum", "Defender", "Loot", "Mythic", "Burns and revives a defender once.",
		"A sunfire guardian burns visitors and revives the first fallen defender once.", "PhoenixNest"),
	room("EclipseBastion", "Eclipse Bastion", "Defender", "Loot", "Secret", "A guardian rises once after defeat.",
		"An eclipse guardian fights hard and rises once with partial health.", "DragonLair"),
}

local definitions: { [string]: RoomDef } = {}
local order = {}
for _, def in list do
	def.Perks = Balance.RoomPerks[def.Id] or table.freeze({})
	table.freeze(def)
	definitions[def.Id] = def
	table.insert(order, def.Id)
end

Rooms.All = table.freeze(definitions)

-- Display order for inventories and the shop: by rarity, then by role.
Rooms.Order = table.freeze(order)

function Rooms.Get(id: any): RoomDef?
	return if type(id) == "string" then definitions[id] else nil
end

-- The room's fixed rarity id ("Common" for an unknown id).
function Rooms.Rarity(id: any): string
	local def = Rooms.Get(id)
	return if def then def.Rarity else "Common"
end

-- True for a room of Kind "Treasure" (any tier).
function Rooms.IsTreasure(id: any): boolean
	local def = Rooms.Get(id)
	return def ~= nil and def.Kind == "Treasure"
end

return table.freeze(Rooms)
