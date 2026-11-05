-- Tiny cross-controller hand-off: signals plus a registry of GUI targets the
-- tutorial can point at. Controllers do not require each other.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Core.Signal)

return {
	BuildRequested = Signal.new(), -- HUD / tutorial asks BuildController to enter build mode
	ShopRequested = Signal.new(),
	OpenPanel = Signal.new(), -- "Loot" | "Collection" | "Keeper" | "Close" (HUD fires, LootController listens)
	CellHint = Signal.new(), -- fires cell key "3,3" or nil; shown by BuildController while building
	Targets = {} :: { [string]: { Instance: GuiObject, Stroke: UIStroke? } }, -- "Build", "Bank", "Shop", "Loot"...
}
