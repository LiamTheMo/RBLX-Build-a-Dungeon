-- Small UI kit: Screen, Panel, Label, Pill, Icon, Rarity, Perks, Button, Bar, Toggle, Slider.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local IconIds = require(ReplicatedStorage.Shared.UI.IconIds)
local Theme = require(script.Parent.Theme)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Sound = require(script.Parent.Sound)

local Kit = {}

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end
Kit.Make = make

function Kit.Corner(parent: Instance, radius: UDim?)
	return make("UICorner", { CornerRadius = radius or Theme.CornerButton }, parent)
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return make("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Kit.Screen(name: string, order: number?): ScreenGui
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = order or 1,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	Scale.Attach(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Kit.Panel(parent: Instance, props: { [string]: any }?): Frame
	local f = make("Frame", { BackgroundColor3 = Theme.BgDeep, BorderSizePixel = 0 }, parent)
	for k, v in props or {} do
		f[k] = v
	end
	Kit.Corner(f, Theme.CornerPanel)
	Kit.Stroke(f)
	return f
end

function Kit.Label(parent: Instance, text: string, size: number?, color: Color3?, heading: boolean?): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or Theme.TextSize.Body,
		TextColor3 = color or Theme.TextPrimary,
		FontFace = if heading then Theme.HeadingFont else Theme.BodyFont,
		TextWrapped = true,
	}, parent)
end

-- Pill label that grows with its text.
function Kit.Pill(parent: Instance, text: string, bg: Color3, fg: Color3, height: number?): TextLabel
	local p = make("TextLabel", {
		BackgroundColor3 = bg,
		TextColor3 = fg,
		Text = text,
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.HeadingFont,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height or 20),
		BorderSizePixel = 0,
	}, parent)
	Kit.Corner(p, Theme.CornerPill)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, p)
	return p
end

-- Drawn glyphs for icons that have no uploaded image (check mark, padlock).
function Kit.Check(parent: Instance, size: UDim2?, color: Color3?): Frame
	local root = make("Frame", { BackgroundTransparency = 1, Size = size or UDim2.fromOffset(24, 24) }, parent)
	for _, leg in { { 0.3, 0.62, 0.17, 0.38, -45 }, { 0.58, 0.48, 0.17, 0.75, 45 } } do
		local f = make("Frame", {
			BackgroundColor3 = color or Theme.Success,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(leg[1], leg[2]),
			Size = UDim2.fromScale(leg[3], leg[4]),
			Rotation = leg[5],
		}, root)
		Kit.Corner(f, UDim.new(0.5, 0))
	end
	return root
end

function Kit.LockGlyph(parent: Instance, size: UDim2?, color: Color3?): Frame
	local root = make("Frame", { BackgroundTransparency = 1, Size = size or UDim2.fromOffset(18, 18) }, parent)
	local c = color or Theme.DisabledText
	local body = make("Frame", { BackgroundColor3 = c, BorderSizePixel = 0, Position = UDim2.fromScale(0.12, 0.45), Size = UDim2.fromScale(0.76, 0.5) }, root)
	Kit.Corner(body, UDim.new(0.2, 0))
	local arc = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.27, 0.05), Size = UDim2.fromScale(0.46, 0.55) }, root)
	Kit.Corner(arc, UDim.new(0.5, 0))
	make("UIStroke", { Color = c, Thickness = 2.5 }, arc)
	return root
end

local FALLBACK = { Coin = "$", Vault = "V", Build = "B", Shop = "S", Sword = "/", Shield = "D", Visitor = "V", Clock = "T", Settings = "*", Challenger = "C", Upgrade = "^", Cross = "X", Warn = "!" }

-- Icon by IconIds name ("Coin", "Vault", ...) as an ImageLabel; drawn glyph for
-- "Check"/"Lock"; a short text fallback when the id is missing.
function Kit.Icon(parent: Instance, name: string, size: UDim2?, color: Color3?): any
	local sz = size or UDim2.fromOffset(32, 32)
	if name == "Check" then
		return Kit.Check(parent, sz, color)
	elseif name == "Lock" then
		return Kit.LockGlyph(parent, sz, color)
	end
	local id = (IconIds :: any)[name]
	if id then
		return make("ImageLabel", { BackgroundTransparency = 1, Image = id, Size = sz, ScaleType = Enum.ScaleType.Fit }, parent)
	end
	local t = Kit.Label(parent, FALLBACK[name] or name, 20, color or Theme.TextPrimary, true)
	t.Size = sz
	t.TextScaled = true
	return t
