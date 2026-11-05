-- Shared pieces of the Loot / Collection / Keeper panels: rarity colours,
-- text helpers, list cards and the modal shell (title, tabs, scroll area).
local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)

local make = Kit.Make

local P = {}

P.RarityColor = Theme.Rarity

function P.Hex(c: Color3): string
	return "#" .. c:ToHex()
end

function P.Pct(f: number): string
	local step = if f < 0.01 then 100 else 10 -- 0.02% needs two decimals
	local v = math.floor(f * 100 * step + 0.5) / step
	return (if v % 1 == 0 then tostring(math.floor(v)) else tostring(v)) .. "%"
end

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
	})
	local side = if rarity then 22 else 16
	make("UIPadding", { PaddingLeft = UDim.new(0, side), PaddingRight = UDim.new(0, side), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 18) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

-- Image for a room id (its sprite, else a kind icon); parent gets it at `size`.
function P.RoomImage(parent: Instance, roomId: string, size: number, kind: string?): any
	local id = SpriteIds.Rooms[roomId]
	if id and Sprites.Ok(id) then
		local img = make("ImageLabel", { Name = "RoomImage", BackgroundTransparency = 1, Image = id, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit }, parent)
		Sprites.Watch(id, function()
			img.Image = ""
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

function P.Section(parent: Instance, text: string, order: number)
	local l = P.Text(parent, text, Theme.TextSize.Heading, Theme.Gold, true, order)
	l.Size = UDim2.new(1, 0, 0, 36)
	return l
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

-- Modal shell. Returns { Gui, Panel, Title, Show(bool), Content(name) -> ScrollingFrame, Tabs }.
function P.Shell(tabNames: { string }, onTab: (string) -> ())
	local gui = Kit.Screen("Panels", 20)
	gui.Enabled = false
	local dim = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, gui)
	local panel = Kit.Panel(dim, { Sprite = "Large", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.92) })
	panel.Active = true
	make("UISizeConstraint", { MaxSize = Vector2.new(820, 680) }, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 18) }, panel)

	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) }, panel)
	local title = P.Text(head, "", Theme.TextSize.Title, Theme.TextPrimary, true)
	title.Size = UDim2.new(1, -72, 1, 0)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.TextYAlignment = Enum.TextYAlignment.Center
	local self = { Gui = gui, Panel = panel, Title = title, Tabs = {}, Scrolls = {} }
	local close = Kit.CloseButton(head, UDim2.fromOffset(56, 56), function()
		gui.Enabled = false
	end)
	close.Instance.AnchorPoint = Vector2.new(1, 0)
	close.Instance.Position = UDim2.fromScale(1, 0)

	local tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 52) }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	for _, name in tabNames do
		self.Tabs[name] = Kit.Button(tabs, { Text = name, Style = "Tab", Size = UDim2.fromOffset(186, 52), TextSize = 20, OnClick = function()
			onTab(name)
		end })
		local scroll = make("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 126),
			Size = UDim2.new(1, 0, 1, -126),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 8,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, panel)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		make("UIPadding", { PaddingRight = UDim.new(0, 12) }, scroll)
		self.Scrolls[name] = scroll
	end
	return self
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
