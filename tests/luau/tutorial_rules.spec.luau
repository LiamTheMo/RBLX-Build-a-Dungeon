local Server = game:GetService("ServerScriptService").Server
local T = require(Server.Rules.TutorialRules)
local Inv = require(Server.Rules.RoomInventory)

local function ctx(o)
	return { SpikePlaced = o and o.spike or false, TreasurePlaced = o and o.treasure or false, OwnsGuard = o and o.guard or false }
end

test("happy path", function()
	local s = "Welcome"
	s = T.Reduce(s, "Next", ctx()); expectEq(s, "PracticeEncounter", "next")
	s = T.Reduce(s, "EncounterEnd", ctx()); expectEq(s, "PlaceSpike", "practice end")
	s = T.Reduce(s, "Commit", ctx({ spike = true })); expectEq(s, "WatchNovice", "spike placed")
	s = T.Reduce(s, "EncounterEnd", ctx({ spike = true })); expectEq(s, "TreasureOffer", "novice end")
	s = T.Reduce(s, "Commit", ctx({ spike = true, treasure = true })); expectEq(s, "BankVault", "treasure placed")
	s = T.Reduce(s, "VaultSet", ctx({ spike = true, treasure = true })); expectEq(s, "BuyGuard", "vault share set")
	s = T.Reduce(s, "Bought", ctx({ spike = true, treasure = true, guard = true })); expectEq(s, "Done", "guard")
end)

test("decline, skip and recovery", function()
	expectEq(T.Reduce("TreasureOffer", "DeclineTreasure", ctx({ spike = true })), "BuyGuard", "decline")
	expectEq(T.Reduce("BankVault", "DeclineTreasure", ctx({ treasure = true })), "BuyGuard", "decline in bank step")
	expectEq(T.Reduce("Welcome", "Skip", ctx()), "Done", "skip")
	expectEq(T.Reduce("Done", "Next", ctx()), "Done", "done is final")
	expectEq(T.Reduce("WatchNovice", "Commit", ctx()), "PlaceSpike", "spike removed")
	expectEq(T.Reduce("BankVault", "Commit", ctx({ spike = true })), "BuyGuard", "treasure removed")
	expectEq(T.Reduce("TreasureOffer", "Load", ctx({ spike = true, guard = true })), "Done", "already owns guard")
	expectEq(T.Reduce("PlaceSpike", "Load", ctx({ spike = true })), "WatchNovice", "already placed")
	expectEq(T.Reduce("Bogus", "Load", ctx()), "Welcome", "unknown step restarts")
	expectEq(T.Reduce("Welcome", "EncounterEnd", ctx()), "Welcome", "ignored event")
end)

-- Investigated "tutorial jumped to Done right after the Practice encounter": the only rules paths are
-- (1) a profile that already owns a GuardRoom (stale Studio profile; recovery rule) and (2) Skip,
-- which becomes allowed once the first encounter ends (Encounters >= 1), while its button sits on the bubble.
test("jump to Done after the practice encounter needs a guard or Skip", function()
	expectEq(T.Reduce("PracticeEncounter", "EncounterEnd", ctx({ guard = true })), "Done", "stale profile owning a guard")
	expectEq(T.Reduce("PracticeEncounter", "EncounterEnd", ctx()), "PlaceSpike", "fresh profile goes to PlaceSpike")
	expectEq(T.Reduce("PlaceSpike", "Skip", ctx()), "Done", "skip after the practice encounter")
	expectEq(T.Reduce("PracticeEncounter", "Next", ctx()), "PracticeEncounter", "stray Next does nothing")
end)

test("skip is locked until an encounter was finished", function()
	expect(not T.CanSkip({ Stats = { Encounters = 0 } }), "locked on a fresh profile")
	expect(T.CanSkip({ Stats = { Encounters = 1 } }), "unlocked after one encounter")
	expect(not T.CanSkip({}), "no stats")
end)

test("room inventory", function()
	local p = { NextSerial = 3, Rooms = { r1 = { Id = "SlimeNest", Level = 1 } } }
	expectEq(Inv.Add(p, "SpikeHall"), "r3", "id")
	expectEq(p.NextSerial, 4, "serial")
	p.Rooms.r4 = { Id = "GuardRoom", Level = 1 }
	expectEq(Inv.Add(p, "GuardRoom"), "r5", "skips taken ids")
	expectEq(Inv.Count(p), 4, "count")
	expect(Inv.Owns(p, "SpikeHall") and not Inv.Owns(p, "TreasureRoom"), "owns")
end)
