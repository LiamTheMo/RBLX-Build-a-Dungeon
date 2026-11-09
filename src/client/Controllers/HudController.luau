-- HUD, encounter panel, shop, settings, toasts and the blocking load-failure
-- message. Presents server state only (State snapshot, Catalog, plot
-- attributes); every button is a request. Icons carry the meaning wherever one is
-- clear (coins, vault, clock, level, role); names show on hover / long-press.
local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Badges = require(Ui.Badges)
local Catalog = require(Ui.Catalog)
local DropCard = require(Ui.DropCard)
local EventBanner = require(Ui.EventBanner)
local Kit = require(Ui.Kit)
local Modal = require(Ui.Modal)
local Net = require(Ui.Net)
local Plots = require(Ui.Plots)
local ReasonText = require(Ui.ReasonText)
local Scale = require(Ui.Scale)
local Sprites = require(Ui.Sprites)
local SpriteIds = require(Ui.SpriteIds)
local IconIds = require(Ui.IconIds)
local P = require(Ui.PanelsKit)
local PanelsVault = require(Ui.PanelsVault)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)

local make = Kit.Make
local V6: any = Sprites.Ids6

local Hud = {}

local ROLE_ICON = { Defender = "Defender", Trap = "Trap", Treasure = "CoinStack", Support = "Support" }
local X = Enum.AutomaticSize.X

local function request(name: string, ...: any): boolean
	local ok, reason = Net.Invoke(name, ...)
	if not ok then
		Toast.Show(ReasonText.Get(reason), "Bad")
		Sound.Play("Error")
	end
	return ok
end

-- Horizontal list (children ordered by LayoutOrder, centred vertically).
local function hlist(parent: Instance, padding: number?, props: { [string]: any }?)
	local l = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 8),
	}, parent)
	for k, v in props or {} do
		l[k] = v
	end
	return l
end

local function pad(parent: Instance, h: number, v: number?)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		PaddingTop = UDim.new(0, v or 0),
		PaddingBottom = UDim.new(0, v or 0),
	}, parent)
end

-- Tap / click on a GuiObject without a child button (auto-sized chips must not hold full-size children).
local function onTap(obj: GuiObject, fn: () -> ())
	obj.Active = true
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Sound.Play("Click")
			fn()
		end
	end)
end

local function pct(x: number?): number
	return math.floor((x or 0) * 100 + 0.5)
end

-- Positions `obj` in a horizontal slot of a content row: x0..x1 are fractions of the row width, centred vertically. Pills hold
-- whole-sprite content, so every part sits in a scale slot (nothing auto-sizes inside an aspect-locked sprite).
local function slot(obj: GuiObject, x0: number, x1: number)
	obj.AnchorPoint = Vector2.new(0, 0.5)
	obj.Position = UDim2.fromScale(x0, 0.5)
	obj.Size = UDim2.fromScale(x1 - x0, 1)
end

-- Icon + a number that tweens (instant when reduced) and pops on gain. Name on hover. The cell fills its slot: the icon
-- takes the left 30%, the number (TextScaled, capped by `Max`) the rest.
local currencyFit: (() -> ())? = nil -- set by the HUD: re-fits the currency pill after a number changes
-- 12,345 -> "12.3K", 1,200,000 -> "1.2M": a big number never outgrows the pill.
local function compactNumber(n: number): string
	if n >= 1000000 then
		return (string.format("%.1fM", n / 1000000):gsub("%.0M", "M"))
	elseif n >= 10000 then
		return (string.format("%.1fK", n / 1000):gsub("%.0K", "K"))
	end
	return tostring(n)
end

