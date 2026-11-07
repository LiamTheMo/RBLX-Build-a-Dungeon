-- Shared pieces of the Bag / Index / Keeper panels: rarity colours,
-- text helpers, list cards and the modal shell (title, tabs, scroll area).
local Theme = require(script.Parent.Theme)
local Percent = require(script.Parent.Percent)
local Scale = require(script.Parent.Scale)
local Kit = require(script.Parent.Kit)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)

local make = Kit.Make

local P = {}
local TAB_ICON = { Chests = "Bag", Index = "Collection" }

P.RarityColor = Theme.Rarity

function P.Hex(c: Color3): string
	return "#" .. c:ToHex()
end

P.Pct = Percent.Format

function P.Rich(text: string, rarity: string): string
	return string.format('<font color="%s">%s</font>', P.Hex(P.RarityColor[rarity] or Theme.TextPrimary), text)
end

local PERK = { Coins = "coins", Loot = "loot chance", Xp = "XP" }
function P.PerkText(perks: any): string
	local out = {}
	for _, p in perks or {} do
		table.insert(out, string.format("+%s %s", P.Pct(p.Amount or 0), PERK[p.Kind] or tostring(p.Kind)))
	end
	return table.concat(out, ", ")
end

function P.Spaced(id: string): string
	return (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

-- Auto-height card with a vertical list inside (PanelSmall, or the tier's card frame when
-- `rarity` names one) .
function P.Card(parent: Instance, order: number?, rarity: string?): Frame
	local f = Kit.Panel(parent, {
		BackgroundColor3 = Theme.BgPanel,
		Size = UDim2.new(1, 0, 0, 56),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
		Rarity = rarity,
		Pad = Vector2.new(6, 4),
	})
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

-- Image for a room id (its sprite, else a kind icon); parent gets it at `size`.
function P.RoomImage(parent: Instance, roomId: string, size: number, kind: string?): any
	local id = SpriteIds.Rooms[roomId]
	if id and Sprites.Ok(id) then
		local img = make("ImageLabel", { Name = "RoomImage", BackgroundTransparency = 1, Image = id, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit }, parent)
		Sprites.Watch(id, function()
			Kit.Neutral(img)
		end)
		return img
	end
	return Kit.Icon(parent, P.KindIcon[kind or ""] or "Defender", UDim2.fromOffset(size, size))
end

-- Room kind -> icon name (Kit.Icon).
P.KindIcon = { Defender = "Defender", Trap = "Trap", Treasure = "CoinStack", Support = "Support" }

-- Wrapped text line that grows downward.
function P.Text(parent: Instance, text: string, size: number?, color: Color3?, heading: boolean?, order: number?): TextLabel
	local l = Kit.Label(parent, text, size, color, heading)
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	l.LayoutOrder = order or 0
	return l
end

-- Section heading with the Feedback.Divider sprite under it. Returns the container (the text is its "Text" child).
function P.Section(parent: Instance, text: string, order: number)
	local f = make("Frame", { Name = "Section", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order }, parent)
	local l = P.Text(f, text, Theme.TextSize.Heading, Theme.Gold, true, 0)
	l.Name, l.Size = "Text", UDim2.new(1, 0, 0, 34)
	local d = Kit.Sprite(f, "Feedback.Divider", { Name = "Divider", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(372, 24), ScaleType = Enum.ScaleType.Fit })
	d.ZIndex = 2
	return f
end

-- Empty state: the EmptyBox sprite with a short caption.
function P.Empty(parent: Instance, text: string, order: number): Frame
	local f = make("Frame", { Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	Kit.Sprite(f, "Feedback.EmptyBox", { Size = UDim2.fromOffset(80, 86), LayoutOrder = 1 })
	local l = Kit.Label(f, text, Theme.TextSize.Body, Theme.TextMuted, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 40), false, 2
	return f
end

-- Row: optional leading image, text block, optional button on the right.
-- lead = { Room = id, Kind = kind? } | { Icon = iconName } (40 px). Returns (row, textLabel, button?).
function P.Row(parent: Instance, text: string, btn: { [string]: any }?, lead: { [string]: any }?)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), AutomaticSize = Enum.AutomaticSize.Y }, parent)
	local btnW = if btn then (btn.Width or 120) else 0
	local leadW = if lead then 48 else 0
	if lead then
		local holder = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(44, 44) }, row)
		local img = if lead.Room then P.RoomImage(holder, lead.Room, 44, lead.Kind) else Kit.Icon(holder, lead.Icon, UDim2.fromOffset(44, 44))
		img.AnchorPoint, img.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	end
	local label = P.Text(row, text)
	label.Position = UDim2.fromOffset(leadW, 0)
	label.Size = UDim2.new(1, -(btnW + 8 + leadW), 0, 48)
	label.TextYAlignment = Enum.TextYAlignment.Center
	local button
	if btn then
		btn.Size = UDim2.fromOffset(btnW, 48)
		button = Kit.Button(row, btn)
		button.Instance.AnchorPoint = Vector2.new(1, 0.5)
		button.Instance.Position = UDim2.new(1, 0, 0.5, 0)
	end
	return row, label, button
end

-- Wrapping row of small "icon + number" chips (odds), growing downward.
function P.ChipFlow(parent: Instance, order: number): Frame
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, f)
	return f
end

