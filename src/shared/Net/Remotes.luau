--!strict
-- Remote names under ReplicatedStorage.Remotes (docs/ARCHITECTURE.md, "Remotes").
-- Function = RemoteFunction (client -> server); Event = RemoteEvent.
-- This module (with Core/Loader and Core/Signal) is all the client and server
-- share: definitions, balance and rules live on the server, and the client gets
-- display data through GetCatalog, the State snapshot and plot attributes.
--
-- Cell keys in layouts and plot attributes are "column,row" strings (e.g. "3,2").

local Remotes = {}

Remotes.Kinds = table.freeze({
	GetCatalog = "Function", -- () -> (true, catalog); no loaded profile needed
	PreviewLayout = "Function", -- (layout) -> (true, routeCells, offRouteCells) | (false, reason, cellKey?); nothing is applied
	SetBuilding = "Function",
	CommitLayout = "Function",
	Buy = "Function",
	Upgrade = "Function",
	SetThreat = "Function", -- (tier: integer) -> (true, tier) | (false, "ThreatLocked" | "EncounterActive")
	SetVaultPercent = "Function", -- (percent: integer 0..100) -> (true, percent) | (false, "EncounterActive")
	TutorialAction = "Function",
	SaveSettings = "Function",
	OpenBox = "Function",
	CraftBlueprint = "Function",
	ScrapRoom = "Function",
	BuyPermanent = "Function",
	State = "Event",
	EncounterFx = "Event",
	Notice = "Event",
	ServerEvent = "Event", -- server -> all: {Kind = "Start" | "End", Id, EndsAt?}
})

return table.freeze(Remotes)
