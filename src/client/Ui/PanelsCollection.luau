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
local Sound = require(script.Parent.Sound)
local Theme = require(script.Parent.Theme)
local Scale = require(script.Parent.Scale)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local C = {}

-- Every entry is ONE whole Panel.Section sprite (706x248) at its own aspect: `w` reference px wide, 2.85 times as wide as tall.
-- The content area is the sprite's Inner rect: innerSize(w) gives its size in px.
local SEC = Kit.Spec("Panel.Section")
local SEC_R = SEC.Size.X / SEC.Size.Y
local function sectionH(w: number): number
	return w / SEC_R
end
local function innerSize(w: number): (number, number)
	local i = SEC.Inner :: Rect
	return w * (i.Max.X - i.Min.X) / SEC.Size.X, sectionH(w) * (i.Max.Y - i.Min.Y) / SEC.Size.Y
end

-- Width (px, reference) the scroll area offers its children.
local function availWidth(scroll: GuiObject): number
	local w = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01) - 20
	if w < 200 then
		w = 900
	end
	return w
end

-- Left badge: the room image / portrait (in the best owned tier's card frame, a whole rarity sprite) when discovered, an empty
-- slot with "?" otherwise. `image` = { Room = id, Kind = kind } | { Portrait = id } | nil. `w` = the entry's width, badgeCap =
-- tallest badge. Returns (text column, entry): the column is a clipped frame beside the badge inside the entry's content area.
local function entry(parent: Instance, order: number, known: boolean, image: { [string]: any }?, rarity: string?, w: number, badgeCap: number?): (Frame, any)
	local card = Kit.Panel(parent, { Sprite = "Small", Size = UDim2.fromOffset(w, sectionH(w)), LayoutOrder = order, Active = true })
	local iw, ih = innerSize(w)
	local bh = math.min(ih, badgeCap or ih)
	local badge
	if known and image and image.Room then
		-- Room rows: a square card frame the height of the row; the owner's icon fills it (the rarity shows as the gem).
		badge = Kit.Panel(card, { Sprite = "Card", Size = UDim2.fromOffset(bh, bh), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	elseif known and rarity and Kit.Spec("Rarity." .. rarity) then
		local rs = Kit.Spec("Rarity." .. rarity)
		badge = Kit.Panel(card, { Rarity = rarity, Size = UDim2.fromOffset(bh * rs.Size.X / rs.Size.Y, bh), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	else
		badge = Kit.Panel(card, { Sprite = if known then "Card" else "Slot", Size = UDim2.fromOffset(bh, bh), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	end
	local bw = badge.Size.X.Offset
	if known and image then
		local img
		if image.Room then
			img = P.RoomImage(card, image.Room, bh, image.Kind)
			img.ZIndex = 3
			local def = Catalog.Room(image.Room)
			badge.Active = true
			Kit.Tip(badge, def and def.DisplayName or image.Room, Theme.Rarity[rarity])
		else
			local id = SpriteIds.Portraits[image.Portrait]
			if id and Sprites.Ok(id) then
				img = make("ImageLabel", { BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Fit }, badge)
			else
				img = Kit.Icon(badge, "Visitor", UDim2.fromOffset(36, 36))
			end
		end
		if image.Room then
			img.AnchorPoint, img.Position, img.Size = Vector2.new(0, 0.5), UDim2.new(0, bh * 0.03, 0.5, 0), UDim2.fromOffset(bh * 0.94, bh * 0.94)
		else
			img.AnchorPoint, img.Position, img.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
		end
		if rarity then
			local gem = Kit.Gem(badge, rarity, UDim2.fromOffset(18, 18))
			gem.AnchorPoint, gem.Position, gem.ZIndex = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), 4
		end
	else
		local q = Kit.Label(badge, "?", 34, Theme.DisabledText, true)
		q.Size = UDim2.fromScale(1, 1)
	end
	local col = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(bw + 12, 0), Size = UDim2.fromOffset(iw - bw - 12, ih), ClipsDescendants = true }, card)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, col)
	return col, card
end

local function roomHint(def: any): string
	if def.Source == "Shop" then
		local lvl = def.ShopLevel or 1
		return (if lvl > 1 then string.format("Shop Lv%d", lvl) else "Shop") .. ", box, blueprint"
	elseif def.Source == "Tutorial" then
		return "Tutorial"
	elseif def.Source == "Loot" then
		return "Chest, blueprint"
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
	-- Collection counter: Hud.PillGold (540x150, one whole sprite) with the trophy.
	local avail = availWidth(scroll)
	make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if Scale.Phone then 2 else 6), LayoutOrder = nxt() }, scroll)
	local counter = Kit.Panel(scroll, { Sprite = "PillGold", Size = if Scale.Phone then UDim2.fromOffset(140, 36) else UDim2.fromOffset(200, 56), LayoutOrder = nxt() })
	local counterRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, counter)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }, counterRow)
	Kit.Icon(counterRow, "Trophy", if Scale.Phone then UDim2.fromOffset(26, 26) else UDim2.fromOffset(38, 38))
	local counterText = Kit.Label(counterRow, string.format("%d/%d", seen, total), if Scale.Phone then 22 else 26, Theme.TextPrimary, true)
	counterText.AutomaticSize, counterText.Size, counterText.TextWrapped = Enum.AutomaticSize.X, UDim2.fromOffset(0, if Scale.Phone then 30 else 40), false
	Kit.Stroke(counterText, Theme.Stroke, 2)

	local phone = Scale.Phone
	-- No heading: the counter row is the header, so two whole rows of rooms show at once (the well is short on both layouts).
	-- Two columns when there is room (always on a phone, so two whole rows show at once), else one; each cell is exactly one
	-- whole sprite (no stretching).
	local roomCols = if avail >= 900 or phone then 2 else 1
	local cellW = math.floor(math.min((avail - 8 * (roomCols - 1)) / roomCols, if phone then 284 else 440))

	local roomGrid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nxt() }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.fromOffset(cellW, sectionH(cellW)), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, roomGrid)
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
		local col = entry(roomGrid, nxt(), known, { Room = id, Kind = def.Kind }, def.Rarity or best, cellW)
		if known then
			local nameLine = P.Text(col, def.DisplayName, if phone then 20 else Theme.TextSize.Heading, Theme.TextPrimary, true, 1)
			nameLine.TextTruncate = Enum.TextTruncate.AtEnd
			local kindLine
			if phone then
				kindLine = nameLine -- no room for the source line: it shows as the name's tip
			else
				kindLine = P.IconLine(col, P.KindIcon[def.Kind] or "Defender", roomHint(def), 2, Theme.Gold)
				kindLine.Size = UDim2.new(1, 0, 0, 26)
			end
			-- Keep special mechanics discoverable on the room art without crowding every card.
			kindLine.Active = true
			Kit.Tip(kindLine, (if phone then roomHint(def) .. "\n" else "") .. (def.Description or "") .. (if def.Ability and def.Ability ~= "" then "\n" .. def.Ability else ""))
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
		local advW = math.floor(math.min(avail, 760))
		local col = entry(scroll, nxt(), known, { Portrait = id }, nil, advW, 150)
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
	make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = nxt() }, scroll)
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