end

-- Rarity badge: name on the rarity colour (text always names the rarity).
function Kit.Rarity(parent: Instance, rarity: string?): TextLabel
	local r = if rarity and Theme.Rarity[rarity] then rarity else "Common"
	return Kit.Pill(parent, r, Theme.Rarity[r], Theme.DangerText, 18)
end

local PERK_ICON = { Coins = "Coin", Loot = "Vault", Xp = "Upgrade" }
local PERK_NAME = { Coins = "coins", Loot = "loot", Xp = "XP" }

-- Row of perk icons (plus "+5% coins" text unless compact).
function Kit.Perks(parent: Instance, perks: { any }?, compact: boolean?): Frame
	local f = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18) }, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, f)
	for i, p in perks or {} do
		Kit.Icon(f, PERK_ICON[p.Kind] or "Upgrade", UDim2.fromOffset(16, 16)).LayoutOrder = i * 2
		if not compact then
			local l = Kit.Label(f, ("+%d%% %s"):format(math.floor((p.Amount or 0) * 100 + 0.5), PERK_NAME[p.Kind] or ""), Theme.TextSize.Caption, Theme.TextPrimary, true)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.fromOffset(0, 18)
			l.TextWrapped = false
			l.LayoutOrder = i * 2 + 1
		end
	end
	return f
end

local STYLES = {
	Primary = { Theme.Gold, Theme.TextOnGold },
	Secondary = { Theme.BgRaised, Theme.TextPrimary },
	Success = { Theme.Success, Theme.DangerText },
	Danger = { Theme.Danger, Theme.DangerText },
	Cancel = { Theme.BgRaised, Theme.TextPrimary },
}

local function shade(c: Color3, amount: number): Color3
	return if amount >= 0 then c:Lerp(Color3.new(1, 1, 1), amount) else c:Lerp(Color3.new(0, 0, 0), -amount)
end

-- Touch targets stay >= 44 px after UIScale (phones scale below 1).
function Kit.MinTouch(b: GuiObject)
	local minSize = make("UISizeConstraint", {}, b)
	local function apply()
		local m = if Scale.Phone or UserInputService.TouchEnabled then 44 / math.max(Scale.Value, 0.1) else 0
		minSize.MinSize = Vector2.new(m, m)
	end
	apply()
	local conn = Scale.Changed:Connect(apply)
	b.Destroying:Once(function()
		conn:Disconnect()
	end)
end

