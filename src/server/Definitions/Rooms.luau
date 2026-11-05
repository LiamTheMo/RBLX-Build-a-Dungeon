--!strict
-- Room identities and placement rules (GDD "Initial room roster"). Tunable
-- numbers (costs, damage, timings) live in Balance.luau, keyed by the same Id.
-- Ids are persisted in profiles: never rename or reuse one.

export type Kind = "Entrance" | "Defender" | "Trap" | "Treasure" | "Support"
-- Permanent: part of every plot. Starter: owned from the first join.
-- Tutorial: granted by onboarding. Shop: bought with banked coins.
export type Source = "Permanent" | "Starter" | "Tutorial" | "Shop"

export type RoomDef = {
	Id: string,
	DisplayName: string,
	Kind: Kind,
	Source: Source,
	Description: string,
	-- Whether the player can place, move and remove it.
	Placeable: boolean,
	-- Most copies on one plot at a time; nil means no limit beyond grid space.
	MaxPlaced: number?,
	-- Whether the player can pay to level it up (up to its rarity's MaxLevel).
	Upgradable: boolean,
	-- Must be the last room on the route when placed.
	EndsRoute: boolean,
}

local Rooms = {}

Rooms.Version = 3

local definitions: { [string]: RoomDef } = {
	Entrance = {
		Id = "Entrance",
		DisplayName = "Entrance",
		Kind = "Entrance",
		Source = "Permanent",
		Description = "Where adventurers arrive. Fixed in place.",
		Placeable = false,
		MaxPlaced = 1,
		Upgradable = false,
		EndsRoute = false,
	},
	SlimeNest = {
		Id = "SlimeNest",
		DisplayName = "Slime Nest",
		Kind = "Defender",
		Source = "Starter",
		Description = "A slime fights each adventurer and slows them for a few seconds.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	SpikeHall = {
		Id = "SpikeHall",
		DisplayName = "Spike Hall",
		Kind = "Trap",
		Source = "Tutorial",
		Description = "Spikes flash, then strike anyone standing on them. Slowed adventurers get hit more.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	GuardRoom = {
		Id = "GuardRoom",
		DisplayName = "Guard Room",
		Kind = "Defender",
		Source = "Shop",
		Description = "A sturdy guard with steady, heavy hits.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	MonsterDen = {
		Id = "MonsterDen",
		DisplayName = "Monster Den",
		Kind = "Support",
		Source = "Shop",
		Description = "No monster of its own. Defender rooms next to it on the route hit harder and are tougher.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	MushroomCavern = {
		Id = "MushroomCavern",
		DisplayName = "Mushroom Cavern",
		Kind = "Trap",
		Source = "Shop",
		Description = "Spores cloud adventurers passing through. Spored adventurers take extra trap damage.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	RestlessCrypt = {
		Id = "RestlessCrypt",
		DisplayName = "Restless Crypt",
		Kind = "Defender",
		Source = "Shop",
		Description = "A skeleton that rises once, at half health, the first time it is knocked out.",
		Placeable = true,
		MaxPlaced = nil,
		Upgradable = true,
		EndsRoute = false,
	},
	TreasureRoom = {
		Id = "TreasureRoom",
		DisplayName = "Treasure Room",
		Kind = "Treasure",
		Source = "Starter",
		Description = "Optional. Attracts adventurers more often and grows a vault bonus, "
			.. "but an adventurer who reaches it steals part of the unbanked vault.",
		Placeable = true,
		MaxPlaced = 1,
		Upgradable = true,
		EndsRoute = true,
	},
}

for _, def in definitions do
	table.freeze(def)
end

Rooms.All = table.freeze(definitions)

-- Display order for inventories and the shop.
Rooms.Order = table.freeze({ "Entrance", "SlimeNest", "SpikeHall", "GuardRoom", "MonsterDen", "MushroomCavern", "RestlessCrypt", "TreasureRoom" })

function Rooms.Get(id: string): RoomDef?
	return definitions[id]
end

return table.freeze(Rooms)