local function cell(parent: Instance, iconName: string, tip: string)
	-- Icon, then the number, side by side in a list (the cell grows with its number; nothing is placed by fractions).
	local root = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Active = true }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, root)
	local icon = Kit.Icon(root, iconName, UDim2.fromOffset(32, 32))
	icon.LayoutOrder = 1
	local number = Kit.Label(root, "0", Theme.TextSize.Number - 4, Theme.TextPrimary, true)
	number.AutomaticSize, number.Size, number.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromScale(0, 1), 2
	number.TextWrapped, number.TextXAlignment = false, Enum.TextXAlignment.Left
	Kit.Tip(root, tip)
	local popScale = make("UIScale", {}, number)
	local value = make("NumberValue", {}, number)
	value.Changed:Connect(function()
		number.Text = compactNumber(math.floor(value.Value + 0.5))
		if currencyFit then currencyFit() end
	end)
	local last = 0
	local function set(n: number)
		if n == last then
			return
		end
		if n > last and not Settings.Reduced() then
			popScale.Scale = 1.1
			Settings.Tween(popScale, TweenInfo.new(0.25), { Scale = 1 })
		end
		last = n
		Settings.Tween(value, TweenInfo.new(0.25), { Value = n })
	end
	-- iconPx: icon side in px; the number takes the rest (set from the pill's Inner height in layout()).
	local function setIcon(px: number)
		icon.Size = UDim2.fromOffset(px, px)
	end
	return { Root = root, Icon = icon, Number = number, Set = set, SetIcon = setIcon }
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function modal(gui: ScreenGui, title: string, titleIcon: string, desktop: Vector2, phone: Vector2, wideFrac: number?, compact: boolean?)
	return Modal.New(gui, title, titleIcon, desktop, phone, wideFrac, compact)
end

local modals = Modal.All

local function closeModals()
	for _, m in modals do
		m.Close()
	end
	Bus.OpenPanel:Fire("Close")
end

local function buildShop(gui: ScreenGui)
	local shop = modal(gui, "Shop", "Shop", Vector2.new(1100, 0), Vector2.new(900, 0), 0.66)
	-- The scroll area is the art's Inner rect (the dark well of Panel.Modal).
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
	}, shop.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 28) }, scroll)
	local grid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 1 }, scroll)
	-- Cards are whole Card.Shop images (294:272): the cell size is set from the well width in Refresh, height from the aspect.
	local gl = make("UIGridLayout", { CellPadding = UDim2.fromOffset(10, 14), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
	local upHead = P.IconLine(scroll, "Upgrade", "", 2, Theme.Gold)
	upHead.Size = UDim2.new(1, 0, 0, 34)
	local upList = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 3 }, scroll)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, upList)
	upHead:FindFirstChildOfClass("TextLabel").Text = "Upgrades"
	upHead:FindFirstChildOfClass("TextLabel").TextColor3 = Theme.Gold
	upHead.Visible = false

	local shopSpec = V6.Card.Shop
	local cards = {}
	local order = 0
	for _, id in Catalog.Current.RoomOrder do
		local def = Catalog.Room(id)
		local cost = def and def.Cost
		if def and def.Source == "Shop" and cost then
			order += 1
			-- Card: one whole Card.Shop image; a category tag on its top edge, art, name and a yellow price button inside.
			local card = Kit.Panel(grid, { LayoutOrder = order, Sprite = "CardShop" })
			card.ClipsDescendants = false
			local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, card)
			make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, content)
			local tag = Kit.Tag(card, def.Kind or "Room", "Tag.Label", Theme.TextOnGold, 28)
			-- The category tag sits at the top-left and the owned count at the top-right, so the two never overlap.
			tag.AnchorPoint, tag.Position, tag.ZIndex, tag.Active = Vector2.new(0, 0.5), UDim2.new(0, 8, 0, 8), 5, true
			Kit.PillLabel(tag).ZIndex = 6
			Kit.Tip(tag, def.Kind .. (if def.Ability and def.Ability ~= "" then "\n" .. def.Ability else ""), nil, def.Rarity)
			make("UIPadding", { PaddingTop = UDim.new(0, if Scale.Phone then 26 else 2) }, content) -- the art runs up between the category tag and the count chip
			local art = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 0 }, content)
			local artImg = P.RoomImage(art, id, 64, def.Kind)
			artImg.AnchorPoint, artImg.Position, artImg.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
			make("UIAspectRatioConstraint", { AspectRatio = 1 }, artImg)
			local name = Kit.Label(content, def.DisplayName, 18, Theme.Rarity[def.Rarity] or Theme.TextPrimary, true)
			-- One fixed name size for every card; a long name wraps to a second line (the row is sized for two).
			name.AutomaticSize, name.Size, name.LayoutOrder, name.TextTruncate = Enum.AutomaticSize.Y, UDim2.new(1, -8, 0, 0), 2, Enum.TextTruncate.None
			name.TextWrapped = true
			Kit.Stroke(name, Theme.Stroke, 2)
			Kit.FixedText(name, Theme.TextSize.Label)
			-- How many you own: Badge.Count at the top-right corner of the card.
			local owned = Kit.Count(card, "x0", true, 30)
			owned.AnchorPoint, owned.Position, owned.ZIndex, owned.Visible = Vector2.new(1, 0.5), UDim2.new(1, -4, 0, 12), 6, false
			Kit.PillLabel(owned).ZIndex = 7
			local entry = { Id = id, Cost = cost, Owned = owned, Name = name, Confirm = 0, Level = def.ShopLevel, Art = art, Tag = tag }
			entry.Button = Kit.Button(content, {
				Text = tostring(cost),
				Style = "Primary",
				Icon = "Coin",
				IconLayout = "Row",
				Variant = "Price",
				TextSize = 22,
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 56),
				OnClick = function()
					if entry.Confirm == 0 then
						entry.Confirm = 1
						shop.Refresh()
						task.delay(3, function()
							if entry.Confirm == 1 then
								entry.Confirm = 0
								shop.Refresh()
							end
						end)
					else
						entry.Confirm = 0
						if request("Buy", id) then
							Sound.Play("Purchase")
						end
						shop.Refresh()
					end
				end,
			})
			table.insert(cards, entry)
		end
	end

	local upRows: { [string]: any } = {}
	local upSignature = ""
	local rowSpec = V6.Row.Well

	-- Width of the scroll well in reference px (a safe default until the first layout).
	local function wellWidth(): number
		local w = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01) - 24
		return if w > 200 then w else 700
	end

	function shop.Refresh()
		local phone = Scale.Phone
		-- Card grid: 4 columns on a wide well, 3 on a narrow one; the height is the art's aspect.
		local avail = wellWidth()
		local cols = if phone then 2 else 3 -- fewer, bigger cards on desktop: the room art is the point of the card
		local cellW = math.floor((avail - 10 * (cols - 1)) / cols)
		local cellH = math.floor(cellW * shopSpec.Size.Y / shopSpec.Size.X)
		-- A phone well is short: size the cards to the visible height so one whole card (price button included) is shown.
		local visH = scroll.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		if phone and visH > 80 and cellH > visH - 64 then
			cellH = math.floor(visH - 64) -- one whole card plus ~50 px of the next row as a scroll hint
			cellW = math.floor(cellH * shopSpec.Size.X / shopSpec.Size.Y)
			-- Smaller cards leave room for a third column (fewer scroll rows).
			cellW = math.min(cellW, math.floor((avail - 20) / 3) - 6)
			cellH = math.floor(cellW * shopSpec.Size.Y / shopSpec.Size.X)
		end
		-- Desktop: cards are as wide as the well allows (3 across); further rows scroll, the last one fully into view.
		gl.CellSize = UDim2.fromOffset(cellW, cellH)
		local innerH = cellH * (shopSpec.Inner.Max.Y - shopSpec.Inner.Min.Y) / shopSpec.Size.Y
		local btnH = math.max(math.floor(innerH * 0.24), if phone then 46 else 40)
		-- Name row: one line unless a name needs two at the fixed size (one count for the layout).
		local nameLines = 1
		for _, e in cards do
			if Kit.Measure(e.Name.Text, Theme.TextSize.Label, Theme.HeadingFont, 2000).X > cellW * 0.86 then
				nameLines = 2
			end
		end
		local nameH = math.ceil(Theme.TextSize.Label * 1.2 * nameLines)
		local k = cellW / shopSpec.Size.X
		for _, e in cards do
			-- Chips scale with the card (a narrow phone card keeps the art visible).
			Kit.SetPillHeight(e.Tag, math.clamp(math.floor(36 * k + 0.5), 18, 30))
			Kit.SetPillHeight(e.Owned, math.clamp(math.floor(40 * k + 0.5), 18, 32))
			e.Name.AutomaticSize, e.Name.Size = Enum.AutomaticSize.None, UDim2.new(1, -8, 0, nameH)
			e.Art.Size = UDim2.new(1, 0, 0, math.max(40, math.floor(innerH - nameH - btnH + 6 - (if phone then 24 else 0))))
			e.Button.Instance.Size = UDim2.new(1, 0, 0, btnH)
			e.Button.SetTextSize(if phone then 18 else 22)
		end
		-- Upgrade rows: Row.Well whole, as wide as the well allows (<= 600), height from the aspect.
		local rowW = math.min(600, avail)
		for _, row in upRows do
			row.Frame.Size = UDim2.fromOffset(rowW, math.floor(rowW * rowSpec.Size.Y / rowSpec.Size.X))
		end
		local s = State.Current
		if not s then
			return
		end
		local coins = s.Coins or 0
		local level = s.Level or 1
		for _, e in cards do
			local count = 0
			for _, room in s.Rooms or {} do
				if room.Id == e.Id then
					count += 1
				end
			end
			Kit.SetText(e.Owned, "x" .. count)
			e.Owned.Visible = count > 0
			local locked = level < e.Level
			e.Name.TextColor3 = if locked then Theme.TextMuted else (Theme.Rarity[Catalog.Room(e.Id).Rarity] or Theme.TextPrimary)
			e.Button.SetText(if e.Confirm == 1 then "Confirm?" else tostring(e.Cost))
			if locked then
				e.Confirm = 0
				e.Button.SetEnabled(false, "Lv " .. e.Level, true)
			else
				e.Button.SetEnabled(coins >= e.Cost, tostring(e.Cost))
			end
		end

		-- Upgradable: every placed room (cost and cap depend on its rarity).
		local rows = {}
		for cellKey, instanceId in s.Layout or {} do
			local room = s.Rooms and s.Rooms[instanceId]
			local def = room and Catalog.Room(room.Id)
			if def and def.Upgradable then
				table.insert(rows, { Cell = cellKey, Id = instanceId, Def = def, Level = room.Level or 1, Rarity = room.Rarity or "Common", Perks = room.Perks, NextCost = room.NextUpgradeCost })
			end
		end
		table.sort(rows, function(a, b)
			return a.Id < b.Id
		end)
		local sig = {}
		for _, r in rows do
			table.insert(sig, r.Id .. ":" .. r.Level .. ":" .. r.Rarity)
		end
		local signature = table.concat(sig, "|")
		if signature ~= upSignature then
			upSignature = signature
			for _, row in upRows do
				row.Frame:Destroy()
			end
			table.clear(upRows)
			for i, r in rows do
				local f = Kit.Panel(upList, { Sprite = "Row", Size = UDim2.fromOffset(rowW, math.floor(rowW * rowSpec.Size.Y / rowSpec.Size.X)), LayoutOrder = i })
				f.ClipsDescendants = false
				local body = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, f)
				local roomImg = P.RoomImage(body, r.Def.Id, 52, r.Def.Kind)
				roomImg.AnchorPoint, roomImg.Position, roomImg.Size = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.13, 1)
				local left = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.15, 0), Size = UDim2.fromScale(0.5, 1), ClipsDescendants = true }, body)
				make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, left)
				local line1 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 }, left)
				hlist(line1, 8)
				local nm = Kit.Label(line1, r.Def.DisplayName, 20, Theme.TextPrimary, true)
				nm.AutomaticSize, nm.Size, nm.TextWrapped, nm.LayoutOrder = X, UDim2.fromOffset(0, 30), false, 1
				Kit.Rarity(line1, r.Rarity, 30).LayoutOrder = 3
				-- Level line: "Lv 2" arrow "3" (or "Lv 4 | Max").
				local nextCost = r.NextCost -- server-computed (nil at the rarity's max level)
				local line2 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2 }, left)
				hlist(line2, 6)
				local lv = Kit.Label(line2, "Lv " .. r.Level, Theme.TextSize.Label, Theme.TextMuted, true)
				lv.AutomaticSize, lv.Size, lv.TextWrapped, lv.LayoutOrder = X, UDim2.fromOffset(0, 22), false, 1
				if nextCost then
					Kit.Icon(line2, "Upgrade", UDim2.fromOffset(18, 18)).LayoutOrder = 2
					local nl = Kit.Label(line2, tostring(r.Level + 1), Theme.TextSize.Label, Theme.Success, true)
					nl.AutomaticSize, nl.Size, nl.TextWrapped, nl.LayoutOrder = X, UDim2.fromOffset(0, 22), false, 3
				end
				local btn = Kit.Button(body, {
					Text = if nextCost then tostring(nextCost) else "Max",
					Style = "Success",
					Icon = if nextCost then "CoinStack" else nil,
					IconLayout = "Row",
					Variant = "Price",
					TextSize = 22,
					Size = UDim2.new(0.34, 0, 1, 0),
					Tip = "Upgrade",
					OnClick = function()
						if request("Upgrade", r.Id) then
							Sound.Play("UpgradePurchase")
						end
					end,
				})
				btn.Instance.AnchorPoint = Vector2.new(1, 0.5)
				btn.Instance.Position = UDim2.fromScale(1, 0.5)
				upRows[r.Id] = { Frame = f, Button = btn, Cost = nextCost }
			end
		end
		upHead.Visible = #rows > 0
		for _, row in upRows do
			if not row.Cost then
				row.Button.SetEnabled(false, "Max")
			else
				row.Button.SetEnabled(coins >= row.Cost)
			end
		end
	end
	shop.OnOpen = shop.Refresh
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if shop.IsOpen then
			shop.Refresh()
		end
	end)
	State.Changed:Connect(function()
		if shop.IsOpen then
			shop.Refresh()
		end
	end)
	return shop
