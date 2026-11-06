-- The display catalog the client fetches with GetCatalog (Rules/Catalog): built
-- from the server definitions, frozen, and holding only display fields.

local Server = game:GetService("ServerScriptService").Server
local Balance = require(Server.Definitions.Balance)
local Grid = require(Server.Definitions.Grid)
local Rooms = require(Server.Definitions.Rooms)
local Visitors = require(Server.Definitions.Visitors)
local Loot = require(Server.Rules.Loot)
local Progression = require(Server.Rules.Progression)
local Catalog = require(Server.Rules.Catalog)
local RarityColors = require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui.RarityColors)

local function set(list)
	local out = {}
	for _, k in list do
		out[k] = true
	end
	return out
end

-- Every key of `t` must be in `allowed` (a set).
local function onlyKeys(t, allowed, what)
	for k in t do
		expect(allowed[k] == true, what .. " has unexpected field " .. tostring(k))
	end
end

local function deepFrozen(t)
	if not table.isfrozen(t) then
		return false
	end
	for _, v in t do
		if type(v) == "table" and not deepFrozen(v) then
			return false
		end
	end
	return true
end

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

local ROOM_FIELDS = set({
	"ArtSource",
	"Id", "DisplayName", "Kind", "Description", "Source", "Cost", "ShopLevel", "Upgradable",
	"MaxPlaced", "EndsRoute", "Placeable", "Craftable", "TrapCycle", "TrapTelegraph",
	"Rarity", "Tier", "MaxLevel", "Perks", "Ability", "Exchange", "CraftCost", "ScrapReturn",
	"BaseHealth", "BaseDamage", "DamagePerSecond", "UnitCount", "SupportDamage", "SupportHealth",
})
local VISITOR_FIELDS = set({ "Id", "DisplayName", "Description", "Arrival", "Traits", "Reward", "Xp", "Theft", "Drops" })
local TRAIT_FIELDS = set({ "Id", "Name", "Text" })
local RARITY_FIELDS = set({ "Id", "MaxLevel", "CraftCost", "ScrapReturn", "Rooms" })
local PERMANENT_FIELDS = set({ "Id", "Name", "MaxLevel", "PerLevelText", "EffectText", "Effect", "PerLevelValue" })
local TOP_FIELDS = set({
	"Rooms", "RoomOrder", "Visitors", "Rarities", "Permanent", "Grid", "Loot", "MaxKeeperLevel",
	"Variants", "Threat", "Events", "Modifiers", "Vault",
})

test("the catalog is deeply frozen and deterministic", function()
	local c = Catalog.Build()
	expect(deepFrozen(c), "deep frozen")
	expect(deepEqual(c, Catalog.Build()), "same result every build")
end)

test("only approved display fields", function()
	local c = Catalog.Build()
	onlyKeys(c, TOP_FIELDS, "catalog")
	for id, r in c.Rooms do
		onlyKeys(r, ROOM_FIELDS, "room " .. id)
	end
	for id, v in c.Visitors do
		onlyKeys(v, VISITOR_FIELDS, "visitor " .. id)
		for _, t in v.Traits do
			onlyKeys(t, TRAIT_FIELDS, "trait of " .. id)
		end
	end
	for _, r in c.Rarities do
		onlyKeys(r, RARITY_FIELDS, "rarity " .. r.Id)
	end
	for _, p in c.Permanent do
		onlyKeys(p, PERMANENT_FIELDS, "permanent " .. p.Id)
	end
	onlyKeys(c.Grid, set({ "Columns", "Rows", "CellSize", "EntranceCell", "EntranceKey" }), "grid")
	onlyKeys(c.Loot, set({ "BoxTypes", "CraftCost", "ScrapReturn" }), "loot")
end)

