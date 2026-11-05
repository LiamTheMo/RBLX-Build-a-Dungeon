--!strict
-- Visitor (NPC adventurer) identities (GDD "Visitors and encounters"). Stats
-- and rewards live in Balance.luau, keyed by the same Id. Ids are persisted:
-- never rename or reuse one.

-- Tutorial: sent once by onboarding. Automatic: arrives on the visitor timer.
-- Invited: only arrives after the player explicitly invites it.
export type Arrival = "Tutorial" | "Automatic" | "Invited"

export type VisitorDef = {
	Id: string,
	DisplayName: string,
	Arrival: Arrival,
	Description: string,
	-- Shown before the visitor enters (see Visitors.TraitText). Empty for the MVP visitors.
	Traits: { string },
}

local Visitors = {}

Visitors.Version = 2

local definitions: { [string]: VisitorDef } = {
	Practice = {
		Id = "Practice",
		DisplayName = "Practice Adventurer",
		Arrival = "Tutorial",
		Description = "A nervous first visitor. Your slime should handle this one.",
		Traits = {},
	},
	Novice = {
		Id = "Novice",
		DisplayName = "Novice",
		Arrival = "Automatic",
		Description = "A fresh adventurer with low health and a modest reward.",
		Traits = {},
	},
	ArmoredChallenger = {
		Id = "ArmoredChallenger",
		DisplayName = "Armored Challenger",
		Arrival = "Invited",
		Description = "Tough and well paid. Steals more if it reaches your Treasure Room.",
		Traits = {},
	},
	Scout = {
		Id = "Scout",
		DisplayName = "Scout",
		Arrival = "Automatic",
		Description = "Quick on its feet and hard to pin down.",
		Traits = { "SureFooted" },
	},
	Cleric = {
		Id = "Cleric",
		DisplayName = "Cleric",
		Arrival = "Automatic",
		Description = "Patches itself up between fights. Hit it hard while it duels.",
		Traits = { "Mender" },
	},
}

-- Player-facing trait text, keyed by the names in VisitorDef.Traits.
Visitors.TraitText = table.freeze({
	SureFooted = table.freeze({ Name = "Sure-footed", Text = "Immune to slows." }),
	Mender = table.freeze({ Name = "Mender", Text = "Heals while walking, but not while fighting." }),
})

for _, def in definitions do
	table.freeze(def.Traits)
	table.freeze(def)
end

Visitors.All = table.freeze(definitions)

function Visitors.Get(id: string): VisitorDef?
	return definitions[id]
end

return table.freeze(Visitors)
