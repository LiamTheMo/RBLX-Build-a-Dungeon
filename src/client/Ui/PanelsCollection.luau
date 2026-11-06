-- Collection tab (rooms and visitors, silhouettes for undiscovered) and Keeper
-- tab (level, XP, permanent upgrades). Display only; the server owns every value
-- (texts from the Catalog, per-player numbers from the State snapshot).
local Badges = require(script.Parent.Badges)
local Catalog = require(script.Parent.Catalog)
local DropCard = require(script.Parent.DropCard)
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
	local badge = Kit.Panel(card, { BackgroundColor3 = if known then Theme.BgRaised else Theme.BgDeep, Size = UDim2.fromOffset(64, 64), Rarity = if known then rarity else nil, Pad = 0 })
	if known and image then
		local img
		if image.Room then
			img = P.RoomImage(badge, image.Room, 44, image.Kind)
			local def = Catalog.Room(image.Room)
			badge.Active = true
			Kit.Tip(badge, def and def.DisplayName or image.Room, Theme.Rarity[rarity])
		else
			local id = SpriteIds.Portraits[image.Portrait]
			if id and Sprites.Ok(id) then
				img = make("ImageLabel", { BackgroundTransparency = 1, Image = id, Size = UDim2.fromOffset(44, 44), ScaleType = Enum.ScaleType.Fit }, badge)
			else
				img = Kit.Icon(badge, "Visitor", UDim2.fromOffset(36, 36))
			end
		end
		img.AnchorPoint, img.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		if rarity then
			local gem = Kit.Gem(badge, rarity, UDim2.fromOffset(18, 18))
			gem.AnchorPoint, gem.Position, gem.ZIndex = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), 4
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
		return (if lvl > 1 then string.format("Shop Lv%d", lvl) else "Shop") .. ", box, blueprint"
	elseif def.Source == "Tutorial" then
		return "Tutorial"
	end
	return "Starter"
end

local ARRIVAL = { Tutorial = "First visitor", Automatic = "Random arrival", Invited = "Special arrival" }

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
		local o = owned[room.Id] or { Total = 0, Rarity = {}, Mods = {} }
		o.Total += 1
		if room.Modifier then
			o.Mods[room.Modifier] = true
		end
		local rarity = Catalog.RoomRarity(room.Id, room)
		o.Rarity[rarity] = (o.Rarity[rarity] or 0) + 1
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
	P.IconLine(scroll, "Trophy", string.format("%d/%d", seen, total), nxt(), Theme.Gold)

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
		local col = entry(scroll, nxt(), known, { Room = id, Kind = def.Kind }, def.Rarity or best)
		if known then
			P.Text(col, def.DisplayName, Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			local kindLine = P.IconLine(col, P.KindIcon[def.Kind] or "Defender", roomHint(def), 2, Theme.Gold)
			kindLine.Size = UDim2.new(1, 0, 0, 26)
			-- Keep special mechanics discoverable on the room art without crowding every card.
			kindLine.Active = true
			Kit.Tip(kindLine, (def.Description or "") .. (if def.Ability and def.Ability ~= "" then "\n" .. def.Ability else ""))
			local o = owned[id]
			local flow = P.ChipFlow(col, 5)
			P.RoomStats(flow, def)
			for mod in if o then o.Mods else {} do
				local order = 20
				P.Chip(flow, order, function(p)
					return Badges.Modifier(p, mod, 24) :: any
				end, mod, Badges.ModifierColor[mod] or Theme.TextPrimary, mod)
			end
			for i, tier in catalog.Rarities do
				local r = tier.Id
				if o and o.Rarity[r] then
					P.Chip(flow, i, function(p)
						return Kit.Gem(p, r, UDim2.fromOffset(22, 22))
					end, "x" .. o.Rarity[r], P.RarityColor[r] or Theme.TextPrimary, r)
				end
			end
		else
			P.Text(col, "???", Theme.TextSize.Heading, Theme.DisabledText, true, 1)
			local lockLine = P.IconLine(col, "Lock", roomHint(def), 2)
			lockLine.Size = UDim2.new(1, 0, 0, 28)
		end
	end

	P.Section(scroll, "Adventurers", nxt())
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
			DropCard.Fill(col, id, state, false, 9) -- coin range, XP, drops and variant chances (State.DropTables)
		else
			P.Text(col, "???", Theme.TextSize.Heading, Theme.DisabledText, true, 1)
			local lockLine = P.IconLine(col, "Lock", ARRIVAL[def.Arrival] or "Defeat adventurers", 2)
			lockLine.Size = UDim2.new(1, 0, 0, 28)
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
	local title = P.Text(head, "Lv " .. level, Theme.TextSize.Title, Theme.TextPrimary, true, 2)
	title.Size, title.AutomaticSize = UDim2.new(1, -66, 1, 0), Enum.AutomaticSize.None
	local bar = Kit.Bar(card, UDim2.new(1, 0, 0, 28))
	bar.Instance.LayoutOrder = 2
	bar.Set(xp / need, string.format("%d/%d", xp, need))
	local b = state.Bonuses or {}
	local flow = P.ChipFlow(card, 3)
	for i, e in { { "Coin", "Coins", "Coins" }, { "Loot", "Loot", "Loot chance" }, { "Xp", "Xp", "XP" } } do
		P.Chip(flow, i, function(p)
			return Kit.Icon(p, e[1], UDim2.fromOffset(24, 24))
		end, "+" .. P.Pct(b[e[2]] or 0), Theme.TextPrimary, e[3])
	end

	P.Section(scroll, "Permanent upgrades", nxt())
	local coins = state.Coins or 0
	local cols = P.Columns(scroll)
	local grid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nxt() }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / cols, -8 * (cols - 1) / cols, 0, 150), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for order, def in catalog.Permanent do
		local id = def.Id
		local lv = (state.Permanent or {})[id] or 0
		local cost = (state.PermanentNextCost or {})[id]
		local icon = ({ Coins = "Coin", Loot = "DropChance", Xp = "Xp", DefenderHealth = "Heal", VisitorInterval = "Speed", VaultRate = "Exchange" })[def.Effect] or "Upgrade"
		local card = Kit.Panel(grid, { LayoutOrder = order, Pad = Vector2.new(4, 2) })
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, card)
		Kit.Icon(card, icon, UDim2.fromOffset(34, 34)).LayoutOrder = 1
		local label = Kit.Label(card, string.format("%s  •  %d/%d", def.PerLevelText, lv, def.MaxLevel), 16, Theme.TextPrimary, true)
		label.Size, label.LayoutOrder, label.TextScaled, label.Active = UDim2.new(1, 0, 0, 36), 2, true, true
		make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 16 }, label)
		Kit.Tip(label, def.Name .. ": " .. def.PerLevelText)
		local buy = Kit.Button(card, { Text = if cost then tostring(cost) else "Max", Icon = if cost then "CoinStack" else nil, IconLayout = "Row", Style = "Primary", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, OnClick = function()
			local ok, res = Net.Invoke("BuyPermanent", id)
			if not ok then Toast.Show(ReasonText.Get(res), "Bad") end
		end })
		buy.SetEnabled(cost ~= nil and coins >= cost)
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return C