test("rooms mirror the definitions, prices and gates", function()
	local c = Catalog.Build()
	expect(deepEqual(c.RoomOrder, Rooms.Order), "room order")
	local count = 0
	for id, def in Rooms.All do
		count += 1
		local r = c.Rooms[id]
		expect(r ~= nil, "room " .. id)
		for _, field in { "Id", "DisplayName", "Kind", "Description", "Source", "Upgradable", "MaxPlaced", "EndsRoute", "Placeable" } do
			expectEq(r[field], def[field], id .. "." .. field)
		end
		expectEq(r.Cost, Balance.Rooms[id] and Balance.Rooms[id].Cost, id .. " cost")
		expectEq(r.ShopLevel, Progression.ShopLevel(id), id .. " shop level")
		expectEq(r.Craftable, Loot.Craftable(id), id .. " craftable")
		expectEq(r.Rarity, def.Rarity, id .. " fixed rarity")
		expectEq(r.Tier, Loot.RarityRank(def.Rarity), id .. " tier rank")
		expectEq(r.MaxLevel, Balance.RarityById[def.Rarity].MaxLevel, id .. " max level")
		expectEq(r.CraftCost, Loot.CraftCost(id), id .. " craft cost")
		expectEq(r.ScrapReturn, Loot.ScrapReturn(id), id .. " scrap return")
		expectEq(#r.Perks, #def.Perks, id .. " perks")
		for i, perk in def.Perks do
			expectEq(r.Perks[i].Kind, perk.Kind, id .. " perk kind")
			expectEq(r.Perks[i].Amount, perk.Amount, id .. " perk amount")
		end
		expect(type(r.Ability) == "string" and #r.Ability > 0 and #r.Ability <= 60, id .. " short ability text")
		if def.Source == "Shop" then
			expect(r.Cost ~= nil and (r.Rarity == "Common" or r.Rarity == "Uncommon"), id .. " sold: Common/Uncommon")
		end
	end
	for _ in c.Rooms do
		count -= 1
	end
	expectEq(count, 0, "no extra rooms")
	expectEq(c.Rooms.SpikeHall.TrapCycle, Balance.Rooms.SpikeHall.Cycle, "spike cycle")
	expectEq(c.Rooms.SpikeHall.TrapTelegraph, Balance.Rooms.SpikeHall.Telegraph, "spike telegraph")
	expectEq(c.Rooms.GuardRoom.TrapCycle, nil, "defenders have no trap cycle")
	expectEq(c.Rooms.ArrowGallery.TrapCycle, 0.8, "arrow cycle")
	expectEq(c.Rooms.TreasureRoom.DisplayName, "Coin Cache", "id kept, new name")
	expectEq(c.Rooms.DragonHoard.Ability, "Vault exchange x2, +25% rare variants", "hoard ability from Balance")
	expectEq(c.Rooms.VoidVault.Ability, "Vault exchange x3.5, thieves take 50%", "void vault ability")
	expectEq(c.Rooms.Strongbox.Exchange, 1.15, "exchange shown")
	expectEq(c.Rooms.GuardRoom.BaseHealth, Balance.Rooms.GuardRoom.DefenderHealth, "base health")
	expectEq(c.Rooms.GuardRoom.BaseDamage, Balance.Rooms.GuardRoom.AttackDamage, "base damage")
	expectEq(c.Rooms.GoblinBarracks.UnitCount, 2, "multi-unit count")
	expectEq(c.Rooms.FrostChamber.DamagePerSecond, true, "zone damage label")
	expectEq(c.Rooms.MonsterDen.SupportDamage, Balance.Rooms.MonsterDen.DamageBonus, "support bonus")
	expectEq(c.Rooms.MonsterDen.Cost, nil, "Rare rooms are not sold")
end)

test("visitors carry trait names and texts", function()
	local c = Catalog.Build()
	for id, def in Visitors.All do
		local v = c.Visitors[id]
		expect(v ~= nil, "visitor " .. id)
		expectEq(v.DisplayName, def.DisplayName, id .. " name")
		expectEq(v.Arrival, def.Arrival, id .. " arrival")
		expectEq(#v.Traits, #def.Traits, id .. " trait count")
		for i, name in def.Traits do
			expectEq(v.Traits[i].Name, Visitors.TraitText[name].Name, id .. " trait name")
			expectEq(v.Traits[i].Text, Visitors.TraitText[name].Text, id .. " trait text")
		end
	end
	expectEq(c.Visitors.Scout.Traits[1].Name, "Sure-footed", "scout")
end)

test("rarities keep the server order and every tier has a client colour", function()
	local c = Catalog.Build()
	expectEq(#c.Rarities, #Balance.Rarities, "count")
	for i, r in Balance.Rarities do
		expectEq(c.Rarities[i].Id, r.Id, "rank " .. i)
		expectEq(c.Rarities[i].MaxLevel, r.MaxLevel, r.Id .. " max level")
		expectEq(c.Rarities[i].CraftCost, r.CraftCost, r.Id .. " craft cost")
		expectEq(c.Loot.CraftCost[r.Id], r.CraftCost, r.Id .. " loot craft cost")
		expectEq(c.Loot.ScrapReturn[r.Id], r.ScrapReturn, r.Id .. " loot scrap return")
		expect(#c.Rarities[i].Rooms > 0, r.Id .. " lists its rooms")
		for _, id in c.Rarities[i].Rooms do
			expectEq(c.Rooms[id].Rarity, r.Id, id .. " in " .. r.Id)
		end
		expect(RarityColors.Fill[r.Id] ~= nil, "client colour for " .. r.Id)
	end
end)

test("permanent upgrades: order, names and effect texts per level", function()
	local c = Catalog.Build()
	expectEq(#c.Permanent, #Balance.Permanent.Order, "count")
	for i, id in Balance.Permanent.Order do
		local p = c.Permanent[i]
		expectEq(p.Id, id, "order " .. i)
		expectEq(p.MaxLevel, Balance.Permanent[id].MaxLevel, id .. " max")
		expectEq(#p.EffectText, p.MaxLevel + 1, id .. " one text per level 0..max")
	end
	local golden = c.Permanent[1]
	expectEq(golden.Name, "Golden Touch", "spaced name")
	expectEq(golden.PerLevelText, "+5% coins", "per level")
	expectEq(golden.EffectText[1], "+0% coins", "level 0")
	expectEq(golden.EffectText[4], "+15% coins", "level 3")
	local byId = {}
	for _, p in c.Permanent do
		byId[p.Id] = p
	end
	expectEq(byId.Lure.EffectText[3], "2 s faster visitors", "lure level 2")
	expectEq(byId.DeepVault.PerLevelText, "+5% vault exchange rate", "deep vault")
	expectEq(byId.Scholar.EffectText[6], "+50% XP", "scholar max")
end)

test("grid, loot and keeper constants", function()
	local c = Catalog.Build()
	expectEq(c.Grid.Columns, Grid.Columns, "columns")
	expectEq(c.Grid.Rows, Grid.Rows, "rows")
	expectEq(c.Grid.CellSize, Grid.CellSize, "cell size")
	expectEq(c.Grid.EntranceCell.Column, Grid.EntranceCell.Column, "entrance column")
	expectEq(c.Grid.EntranceKey, "3,1", "entrance key")
	expect(deepEqual(c.Loot.BoxTypes, Loot.BoxTypes), "box types")
	expectEq(c.Loot.CraftCost.Common, 5, "common craft cost")
	expectEq(c.Loot.ScrapReturn.Secret, 10, "secret scrap return")
	expectEq(c.MaxKeeperLevel, Balance.Progression.MaxLevel, "max keeper level")
end)
