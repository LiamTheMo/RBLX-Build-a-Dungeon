--!strict
-- Remote names under ReplicatedStorage.Remotes (docs/ARCHITECTURE.md, "Remotes").
-- Function = RemoteFunction (client -> server); Event = RemoteEvent.

local Remotes = {}

Remotes.Kinds = table.freeze({
	SetBuilding = "Function",
	CommitLayout = "Function",
	Bank = "Function",
	Buy = "Function",
	Upgrade = "Function",
	InviteChallenger = "Function",
	TutorialAction = "Function",
	SaveSettings = "Function",
	OpenBox = "Function",
	CraftBlueprint = "Function",
	ScrapRoom = "Function",
	BuyPermanent = "Function",
	State = "Event",
	EncounterFx = "Event",
	Notice = "Event",
})

return table.freeze(Remotes)
