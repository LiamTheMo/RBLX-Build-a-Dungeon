-- Tiny cross-controller hand-off: signals plus a registry of GUI targets the
-- tutorial can point at. Controllers do not require each other.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Core.Signal)

return {
	BuildRequested = Signal.new(), -- HUD / tutorial asks BuildController to enter build mode
	ShopRequested = Signal.new(),
	VaultRequested = Signal.new(),
	RoomAwarded = Signal.new(),
	OpenPanel = Signal.new(), -- "Bag" | "Index" | "Keeper" | "Close" (HUD fires, LootController listens)
	CellHint = Signal.new(), -- fires cell key "3,3" or nil; shown by BuildController while building
	ToastOffset = 0, -- px (reference) the toast stack moves down while the event banner shows
	Targets = {} :: { [string]: { Instance: GuiObject, Stroke: UIStroke?, Button: any? } }, -- "Build", "Shop", "Loot", "Vault"...
}