end

-- Fits a fixed-width control (design width `designW`) into `holder` by scaling it down when the holder is narrower.
local function scaledSlot(holder: GuiObject, designW: number): Frame
	local inner = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 1) }, holder)
	local us = make("UIScale", {}, inner)
	local function fit()
		local w = holder.AbsoluteSize.X / math.max(Scale.Value, 0.01)
		if w < 10 then
			return
		end
		local s = math.min(1, w / designW)
		us.Scale = s
		inner.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return inner
end

local function buildSettings(gui: ScreenGui)
	-- Panel.ModalCompact (394:270): the rows sit in its Inner rect.
	local panel = modal(gui, "Settings", "Settings", Vector2.new(580, 0), Vector2.new(520, 0), nil, true)
	local list = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, panel.Body)
	make("UIListLayout", { Padding = UDim.new(0, if Scale.Phone then 2 else 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Top }, list)
	-- Icon at the left, the control filling the rest of the row.
	local function row(icon: string, tip: string, order: number): Frame
		local r = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if Scale.Phone then 52 else 76), LayoutOrder = order }, list)
		local ic = Kit.Icon(r, icon, UDim2.fromOffset(36, 36))
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 4, 0.5, 0)
		local holder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -52, 1, 0), Active = true }, r)
		Kit.Tip(r, tip)
		return holder
	end
	local v = Settings.Values
	local motion = row("ReducedMotion", "Reduced motion", 1)
	local ml = Kit.Label(motion, "Reduced motion", Theme.TextSize.Heading, Theme.TextPrimary)
	ml.Size, ml.TextXAlignment, ml.TextWrapped = UDim2.new(1, -104, 1, 0), Enum.TextXAlignment.Left, false
	Kit.FixedText(ml, Theme.TextSize.Heading)
	local toggle = Kit.Toggle(motion, v.ReducedMotion, function(on)
		Settings.Set("ReducedMotion", on)
	end)
	toggle.Instance.AnchorPoint, toggle.Instance.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)
	-- Slider: fixed art size (track 233 + knob + readout ~ 360 wide), scaled down on a narrow well.
	local music = Kit.Slider(scaledSlot(row("Music", "Music", 2), 360), v.MusicVolume, function(x)
		Settings.Set("MusicVolume", x)
	end)
	music.Instance.AnchorPoint, music.Instance.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
	local sfx = Kit.Slider(scaledSlot(row("SoundOn", "Sound effects", 3), 360), v.SfxVolume, function(x)
		Settings.Set("SfxVolume", x)
	end)
	sfx.Instance.AnchorPoint, sfx.Instance.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
	Settings.Changed:Connect(function()
		toggle.Set(Settings.Values.ReducedMotion)
		music.Set(Settings.Values.MusicVolume)
		sfx.Set(Settings.Values.SfxVolume)
	end)
	return panel
end

