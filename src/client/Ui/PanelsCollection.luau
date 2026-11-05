-- Collection tab (rooms and visitors, silhouettes for undiscovered) and Keeper
-- tab (level, XP, permanent upgrades). Display only; the server owns every value
-- (texts from the Catalog, per-player numbers from the State snapshot).
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local P = require(script.Parent.PanelsKit)
local ReasonText = require(script.Parent.ReasonText)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local C = {}

-- Left badge: the room image / portrait (in the best owned tier's card frame) when discovered,
-- a "?" silhouette otherwise. `image` = { Room = id, Kind = kind } | { Portrait = id } | nil.
-- Returns the text column.
local function entry(parent: Instance, order: number, known: boolean, image: { [string]: any }?, rarity: string?): Frame
	local card = P.Card(parent, order)
	card:FindFirstChildOfClass("UIListLayout"):Destroy()
	local badge = Kit.Panel(card, { BackgroundColor3 = if known then Theme.BgRaised else Theme.BgDeep, Size = UDim2.fromOffset(64, 64), Rarity = if known then rarity else nil })
	if known and image then
		local img
		if image.Room then
			img = P.RoomImage(badge, image.Room, 50, image.Kind)
		else
			local id = SpriteIds.Portraits[image.Portrait]
			if id and Sprites.Ok(id) then
				img = make("ImageLabel", { BackgroundTransparency = 1, Image = id, Size = UDim2.fromOffset(50, 50), ScaleType = Enum.ScaleType.Fit }, badge)
			else
				img = Kit.Icon(badge, "Visitor", UDim2.fromOffset(40, 40))
			end
		end
		img.AnchorPoint, img.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		if rarity then
			local gem = Kit.Gem(badge, rarity, UDim2.fromOffset(20, 20))
			gem.AnchorPoint, gem.Position, gem.ZIndex = Vector2.new(1, 0), UDim2.new(1, 2, 0, -2), 4
		end
	else
		local q = Kit.Label(badge, "?", 34, Theme.DisabledText, true)
		q.Size = UDim2.fromScale(1, 1)
	end
	local col = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 0, 64), AutomaticSize = Enum.AutomaticSize.Y }, card)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	-- The card grows with the text column; keep the badge row at least 64 tall.
	card.Size = UDim2.new(1, 0, 0, 88)
	return col
end

local function roomHint(def: any): string
	if def.Source == "Shop" then
		local lvl = def.ShopLevel or 1
		return (if lvl > 1 then string.format("Shop (keeper level %d)", lvl) else "Shop") .. ", boxes or blueprints"
	elseif def.Source == "Tutorial" then
		return "Granted by the tutorial"
	end
	return "Starter room"
end

local ARRIVAL = { Tutorial = "Your first practice visitor", Automatic = "Arrives on its own", Invited = "Invite it from the HUD once unlocked" }

function C.BuildCollection(scroll: ScrollingFrame, state: any)
	local catalog = Catalog.Wait()
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
	for _, id in catalog.RoomOrder do
		local def = catalog.Rooms[id]
		if def and def.Kind ~= "Entrance" then
			table.insert(roomIds, id)
		end
	end
	local visitorIds = {}
	for id in catalog.Visitors do
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
		local def = catalog.Rooms[id]
		local known = found[id] == true
		local best
		for i = #catalog.Rarities, 1, -1 do
			if owned[id] and owned[id].Rarity[catalog.Rarities[i].Id] then
				best = catalog.Rarities[i].Id
				break
			end
		end
		local col = entry(scroll, nxt(), known, { Room = id, Kind = def.Kind }, best)
		if known then
			P.Text(col, def.DisplayName, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			P.Text(col, def.Kind .. " | " .. roomHint(def), Theme.TextSize.Caption, Theme.Gold, false, 2)
			P.Text(col, def.Description, Theme.TextSize.Body, Theme.TextMuted, false, 3)
			local o = owned[id]
			local parts = {}
			if o then
				for _, tier in catalog.Rarities do
					local r = tier.Id
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
	local dropChances = state.DropChances or {} -- server-computed, with the loot bonus
	for _, id in visitorIds do
		local def = catalog.Visitors[id]
		local known = found[id] == true
		local col = entry(scroll, nxt(), known, { Portrait = id })
		if known then
			P.Text(col, def.DisplayName, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			P.Text(col, def.Description, Theme.TextSize.Body, Theme.TextMuted, false, 2)
			for i, t in def.Traits do
				P.Text(col, string.format("%s: %s", t.Name, t.Text), Theme.TextSize.Caption, Theme.Warning, false, 2 + i)
			end
			local d = dropChances[id]
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

function C.BuildKeeper(scroll: ScrollingFrame, state: any)
	local catalog = Catalog.Wait()
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end

	local card = P.Card(scroll, nxt())
	local level, xp, need = state.Level or 1, state.Xp or 0, math.max(state.XpToNext or 1, 1)
	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1 }, card)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, head)
	local portrait = SpriteIds.Portraits.Keeper
	if Sprites.Ok(portrait) then
		make("ImageLabel", { BackgroundTransparency = 1, Image = portrait, Size = UDim2.fromOffset(56, 56), ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, head)
	else
		Kit.Icon(head, "Keeper", UDim2.fromOffset(48, 48)).LayoutOrder = 1
	end
	local title = P.Text(head, "Keeper level " .. level, Theme.TextSize.Heading, Theme.TextPrimary, true, 2)
	title.Size, title.AutomaticSize = UDim2.new(1, -66, 1, 0), Enum.AutomaticSize.None
	local bar = Kit.Bar(card, UDim2.new(1, 0, 0, 28))
	bar.Instance.LayoutOrder = 2
	bar.Set(xp / need, string.format("XP %d / %d", xp, need))
	local b = state.Bonuses or {}
	P.Text(card, string.format("Bonuses: coins +%s, loot +%s, XP +%s", P.Pct(b.Coins or 0), P.Pct(b.Loot or 0), P.Pct(b.Xp or 0)), Theme.TextSize.Caption, Theme.TextMuted, false, 3)

	P.Section(scroll, "Permanent upgrades", nxt())
	P.Text(scroll, "Bought with banked coins. They never reset.", Theme.TextSize.Body, Theme.TextMuted, false, nxt())
	local coins = state.Coins or 0
	for _, def in catalog.Permanent do
		local id = def.Id
		local lv = (state.Permanent or {})[id] or 0
		local cost = (state.PermanentNextCost or {})[id] -- nil at max
		local text = string.format("%s\nPer level: %s\nLevel %d / %d (now %s)", def.Name, def.PerLevelText, lv, def.MaxLevel, def.EffectText[lv + 1] or "")
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
