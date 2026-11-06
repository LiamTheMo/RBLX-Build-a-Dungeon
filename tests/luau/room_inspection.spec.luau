-- Placed treasure detection must recognize every treasure tier, including
-- disconnected rooms; it only controls visibility, never vault authority.
local Server = game:GetService("ServerScriptService").Server
local Ui = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui
local Catalog = require(Ui.Catalog)
local State = require(Ui.State)
Catalog.Current = require(Server.Rules.Catalog).Build()

test("placed room kind uses the server catalog for every treasure tier", function()
	State.Current = { Layout = { ["1,1"] = "r1" }, Rooms = { r1 = { Id = "Treasury" } } }
	expect(State.HasPlacedKind("Treasure"), "higher-tier treasury detected")
	expect(not State.HasPlacedKind("Defender"), "other role not detected")
	State.Current.Layout = {}
	expect(not State.HasPlacedKind("Treasure"), "inventory alone does not count")
	State.Current.Layout["1,1"] = "missing"
	expect(not State.HasPlacedKind("Treasure"), "stale instance is safe")
	State.Current = nil
	expect(not State.HasPlacedKind("Treasure"), "missing state is safe")
end)
