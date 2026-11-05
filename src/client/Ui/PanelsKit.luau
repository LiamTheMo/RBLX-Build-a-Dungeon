-- Shared pieces of the Loot / Collection / Keeper panels: rarity colours,
-- text helpers, list cards and the modal shell (title, tabs, scroll area).
local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local make = Kit.Make

local P = {}

P.RarityColor = {
	Common = Theme.TextMuted,
	Uncommon = Theme.Success,
	Rare = Color3.fromRGB(90, 160, 255),
	Mythic = Color3.fromRGB(190, 110, 255),
}

function P.Hex(c: Color3): string
	return "#" .. c:ToHex()
end

function P.Pct(f: number): string
	local v = math.floor(f * 1000 + 0.5) / 10
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

-- Auto-height card with a vertical list inside.
function P.Card(parent: Instance, order: number?): Frame
	local f = make("Frame", {
		BackgroundColor3 = Theme.BgPanel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 56),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
	}, parent)
	Kit.Corner(f)
	Kit.Stroke(f, Theme.Stroke, 2)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

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

-- Row: text block on the left, optional button on the right. Returns (row, textLabel, button?).
function P.Row(parent: Instance, text: string, btn: { [string]: any }?)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.Y }, parent)
	local btnW = if btn then (btn.Width or 120) else 0
	local label = P.Text(row, text)
	label.Size = UDim2.new(1, -(btnW + 8), 0, 44)
	label.TextYAlignment = Enum.TextYAlignment.Center
	local button
	if btn then
		btn.Size = UDim2.fromOffset(btnW, 44)
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
	local panel = Kit.Panel(dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.92) })
	panel.Active = true
	make("UISizeConstraint", { MaxSize = Vector2.new(820, 680) }, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, panel)

	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) }, panel)
	local title = P.Text(head, "", Theme.TextSize.Title, Theme.TextPrimary, true)
	title.Size = UDim2.new(1, -72, 1, 0)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.TextYAlignment = Enum.TextYAlignment.Center
	local self = { Gui = gui, Panel = panel, Title = title, Tabs = {}, Scrolls = {} }
	local close = Kit.Button(head, { Text = "X", Style = "Secondary", Size = UDim2.fromOffset(56, 56), OnClick = function()
		gui.Enabled = false
	end })
	close.Instance.AnchorPoint = Vector2.new(1, 0)
	close.Instance.Position = UDim2.fromScale(1, 0)

	local tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 48) }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	for _, name in tabNames do
		self.Tabs[name] = Kit.Button(tabs, { Text = name, Size = UDim2.fromOffset(186, 48), TextSize = 20, OnClick = function()
			onTab(name)
		end })
		local scroll = make("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 120),
			Size = UDim2.new(1, 0, 1, -120),
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