-- opts: Text, Style (Primary/Secondary/Success/Danger/Cancel), Size (UDim2, default 140x56;
-- never below 44 px), OnClick, Icon (IconIds name, "Check", "Lock"), IconLayout ("Column" =
-- icon above the label, default; "Row" = icon at the left), Edge (stroke colour).
-- Returns { Instance, Stroke, Icon, SetText, SetEnabled(on, reasonText?, locked?),
-- SetSelected, SetStyle, SetEdge, SetBadge(n) }.
function Kit.Button(parent: Instance, opts: { [string]: any })
	local style = STYLES[opts.Style or "Secondary"]
	local size: UDim2 = opts.Size or UDim2.fromOffset(140, 56)
	size = UDim2.new(
		size.X.Scale,
		if size.X.Scale == 0 then math.max(size.X.Offset, 44) else size.X.Offset,
		size.Y.Scale,
		if size.Y.Scale == 0 then math.max(size.Y.Offset, 44) else size.Y.Offset
	)

	local b = make("TextButton", {
		Text = opts.Text or "",
		AutoButtonColor = false,
		Size = size,
		BackgroundColor3 = style[1],
		TextColor3 = style[2],
		TextSize = opts.TextSize or Theme.TextSize.Button,
		FontFace = Theme.HeadingFont,
		TextWrapped = true,
		BorderSizePixel = 0,
		LayoutOrder = opts.LayoutOrder or 0,
	}, parent)
	Kit.Corner(b)
	local stroke = Kit.Stroke(b)
	local pad = make("UIPadding", {}, b)
	Kit.MinTouch(b)

	local self: any = { Instance = b, Stroke = stroke }
	local enabled, selected, hover, baseText = true, false, false, opts.Text or ""
	local edge: Color3? = opts.Edge
	local scale = make("UIScale", {}, b)

	local icon: any = nil
	if opts.Icon then
		local row = opts.IconLayout == "Row"
		icon = Kit.Icon(b, opts.Icon, UDim2.new(0, 0, if row then 0.6 else 0.5, 0), style[2])
		make("UIAspectRatioConstraint", { DominantAxis = Enum.DominantAxis.Height }, icon)
		icon.AnchorPoint = if row then Vector2.new(0, 0.5) else Vector2.new(0.5, 0)
		icon.Position = if row then UDim2.new(0, 12, 0.5, 0) else UDim2.new(0.5, 0, 0.07, 0)
		if row then
			pad.PaddingLeft = UDim.new(0, 44)
		else
			b.TextYAlignment = Enum.TextYAlignment.Bottom
			pad.PaddingBottom = UDim.new(0, 4)
		end
		self.Icon = icon
	end

	local function paint(press: boolean?)
		local fill, text = style[1], style[2]
		if not enabled then
			fill, text = Theme.Disabled, Theme.DisabledText
		elseif press then
			fill = shade(fill, -0.1)
		elseif hover then
			fill = shade(fill, 0.08)
		end
		b.BackgroundColor3, b.TextColor3 = fill, text
		stroke.Color = if selected then Theme.Gold else (edge or Theme.Stroke)
		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = if enabled then 0 else 0.55
		end
		local target = if not enabled then 1 elseif press then 0.96 elseif hover then 1.03 else 1
		Settings.Tween(scale, TweenInfo.new(press and 0.06 or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
	end

	b.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			hover = true
			paint()
		end
	end)
	b.MouseLeave:Connect(function()
		hover = false
		paint()
	end)
	b.MouseButton1Down:Connect(function()
		paint(true)
	end)
	b.MouseButton1Up:Connect(function()
		paint()
	end)
	b.Activated:Connect(function()
		if enabled and opts.OnClick then
			Sound.Play("Click")
			opts.OnClick()
		end
	end)

	local function refreshText()
		b.Text = if selected and baseText ~= "" then baseText .. " (Selected)" else baseText
	end
	local lock: any = nil
	function self.SetText(text: string)
		baseText = text
		refreshText()
	end
	function self.SetEnabled(on: boolean, reason: string?, locked: boolean?)
		enabled = on
		b.Active = on
		if not on and reason then
			b.Text = reason
		else
			refreshText()
		end
		-- Lock glyph beside the reason ("Need 50 more").
		local showLock = locked == true and not on and not icon
		if showLock and not lock then
			lock = Kit.Icon(b, "Lock", UDim2.fromOffset(18, 18), Theme.DisabledText)
			lock.AnchorPoint = Vector2.new(0, 0.5)
			lock.Position = UDim2.new(0, 10, 0.5, 0)
		end
		if lock then
			lock.Visible = showLock
			pad.PaddingLeft = UDim.new(0, if showLock then 30 else 0)
		end
		paint()
	end
	function self.SetSelected(on: boolean)
		selected = on
		refreshText()
		paint()
	end
	function self.SetStyle(name: string)
		style = STYLES[name]
		paint()
	end
	function self.SetEdge(color: Color3?)
		edge = color
		paint()
	end
	local badge: TextLabel? = nil
	function self.SetBadge(n: number)
		if n <= 0 then
			if badge then
				badge.Visible = false
			end
			return
		end
		if not badge then
			badge = Kit.Pill(b, "", Theme.Gold, Theme.TextOnGold, 22)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 6, 0, -6)
			badge.ZIndex = 5
			Kit.Stroke(badge, Theme.Stroke, 2)
		end
		badge.Visible = true
		badge.Text = if n > 99 then "99+" else tostring(n)
	end
	return self
end