function P.Chip(flow: Instance, order: number, art: (Instance) -> GuiObject, text: string, color: Color3, tip: string, tipColor: Color3?, rarity: string?)
	local c = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = order, Active = true }, flow)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, c)
	art(c).LayoutOrder = 1
	local l = Kit.Label(c, text, Theme.TextSize.Caption + 1, color, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 26), false, 2
	Kit.Tip(c, tip, tipColor)
	if rarity == "Secret" then Kit.Prismatic(l) end
	return c
end

-- Base values supplied by the server, for room cards and the world inspector.
-- Specials with more context remain available as an ability tooltip.
function P.RoomStats(flow: Instance, def: any)
	for i, stat in {
		{ "Heal", def.BaseHealth, "Base defender health" },
		{ "Sword", def.BaseDamage, if def.DamagePerSecond then "Base damage per second" else "Base damage per hit" },
		{ "Defender", def.UnitCount, "Defender units" },
	} do
		if type(stat[2]) == "number" then
			P.Chip(flow, i, function(p) return Kit.Icon(p, stat[1], UDim2.fromOffset(22, 22)) end, tostring(stat[2]) .. (if i == 2 and def.DamagePerSecond then "/s" else ""), Theme.TextPrimary, stat[3])
		end
	end
	for i, stat in { { "Sword", def.SupportDamage, "Bonus damage" }, { "Heal", def.SupportHealth, "Bonus defender health" } } do
		if type(stat[2]) == "number" then
			P.Chip(flow, i + 3, function(p) return Kit.Icon(p, stat[1], UDim2.fromOffset(22, 22)) end, "+" .. P.Pct(stat[2]), Theme.TextPrimary, stat[3])
		end
	end
	if type(def.Exchange) == "number" then
		P.Chip(flow, 0, function(p) return Kit.Icon(p, "Exchange", UDim2.fromOffset(22, 22)) end, string.format("x%.2g", def.Exchange), Theme.Gold, "Base vault exchange")
	end
end

-- Icon + text on one line (heading rows of the panels).
function P.IconLine(parent: Instance, icon: string, text: string, order: number, color: Color3?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	Kit.Icon(f, icon, UDim2.fromOffset(28, 28)).LayoutOrder = 1
	local l = Kit.Label(f, text, Theme.TextSize.Body, color or Theme.TextMuted, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 32), false, 2
	return f
end

-- Modal shell. Returns { Gui, Panel, Title, Show(bool), Content(name) -> ScrollingFrame, Tabs }.
function P.Shell(tabNames: { string }, onTab: (string) -> ())
	local gui = Kit.Screen("Panels", 20)
	gui.Enabled = false
	local dim = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, gui)
	Kit.Sprite(dim, "Feedback.Scrim", { Name = "Scrim", Position = UDim2.fromOffset(-400, -400), Size = UDim2.new(1, 800, 1, 800), ImageTransparency = 0.2, ScaleType = Enum.ScaleType.Stretch, ZIndex = 0 })
	local panel = Kit.Panel(dim, { Sprite = "Large", Pad = Vector2.new(8, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.92) })
	panel.Active = true
	make("UISizeConstraint", { MaxSize = Vector2.new(900, 680) }, panel)

	local tabHeight = 56
	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52) }, panel)
	local titleBar = Kit.Panel(head, { Sprite = "TitleBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.6, -24, 1, 0) })
	local title = Kit.Label(titleBar, if tabNames[1] == "Bag" then "Inventory" else "Index", Theme.TextSize.Title, Theme.TextPrimary, true)
	title.Size = UDim2.fromScale(1, 1)
	title.TextScaled, title.TextTruncate = true, Enum.TextTruncate.AtEnd
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = Theme.TextSize.Title }, title)
	local self = { Gui = gui, Panel = panel, Title = title, Tabs = {}, Scrolls = {} }
	local close = Kit.CloseButton(head, UDim2.fromOffset(52, 52), function()
		gui.Enabled = false
	end)
	close.Instance.AnchorPoint = Vector2.new(1, 0)
	close.Instance.Position = UDim2.fromScale(1, 0)

	local tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, tabHeight), Visible = #tabNames > 1 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	for _, name in tabNames do
		self.Tabs[name] = Kit.Button(tabs, { Text = name, Icon = TAB_ICON[name] or name, IconLayout = "Row", Style = "Tab", Size = UDim2.new(1 / #tabNames, -8 * (#tabNames - 1) / #tabNames - 1, 0, tabHeight), TextSize = 20, OnClick = function()
			onTab(name)
		end })
		local tabLabel = self.Tabs[name].Instance:FindFirstChild("Label")
		tabLabel.TextScaled = true
		make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 20 }, tabLabel)
		local scroll = make("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, if #tabNames > 1 then tabHeight + 66 else 58),
			Size = UDim2.new(1, 0, 1, -(if #tabNames > 1 then tabHeight + 66 else 58)),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 10,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, panel)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		make("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 6) }, scroll)
		self.Scrolls[name] = scroll
	end
	return self
end

-- Prefer three columns, retaining usable cards on a narrow portrait phone.
function P.Columns(scroll: ScrollingFrame): number
	local width = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01)
	if width < 1 then width = workspace.CurrentCamera.ViewportSize.X / math.max(Scale.Value, 0.01) * 0.85 end
	return if width >= 450 then 3 else 2
end

-- Clears a scroll area but keeps its scroll position.
function P.Reset(scroll: ScrollingFrame)
	local y = scroll.CanvasPosition
	for _, c in scroll:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	return y
end

return P