local keeperHooked = setmetatable({}, { __mode = "k" })
local keeperState = setmetatable({}, { __mode = "k" })
function C.BuildKeeper(scroll: ScrollingFrame, state: any)
	keeperState[scroll] = state
	-- The card grid is sized from the well; rebuild once the well has its real size.
	if not keeperHooked[scroll] then
		keeperHooked[scroll] = true
		local pending = false
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if pending then
				return
			end
			pending = true
			task.delay(0.1, function()
				pending = false
				if scroll.Parent and scroll.Visible and keeperState[scroll] then
					C.BuildKeeper(scroll, keeperState[scroll])
				end
			end)
		end)
	end
	local catalog = Catalog.Wait()
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end
	local phone = Scale.Phone
	local avail = availWidth(scroll)
	local sc = math.max(Scale.Value, 0.01)
	local visH = scroll.AbsoluteSize.Y / sc
	if visH < 100 then
		visH = if phone then 190 else 430
	end
	local function spacer(h: number, o: number)
		make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h), LayoutOrder = o }, scroll)
	end
	spacer(4, nxt())

	-- Compact header: ONE Row.Well line with portrait, level and the XP bar (the perk totals live in the HUD chips).
	local level, xp, need = state.Level or 1, state.Xp or 0, math.max(state.XpToNext or 1, 1)
	local ROW = Kit.Spec("Row.Well")
	local hw = math.floor(math.min(avail, if phone then 300 else 320))
	local hh = hw * ROW.Size.Y / ROW.Size.X
	local head = Kit.Panel(scroll, { Sprite = "Row", Size = UDim2.fromOffset(hw, hh), LayoutOrder = nxt() })
	local hc = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, head)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, hc)
	local ihh = hh * 0.6
	local portrait = SpriteIds.Portraits.Keeper
	local pic
	if Sprites.Ok(portrait) then
		pic = make("ImageLabel", { BackgroundTransparency = 1, Image = portrait, Size = UDim2.fromOffset(ihh, ihh), ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, hc)
	else
		pic = Kit.Icon(hc, "Keeper", UDim2.fromOffset(ihh, ihh))
		pic.LayoutOrder = 1
	end
	local title = Kit.Label(hc, "Lv " .. level, Theme.TextSize.Heading, Theme.TextPrimary, true)
	title.Size, title.TextWrapped, title.LayoutOrder, title.TextXAlignment = UDim2.fromOffset(ihh * 1.5, ihh), false, 2, Enum.TextXAlignment.Left
	Kit.Stroke(title, Theme.Stroke, 2)
	Kit.FixedText(title, Theme.TextSize.Heading)
	local bw = hw * 0.9 - ihh * 2.5 - 24
	local bar = Kit.Bar(hc, UDim2.fromOffset(math.max(bw, 90), ihh * 1.1))
	bar.Instance.LayoutOrder = 3
	bar.Set(xp / need, string.format("%d/%d", xp, need))

	if phone then
		-- No room for the level line on a phone well (the HUD already shows level and XP): the cards get the space.
		head.Visible, head.Size, hh = false, UDim2.fromOffset(0, 0), 0
	end
	local coins = state.Coins or 0
	-- Grid of whole Card.Shop cards (294:272), 3 across: icon, effect, level chip, ButtonPrice. Desktop shows 2 rows; on a phone
	-- one full row and a visible part of the next as a scroll hint.
	local CARD = Kit.Spec("Card.Shop")
	local ratio = CARD.Size.X / CARD.Size.Y
	local gap = 10
	local widthCell = math.floor((avail - gap * 2) / 3)
	local freeH = visH - 12 - hh - 6 - 14
	local fromH
	if phone then
		fromH = math.max(freeH - 40, 150) -- leaves ~40 px of the next row visible
	else
		fromH = (freeH - gap) / 2
	end
	-- Desktop: the three columns fill the well's width (big cards; the second row scrolls into view). Phone: sized so one
	-- whole row plus a hint of the next shows.
	local cellW = math.floor(if phone then math.min(widthCell, fromH * ratio) else widthCell)
	cellW = math.max(cellW, 120)
	local cellH = math.floor(cellW / ratio)
	local grid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(cellW * 3 + gap * 2, 0), LayoutOrder = nxt() }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(gap, gap), CellSize = UDim2.fromOffset(cellW, cellH), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
	local ci = CARD.Inner :: Rect
	local innerW = cellW * (ci.Max.X - ci.Min.X) / CARD.Size.X
	local innerH = cellH * (ci.Max.Y - ci.Min.Y) / CARD.Size.Y
	local btnW = math.floor(innerW * 0.94)
	local btnH = math.floor(math.min(innerH * 0.32, btnW / 3))
	for index, def in catalog.Permanent do
		local id = def.Id
		local lv = (state.Permanent or {})[id] or 0
		local cost = (state.PermanentNextCost or {})[id]
		local icon = ({ Coins = "Coin", Loot = "DropChance", Xp = "Xp", DefenderHealth = "Heal", VariantChance = "Crown", VaultRate = "Exchange" })[def.Effect] or "Upgrade"
		local card = Kit.Panel(grid, { Sprite = "CardShop", LayoutOrder = index, Active = true })
		card.ClipsDescendants = false
		local content = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, card)
		make("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, content)
		local isz = math.floor(innerH * (if phone then 0.2 else 0.3))
		local art = Kit.Icon(content, icon, UDim2.fromOffset(isz, isz))
		art.LayoutOrder = 1
		local label = Kit.Label(content, def.PerLevelText, 22, Theme.TextPrimary, true)
		-- The upgrade name: one fixed size on every card, two lines allowed (the row is sized for two).
		label.Size, label.LayoutOrder, label.TextWrapped = UDim2.fromOffset(innerW, 50), 2, true
		Kit.FixedText(label, 20)
		Kit.Stroke(label, Theme.Stroke, 1.5)
		Kit.Tip(content, def.Name .. ": " .. def.PerLevelText)
		local chip = Kit.Tag(content, string.format("%d/%d", lv, def.MaxLevel), if lv >= def.MaxLevel then "Chip.Gold" else "Chip.Purple", if lv >= def.MaxLevel then Theme.TextOnGold else Theme.TextPrimary, math.max(26, math.floor(innerH * 0.17)))
		chip.LayoutOrder = 3
		local buy = Kit.Button(content, { Text = if cost then tostring(cost) else "Max", Icon = if cost then "Coin" else nil, IconLayout = "Row", Style = "Primary", Price = true, TextSize = 26, Size = UDim2.fromOffset(btnW, btnH), LayoutOrder = 4, OnClick = function()
			local ok, res = Net.Invoke("BuyPermanent", id)
			if not ok then Toast.Show(ReasonText.Get(res), "Bad") else Sound.Play("UpgradePurchase") end
		end })
		buy.SetEnabled(cost ~= nil and coins >= cost)
	end
	spacer(24, nxt())
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return C