-- Pill progress bar with text over it. Returns { Instance, Set(fraction, text, danger?) }.
function Kit.Bar(parent: Instance, size: UDim2, color: Color3?)
	local bar = make("Frame", { BackgroundColor3 = Theme.BgPanel, Size = size, BorderSizePixel = 0 }, parent)
	Kit.Corner(bar, Theme.CornerPill)
	Kit.Stroke(bar, Theme.Stroke, 2)
	local fill = make("Frame", { BackgroundColor3 = color or Theme.Success, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, bar)
	Kit.Corner(fill, Theme.CornerPill)
	local label = Kit.Label(bar, "", 14, Theme.TextPrimary, true)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.TextStrokeColor3 = Theme.Stroke
	label.TextStrokeTransparency = 0.3
	local self = { Instance = bar }
	function self.Set(fraction: number, text: string, danger: boolean?)
		fraction = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = if danger then Theme.Danger else (color or Theme.Success)
		label.Text = text
	end
	return self
end

-- Switch 84x44: check mark + "On" / "Off" word. Returns { Instance, Set(on) }.
function Kit.Toggle(parent: Instance, initial: boolean, onChange: (boolean) -> ())
	local on = initial
	local b = make("TextButton", {
		Size = UDim2.fromOffset(84, 44),
		AutoButtonColor = false,
		TextSize = 18,
		FontFace = Theme.HeadingFont,
		TextXAlignment = Enum.TextXAlignment.Right,
		BorderSizePixel = 0,
	}, parent)
	Kit.Corner(b, Theme.CornerPill)
	Kit.Stroke(b)
	Kit.MinTouch(b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }, b)
	local check = Kit.Check(b, UDim2.fromOffset(22, 22), Theme.DangerText)
	check.AnchorPoint = Vector2.new(0, 0.5)
	check.Position = UDim2.new(0, 0, 0.5, 0)
	local function paint()
		b.Text = if on then "On" else "Off"
		b.BackgroundColor3 = if on then Theme.Success else Theme.Disabled
		b.TextColor3 = if on then Theme.DangerText else Theme.DisabledText
		check.Visible = on
	end
	paint()
	b.Activated:Connect(function()
		on = not on
		paint()
		Sound.Play("Click")
		onChange(on)
	end)
	return {
		Instance = b,
		Set = function(v: boolean)
			on = v
			paint()
		end,
	}
end

-- Horizontal slider 0..1 with a percent readout. Returns { Instance, Set(v) }.
function Kit.Slider(parent: Instance, initial: number, onChange: (number) -> ())
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(340, 44) }, parent)
	local track = make("Frame", {
		BackgroundColor3 = Theme.BgRaised,
		Size = UDim2.fromOffset(260, 12),
		Position = UDim2.fromOffset(0, 16),
		BorderSizePixel = 0,
	}, root)
	Kit.Corner(track, Theme.CornerPill)
	Kit.Stroke(track, Theme.Stroke, 2)
	local fill = make("Frame", { BackgroundColor3 = Theme.Gold, BorderSizePixel = 0 }, track)
	Kit.Corner(fill, Theme.CornerPill)
	local thumb = make("Frame", {
		BackgroundColor3 = Theme.TextPrimary,
		Size = UDim2.fromOffset(32, 32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
	}, track)
	Kit.Corner(thumb, Theme.CornerPill)
	Kit.Stroke(thumb)
	local readout = Kit.Label(root, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	readout.Position = UDim2.fromOffset(272, 0)
	readout.Size = UDim2.fromOffset(68, 44)

	local value = initial
	local function paint()
		fill.Size = UDim2.new(value, 0, 1, 0)
		thumb.Position = UDim2.new(value, 0, 0.5, 0)
		readout.Text = math.floor(value * 100 + 0.5) .. "%"
	end
	paint()

	-- 44 px hit area over the track and thumb.
	local hitH = if Scale.Phone or UserInputService.TouchEnabled then math.max(44, 44 / math.max(Scale.Value, 0.1)) else 44
	local hit = make("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(260 + 32, hitH),
		Position = UDim2.fromOffset(-16, 6 - hitH / 2),
		ZIndex = 5,
	}, track)
	local dragging = false
	local function setFrom(x: number)
		value = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		value = math.floor(value * 100 + 0.5) / 100
		paint()
		onChange(value)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return {
		Instance = root,
		Set = function(v: number)
			if not dragging then
				value = v
				paint()
			end
		end,
	}
end

return Kit
