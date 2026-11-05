-- Collection tab (rooms and visitors, silhouettes for undiscovered) and Keeper
-- tab (level, XP, permanent upgrades). Display only; the server owns every value.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Definitions.Balance)
local Rooms = require(Shared.Definitions.Rooms)
local Visitors = require(Shared.Definitions.Visitors)
local Loot = require(Shared.Rules.Loot)
local Progression = require(Shared.Rules.Progression)
local IconIds = require(Shared.UI.IconIds)
local ReasonText = require(Shared.UI.ReasonText)

local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local P = require(script.Parent.PanelsKit)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local C = {}

local KIND_ICON = { Defender = IconIds.Shield, Trap = IconIds.Sword, Treasure = IconIds.Vault, Support = IconIds.Upgrade }

-- Left badge: icon when discovered, "?" silhouette otherwise. Returns the text column.
local function entry(parent: Instance, order: number, known: boolean, icon: string?): Frame
	local card = P.Card(parent, order)
	card:FindFirstChildOfClass("UIListLayout"):Destroy()
	local badge = make("Frame", { BackgroundColor3 = if known then Theme.BgRaised else Theme.BgDeep, Size = UDim2.fromOffset(56, 56) }, card)
	Kit.Corner(badge)
	Kit.Stroke(badge, Theme.Stroke, 2)
	if known and icon then
		make("ImageLabel", { BackgroundTransparency = 1, Image = icon, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40) }, badge)
	else
		local q = Kit.Label(badge, "?", 34, Theme.DisabledText, true)
		q.Size = UDim2.fromScale(1, 1)
	end
	local col = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(68, 0), Size = UDim2.new(1, -68, 0, 56), AutomaticSize = Enum.AutomaticSize.Y }, card)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	-- The card grows with the text column; keep the badge row at least 56 tall.
	card.Size = UDim2.new(1, 0, 0, 76)
	return col
end

local function roomHint(def: any): string
	if def.Source == "Shop" then
		local lvl = Progression.ShopLevel(def.Id)
		return (if lvl > 1 then string.format("Shop (keeper level %d)", lvl) else "Shop") .. ", boxes or blueprints"
	elseif def.Source == "Tutorial" then
		return "Granted by the tutorial"
	end
	return "Starter room"
end

local ARRIVAL = { Tutorial = "Your first practice visitor", Automatic = "Arrives on its own", Invited = "Invite it from the HUD once unlocked" }

