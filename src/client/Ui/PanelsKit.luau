-- Shared pieces of the Bag / Index / Keeper panels: rarity colours,
-- text helpers, list cards and the modal shell (title, tabs, scroll area).
local Theme = require(script.Parent.Theme)
local Percent = require(script.Parent.Percent)
local Scale = require(script.Parent.Scale)
local Kit = require(script.Parent.Kit)
local Atlas = require(script.Parent.Atlas)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)

local make = Kit.Make

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

-- Auto-height card with a vertical list inside (PanelSmall, or the tier's card frame when
-- `rarity` names one) .
function P.Card(parent: Instance, order: number?, rarity: string?, sprite: string?): Frame
	local f = Kit.Panel(parent, {
		Sprite = sprite or "Small",
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
	if (Atlas :: any)[roomId] then
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

-- The one tab component (Tab.On / Tab.Off): icon and label centred together, same text size everywhere.
function P.TabButton(parent: Instance, opts: { [string]: any })
	local btn = Kit.Button(parent, { Text = opts.Text, Icon = opts.Icon, IconLayout = "Row", Style = "Tab", Size = opts.Size, TextSize = if Scale.Phone then 22 else 28, OnClick = opts.OnClick })
	local label = btn.Instance:FindFirstChild("Label") :: TextLabel
	local icon = btn.Icon
	local pad = label:FindFirstChildOfClass("UIPadding") :: UIPadding
	label.TextXAlignment = Enum.TextXAlignment.Left
	local function place()
		local sc = math.max(Scale.Value, 0.01)
		local w, iw, tw = btn.Instance.AbsoluteSize.X / sc, icon.AbsoluteSize.X / sc, label.TextBounds.X / sc
		local x = math.max(10, (w - iw - 10 - tw) / 2)
		icon.Position = UDim2.new(0, x, 0.5, 0)
		pad.PaddingLeft = UDim.new(0, x + iw + 10)
	end
	for _, signal in { btn.Instance:GetPropertyChangedSignal("AbsoluteSize"), label:GetPropertyChangedSignal("TextBounds"), label:GetPropertyChangedSignal("TextSize") } do
		signal:Connect(place)
	end
	task.defer(place)
	return btn
end

-- Modal shell (Bag / Index / Upgrades): the shared chrome (Kit.ModalChrome), a tab row of Tab.On / Tab.Off buttons and
-- one scroll area per tab inside a Panel.Section well. reserveRow keeps the tab row for a caller-made sub-tab row
-- (P.TabRow(scroll)). Returns { Gui, Panel, Title, Show(bool), Tabs, Scrolls, Layout }.
local PAD_X, PAD_TOP, PAD_BOTTOM, TAB_H = 22, 64, 26, 78
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
	local chrome = Kit.ModalChrome(dim, if tabNames[1] == "Bag" then "Inventory" else "Index", function()
		gui.Enabled = false
	end)
	local panel = chrome.Root
	panel.Name = "Modal"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	local hasRow = reserveRow == true or #tabNames > 1
	-- The tab row sits in the header band of Panel.Modal; the content rect is the dark well below it.
	local tabs = make("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(PAD_X, 8), Size = UDim2.new(1, -PAD_X * 2, 0, TAB_H), Visible = hasRow }, panel)
	if #tabNames > 1 then
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	end
	local well = make("Frame", { Name = "Well", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(PAD_X, PAD_TOP), Size = UDim2.new(1, -PAD_X * 2, 1, -PAD_TOP - PAD_BOTTOM) }, panel)
	self = { Gui = gui, Panel = panel, Title = chrome.Title, Tabs = {}, Scrolls = {}, Well = well, TabRow = tabs }

	function self.Layout()
		local view = gui.AbsoluteSize / math.max(Scale.Value, 0.01)
		local width = math.min(if Scale.Phone then 1000 else math.max(1080, view.X * 0.63), view.X - 24)
		local overhang = chrome.Layout(width)
		-- Plate + modal sit between a small top margin and the navigation row.
		-- Phones start below the currency pill so the title plate never covers it.
		local top = if Scale.Phone then 64 else 100
		local available = view.Y - (if Scale.Phone then 116 else 170) - top
		local height = math.max(math.min(if Scale.Phone then 640 else math.max(720, view.Y * 0.66), available - overhang), 150)
		panel.Size = UDim2.fromOffset(width, height)
		panel.Position = UDim2.new(0.5, 0, 0, top + overhang + math.max(0, (available - overhang - height) / 2))
		local rowH = if Scale.Phone then 50 else TAB_H
		-- The tab row sits just below the title plate's lower half, over the top of the well.
		local tabY = if Scale.Phone then 28 else 44
		tabs.Position, tabs.Size = UDim2.fromOffset(PAD_X, tabY), UDim2.new(1, -PAD_X * 2, 0, rowH)
		local y = if hasRow then tabY + rowH + 8 else (if Scale.Phone then PAD_TOP - 4 else PAD_TOP)
		well.Position, well.Size = UDim2.fromOffset(PAD_X, y), UDim2.new(1, -PAD_X * 2, 1, -y - PAD_BOTTOM)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(self.Layout)
	Scale.Changed:Connect(self.Layout)

	for _, name in tabNames do
		if #tabNames > 1 then
			self.Tabs[name] = P.TabButton(tabs, { Text = if name == "Keeper" then "Permanent Upgrades" else name, Icon = TAB_ICON[name] or name, Size = UDim2.new(1 / #tabNames, -10 * (#tabNames - 1) / #tabNames - 1, 1, 0), OnClick = function()
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
			ScrollBarThickness = 12,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, well)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroll)
		make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 70) }, scroll)
		self.Scrolls[name] = scroll
		tabRows[scroll] = tabs
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
