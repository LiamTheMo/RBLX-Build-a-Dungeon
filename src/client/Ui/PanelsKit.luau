-- Shared pieces of the Bag / Index / Keeper panels: rarity colours,
-- text helpers, list cards and the modal shell (title, tabs, scroll area).
local Theme = require(script.Parent.Theme)
local Percent = require(script.Parent.Percent)
local Scale = require(script.Parent.Scale)
local Kit = require(script.Parent.Kit)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)

local make = Kit.Make
local V6: any = Sprites.Ids6

local P = {}
local TAB_ICON = { Chests = "Bag", Index = "Collection", Keeper = "Upgrade", Threat = "T1" }

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

-- Auto-height container with a vertical list inside. It has NO art of its own (a sprite cannot grow with its content without
-- being stretched): put sprite rows (Kit.Panel Sprite = "Row" / "Small" with Fit = "Width") or whole cards inside it.
function P.Card(parent: Instance, order: number?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0 }, parent)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, f)
	return f
end

-- Image for a room id (its sprite, else a kind icon); parent gets it at `size`.
function P.RoomImage(parent: Instance, roomId: string, size: number, kind: string?): any
	-- The owner's room icons come first: whole square images, Fit (never stretched).
	local spec = (V6.RoomIcons :: any)[roomId]
	local owner = spec and spec.Id
	if owner and Sprites.Ok(owner) then
		local img = make("ImageLabel", { Name = "RoomImage", BackgroundTransparency = 1, Image = owner, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit }, parent)
		Sprites.Watch(owner, function()
			Kit.Neutral(img)
		end, img)
		return img
	end
	if (V6.Icons :: any)[roomId] then
		local img = Kit.Icon(parent, roomId, UDim2.fromOffset(size, size))
		img.Name = "RoomImage"
		return img
	end
	local id = SpriteIds.Rooms[roomId]
	if id and Sprites.Ok(id) then
		local img = make("ImageLabel", { Name = "RoomImage", BackgroundTransparency = 1, Image = id, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit }, parent)
		Sprites.Watch(id, function()
			Kit.Neutral(img)
		end, img)
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

-- Section heading with the Misc.Divider sprite under it. Returns the container (the text is its "Text" child).
function P.Section(parent: Instance, text: string, order: number)
	local phone = Scale.Phone
	local f = make("Frame", { Name = "Section", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if phone then 36 else 58), LayoutOrder = order }, parent)
	local l = P.Text(f, text, Theme.TextSize.Heading, Theme.Gold, true, 0)
	l.Name, l.Size, l.TextXAlignment = "Text", UDim2.new(1, 0, 0, 34), Enum.TextXAlignment.Center
	Kit.Stroke(l, Theme.Stroke, 2)
	local d = Kit.Sprite(f, "Misc.Divider", { Name = "Divider", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(420, 30), ScaleType = Enum.ScaleType.Fit })
	d.ZIndex = 2
	d.Visible = not phone
	return f
end

-- Empty state: an empty Slot.Empty cell with a short caption.
function P.Empty(parent: Instance, text: string, order: number): Frame
	local f = make("Frame", { Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	Kit.Sprite(f, "Slot.Empty", { Size = UDim2.fromOffset(80, 80), LayoutOrder = 1 })
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
	local c = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), LayoutOrder = order, Active = true }, flow)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, c)
	art(c).LayoutOrder = 1
	local l = Kit.Label(c, text, Theme.TextSize.Body, color, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 34), false, 2
	Kit.Stroke(l, Theme.Stroke, 2)
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
			P.Chip(flow, i, function(p) return Kit.Icon(p, stat[1], UDim2.fromOffset(30, 30)) end, tostring(stat[2]) .. (if i == 2 and def.DamagePerSecond then "/s" else ""), Theme.TextPrimary, stat[3])
		end
	end
	for i, stat in { { "Sword", def.SupportDamage, "Bonus damage" }, { "Heal", def.SupportHealth, "Bonus defender health" } } do
		if type(stat[2]) == "number" then
			P.Chip(flow, i + 3, function(p) return Kit.Icon(p, stat[1], UDim2.fromOffset(30, 30)) end, "+" .. P.Pct(stat[2]), Theme.TextPrimary, stat[3])
		end
	end
	if type(def.Exchange) == "number" then
		P.Chip(flow, 0, function(p) return Kit.Icon(p, "Exchange", UDim2.fromOffset(30, 30)) end, string.format("x%.2g", def.Exchange), Theme.Gold, "Base vault exchange")
	end