function C.BuildCollection(scroll: ScrollingFrame, state: any)
	local pos = P.Reset(scroll)
	local found = state.Discovered or {}
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end

	local owned = {} -- roomId -> { total, byRarity }
	for _, room in state.Rooms or {} do
		local o = owned[room.Id] or { Total = 0, Rarity = {} }
		o.Total += 1
		o.Rarity[room.Rarity or "Common"] = (o.Rarity[room.Rarity or "Common"] or 0) + 1
		owned[room.Id] = o
	end

	local roomIds, total, seen = {}, 0, 0
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		if def and def.Kind ~= "Entrance" then
			table.insert(roomIds, id)
		end
	end
	local visitorIds = {}
	for id in Visitors.All do
		table.insert(visitorIds, id)
	end
	table.sort(visitorIds)
	for _, id in roomIds do
		total += 1
		seen += if found[id] then 1 else 0
	end
	for _, id in visitorIds do
		total += 1
		seen += if found[id] then 1 else 0
	end
	P.Text(scroll, string.format("Discovered %d / %d", seen, total), Theme.TextSize.Body, Theme.TextMuted, false, nxt())

	P.Section(scroll, "Rooms", nxt())
	for _, id in roomIds do
		local def = Rooms.Get(id) :: any
		local known = found[id] == true
		local col = entry(scroll, nxt(), known, KIND_ICON[def.Kind])
		if known then
			P.Text(col, def.DisplayName, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			P.Text(col, def.Kind .. " | " .. roomHint(def), Theme.TextSize.Caption, Theme.Gold, false, 2)
			P.Text(col, def.Description, Theme.TextSize.Body, Theme.TextMuted, false, 3)
			local o = owned[id]
			local parts = {}
			if o then
				for _, r in Balance.Rarities.Order do
					if o.Rarity[r] then
						table.insert(parts, P.Rich(string.format("%s x%d", r, o.Rarity[r]), r))
					end
				end
			end
			P.Text(col, if o then string.format("Owned: %d (%s)", o.Total, table.concat(parts, ", ")) else "Owned: 0", Theme.TextSize.Caption, Theme.TextPrimary, false, 4)
		else
			P.Text(col, "???", Theme.TextSize.Heading, Theme.DisabledText, true, 1)
			P.Text(col, "Find it: " .. roomHint(def), Theme.TextSize.Body, Theme.TextMuted, false, 2)
		end
	end

	P.Section(scroll, "Adventurers", nxt())
	local lootBonus = (state.Bonuses and state.Bonuses.Loot) or 0
	for _, id in visitorIds do
		local def = Visitors.Get(id) :: any
		local known = found[id] == true
		local col = entry(scroll, nxt(), known, IconIds.Visitor)
		if known then
			P.Text(col, def.DisplayName, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			P.Text(col, def.Description, Theme.TextSize.Body, Theme.TextMuted, false, 2)
			for i, trait in def.Traits do
				local t = Visitors.TraitText[trait]
				if t then
					P.Text(col, string.format("%s: %s", t.Name, t.Text), Theme.TextSize.Caption, Theme.Warning, false, 2 + i)
				end
			end
			local d = Loot.DropChances(id, lootBonus)
			local drops = if d and (d.Box > 0 or d.Blueprint > 0)
				then string.format("Drops: %s Box %s, Blueprint %s (with your loot bonus)", d.BoxType, P.Pct(d.Box), P.Pct(d.Blueprint))
				else "Drops: none"
			P.Text(col, drops, Theme.TextSize.Caption, Theme.TextPrimary, false, 9)
		else
			P.Text(col, "???", Theme.TextSize.Heading, Theme.DisabledText, true, 1)
			P.Text(col, "Meet it: " .. (ARRIVAL[def.Arrival] or "Defeat adventurers"), Theme.TextSize.Body, Theme.TextMuted, false, 2)
		end
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

local EFFECT = {
	Coins = function(a) return string.format("+%s coins", P.Pct(a)) end,
	Loot = function(a) return string.format("+%s loot chance", P.Pct(a)) end,
	Xp = function(a) return string.format("+%s XP", P.Pct(a)) end,
	DefenderHealth = function(a) return string.format("+%s defender health", P.Pct(a)) end,
	VisitorInterval = function(a) return string.format("%d s faster visitors", a) end,
	VaultBonusCap = function(a) return string.format("+%s vault bonus cap", P.Pct(a)) end,
}

function C.BuildKeeper(scroll: ScrollingFrame, state: any)
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end

	local card = P.Card(scroll, nxt())
	local level, xp, need = state.Level or 1, state.Xp or 0, math.max(state.XpToNext or 1, 1)
	P.Text(card, "Keeper level " .. level, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
	local bar = Kit.Bar(card, UDim2.new(1, 0, 0, 24))
	bar.Instance.LayoutOrder = 2
	bar.Set(xp / need, string.format("XP %d / %d", xp, need))
	local b = state.Bonuses or {}
	P.Text(card, string.format("Bonuses: coins +%s, loot +%s, XP +%s", P.Pct(b.Coins or 0), P.Pct(b.Loot or 0), P.Pct(b.Xp or 0)), Theme.TextSize.Caption, Theme.TextMuted, false, 3)

	P.Section(scroll, "Permanent upgrades", nxt())
	P.Text(scroll, "Bought with banked coins. They never reset.", Theme.TextSize.Body, Theme.TextMuted, false, nxt())
	local coins = state.Coins or 0
	for _, id in Balance.Permanent.Order do
		local def = Balance.Permanent[id]
		local lv = (state.Permanent or {})[id] or 0
		local cost = Progression.PermanentCost(id, lv)
		local fmt = EFFECT[def.Effect] or tostring
		local text = string.format("%s\nPer level: %s\nLevel %d / %d (now %s)", P.Spaced(id), fmt(def.PerLevel), lv, def.MaxLevel, fmt(def.PerLevel * lv))
		local row = P.Card(scroll, nxt())
		local _, label, buy = P.Row(row, text, { Text = if cost then "Buy " .. cost else "Max", Style = "Primary", Width = 130, OnClick = function()
			local ok, res = Net.Invoke("BuyPermanent", id)
			if not ok then
				Toast.Show(ReasonText.Get(res), "Bad")
			end
		end })
		label.Size = UDim2.new(1, -138, 0, 44)
		buy.SetEnabled(cost ~= nil and coins >= cost, if cost == nil then "Max" elseif coins >= cost then nil else "Need " .. (cost - coins))
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return C
