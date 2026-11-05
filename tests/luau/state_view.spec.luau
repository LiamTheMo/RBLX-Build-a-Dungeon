-- Server-computed State snapshot fields (Rules/StateView): the client shows these
-- instead of running Loot, Economy or Progression itself.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Visitors = require(Server.Definitions.Visitors)
local Economy = require(Server.Rules.Economy)
local Loot = require(Server.Rules.Loot)
local Progression = require(Server.Rules.Progression)
local ProfileSchema = require(Server.Rules.ProfileSchema)
local RoomInventory = require(Server.Rules.RoomInventory)
local StateView = require(Server.Rules.StateView)

local function deepEqual(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function profileWith(level, pity)
	local p = ProfileSchema.Default()
	p.Level, p.BoxPity = level, pity
	return p
end

test("BoxOdds equals Loot.Odds(box, pity, level) for that player", function()
	for _, case in { { 1, 0 }, { 3, 4 }, { 5, 9 }, { 8, 0 }, { 100, 9 } } do
		local profile = profileWith(case[1], case[2])
		local view = StateView.Derived(profile)
		for _, box in Loot.BoxTypes do
			local expected = Loot.Odds(box, case[2], case[1])
			expect(deepEqual(view.BoxOdds[box], expected), ("%s box at level %d, pity %d"):format(box, case[1], case[2]))
		end
	end
end)

test("pity changes the odds the snapshot shows", function()
	local fresh = StateView.Derived(profileWith(1, 0)).BoxOdds.Dungeon
	local pity = StateView.Derived(profileWith(1, Balance.Loot.PityAfter)).BoxOdds.Dungeon
	expectEq(fresh.Rarities[1].Id, "Common", "common possible without pity")
	expect(pity.Rarities[1].Id ~= "Common", "pity removes tiers below " .. Balance.Loot.PityRarity)
end)

test("rooms are copies with NextUpgradeCost; the profile is untouched", function()
	local profile = ProfileSchema.Default()
	local rare = RoomInventory.Add(profile, "GuardRoom", "Rare")
	profile.Rooms[rare].Level = 5 -- Rare max
	local view = StateView.Derived(profile)
	for id, room in profile.Rooms do
		local copy = view.Rooms[id]
		expect(copy ~= nil and copy ~= room, "copied " .. id)
		expectEq(copy.Id, room.Id, "same room " .. id)
		expectEq(copy.NextUpgradeCost, Economy.UpgradeCost(room.Level, room.Rarity), "cost " .. id)
		expectEq(room.NextUpgradeCost, nil, "profile not modified " .. id)
	end
	expectEq(view.Rooms[rare].NextUpgradeCost, nil, "nil at the rarity's max")
end)

test("permanent next costs match Progression.PermanentCost, nil at max", function()
	local profile = ProfileSchema.Default()
	profile.Permanent = { GoldenTouch = 3, Scholar = Balance.Permanent.Scholar.MaxLevel }
	local view = StateView.Derived(profile)
	for _, id in Balance.Permanent.Order do
		expectEq(view.PermanentNextCost[id], Progression.PermanentCost(id, profile.Permanent[id] or 0), id)
	end
	expectEq(view.PermanentNextCost.Scholar, nil, "max")
end)

test("drop chances include the player's loot bonus", function()
	local profile = ProfileSchema.Default()
	profile.Permanent = { LuckyCharm = 4 }
	local view = StateView.Derived(profile)
	local bonus = Progression.Bonuses(profile).Loot
	expect(bonus > 0, "has a loot bonus")
	for id in Visitors.All do
		expect(deepEqual(view.DropChances[id], Loot.DropChances(id, bonus)), id)
	end
end)

test("vault bonus, cap, XP and bonuses match the rules", function()
	local profile = ProfileSchema.Default()
	profile.Vault, profile.Level = 1234, 4
	profile.Permanent = { DeepVault = 2 }
	local view = StateView.Derived(profile)
	local extra = Progression.VaultCapBonus(profile)
	expectEq(view.VaultBonus, Economy.VaultBonus(1234, extra), "vault bonus")
	expectEq(view.VaultBonusCap, Economy.VaultBonus(1e12, extra), "cap")
	expectEq(view.XpToNext, Progression.XpToNext(4), "xp to next")
	expect(deepEqual(view.Bonuses, Progression.Bonuses(profile)), "bonuses")
end)