local function build()
	local gui = Kit.Screen("Hud", 1)

	Net.OnEvent("Notice", function(n)
		if type(n) == "table" and type(n.Text) == "string" then
			-- The box reveal card already shows this result.
			if string.sub(n.Text, 1, 10) == "You found " then
				return
			end
			if State.IsHeld() then -- a box is opening: show it after the reveal
				local c
				c = State.Released:Connect(function()
					c:Disconnect()
					Toast.Show(n.Text, n.Kind)
				end)
				return
			end
			Toast.Show(n.Text, n.Kind)
		end
	end)

	-- Currency pill: Hud.Pill (538:152), one whole image. Coins, the vault (once a treasure room exists) and the vault share sit
	-- in its Inner rect, each in a scale slot; sizes come from the art's aspect (see layout()).
	local currency = Kit.Panel(gui, { Sprite = "Pill" })
	local currencyRow = make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, currency)
	-- Coin + number, chest + number, then the vault share chip: one centred row with gaps, so nothing can collide.
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }, currencyRow)
	local pillPadL, pillPadT, pillPadR, pillPadB = Kit.InnerPadding(V6.Hud.Pill)
	make("UIPadding", { PaddingLeft = UDim.new(pillPadL, 0), PaddingRight = UDim.new(pillPadR, 0), PaddingTop = UDim.new(pillPadT, 0), PaddingBottom = UDim.new(pillPadB, 0) }, currencyRow)
	local banked = cell(currencyRow, "Coin", "Coins")
	local vault = cell(currencyRow, "Vault", "Vault")
	banked.Root.LayoutOrder, vault.Root.LayoutOrder = 1, 2
	-- The vault share (%) as a gold chip; the whole cell opens the vault slider.
	local bonus = Kit.Pill(currencyRow, "", Theme.Gold, Theme.TextOnGold, 36)
	bonus.LayoutOrder = 3
	local function slotCurrency() end
	-- One number size for both cells (never per cell): the largest of 26 down to 18 that fits the pill's content width.
	local function fitCurrency()
		local sc = math.max(Scale.Value, 0.01)
		local avail = currency.AbsoluteSize.X / sc * (1 - pillPadL - pillPadR)
		if avail < 20 then return end
		local cells = {}
		for _, c in { banked, vault } do
			if c.Root.Visible then table.insert(cells, c) end
		end
		local chipW = if bonus.Visible then bonus.AbsoluteSize.X / sc + 12 else 0
		local size = Theme.TextSize.Number - 4
		while size > Theme.TextSize.Label do
			local total = chipW + 12 * (#cells - 1)
			for _, c in cells do
				total += c.Icon.AbsoluteSize.X / sc + 4 + Kit.Measure(c.Number.Text, size, Theme.HeadingFont, 2000).X
			end
			if total <= avail then break end
			size -= 1
		end
		banked.Number.TextSize, vault.Number.TextSize = size, size
	end
	currencyFit = fitCurrency
	-- Keep the tutorial ring off the pill's content: it is a sibling in the screen, placed over the vault cell.
	local vaultRing = Kit.Ring(gui, 6)
	local function positionVaultRing()
		local scale = math.max(Scale.Value, 0.01)
		local pos = (vault.Root.AbsolutePosition - gui.AbsolutePosition) / scale
		local size = vault.Root.AbsoluteSize / scale
		vaultRing.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
		vaultRing.Size = UDim2.fromOffset(size.X + 12, size.Y + 12)
	end
	vault.Root:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionVaultRing)
	vault.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionVaultRing)
	Scale.Changed:Connect(positionVaultRing)

	-- Keeper level and XP: Hud.Pill with the Lv chip at the left and the whole Bar.Track beside it.
	local levelPanel = Kit.Panel(gui, { Sprite = "Pill" })
	local levelRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, levelPanel)
	local levelIcon = Kit.Icon(levelRow, "Level", UDim2.fromOffset(30, 30))
	levelIcon.LayoutOrder = 0
	levelIcon.Visible = false -- the reference shows the Lv chip and the XP bar only
	local levelPill = Kit.Pill(levelRow, "Lv 1", Theme.Gold, Theme.TextOnGold, 40)
	levelPill.AnchorPoint, levelPill.Position = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5)
	local xpBar = Kit.Bar(levelRow, UDim2.fromScale(0.68, 1))
	xpBar.Instance.AnchorPoint, xpBar.Instance.Position = Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5)
	local levelGlow = Kit.Glow(levelPanel, Theme.Gold, 1)
	levelGlow.Size, levelGlow.ZIndex = UDim2.new(1.4, 0, 3, 0), 10
	local levelPop = make("UIScale", {}, levelPanel)
	-- Level-up (and reduced-motion) mark: the pill takes a warm tint (a ring would not fit its 3.5:1 shape).
	local function levelMark(on: boolean)
		levelPanel.ImageColor3 = if on then Color3.fromRGB(255, 232, 150) else Color3.new(1, 1, 1)
	end
	-- Level-up banner (Banner.LevelUp, 680:248, whole) with its Fx.Burst glow, shown briefly top-centre.
	local lvlBanner = make("Frame", { Name = "LevelUp", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 270), Size = UDim2.fromOffset(460, 168), Visible = false, ZIndex = 30 }, gui)
	local lvlGlow = Kit.Glow(lvlBanner, Theme.Gold, 0.35)
	lvlGlow.Size, lvlGlow.ZIndex = UDim2.new(2, 0, 3, 0), 30
	local lvlArt = Kit.Sprite(lvlBanner, "Banner.LevelUp", { Size = UDim2.fromScale(1, 1), ZIndex = 31 })
	local lvlText = Kit.Label(lvlBanner, "LEVEL UP!", 34, Theme.TextPrimary, true)
	lvlText.Size, lvlText.ZIndex, lvlText.TextWrapped = UDim2.new(0.66, 0, 0.3, 0), 32, false
	lvlText.AnchorPoint, lvlText.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.66)
	Kit.Stroke(lvlText, Theme.Stroke, 3)
	Kit.FixedText(lvlText, 36)
	local lvlScale = make("UIScale", {}, lvlBanner)
	local lvlId = 0

	-- Under the level pill: the next goal chip, then the active bonuses (each one whole Hud.Pill).
	local leftStack = make("Frame", { Name = "LeftStack", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, leftStack)
	local goal = Kit.Panel(leftStack, { Sprite = "Pill", LayoutOrder = 1, Active = true, Visible = false })
	local goalRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, goal)
	local goalFlag = Kit.Icon(goalRow, "Flag", UDim2.fromScale(0.2, 1))
	slot(goalFlag, 0, 0.3)
	local goalArt = make("Frame", { BackgroundTransparency = 1 }, goalRow)
	slot(goalArt, 0.32, 0.7)
	local goalText = Kit.Label(goalRow, "", 22, Theme.TextPrimary, true)
	slot(goalText, 0.72, 1)
	goalText.TextWrapped, goalText.TextXAlignment = false, Enum.TextXAlignment.Left
	Kit.FixedText(goalText, 20)
	local goalKind, goalSig = "", ""
	Kit.Tip(goal, "Next goal")
	-- Active bonuses: one small whole pill per bonus (icon + percent).
	local bonusRow = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 44), Visible = false, LayoutOrder = 2 }, leftStack)
	hlist(bonusRow, 6)
	local bonusSig = ""
	local bonusHidden = false -- a modal covers the buff chips (D2)
	local bonusPillH = 56

	-- Settings gear: Round.Purple, top-right.
	local gear = Kit.Button(gui, { Text = "", Icon = "Settings", IconScale = 0.66, Style = "Secondary", Round = true, Size = UDim2.fromOffset(56, 56), Tip = "Settings" })

	-- Next visitor chip: Hud.BarWide with the clock / crossed swords, the name, the portrait and trait chips in scale slots
	-- (a countdown only for a real fixed delay).
	local chipBar = make("Frame", { Name = "ChipBar", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, gui)
	hlist(chipBar, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local chip = Kit.Panel(chipBar, { Sprite = "Pill", LayoutOrder = 1 })
	local chipRowF = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, chip)
	local chipIcon = Kit.Icon(chipRowF, "Clock", UDim2.fromScale(0.1, 1))
	slot(chipIcon, 0, 0.17)
	local status = Kit.Label(chipRowF, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	slot(status, 0.19, 0.6)
	status.TextWrapped, status.TextXAlignment = false, Enum.TextXAlignment.Left
	Kit.FixedText(status, Theme.TextSize.Body)
	local nextPortrait = make("ImageLabel", { BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false, Image = "", Active = true }, chipRowF)
	slot(nextPortrait, 0.6, 0.74)
	local nextName = ""
	Kit.Tip(nextPortrait, function()
		return nextName
	end)
	local traitRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.25, 1), ClipsDescendants = true }, chipRowF)
	hlist(traitRow, 4, { HorizontalAlignment = Enum.HorizontalAlignment.Right })
	local shownNext: string? = nil
	local nextInfoId: string? = nil
	local threatButton = Kit.Button(chipBar, { Text = "", Icon = "T1", IconScale = 0.82, Style = "Secondary", Round = true, Size = UDim2.fromOffset(46, 46), LayoutOrder = 2, Tip = "Threat" })
	local infoButton = Kit.Button(chipBar, { Text = "", Icon = "DropChance", IconScale = 0.6, Style = "Secondary", Round = true, Size = UDim2.fromOffset(46, 46), LayoutOrder = 3, Tip = "Drops" })

	-- Bottom navigation: Nav.Off (purple) buttons, icon over label; the open panel (and Build) wear Nav.On (yellow). Nav art is
	-- square (1:1), so every button is a square.
	local bar = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(0.5, 1) }, gui)
	hlist(bar, 12, { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom })
	local buttons = {}
	local function action(key: string, icon: string, text: string, _style: string, order: number, onClick: () -> ())
		local b = Kit.Button(bar, { Text = text, Icon = icon, IconScale = 0.58, Style = "Nav", LayoutOrder = order, Tip = text, OnClick = onClick })
		buttons[key] = b
		return b
	end
	local shop, settingsPanel
	local function toggle(panel: any)
		if panel.IsOpen then
			panel.Close()
		else
			Bus.OpenPanel:Fire("Close")
			panel.Open()
		end
	end
	action("Build", "Build", "Build", "Primary", 1, function()
		closeModals()
		Bus.BuildRequested:Fire()
	end)
	action("Shop", "Shop", "Shop", "Secondary", 2, function()
		toggle(shop)
	end)
	-- Bag holds chests and owned items; Index holds rooms, visitors and Keeper.
	action("Bag", "Bag", "Bag", "Secondary", 3, function()
		closeModals()
		Bus.OpenPanel:Fire("Bag")
	end)
	action("Index", "Collection", "Index", "Secondary", 4, function()
		closeModals()
		Bus.OpenPanel:Fire("Index")
	end)
	action("Keeper", "Upgrade", "Upgrades", "Secondary", 5, function()
		closeModals()
		Bus.OpenPanel:Fire("Keeper")
	end)
	gear.Instance.Activated:Connect(function()
		toggle(settingsPanel)
	end)
	for _, key in { "Build", "Shop" } do
		Bus.Targets[key] = { Instance = buttons[key].Instance, Stroke = buttons[key].Stroke, Button = buttons[key] }
	end
	Bus.Targets.Loot = { Instance = buttons.Bag.Instance, Stroke = buttons.Bag.Stroke, Button = buttons.Bag }
	for _, key in { "Index", "Collection" } do
		Bus.Targets[key] = { Instance = buttons.Index.Instance, Stroke = buttons.Index.Stroke, Button = buttons.Index }
	end
	Bus.Targets.Keeper = { Instance = buttons.Keeper.Instance, Stroke = buttons.Keeper.Stroke, Button = buttons.Keeper }
	Bus.ShopRequested:Connect(function()
		shop.Open()
	end)

	shop = buildShop(gui)
	settingsPanel = buildSettings(gui)

	-- Threat picker, vault slider and drop card popups (bodies in Ui/PanelsThreat, PanelsVault, DropCard).
	local vaultModal = modal(gui, "Vault", "Vault", Vector2.new(1100, 0), Vector2.new(900, 0), 0.66)
	local vaultPanel = PanelsVault.Build(vaultModal.Body)
	vaultModal.OnOpen = vaultPanel.Refresh
	Bus.VaultRequested:Connect(function()
		if State.HasPlacedKind("Treasure") then
			Bus.OpenPanel:Fire("Close")
			vaultModal.Open()
		end
	end)
	local dropModal = modal(gui, "Drops", "DropChance", Vector2.new(900, 0), Vector2.new(800, 0), 0.55)
	local dropScroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
	}, dropModal.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, dropScroll)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 24) }, dropScroll)
	local dropId: string? = nil
	local dropEncounterTier: number? = nil
	local function fillDrops()
		for _, c in dropScroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local def = dropId and Catalog.Visitor(dropId)
		dropModal.Title.Text = def and def.DisplayName or "Drops"
		if dropId and State.Current then
			local selectedTier = State.Current.ThreatActive
			if dropEncounterTier and selectedTier and dropEncounterTier ~= selectedTier then
				local note = Kit.Label(dropScroll, `These details use T{selectedTier} for upcoming visitors; the inspected visitor is T{dropEncounterTier}.`, Theme.TextSize.Body, Theme.TextPrimary, true)
				note.Size, note.AutomaticSize, note.LayoutOrder = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.Y, 0
			end
			DropCard.Fill(dropScroll, dropId, State.Current, true)
		end
	end
	dropModal.OnOpen = fillDrops
	local function showDrops(visitorId: any, encounterTier: number?)
		if type(visitorId) ~= "string" or visitorId == "" then
			return
		end
		if dropModal.IsOpen and dropId == visitorId and dropEncounterTier == encounterTier then
			dropModal.Close()
			return
		end
		dropId = visitorId
		dropEncounterTier = encounterTier
		Bus.OpenPanel:Fire("Close")
		dropModal.Open()
	end
	State.Changed:Connect(function()
		if dropModal.IsOpen then
			fillDrops()
		end
	end)
	threatButton.Instance.Activated:Connect(function()
		closeModals()
		Bus.OpenPanel:Fire("Threat")
	end)
	infoButton.Instance.Activated:Connect(function()
		showDrops(nextInfoId)
	end)
	onTap(vault.Root, function()
		toggle(vaultModal)
	end)
	Bus.Targets.Vault = {
		Instance = vault.Root,
		Button = {
			SetHighlight = function(t: number?)
				vaultRing.Visible = t ~= nil
				if t ~= nil then positionVaultRing() end
			end,
		},
	}
	EventBanner.Start()

	-- Encounter panel: Card.Info (312:330, one whole image). The visitor's portrait and name sit in its header band, the rows
	-- (tier / variant / drops button, health, reward, risk) in its Inner rect; rows with no value are hidden.
	local infoSpec = V6.Card.Info
	local enc = Kit.Panel(gui, { Sprite = "CardInfo", Visible = false })
	enc.ClipsDescendants = false
	enc:FindFirstChild("Inset"):Destroy()
	local header = make("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromScale(0.1, 0.1), Size = UDim2.fromScale(0.8, 0.17) }, enc)
	local il, it, ir, ib = Kit.InnerPadding(infoSpec)
	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromScale(il, it + 0.01), Size = UDim2.fromScale(1 - il - ir, 1 - it - ib - 0.02) }, enc)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center }, body)
	local nameRow = header
	-- Tags: threat tier shield and the rare-variant nameplate, with the drop-table button at the right.
	local tagRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 }, body)
	local tagLeft = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) }, tagRow)
	hlist(tagLeft, 8)
	local encTier = Kit.Icon(tagLeft, "T1", UDim2.fromOffset(36, 36))
	encTier.LayoutOrder = 1
	local encVariantHolder = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2 }, tagLeft)
	hlist(encVariantHolder, 0)
	local encInfo = Kit.Button(tagRow, { Text = "", Icon = "DropChance", IconScale = 0.7, Style = "Secondary", Round = true, Size = UDim2.fromOffset(44, 44), Tip = "Drops" })
	encInfo.Instance.AnchorPoint, encInfo.Instance.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)
	local shownVariant = ""
	local portrait = make("ImageLabel", { BackgroundTransparency = 1, Image = IconIds.Visitor, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(0.2, 1), ScaleType = Enum.ScaleType.Fit }, nameRow)
	local encName = Kit.Label(nameRow, "", Theme.TextSize.Heading, Theme.TextPrimary, true)
	-- Fixed title size; two lines fit the header band (which sits clear of the top rim of the card), so a long name wraps,
	-- never touches the rim and never shrinks.
	encName.AnchorPoint, encName.Position, encName.Size, encName.TextXAlignment, encName.TextWrapped = Vector2.new(0, 0.5), UDim2.new(0.22, 4, 0.5, 0), UDim2.new(0.78, -4, 1, 0), Enum.TextXAlignment.Left, true
	Kit.FixedText(encName, 22)
	-- Health: the whole Hud.BarWide bar with "5/70" centred, coloured by remaining health.
	local hpRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3 }, body)
	local hp = Kit.Bar(hpRow, UDim2.fromScale(1, 1), Theme.Success, true)
	hp.Instance.AnchorPoint, hp.Instance.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	Kit.Tip(hp.Instance, "Health")
	local chipRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 4 }, body)
	hlist(chipRow, 6)
	local slowChip = Kit.Icon(chipRow, "Slow", UDim2.fromOffset(24, 24))
	slowChip.LayoutOrder = 1
	slowChip.Active = true
	Kit.Tip(slowChip, "Slowed")
	local sporeChip = Kit.Icon(chipRow, "Spores", UDim2.fromOffset(24, 24))
	sporeChip.LayoutOrder = 2
	local rewardRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 5, Active = true }, body)
	hlist(rewardRow, 6)
	local rewardIcon = Kit.Icon(rewardRow, "CoinRange", UDim2.fromOffset(26, 26))
	rewardIcon.LayoutOrder = 1
	local encReward = Kit.Label(rewardRow, "", Theme.TextSize.Body, Theme.Gold, true)
	encReward.AutomaticSize, encReward.Size, encReward.LayoutOrder, encReward.TextWrapped = X, UDim2.fromOffset(0, 28), 2, false
	Kit.Tip(rewardRow, "Reward")
	local riskRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 6, Active = true }, body)
	hlist(riskRow, 6)
	Kit.Icon(riskRow, "Thief", UDim2.fromOffset(26, 26)).LayoutOrder = 1
	local encRisk = Kit.Label(riskRow, "", Theme.TextSize.Body, Theme.Danger, true)
	encRisk.AutomaticSize, encRisk.Size, encRisk.LayoutOrder, encRisk.TextWrapped = X, UDim2.fromOffset(0, 26), 2, false
	Kit.Tip(riskRow, "Stolen if it reaches the vault")

	local plot = Plots.WaitOwn()

	local function layout()
		local phone = Scale.Phone
		-- Hud.Pill art: width follows height at 538:152; the content rect is its Inner (about 0.54 of the height).
		local pillSpec = V6.Hud.Pill
		local pr = pillSpec.Size.X / pillSpec.Size.Y
		local innerFrac = (pillSpec.Inner.Max.Y - pillSpec.Inner.Min.Y) / pillSpec.Size.Y
		local function pillBox(obj: GuiObject, h: number)
			obj.Size = UDim2.fromOffset(math.floor(h * pr + 0.5), h)
		end
		local ph = if phone then 84 else 108
		local innerH = ph * innerFrac
		pillBox(currency, ph)
		pillBox(levelPanel, ph)
		Kit.SetPillHeight(bonus, math.floor(innerH * 0.82))
		Kit.SetPillHeight(levelPill, math.floor(innerH * 0.9))
		pillBox(goal, if phone then 40 else 52)
		-- XP text sized to the pill's Inner height (the bar's own window is thinner), currency icons likewise.
		local xt = xpBar.Instance:FindFirstChild("Text", true)
		if xt and xt:IsA("TextLabel") then
			local lim = xt:FindFirstChildOfClass("UITextSizeConstraint")
			if lim then lim:Destroy() end
			xt.TextScaled = false
			xt.TextSize = math.max(Theme.TextSize.Label, math.floor(innerH * 0.5))
			xt.ZIndex = 6
		end
		banked.SetIcon(math.floor(innerH * 0.74))
		vault.SetIcon(math.floor(innerH * 0.74))
		task.defer(fitCurrency)
		bonusPillH = if phone then 46 else 60
		for _, c in bonusRow:GetChildren() do
			if c:IsA("GuiObject") then
				pillBox(c, bonusPillH)
			end
		end
		local barSpec = V6.Hud.Pill
		local chipH = if phone then 52 else 72
		chip.Size = UDim2.fromOffset(math.floor(chipH * barSpec.Size.X / barSpec.Size.Y + 0.5), chipH)
		local chipInner = chipH * (barSpec.Inner.Max.Y - barSpec.Inner.Min.Y) / barSpec.Size.Y
		status.TextSize = math.max(Theme.TextSize.Label, math.floor(chipInner * 0.62))
		chipIcon.Size = UDim2.fromScale(0.17, 1)
		-- Visitor card: whole Card.Info at 312:330.
		local encW = if phone then 292 else 330
		enc.Size = UDim2.fromOffset(encW, math.floor(encW * infoSpec.Size.Y / infoSpec.Size.X + 0.5))
		local bodyH = enc.Size.Y.Offset * (infoSpec.Inner.Max.Y - infoSpec.Inner.Min.Y) / infoSpec.Size.Y
		hpRow.Size = UDim2.new(1, 0, 0, math.floor(math.min(bodyH * 0.26, 44)))
		if phone then
			gear.Instance.AnchorPoint, gear.Instance.Position, gear.Instance.Size = Vector2.new(1, 0), UDim2.new(1, -8, 0, 4), UDim2.fromOffset(60, 60)
			levelPanel.AnchorPoint, levelPanel.Position = Vector2.new(0, 0), UDim2.fromOffset(8, 4)
			leftStack.AnchorPoint, leftStack.Position = Vector2.new(0, 0), UDim2.fromOffset(8, 4 + ph + 6)
			currency.AnchorPoint, currency.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4)
			chipBar.AnchorPoint, chipBar.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4 + ph + 6)
			threatButton.Instance.Size, infoButton.Instance.Size = UDim2.fromOffset(56, 56), UDim2.fromOffset(56, 56)
			bar.Position = UDim2.new(0.5, 0, 1, -12)
			enc.AnchorPoint, enc.Position = Vector2.new(1, 0), UDim2.new(1, -8, 0, 76)
		else
			gear.Instance.AnchorPoint, gear.Instance.Position, gear.Instance.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 10), UDim2.fromOffset(84, 84)
			levelPanel.AnchorPoint, levelPanel.Position = Vector2.new(0, 0), UDim2.fromOffset(16, 8)
			leftStack.AnchorPoint, leftStack.Position = Vector2.new(0, 0), UDim2.fromOffset(16, 8 + ph + 8)
			currency.AnchorPoint, currency.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8)
			chipBar.AnchorPoint, chipBar.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8 + ph + 8)
			threatButton.Instance.Size, infoButton.Instance.Size = UDim2.fromOffset(72, 72), UDim2.fromOffset(72, 72)
			bar.Position = UDim2.new(0.5, 0, 1, -16)
			enc.AnchorPoint, enc.Position = Vector2.new(1, 0), UDim2.new(1, -16, 0, 130)
		end
		local count = 0
		for _ in buttons do count += 1 end
		local available = gui.AbsoluteSize.X / math.max(Scale.Value, 0.01)
		local navSide = math.min(if phone then 108 else 140, (available - 32 - 12 * (count - 1)) / count)
		for _, b in buttons do
			local side = math.max(navSide, 44 / Scale.Value)
			b.Instance.Size = UDim2.fromOffset(side, side)
			-- One fixed label size for every nav button (sized for the longest word, "Upgrades").
			local lbl = b.Label :: TextLabel
			lbl.TextScaled = false
			lbl.TextWrapped = false
			lbl.TextSize = 20 -- >= 18 reference px, the same on desktop and phone
		end
		encName.TextSize = 22
		shop.Layout()
		settingsPanel.Layout()
		vaultModal.Layout()
		vaultPanel.Layout()
		dropModal.Layout()
		if shop.IsOpen then
			shop.Refresh()
		end
	end
	Scale.Changed:Connect(layout)
	layout()

	-- Nav state: Build is always lit; Shop / Bag / Index / Upgrades light (Nav.On) while their panel is open.
	buttons.Build.SetSelected(true)
	local navLit: { [string]: boolean } = {}
	task.spawn(function()
		while gui.Parent do
			local open: { [string]: boolean } = {}
			for _, panels in gui.Parent:GetChildren() do
				if panels:IsA("ScreenGui") and panels:GetAttribute("Panel") ~= nil and panels.Enabled then
					open[tostring(panels:GetAttribute("Panel"))] = true
				end
			end
			open.Shop = shop.IsOpen
			-- Only the open panel wears Nav.On; Build is lit while nothing is open.
			local anyOpen = false
			for _, m in modals do
				anyOpen = anyOpen or m.IsOpen
			end
			for _, isOpen in open do
				anyOpen = anyOpen or isOpen
			end
			open.Build = not anyOpen
			for key, panel in { Build = "Build", Shop = "Shop", Bag = "Bag", Index = "Index", Keeper = "Keeper" } do
				local on = open[panel] == true
				if navLit[key] ~= on then
					navLit[key] = on
					buttons[key].SetSelected(on)
				end
			end
			task.wait(0.12)
		end
	end)

	local function applyBonusVisible()
		local s = State.Current
		bonusRow.Visible = bonusSig ~= "0,0,0" and bonusSig ~= "" and not bonusHidden and not (s and s.Building and Scale.Phone)
	end

	local function syncChipVisibility()
		local covered = false
		for _, m in modals do covered = covered or m.Group.Visible end
		for _, panels in gui.Parent:GetChildren() do
			if (panels:GetAttribute("Panel") ~= nil or panels.Name == "BatchRewards" or panels.Name == "Reveal") and panels:IsA("ScreenGui") and panels.Enabled then covered = true end
		end
		chipBar.Visible = not covered and not (State.Current and State.Current.Building)
		-- The buff chips hide while any modal is open, so a panel never clips them.
		bonusHidden = covered
		applyBonusVisible()
	end

	local function refreshEncounter()
		local s = State.Current
		local visitorId = plot:GetAttribute("VisitorId")
		local show = type(visitorId) == "string" and visitorId ~= ""
		-- Hidden while a modal panel (Shop/Settings/Bag/Index) is open so they never overlap.
		local covered = false
		for _, m in modals do
			covered = covered or m.Group.Visible
		end
		for _, panels in gui.Parent:GetChildren() do
			if (panels:GetAttribute("Panel") ~= nil or panels.Name == "BatchRewards" or panels.Name == "Reveal") and panels:IsA("ScreenGui") and panels.Enabled then covered = true end
		end
		enc.Visible = show and not covered
		if not show then
			return
		end
		local def = Catalog.Visitor(visitorId)
		encName.Text = def and def.DisplayName or visitorId
		local pid = SpriteIds.Portraits[visitorId]
		portrait.Image = if Sprites.Ok(pid) then pid else IconIds.Visitor
		local health = plot:GetAttribute("VisitorHealth") or 0
		local max = math.max(plot:GetAttribute("VisitorMaxHealth") or 1, 1)
		local frac = math.clamp(health / max, 0, 1)
		hp.Set(frac, ("%d/%d"):format(health, max), if frac > 0.6 then Theme.Success elseif frac > 0.3 then Theme.Warning else Theme.Danger)
		local slowed, spored = plot:GetAttribute("VisitorSlowed") == true, plot:GetAttribute("VisitorSpored") == true
		slowChip.Visible, sporeChip.Visible, chipRow.Visible = slowed, spored, slowed or spored
		-- The coin range and theft are computed by the server (plot attributes, refreshed each step); the
		-- actual payout only appears in the End effect.
		local hasTreasure = State.HasPlacedKind("Treasure")
		local rMin, rMax = plot:GetAttribute("VisitorRewardMin") or 0, plot:GetAttribute("VisitorRewardMax") or 0
		encReward.Text = Badges.Range({ Min = rMin, Max = rMax })
		rewardRow.Visible = rMin > 0 or rMax > 0
		local theft = plot:GetAttribute("VisitorTheft") or 0
		riskRow.Visible = hasTreasure and theft > 0
		encRisk.Text = "-" .. Badges.Comma(theft)
		-- Tier shield (hidden at T1) and the rare-variant nameplate.
		local tier = plot:GetAttribute("Threat")
		tier = if type(tier) == "number" then tier else 1
		encTier.Visible = tier > 1
		if encTier:IsA("ImageLabel") then
			Kit.SetIcon(encTier, "T" .. math.clamp(tier, 1, 6))
		end
		local variant = plot:GetAttribute("VisitorVariant")
		variant = if type(variant) == "string" then variant else ""
		if variant ~= shownVariant then
			shownVariant = variant
			for _, c in encVariantHolder:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			if variant ~= "" then
				Badges.Variant(encVariantHolder, variant, 36)
			end
		end
	end
	encInfo.Instance.Activated:Connect(function()
		showDrops(plot:GetAttribute("VisitorId"), plot:GetAttribute("Threat"))
	end)
	for _, attr in { "VisitorId", "VisitorHealth", "VisitorMaxHealth", "VisitorSlowed", "VisitorSpored", "VisitorRewardMin", "VisitorRewardMax", "VisitorVariant", "Threat", "VisitorTheft" } do
		plot:GetAttributeChangedSignal(attr):Connect(refreshEncounter)
	end
	for _, m in modals do
		m.Group:GetPropertyChangedSignal("Visible"):Connect(refreshEncounter)
		m.Group:GetPropertyChangedSignal("Visible"):Connect(syncChipVisibility)
	end
	local function watchPanels(panels)
		if panels:IsA("ScreenGui") and (panels.Name == "Panels" or panels:GetAttribute("Panel") ~= nil) then
			panels:GetPropertyChangedSignal("Enabled"):Connect(refreshEncounter)
			panels:GetPropertyChangedSignal("Enabled"):Connect(syncChipVisibility)
		end
	end
	gui.Parent.ChildAdded:Connect(watchPanels)
	for _, panels in gui.Parent:GetChildren() do watchPanels(panels) end

	local lastLevel: number? = nil
	local lastCoins = 0
	local glowId = 0
	local function levelUp(level: number)
		glowId += 1
		local mine = glowId
		lvlId += 1
		local bid = lvlId
		lvlText.Text = "LEVEL UP! " .. level
		lvlBanner.Visible = true
		lvlScale.Scale = if Settings.Reduced() then 1 else 0.6
		Settings.Tween(lvlScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		task.delay(2.4, function()
			if lvlId == bid then
				lvlBanner.Visible = false
			end
		end)
		levelMark(true)
		task.delay(1.5, function()
			if glowId == mine then
				levelMark(false)
			end
		end)
		if Settings.Reduced() then
			return
		end
		levelGlow.ImageTransparency, levelPop.Scale = 0.3, 1.1
		Settings.Tween(levelGlow, TweenInfo.new(0.9), { ImageTransparency = 1 })
		Settings.Tween(levelPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end

	local BONUS_ICON = { { "Coins", "Coin", "Coins" }, { "Loot", "Loot", "Loot chance" }, { "Xp", "Xp", "XP" } }
	local function refresh()
		local s = State.Current
		if not s then
			return
		end
		local coins = s.Coins or 0
		banked.Set(coins)
		if coins > lastCoins and lastCoins > 0 then
			Sound.Play("CoinGain")
		end
		lastCoins = coins
		vault.Set(s.Vaulted or 0)
		local chests = 0
		for _, n in s.Boxes or {} do
			chests += n
		end
		buttons.Bag.SetBadge(chests)
		local hasTreasure = State.HasPlacedKind("Treasure")
		vault.Root.Visible = hasTreasure
		local share = s.VaultPercent or 0
		bonus.Visible = hasTreasure
		Kit.SetText(bonus, share .. "%")
		slotCurrency()

		-- Threat button: the tier visitors use now. Hidden until the tutorial is done.
		local tier = s.ThreatActive or s.Threat or 1
		threatButton.Instance.Visible = s.Tutorial ~= nil and s.Tutorial.Done == true
		if threatButton.Icon and threatButton.Icon:IsA("ImageLabel") then
			Kit.SetIcon(threatButton.Icon, "T" .. math.clamp(tier, 1, 6))
		end

		-- Next goal: an affordable permanent upgrade, else the nearest threat tier or shop room.
		local nu = s.NextUnlocks or {}
		local kind, sig, level
		if nu.Permanent and nu.Permanent.Affordable then
			kind, sig = "Perm", "Perm:" .. tostring(nu.Permanent.Id)
		else
			local t, r = nu.Threat, nu.ShopRoom
			if t and (not r or t.Level <= r.Level) then
				kind, sig, level = "Threat", "T" .. t.Tier, t.Level
			elseif r then
				kind, sig, level = "Room", "R" .. r.RoomId, r.Level
			end
		end
		goal.Visible = kind ~= nil
		goalKind = kind or ""
		if kind and sig .. ":" .. tostring(level) ~= goalSig then
			goalSig = sig .. ":" .. tostring(level)
			for _, c in goalArt:GetChildren() do
				c:Destroy()
			end
			local art: any
			if kind == "Perm" then
				art = Kit.Icon(goalArt, "Upgrade", UDim2.fromScale(1, 1))
				goalText.Text = "!"
				goalText.TextColor3 = Theme.Gold
			elseif kind == "Threat" then
				art = Badges.Tier(goalArt, nu.Threat.Tier, UDim2.fromScale(1, 1))
				goalText.Text = "Lv " .. level
				goalText.TextColor3 = Theme.TextPrimary
			else
				local def = Catalog.Room(nu.ShopRoom.RoomId)
				art = P.RoomImage(goalArt, nu.ShopRoom.RoomId, 28, def and def.Kind)
				goalText.Text = "Lv " .. level
				goalText.TextColor3 = Theme.TextPrimary
			end
			art.Size = UDim2.fromScale(1, 1)
		end

		local level = s.Level or 1
		Kit.SetText(levelPill, "Lv " .. level)
		if level >= Catalog.Current.MaxKeeperLevel then
			xpBar.Set(1, "MAX")
		else
			local need = math.max(s.XpToNext or 1, 1)
			xpBar.Set((s.Xp or 0) / need, ("%d/%d"):format(s.Xp or 0, need))
		end
		if lastLevel and level > lastLevel then
			levelUp(level)
		end
		lastLevel = level

		-- Bonus chips (rebuilt only when the values change): each one a whole Hud.Pill with icon + percent in scale slots.
		local b = s.Bonuses or {}
		local sigParts = {}
		for _, e in BONUS_ICON do
			table.insert(sigParts, pct(b[e[1]]))
		end
		local sig = table.concat(sigParts, ",")
		if sig ~= bonusSig then
			bonusSig = sig
			for _, c in bonusRow:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			for i, e in BONUS_ICON do
				local v = pct(b[e[1]])
				if v > 0 then
					local c = Kit.Panel(bonusRow, { Sprite = "Pill", LayoutOrder = i, Active = true })
					local pr = V6.Hud.Pill.Size.X / V6.Hud.Pill.Size.Y
					c.Size = UDim2.fromOffset(math.floor(bonusPillH * pr + 0.5), bonusPillH)
					local cr = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, c)
					local ic = Kit.Icon(cr, e[2], UDim2.fromScale(0.3, 1))
					slot(ic, 0, 0.3)
					local l = Kit.Label(cr, "+" .. v .. "%", 27, Theme.TextPrimary, true)
					slot(l, 0.33, 1)
					l.TextWrapped, l.TextXAlignment = false, Enum.TextXAlignment.Left
					Kit.FixedText(l, 24)
					Kit.Tip(c, e[3])
				end
			end
		end
		applyBonusVisible()

		local boxes = s.Boxes or {}
		buttons.Bag.SetBadge((boxes.Dungeon or 0) + (boxes.Rare or 0))
		buttons.Build.SetStyle(if next(s.Layout or {}) == nil then "Success" else "Primary")

		bar.Visible = not s.Building
		gear.Instance.Visible = not s.Building
		syncChipVisibility()
		goal.Visible = goal.Visible and not s.Building
		levelPanel.Visible = not (s.Building and Scale.Phone)
		refreshEncounter()
	end
	State.Changed:Connect(refresh)
	refresh()
	onTap(goal, function()
		if goalKind == "Perm" then
			Bus.OpenPanel:Fire("Keeper")
		elseif goalKind == "Room" then
			toggle(shop)
		elseif goalKind == "Threat" then
			closeModals()
			Bus.OpenPanel:Fire("Threat")
		end
	end)

	-- Next visitor: portrait and trait icons (rebuilt when the id changes).
	local function showNext(id: string?)
		if id == shownNext then
			return
		end
		shownNext = id
		for _, c in traitRow:GetChildren() do
			if c:IsA("TextLabel") or c:IsA("Frame") or c:IsA("ImageLabel") then
				c:Destroy()
			end
		end
		local def = id and Catalog.Visitor(id)
		nextName = def and def.DisplayName or ""
		local pid = id and SpriteIds.Portraits[id]
		nextPortrait.Visible = Sprites.Ok(pid)
		nextPortrait.Image = if nextPortrait.Visible then pid else ""
		for i, info in def and def.Traits or {} do
			if info.Id == "Mender" or info.Id == "SureFooted" then
				local ic = Kit.Icon(traitRow, if info.Id == "Mender" then "Heal" else "SureFooted", UDim2.fromOffset(26, 26))
				ic.LayoutOrder = i
				ic.Active = true
				Kit.Tip(ic, info.Name)
			else
				Kit.Pill(traitRow, info.Name, Theme.BgRaised, Theme.TextPrimary, 28).LayoutOrder = i
			end
		end
	end

	task.spawn(function()
		while true do
			local s = State.Current
			local text, upcoming, icon = "", nil, "Clock"
			if s and s.Building then
				text, icon = "", nil -- nothing while building
			elseif plot:GetAttribute("State") == "Encounter" or (plot:GetAttribute("VisitorId") or "") ~= "" then
				text, icon = "", "Sword" -- a visitor is inside: crossed swords
			else
				-- Visitors arrive back to back: a timer shows only for a real fixed delay (first visitor, build resume).
				local at = plot:GetAttribute("NextVisitorAt")
				local left = if type(at) == "number" then at - workspace:GetServerTimeNow() else 0
				local id = plot:GetAttribute("NextVisitorId")
				upcoming = if type(id) == "string" and id ~= "" then id else nil
				if left > 0.25 then
					text = formatTime(left)
				else
					icon = nil
					local def = upcoming and Catalog.Visitor(upcoming)
					text = if def then def.DisplayName else ""
				end
			end
			status.Text = text
			status.Visible = text ~= ""
			chip.Visible = text ~= "" -- no empty pill while a visitor is inside (the visitor card shows it)
			chipIcon.Visible = icon ~= nil
			if icon and chipIcon:IsA("ImageLabel") then Kit.SetIcon(chipIcon, icon) end
			showNext(upcoming)
			infoButton.Instance.Visible = upcoming ~= nil
			nextInfoId = upcoming
			task.wait(0.25)
		end
	end)
end

function Hud.Init()
	State.Start()
	Settings.Start()
end

function Hud.Start()
	-- Loading spinner (Misc.Spinner) until the catalog and the first State snapshot are here.
	local spinGui = Kit.Screen("Loading", 90)
	local spin = Kit.Sprite(spinGui, "Misc.Spinner", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(72, 72) })
	local spinConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
		spin.Rotation = (spin.Rotation + dt * 360) % 360
	end)
	local failGui = Kit.Screen("LoadFailure", 100)
	failGui.Enabled = false
	local fail = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 100, Active = true }, failGui)
	Kit.Scrim(fail, 0.15, { ZIndex = 100 })
	-- Panel.ModalCompact (394:270) whole; the icon and the message sit in its Inner rect.
	local failSpec = Kit.Spec("Panel.ModalCompact")
	local failPanel = Kit.Panel(fail, { Sprite = "LoadFail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, math.floor(520 * failSpec.Size.Y / failSpec.Size.X)), ZIndex = 101 })
	local failIcon = Kit.Icon(failPanel, "Warn", UDim2.fromOffset(56, 56))
	failIcon.AnchorPoint, failIcon.Position, failIcon.ZIndex = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), 102
	local failText = Kit.Label(failPanel, "Your progress could not load. Please rejoin.", Theme.TextSize.Heading, Theme.TextPrimary, true)
	failText.Position, failText.Size, failText.ZIndex = UDim2.fromOffset(0, 60), UDim2.new(1, 0, 1, -60), 102
	Kit.FixedText(failText, Theme.TextSize.Heading)
	Kit.Stroke(failText, Theme.Stroke, 3)
	local function layoutFailure()
		local view = failGui.AbsoluteSize / math.max(Scale.Value, 0.01)
		if view.X > 32 and view.Y > 32 then
			local w = math.min(520, view.X - 16, (view.Y - 16) * failSpec.Size.X / failSpec.Size.Y)
			failPanel.Size = UDim2.fromOffset(w, w * failSpec.Size.Y / failSpec.Size.X)
		end
	end
	Scale.Changed:Connect(layoutFailure)
	failGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutFailure)
	layoutFailure()
	local function stopSpinner()
		spinConn:Disconnect()
		if spinGui.Parent then spinGui:Destroy() end
	end
	local function showFailure(snapshot: any)
		if snapshot and snapshot.LoadState == "Failed" then
			failGui.Enabled = true
			stopSpinner()
		end
	end
	State.Changed:Connect(showFailure)
	showFailure(State.Current)
	task.spawn(function()
		Catalog.Wait() -- open to every player, so the load-failure screen still appears
		build()
		local t0 = os.clock()
		while not State.Current and os.clock() - t0 < 15 do
			task.wait(0.1)
		end
		stopSpinner()
	end)
end

return Hud
