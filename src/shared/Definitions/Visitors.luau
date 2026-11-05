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
	-- Shown before the visitor enters. Empty for the MVP visitors.
	Traits: { string },
}

local Visitors = {}

Visitors.Version = 1

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
}

for _, def in definitions do
	table.freeze(def.Traits)
	table.freeze(def)
end

Visitors.All = table.freeze(definitions)

function Visitors.Get(id: string): VisitorDef?
	return definitions[id]
end

return table.freeze(Visitors)
