--!strict
-- The display catalog the client fetches once with GetCatalog (docs/ARCHITECTURE.md,
-- "Catalog"). Pure: built from the server definitions, no Instances. It holds only
-- what the UI shows (names, descriptions, prices, gates, labels, base coin
-- ranges, XP, theft shares and base drop tables, threat tiers, variants,
-- events, each room's fixed rarity, perks and short ability line); simulation
-- rules stay server-side; base combat numbers are sent only for display.
-- Everything per player (odds, upgrade costs, effective drop tables) is in the
-- State snapshot.

local Definitions = script.Parent.Parent.Definitions
local Balance = require(Definitions.Balance)
local Grid = require(Definitions.Grid)
local Rooms = require(Definitions.Rooms)
local Visitors = require(Definitions.Visitors)
local Economy = require(script.Parent.Economy)
local Loot = require(script.Parent.Loot)
local Threat = require(script.Parent.Threat)
local Progression = require(script.Parent.Progression)
local Route = require(script.Parent.Route)

local Catalog = {}

-- Same rounding as the client's percentage labels (0.02% keeps two decimals).
local function pct(f: number): string
	local step = if f < 0.01 then 100 else 10
	local v = math.floor(f * 100 * step + 0.5) / step
	return (if v % 1 == 0 then tostring(math.floor(v)) else tostring(v)) .. "%"
end

-- Player text for a permanent upgrade's total effect, by Balance.Permanent Effect.
local EFFECT: { [string]: (number) -> string } = {
	Coins = function(a)
		return string.format("+%s coins", pct(a))
	end,
	Loot = function(a)
		return string.format("+%s loot chance", pct(a))
	end,
	Xp = function(a)
		return string.format("+%s XP", pct(a))
	end,
	DefenderHealth = function(a)
		return string.format("+%s defender health", pct(a))
	end,
	VisitorInterval = function(a)
		return string.format("%d s faster visitors", a)
	end,
	VaultRate = function(a)
		return string.format("+%s vault exchange rate", pct(a))
	end,
}

local function spaced(id: string): string
	return (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

local function deepFreeze(t: any): any
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

local function num(n: number): string
	local v = math.floor(n * 100 + 0.5) / 100
	return if v % 1 == 0 then tostring(math.floor(v)) else tostring(v)
end

-- Treasure ability line from Balance (so it never drifts from the numbers).
local function treasureAbility(stats: any): string
	local text = "Vault exchange x" .. num(stats.Exchange or 1)
	if stats.VariantBonus then
		text ..= string.format(", +%s rare variants", pct(stats.VariantBonus))
	end
	if stats.TheftScale then
		text ..= string.format(", thieves take %s", pct(stats.TheftScale))
	end
	return text
end

local function room(def: any): any
	local stats = Balance.Rooms[def.Id]
	local cost = stats and stats.Cost
	local perks = {}
	for i, perk in def.Perks do
		perks[i] = { Kind = perk.Kind, Amount = perk.Amount }
	end
	local tier = Balance.RarityById[def.Rarity]
	return {
		Id = def.Id,
		DisplayName = def.DisplayName,
		ArtSource = def.ArtSource,
		Kind = def.Kind,
		Description = def.Description,
		Source = def.Source, -- "Shop" = sold for coins; "Loot" = boxes and blueprints only
		Rarity = def.Rarity, -- fixed by the definition
		Tier = Loot.RarityRank(def.Rarity), -- index in Rarities
		MaxLevel = tier and tier.MaxLevel,
		Perks = perks, -- {{Kind = "Coins"|"Loot"|"Xp", Amount}}
		Ability = if def.Kind == "Treasure" and stats then treasureAbility(stats) else def.Ability,
		Exchange = stats and stats.Exchange, -- treasure rooms: vault exchange multiplier
		BaseHealth = stats and (stats.DefenderHealth or (stats.Units and stats.Units[1].Health)),
		BaseDamage = stats and (stats.AttackDamage or stats.Damage or stats.ZoneDamage or (stats.Units and stats.Units[1].Damage)),
		DamagePerSecond = stats and stats.ZoneDamage ~= nil,
		UnitCount = stats and stats.Units and #stats.Units,
		SupportDamage = stats and (stats.DamageBonus or stats.TrapDamageBonus),
		SupportHealth = stats and stats.HealthBonus,
		CraftCost = Loot.CraftCost(def.Id), -- blueprints to craft one (nil if not craftable)
		ScrapReturn = Loot.ScrapReturn(def.Id), -- blueprints back for scrapping one
		Cost = if type(cost) == "number" then cost else nil, -- shop price (Buy)
		ShopLevel = Progression.ShopLevel(def.Id), -- keeper level to buy (1 = no gate)
		Upgradable = def.Upgradable,
		MaxPlaced = def.MaxPlaced,
		EndsRoute = def.EndsRoute,
		Placeable = def.Placeable,
		Craftable = Loot.Craftable(def.Id), -- blueprints craft it; scrapping returns them
		-- Strike traps (Spike Hall, Arrow Gallery, Flame Vent): the warning flash timing (cosmetic).
		TrapCycle = stats and stats.Cycle,
		TrapTelegraph = stats and stats.Telegraph,
	}
end

local function visitor(def: any): any
	local traits = {}
	for _, name in def.Traits do
		local text = Visitors.TraitText[name]
		if text then
			table.insert(traits, { Id = name, Name = text.Name, Text = text.Text })
		end
	end
	local min, max = Economy.RewardRange(def.Id)
	return {
		Id = def.Id,
		DisplayName = def.DisplayName,
		Description = def.Description,
		Arrival = def.Arrival,
		Traits = traits,
		Reward = { Min = min, Max = max }, -- base coins, rolled once per encounter
		Xp = Progression.XpFor(def.Id, 0),
		Theft = Balance.Visitors[def.Id].TheftFraction, -- share of vaulted coins stolen
		-- Base drop table (threat 1, no bonuses, every blueprint room ungated; blueprint
		-- entries carry RoomId and Rarity).
		Drops = Loot.DropTable(def.Id, 0, 1, nil),
	}
end

local function permanent(id: string): any
	local def = Balance.Permanent[id]
	local fmt = EFFECT[def.Effect] or tostring
	local effects = {}
	for level = 0, def.MaxLevel do
		effects[level + 1] = fmt(def.PerLevel * level)
	end
	return {
		Id = id,
		Name = spaced(id),
		MaxLevel = def.MaxLevel,
		PerLevelText = fmt(def.PerLevel),
		Effect = def.Effect,
		PerLevelValue = if def.Effect == "VisitorInterval" then tostring(def.PerLevel) .. "s" else "+" .. pct(def.PerLevel),
		EffectText = effects, -- index level + 1: the total effect at that level
	}
end

-- Builds a new, deeply frozen catalog. See docs/ARCHITECTURE.md for the shape.
function Catalog.Build(): any
	local rooms = {}
	for id, def in Rooms.All do
		rooms[id] = room(def)
	end
	local visitors = {}
	for id, def in Visitors.All do
		visitors[id] = visitor(def)
	end
	local rarities = {}
	local craftCost, scrapReturn = {}, {}
	for i, r in Balance.Rarities do
		local ids = {}
		for _, id in Rooms.Order do
			local def = Rooms.Get(id) :: any
			if def.Placeable and def.Rarity == r.Id then
				table.insert(ids, id)
			end
		end
		rarities[i] = {
			Id = r.Id,
			MaxLevel = r.MaxLevel,
			CraftCost = r.CraftCost,
			ScrapReturn = r.ScrapReturn,
			Rooms = ids, -- placeable rooms of this tier, in RoomOrder
		}
		craftCost[r.Id] = r.CraftCost
		scrapReturn[r.Id] = r.ScrapReturn
	end
	local permanents = {}
	for i, id in Balance.Permanent.Order do
		permanents[i] = permanent(id)
	end
	local variants = {}
	for i, v in Balance.Variants do
		variants[i] = {
			Id = v.Id,
			Chance = v.Chance,
			Health = v.Health,
			Coins = v.Coins,
			Drops = v.Drops,
			GuaranteedBox = v.GuaranteedBox,
		}
	end
	local tiers = {}
	for tier, level in Balance.Threat.UnlockLevels do
		local scale = Threat.Scale(tier)
		tiers[tier] = {
			Tier = tier,
			UnlockLevel = level,
			Health = scale.Health,
			Damage = scale.Damage,
			Coins = scale.Coins,
			Xp = scale.Xp,
			Drops = scale.Drops,
			Roster = Threat.Roster(tier),
		}
	end
	local events = {}
	for i, e in Balance.Events.List do
		events[i] = { Id = e.Id, Name = e.Name, Text = e.Text }
	end
	local modifiers = {}
	for i, m in Balance.Events.Modifiers do
		modifiers[i] = { Id = m.Id, Name = m.Id, Effect = m.Effect, Amount = m.Amount, Text = m.Text }
	end
	local entrance = Grid.EntranceCell
	return deepFreeze({
		Rooms = rooms,
		RoomOrder = table.clone(Rooms.Order),
		Visitors = visitors,
		Rarities = rarities, -- ordered, lowest first; index is rank
		Permanent = permanents, -- in shop order
		Grid = {
			Columns = Grid.Columns,
			Rows = Grid.Rows,
			CellSize = Grid.CellSize,
			EntranceCell = { Column = entrance.Column, Row = entrance.Row },
			EntranceKey = Route.Key(entrance.Column, entrance.Row),
		},
		Loot = {
			BoxTypes = table.clone(Loot.BoxTypes),
			SaleCoins = table.clone(Balance.Loot.SaleCoins),
			CraftCost = craftCost, -- [tier] = blueprints to craft a room of that tier
			ScrapReturn = scrapReturn, -- [tier] = blueprints back for scrapping one
		},
		MaxKeeperLevel = Balance.Progression.MaxLevel,
		Variants = variants, -- rarest first; base chances
		Threat = tiers, -- index = tier
		Events = events,
		Modifiers = modifiers,
		Vault = { MinInterval = Balance.Timing.MinVisitorInterval, BaseInterval = Balance.Timing.VisitorInterval },
	})
end

return table.freeze(Catalog)