end

-- Icon + text on one line (heading rows of the panels).
function P.IconLine(parent: Instance, icon: string, text: string, order: number, color: Color3?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	Kit.Icon(f, icon, UDim2.fromOffset(34, 34)).LayoutOrder = 1
	local l = Kit.Label(f, text, Theme.TextSize.Body, color or Theme.TextMuted, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 32), false, 2
	return f
end

-- The one tab component (Tab.On / Tab.Off, or Tab.WideOn / Tab.WideOff with opts.Wide): icon and label centred together, one
-- whole sprite per state. opts.Size is the hit box (the art fits inside it, centred); the label size follows the art's height.
function P.TabButton(parent: Instance, opts: { [string]: any })
	local btn = Kit.Button(parent, { Text = opts.Text, Icon = opts.Icon, IconLayout = "Row", Style = "Tab", Variant = if opts.Wide then "Wide" else nil, Size = opts.Size, TextSize = 28, OnClick = opts.OnClick })
	local label = btn.Instance:FindFirstChild("Label", true) :: TextLabel
	local icon = btn.Icon
	local content = btn.Content
	local pad = label:FindFirstChildOfClass("UIPadding") :: UIPadding
	label.TextScaled, label.TextWrapped = false, false
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit:Destroy()
	end
	label.TextXAlignment = Enum.TextXAlignment.Left
	local function place()
		local sc = math.max(Scale.Value, 0.01)
		local w, h = content.AbsoluteSize.X / sc, content.AbsoluteSize.Y / sc
		if w < 2 or h < 2 then
			return
		end
		label.TextSize = 24 -- one fixed tab label size (the tab art is the band's height)
		local iw = icon.AbsoluteSize.X / sc
		local tw = label.TextBounds.X / sc
		local x = math.max(0, (w - iw - 8 - tw) / 2)
		icon.Position = UDim2.new(0, x, 0.5, 0)
		pad.PaddingLeft = UDim.new(0, x + iw + 8)
	end
	for _, signal in { content:GetPropertyChangedSignal("AbsoluteSize"), label:GetPropertyChangedSignal("TextBounds") } do
		signal:Connect(place)
	end
	task.defer(place)
	return btn
end

-- Two wide tabs side by side, centred with a small gap (like the reference): each hit box is the band's height times the
-- Tab.Wide* aspect, so the art is never stretched. `row` holds a centred horizontal UIListLayout.
function P.CentreTabs(row: GuiObject, tabs: { any })
	local function fit()
		local h = row.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		if h < 2 then
			return
		end
		for _, t in tabs do
			t.Instance.Size = UDim2.fromOffset(math.floor(h * 4.15), h)
		end
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	Scale.Changed:Connect(fit)
	task.defer(fit)
end

-- Modal shell (Bag / Index / Upgrades): the shared chrome (Kit.ModalChrome: Panel.Modal, one whole image at its own aspect), a
-- tab row of Tab buttons in the art's header band and one scroll area per tab inside the art's Inner rect (the dark well).
-- reserveRow keeps the tab row for a caller-made sub-tab row (P.TabRow(scroll)). Returns { Gui, Panel, Title, Show(bool),
-- Tabs, Scrolls, Layout }.
local tabRows = setmetatable({}, { __mode = "k" })

-- The tab row frame above the well of this shell's scroll area (for sub-tabs of a single-tab shell).
function P.TabRow(scroll: Instance): Frame?
	return tabRows[scroll]
end

function P.Shell(tabNames: { string }, onTab: (string) -> (), reserveRow: boolean?)
	local gui = Kit.Screen("Panels", 20)
	gui.Enabled = false
	-- The dim layer leaves the bottom navigation row free (Bag / Index / Upgrades stay clickable); tapping the dim
	-- outside the modal dismisses it.
	-- One light dim for every modal, in its own screen below the HUD (never intercepts input, HUD stays bright).
	local dimGui = Kit.Screen("PanelsDim", 0)
	dimGui.ScreenInsets = Enum.ScreenInsets.None
	dimGui.Enabled = false
	Kit.Scrim(dimGui, 0.72, {})
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		dimGui.Enabled = gui.Enabled
	end)
	local dim = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -(Scale.Phone and 116 or 170)), BorderSizePixel = 0 }, gui)
	dim.Activated:Connect(function()
		gui.Enabled = false
	end)
	local self: any
	local hasRowEarly = reserveRow == true or #tabNames > 1
	local chrome = Kit.ModalChrome(dim, if tabNames[1] == "Bag" then "Inventory" else "Index", function()
		gui.Enabled = false
	end, if hasRowEarly then "Tabbed" else "Plain")
	local panel = chrome.Root
	panel.Name = "Modal"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	local hasRow = reserveRow == true or #tabNames > 1
	-- The tab row sits in the header band of Panel.Modal (above the Inner rect); the content rect is the dark well below it.
	local tabs = make("Frame", { Name = "Tabs", BackgroundTransparency = 1, Visible = hasRow }, panel)
	if #tabNames > 1 then
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 14) }, tabs)
	end
	local well = make("Frame", { Name = "Well", BackgroundTransparency = 1, ClipsDescendants = true }, panel)
	self = { Gui = gui, Panel = panel, Title = chrome.Title, Tabs = {}, Scrolls = {}, Well = well, TabRow = tabs }

	function self.Layout()
		local view = gui.AbsoluteSize / math.max(Scale.Value, 0.01)
		local reserve = if Scale.Phone then 116 else 170
		local top = if Scale.Phone then 64 else 100
		local available = view.Y - reserve - top
		local width = math.min(if Scale.Phone then 1000 else math.max(1080, view.X * 0.66), view.X - 24)
		local overhang = chrome.Layout(width)
		width = math.min(width, (available - overhang) * chrome.Ratio)
		overhang = chrome.Layout(width)
		width = math.min(width, (available - overhang) * chrome.Ratio)
		local height = width / chrome.Ratio
		panel.Size = UDim2.fromOffset(width, height)
		panel.Position = UDim2.new(0.5, 0, 0, top + overhang + math.max(0, (available - overhang - height) / 2))
		local bx, by, bw, bh = chrome.BodyRect(width, height)
		-- Header band: from just under the title plate's lower half to the top of the well.
		local k = width / chrome.Spec.Size.X
		local tabY, tabH = 48 * k, 66 * k
		tabs.Position, tabs.Size = UDim2.fromOffset(bx, tabY), UDim2.fromOffset(bw, tabH)
		well.Position, well.Size = UDim2.fromOffset(bx, by), UDim2.fromOffset(bw, bh)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(self.Layout)
	Scale.Changed:Connect(self.Layout)

	local wide = #tabNames == 2
	for _, name in tabNames do
		if #tabNames > 1 then
			self.Tabs[name] = P.TabButton(tabs, { Text = if name == "Keeper" then "Permanent" else name, Icon = TAB_ICON[name] or name, Wide = wide, Size = UDim2.new(1 / #tabNames, 0, 1, 0), OnClick = function()
				onTab(name)
			end })
		else
			self.Tabs[name] = { SetSelected = function() end }
		end
		local scroll = make("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 10,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, well)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroll)
		make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12) }, scroll)
		self.Scrolls[name] = scroll
		tabRows[scroll] = tabs
	end
	if wide then
		P.CentreTabs(tabs, { self.Tabs[tabNames[1]], self.Tabs[tabNames[2]] })
	end
	self.Layout()
	return self
end

-- Prefer three columns, retaining usable cards on a narrow portrait phone.
function P.Columns(scroll: ScrollingFrame): number
	local width = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01)
	if width < 1 then width = workspace.CurrentCamera.ViewportSize.X / math.max(Scale.Value, 0.01) * 0.85 end
	return if width >= 880 then 4 elseif width >= 450 then 3 else 2
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
