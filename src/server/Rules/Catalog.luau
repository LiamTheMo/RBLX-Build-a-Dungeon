--!strict
-- The display catalog the client fetches once with GetCatalog (docs/ARCHITECTURE.md,
-- "Catalog"). Pure: built from the server definitions, no Instances. It holds only
-- what the UI shows (names, descriptions, prices, gates, labels); simulation
-- numbers (health, damage, rewards, theft, drop and box weights) stay server-side.
-- Everything per player (odds, upgrade costs, drop chances) is in the State snapshot.

local Definitions = script.Parent.Parent.Definitions
local Balance = require(Definitions.Balance)
local Grid = require(Definitions.Grid)
local Rooms = require(Definitions.Rooms)
local Visitors = require(Definitions.Visitors)
local Loot = require(script.Parent.Loot)
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
	VaultBonusCap = function(a)
		return string.format("+%s vault bonus cap", pct(a))
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

local function room(def: any): any
	local stats = Balance.Rooms[def.Id]
	local cost = stats and stats.Cost
	return {
		Id = def.Id,
		DisplayName = def.DisplayName,
		Kind = def.Kind,
		Description = def.Description,
		Source = def.Source,
		Cost = if type(cost) == "number" then cost else nil, -- shop price (Buy)
		ShopLevel = Progression.ShopLevel(def.Id), -- keeper level to buy (1 = no gate)
		Upgradable = def.Upgradable,
		MaxPlaced = def.MaxPlaced,
		EndsRoute = def.EndsRoute,
		Placeable = def.Placeable,
		Craftable = Loot.Craftable(def.Id), -- blueprints craft it; scrapping returns them
		-- Trap rooms with a fixed strike cycle: the warning flash timing (cosmetic).
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
	return {
		Id = def.Id,
		DisplayName = def.DisplayName,
		Description = def.Description,
		Arrival = def.Arrival,
		Traits = traits,
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
	for i, r in Balance.Rarities do
		rarities[i] = {
			Id = r.Id,
			StatMultiplier = r.StatMultiplier,
			MaxLevel = r.MaxLevel,
			PerkCount = r.PerkCount,
			PerkSize = r.PerkSize,
		}
	end
	local permanents = {}
	for i, id in Balance.Permanent.Order do
		permanents[i] = permanent(id)
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
			CraftCost = Balance.Loot.CraftCost,
			ScrapReturn = Balance.Loot.ScrapReturn,
		},
		MaxKeeperLevel = Balance.Progression.MaxLevel,
	})
end

return table.freeze(Catalog)
