-- Small UI kit: Screen, Panel, Label, Pill, Icon, Rarity, Perks, Button, Bar, Toggle, Slider.
-- Owner rule: every UI visual is a AI design assistant sprite (SpriteIds / SpriteIds3 / SpriteIds4). Code only lays things out and
-- tints/fades the art; when a sprite is unusable the piece shows the minimal neutral image (Sprites.FallbackId), never a
-- code-drawn replacement shape.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local IconIds = require(script.Parent.IconIds)
local RarityColors = require(script.Parent.RarityColors)
local SpriteIds = require(script.Parent.SpriteIds)
local SpriteIds3 = require(script.Parent.SpriteIds3)
local Sprites = require(script.Parent.Sprites)
local Theme = require(script.Parent.Theme)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Sound = require(script.Parent.Sound)

local V4: any = Sprites.Ids4
local Kit = {}

-- Scroll bars: every ScrollingFrame wears the v4 thumb sprite (Roblox has no track image property).
local THUMB = V4.Controls.ScrollBarThumb.Id

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
		(i :: any).FontFace = Theme.BodyFont -- the one UI family; a prop below may still override it
	elseif class == "ScrollingFrame" then
		local s: any = i
		s.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		s.ScrollBarImageTransparency = 0
		s.TopImage, s.MidImage, s.BottomImage = THUMB, THUMB, THUMB
	end
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

-- Sprite skins ---------------------------------------------------------------
-- A skin is a spec (Id, optional SliceCenter, Size) drawn on an image object. Sliced skins get a SliceScale kept in
-- step with the object's size: "Uniform" scales the whole sprite to fit (pills, buttons, bars, rarity frames), "Border"
-- keeps the border near `cap` reference px (big panels). Reference px = screen px / UIScale, so desktop and phone look
-- alike. The scale is capped at 0.5 (Roblox drops right/bottom slices above ~0.5); v4 bands are >= 24 px so 0.3-0.5 is
-- the sweet spot.
local fitters = setmetatable({}, { __mode = "k" })

local function fit(img: GuiObject, spec: any, mode: string?, cap: number?, onScale: ((number) -> ())?)
	local activeSpec = spec
	local nudge = 0
	local function apply()
		local c = activeSpec.SliceCenter
		local a = img.AbsoluteSize / math.max(Scale.Value, 0.01)
		if a.X < 2 or a.Y < 2 then
			return
		end
		local s
		if mode == "Border" then
			s = math.min((cap or 14) / ((c.Min.X + c.Min.Y) / 2), 0.5)
		else
			s = math.min(a.X / activeSpec.Size.X, a.Y / activeSpec.Size.Y, 0.5)
		end
		-- The two borders must never overlap.
		s = math.min(s, 0.98 * a.X / (c.Min.X + activeSpec.Size.X - c.Max.X + 0.001), 0.98 * a.Y / (c.Min.Y + activeSpec.Size.Y - c.Max.Y + 0.001))
		local target: any = img
		target.SliceScale = s
		-- Re-assign SliceScale a moment after the last change: Studio sometimes leaves the right/bottom slices
		-- unrendered when it is only set once as the frame is laid out.
		nudge += 1
		local mine = nudge
		task.delay(0.1, function()
			if mine == nudge and img.Parent then
				target.SliceScale = math.max(0.001, s - 0.001)
			end
		end)
		if onScale then
			onScale(s)
		end
	end
	fitters[img] = function(nextSpec)
		activeSpec = nextSpec
		apply()
	end
	apply()
	img:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

-- Neutral image shown in place of an unusable sprite.
local function neutral(img: any)
	img.Image = Sprites.FallbackId
	local f = Sprites.Fallback
	if f and f.SliceCenter then
		img.ScaleType, img.SliceCenter = Enum.ScaleType.Slice, f.SliceCenter
		img.SliceScale = 0.15
	else
		img.ScaleType = Enum.ScaleType.Fit
	end
end
Kit.Neutral = neutral

-- Draws spec on img (ImageLabel/ImageButton). A missing or unloadable id shows the neutral image and returns false.
local function skin(img: any, spec: any, mode: string?, cap: number?, onFail: (() -> ())?, onScale: ((number) -> ())?): boolean
	if not spec or not Sprites.Ok(spec.Id) then
		neutral(img)
		return false
	end
	img.Image = spec.Id
	if spec.SliceCenter then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = spec.SliceCenter
		fit(img, spec, mode, cap, onScale)
	else
		img.ScaleType = if spec.Stretch then Enum.ScaleType.Stretch else Enum.ScaleType.Fit
	end
	Sprites.Watch(spec.Id, function()
		neutral(img)
		if onFail then
			onFail()
		end
	end)
	return true
end
Kit.Skin = skin

-- Sliced image whose SliceScale follows its HEIGHT only (bar fills / slider fills: their width changes with the value).
local function skinByHeight(img: any, spec: any)
	if not Sprites.Ok(spec.Id) then
		neutral(img)
		return
	end
	img.Image, img.ScaleType, img.SliceCenter = spec.Id, Enum.ScaleType.Slice, spec.SliceCenter
	local nudge = 0
	local function apply()
		local h = img.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		if h < 2 then
			return
		end
		local s = math.min(h / spec.Size.Y, 0.5)
		img.SliceScale = s
		nudge += 1
		local mine = nudge
		task.delay(0.1, function()
			if mine == nudge and img.Parent then
				img.SliceScale = math.max(0.001, s - 0.001)
			end
		end)
	end
	apply()
	img:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	Sprites.Watch(spec.Id, function()
		neutral(img)
	end)
end
Kit.SkinByHeight = skinByHeight

-- Spec lookup in the v4 set by dotted path ("Feedback.GlowSoft"); nil when missing.
function Kit.Spec(path: string): any
	local node: any = V4
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

-- A decorative sprite image (no input): path is a v4 spec path ("Feedback.GlowSoft"); props are ImageLabel properties.
-- Sliced specs stay "Uniform"-fitted to the object.
function Kit.Sprite(parent: Instance?, path: string, props: { [string]: any }?): any
	local img = make("ImageLabel", { Name = (string.match(path, "[^%.]+$")), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Image = "" }, nil)
	for k, v in props or {} do
		img[k] = v
	end
	skin(img, Kit.Spec(path), "Uniform", nil, nil)
	if props and props.ScaleType then
		img.ScaleType = props.ScaleType -- skin() picks Fit/Slice; an explicit choice (Stretch scrims) wins
	end
	img.Parent = parent
	return img
end

-- Soft light behind something (Feedback.GlowSoft, additive). Returns the image; size and place it.
function Kit.Glow(parent: Instance, color: Color3?, transparency: number?): any
	return Kit.Sprite(parent, "Feedback.GlowSoft", {
		ImageColor3 = color or Theme.Gold,
		ImageTransparency = transparency or 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 0,
	})
end

-- Tutorial / selection ring (Feedback.HighlightRing) around an object, outset by `outset` reference px.
function Kit.Ring(parent: Instance, outset: number?): any
	local o = outset or 8
	return Kit.Sprite(parent, "Feedback.HighlightRing", {
		Size = UDim2.new(1, o * 2, 1, o * 2),
		Position = UDim2.fromOffset(-o, -o),
		ZIndex = 8,
		Visible = false,
	})
end

-- Panels ---------------------------------------------------------------------
-- kind = { spec, mode, cap, noInset }.
local P4, F4, C4 = V4.Panels, V4.Feedback, V4.Controls
local PANELS: { [string]: { any } } = {
	Large = { P4.Large, "Border", 22 },
	Small = { P4.Small, "Border", 18 },
	Pill = { P4.HudPill, "Uniform", nil, true },
	Row = { P4.Row, "Border", 12 },
	Chip = { P4.Chip, "Uniform", nil, true },
	Tooltip = { P4.Tooltip, "Border", 9 },
	TitleBar = { P4.TitleBar, "Border", 14, true },
	ToastInfo = { F4.ToastInfo, "Border", 18 },
	ToastGood = { F4.ToastGood, "Border", 18 },
	ToastBad = { F4.ToastBad, "Border", 18 },
	Bubble = { F4.TutorialBubble, "Border", 28 }, -- 0.4 slice scale: the tail band renders cleanly below 0.5
	LoadFail = { F4.LoadFailPanel, "Border", 24 },
	ReelWindow = { V4.Reel.Window, "Border", 24 },
}
Kit.PanelKinds = PANELS

-- Kept for older callers.
function Kit.SafeSpec(spec: any): any
	return spec
end
Kit.V4Frames = V4.Frames

-- props: any property of the panel plus
--   Sprite  a PANELS kind ("Large", "Small" (default), "Pill", "Row", "Chip", "Tooltip", "TitleBar", "ToastInfo/Good/Bad",
--           "Bubble", "LoadFail")
--   Rarity  tier name: draws that tier's card frame instead
--   Pad     extra content padding in px (number or Vector2) added to the frame's border.
-- The panel is an ImageLabel wearing the sprite. Panels get a UIPadding "Inset" equal to the sliced border (kept in step
-- with the SliceScale) plus Pad, so children never sit on the frame's rim, and clip to the frame. Pills/chips carry no
-- inset: callers pad their own content.
function Kit.Panel(parent: Instance, props: { [string]: any }?): any
	local f = make("ImageLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, Image = "" }, parent)
	local kind, rarity = "Small", nil
	local padX, padY = 0, 0
	for k, v in props or {} do
		if k == "Sprite" then
			kind = if type(v) == "string" then v else "Small"
		elseif k == "Rarity" then
			rarity = v
		elseif k == "Pad" then
			if typeof(v) == "Vector2" then
				padX, padY = v.X, v.Y
			else
				padX, padY = v, v
			end
		elseif k ~= "BackgroundColor3" then -- the art carries the colour
			f[k] = v
		end
	end
	local entry = PANELS[kind] or PANELS.Small
	local spec, mode, cap, noInset = entry[1], entry[2], entry[3], entry[4]
	if rarity and V4.Rarity[rarity] then
		spec, mode, cap, noInset = V4.Rarity[rarity].Frame, "Uniform", nil, false
	end
	local inset = nil
	local function setInset(l: number, t: number, r: number, b: number)
		if inset then
			inset.PaddingLeft, inset.PaddingTop = UDim.new(0, math.ceil(l + padX)), UDim.new(0, math.ceil(t + padY))
			inset.PaddingRight, inset.PaddingBottom = UDim.new(0, math.ceil(r + padX)), UDim.new(0, math.ceil(b + padY))
		end
	end
	if not noInset then
		inset = make("UIPadding", { Name = "Inset" }, f)
	end
	skin(f, spec, mode, cap, nil, function(s)
		local c = spec.SliceCenter
		if c then
			setInset(c.Min.X * s + 2, c.Min.Y * s + 2, (spec.Size.X - c.Max.X) * s + 2, (spec.Size.Y - c.Max.Y) * s + 2)
		end
	end)
	if not noInset then
		f.ClipsDescendants = true
		setInset(14, 14, 14, 14) -- until the first measure
	end
	if rarity == "Secret" then Kit.Prismatic(f) end
	return f
end

-- Rarity gem (small diamond/jewel) of a tier.
function Kit.Gem(parent: Instance, rarity: string?, size: UDim2?): any
	local r = if rarity and SpriteIds.Rarity[rarity] then rarity else "Common"
	local gem = make("ImageLabel", { Name = "Gem", BackgroundTransparency = 1, Size = size or UDim2.fromOffset(24, 24), ScaleType = Enum.ScaleType.Fit }, parent)
	skin(gem, { Id = SpriteIds.Rarity[r].Gem }, nil, nil, nil)
	if r == "Secret" then Kit.Prismatic(gem) end
	return gem
end

-- Close "X" button. Returns { Instance }.
function Kit.CloseButton(parent: Instance, size: UDim2?, onClick: () -> ())
	local sz = size or UDim2.fromOffset(52, 52)
	local b = make("ImageButton", { Name = "Close", BackgroundTransparency = 1, AutoButtonColor = false, Size = sz, Image = "" }, parent)
	Kit.MinTouch(b)
	local scale = make("UIScale", {}, b)
	skin(b, SpriteIds.Kit.Close, nil, nil, nil)
	b.MouseButton1Down:Connect(function()
		Settings.Tween(scale, TweenInfo.new(0.06), { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		Settings.Tween(scale, TweenInfo.new(0.12), { Scale = 1 })
	end)
	b.Activated:Connect(function()
		Sound.Play("Click")
		onClick()
	end)
	return { Instance = b }
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

-- Chips -----------------------------------------------------------------------
-- A chip is an ImageLabel wearing a chip sprite with a child TextLabel "Label" (set text with Kit.SetText, restyle the
-- label with Kit.PillLabel). The sprite follows the colour asked for: gold / green / red / grey / dark chips are their own
-- art, other plum fills use the plain Panels.Chip.
local function chipSpec(bg: Color3): any
	if bg == Theme.Gold then
		return C4.Chip.Gold
	elseif bg == Theme.Success then
		return C4.Chip.Green
	elseif bg == Theme.Danger then
		return C4.Chip.Red
	elseif bg == Theme.Disabled then
		return C4.Chip.Grey
	elseif bg == Theme.BgDeep then
		return C4.Chip.Dark
	end
	return P4.Chip
end

local function pillWith(parent: Instance, text: string, spec: any, fg: Color3, height: number?): any
	local h = height or 20
	local root = make("ImageLabel", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), Image = "" }, parent)
	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		TextColor3 = fg,
		Text = text,
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.HeadingFont,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		TextWrapped = false,
		ZIndex = 2,
	}, root)
	make("UIPadding", { PaddingLeft = UDim.new(0, math.max(10, h * 0.5)), PaddingRight = UDim.new(0, math.max(10, h * 0.5)) }, label)
	skin(root, spec, "Uniform", nil, nil)
	return root
end

function Kit.Pill(parent: Instance, text: string, bg: Color3, fg: Color3, height: number?): any
	local pill = pillWith(parent, text, chipSpec(bg), fg, height)
	if bg == Theme.Gold then
		pill.ScaleType = Enum.ScaleType.Stretch
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
		make("UIStroke", { Color = Color3.fromRGB(103, 42, 158), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	end
	return pill
end

-- The text label of a Kit.Pill.
function Kit.PillLabel(pill: any): TextLabel
	return pill:FindFirstChild("Label") or pill
end

-- Sets the text of a Kit.Pill.
function Kit.SetText(pill: any, text: string)
	local l = pill:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then
		l.Text = text
	else
		pill.Text = text
	end
end

-- Threat / event / variant / misc sprites (SpriteIds3) by icon name. Threat.Lock and Threat.Check become
-- "ThreatLock" / "ThreatCheck" (plain "Lock" / "Check" are the older icons).
local FLAT3: { [string]: string } = {}
for group, entries in SpriteIds3 do
	for name, id in entries do
		FLAT3[if group == "Threat" and (name == "Lock" or name == "Check") then "Threat" .. name else name] = id
	end
end
Kit.Sprites3 = FLAT3

-- v4 icon sprites by name: Slow, SureFooted, ReducedMotion, ModifierRing, ModBlazing/Lucky/Golden, CoinFloat, XpFloat,
-- Back, Plus, Minus, Sort, Filter, Crown, and the feedback icons as Info / Good / Warn.
local V4ICONS: { [string]: string } = {}
for name, spec in V4.Icons do
	V4ICONS[name] = spec.Id
end
V4ICONS.Info, V4ICONS.Good, V4ICONS.Warn = F4.IconInfo.Id, F4.IconGood.Id, F4.IconWarn.Id
Kit.Icons4 = V4ICONS

-- Icon-name aliases onto SpriteIds.Icons.
local ICON_ALIAS = { Loot = "Box", Cross = false }

-- Icon by name as an ImageLabel: a SpriteIds.Icons entry, a SpriteIds3 one, a v4 icon, else an IconIds one ("Coin",
-- "Vault", ...). Nothing usable shows the neutral image.
function Kit.Icon(parent: Instance, name: string, size: UDim2?, color: Color3?): any
	local sz = size or UDim2.fromOffset(32, 32)
	local alias = ICON_ALIAS[name]
	local id = if name == "Cross" then SpriteIds.Kit.Close.Id else ((SpriteIds.Icons :: any)[if alias == nil then name else alias] or FLAT3[name] or V4ICONS[name] or (IconIds :: any)[name])
	local img = make("ImageLabel", { Name = name, BackgroundTransparency = 1, Size = sz, ScaleType = Enum.ScaleType.Fit, Image = "" }, parent)
	if id and Sprites.Ok(id) then
		img.Image = id
		Sprites.Watch(id, function()
			neutral(img)
		end)
	else
		neutral(img)
	end
	return img
end

-- Check mark / padlock: the sprite icons.
function Kit.Check(parent: Instance, size: UDim2?, color: Color3?): any
	return Kit.Icon(parent, "Check", size or UDim2.fromOffset(24, 24), color)
end

function Kit.LockGlyph(parent: Instance, size: UDim2?, color: Color3?): any
	return Kit.Icon(parent, "Lock", size or UDim2.fromOffset(18, 18), color)
end

-- Soft prismatic gradient on a stroke or image that slowly turns (static under reduced motion).
local PRISM = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("#FF9AD5")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("#FFE79A")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("#9AFFC8")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("#9AC8FF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("#FF9AD5")),
})
function Kit.Prismatic(stroke: Instance): UIGradient
	local existing = stroke:FindFirstChild("Prismatic")
	if existing and existing:IsA("UIGradient") then return existing end
	local g = make("UIGradient", { Name = "Prismatic", Color = PRISM }, stroke)
	local tween = TweenService:Create(g, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 })
	local function update()
		if Settings.Reduced() then tween:Cancel(); g.Rotation = 0 else tween:Play() end
	end
	local connection = Settings.Changed:Connect(update)
	g.Destroying:Connect(function() connection:Disconnect(); tween:Cancel() end)
	update()
	return g
end

-- Rarity badge (the RarityBadge sprite of the tier with its name; text always names the rarity).
function Kit.Rarity(parent: Instance, rarity: string?): any
	local r = if rarity and RarityColors.Fill[rarity] and C4.RarityBadge[rarity] then rarity else "Common"
	local pill = pillWith(parent, r, C4.RarityBadge[r], Theme.TextPrimary, 22)
	if r == "Secret" then Kit.Prismatic(pill) end
	local l = Kit.PillLabel(pill)
	l.TextStrokeColor3, l.TextStrokeTransparency = Theme.Stroke, 0.3
	return pill
end

local PERK_ICON = { Coins = "Coin", Loot = "Loot", Xp = "Xp" }

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
			local l = Kit.Label(f, ("+%d%%"):format(math.floor((p.Amount or 0) * 100 + 0.5)), Theme.TextSize.Caption, Theme.TextPrimary, true)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.fromOffset(0, 18)
			l.TextWrapped = false
			l.LayoutOrder = i * 2 + 1
		end
	end
	return f
end

-- Buttons -----------------------------------------------------------------------
local B4 = V4.Buttons
local STYLES = {
	Primary = { Theme.Gold, Theme.TextOnGold, B4.Primary },
	Secondary = { Theme.BgRaised, Theme.TextPrimary, B4.Secondary },
	Success = { Theme.Success, Theme.DangerText, B4.Success },
	Danger = { Theme.Danger, Theme.DangerText, B4.Danger },
	Cancel = { Theme.BgRaised, Theme.TextPrimary, B4.Secondary },
	Tab = { Theme.BgRaised, Theme.TextPrimary, nil },
}

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

-- Tooltip: hover (mouse) or press-and-hold (touch) shows a short label above the object, or below
-- it near the top edge. For icon-only UI whose meaning is not obvious.
local tipGui: ScreenGui? = nil
local tipFrame: GuiObject? = nil
local tipText: TextLabel? = nil
local tipId = 0
local function ensureTip()
	if tipGui and tipGui.Parent then
		return
	end
	local gui = make("ScreenGui", { Name = "Tips", ResetOnSpawn = false, DisplayOrder = 80, ScreenInsets = Enum.ScreenInsets.None }, nil)
	Scale.Attach(gui)
	local f = Kit.Panel(gui, { Sprite = "Tooltip", Visible = false, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Active = false })
	f.ClipsDescendants = false
	local t = Kit.Label(f, "", Theme.TextSize.Caption + 2, Theme.TextPrimary, true)
	t.AutomaticSize, t.Size, t.TextWrapped = Enum.AutomaticSize.XY, UDim2.fromOffset(0, 0), false
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }, t)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tipGui, tipFrame, tipText = gui, f, t
end

local function showTip(obj: GuiObject, text: string, color: Color3?)
	ensureTip()
	local f, t, gui = tipFrame :: GuiObject, tipText :: TextLabel, tipGui :: ScreenGui
	t.Text = text
	t.TextColor3 = color or Theme.TextPrimary
	f.Visible = true
	task.defer(function()
		local sc = math.max(Scale.Value, 0.01)
		local view = gui.AbsoluteSize / sc
		local half = f.AbsoluteSize.X / sc / 2
		local c = (obj.AbsolutePosition + obj.AbsoluteSize / 2 - gui.AbsolutePosition) / sc
		local above = c.Y - obj.AbsoluteSize.Y / sc / 2 - 8
		local height = f.AbsoluteSize.Y / sc
		local y = if above >= height + 6 then above - height else c.Y + obj.AbsoluteSize.Y / sc / 2 + 8
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.fromOffset(math.clamp(c.X, half + 6, math.max(half + 6, view.X - half - 6)), math.clamp(y, 6, math.max(6, view.Y - height - 6)))
	end)
end

function Kit.Tip(obj: GuiObject, text: string | () -> string, color: Color3?)
	local function hide(id: number)
		if tipFrame and id == tipId then
			tipFrame.Visible = false
		end
	end
	obj.MouseEnter:Connect(function()
		if not UserInputService.MouseEnabled then
			return
		end
		tipId += 1
		local id = tipId
		task.delay(0.35, function()
			if id == tipId and obj.Parent then
				showTip(obj, if type(text) == "function" then text() else text, color)
			end
		end)
	end)
	obj.MouseLeave:Connect(function()
		tipId += 1
		hide(tipId)
	end)
	obj.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tipId += 1
			hide(tipId)
		end
	end)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		tipId += 1
		local id = tipId
		local held = true
		local beganAt = os.clock()
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local ended
		ended = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				held = false
				ended:Disconnect()
				local moved = (Vector2.new(input.Position.X, input.Position.Y) - start).Magnitude
				if input.UserInputState == Enum.UserInputState.End and moved < 12 and os.clock() - beganAt < 0.45 and id == tipId and obj.Parent then
					showTip(obj, if type(text) == "function" then text() else text, color)
					task.delay(2.5, function() hide(id) end)
				end
			end
		end)
		task.delay(0.45, function()
			if id == tipId and held and obj.Parent then
				showTip(obj, if type(text) == "function" then text() else text, color)
				task.delay(1.6, function()
					hide(id)
				end)
			end
		end)
	end)
	obj.Destroying:Once(function()
		tipId += 1
		hide(tipId)
	end)
end

-- opts: Text, Style (Primary/Secondary/Success/Danger/Cancel/Tab), Size (UDim2, default 140x56;
-- never below 44 px), OnClick, Icon (icon name, see Kit.Icon), IconLayout ("Column" = icon above
-- the label, default; "Row" = icon at the left), Round (the round icon-button sprite), Shadow (ButtonShadow sprite under
-- the button), Rarity (tier name: the button is that tier's card frame instead of a styled button).
-- The button is a TextButton (transparent) holding the sprite "Skin" (normal / pressed / disabled art), an optional
-- "Icon" and the text "Label". Selection and the tutorial highlight show the HighlightRing sprite.
-- Returns { Instance, Stroke (always disabled; kept for callers), Icon, SetText, SetTextSize, SetEnabled(on, reasonText?,
-- locked?), SetSelected (visual only), SetStyle, SetEdge, SetBadge(n), SetHighlight(thickness?), Shimmer }.
function Kit.Button(parent: Instance, opts: { [string]: any })
	local style = STYLES[opts.Style or "Secondary"]
	local isTab = opts.Style == "Tab"
	local isRound = opts.Round == true
	local size: UDim2 = opts.Size or UDim2.fromOffset(140, 56)
	size = UDim2.new(
		size.X.Scale,
		if size.X.Scale == 0 then math.max(size.X.Offset, 44) else size.X.Offset,
		size.Y.Scale,
		if size.Y.Scale == 0 then math.max(size.Y.Offset, 44) else size.Y.Offset
	)

	local b = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = opts.LayoutOrder or 0,
	}, parent)
	Kit.MinTouch(b)
	if opts.Shadow then
		local sh = make("ImageLabel", { Name = "Shadow", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 5), Size = UDim2.fromScale(1, 1), ZIndex = 0, Active = false, Image = "" }, b)
		if isRound then
			skin(sh, B4.Round, nil, nil, nil)
			sh.ImageColor3, sh.ImageTransparency = Color3.new(0, 0, 0), 0.6
		else
			skin(sh, C4.ButtonShadow, "Uniform", nil, nil)
		end
	end
	if opts.Tip then
		Kit.Tip(b, opts.Tip, opts.Rarity and Theme.Rarity[opts.Rarity])
	end

	local self: any = { Instance = b, Stroke = make("UIStroke", { Enabled = false, Thickness = 0 }, b) }
	local enabled, selected, hover, pressed, baseText = true, false, false, false, opts.Text or ""
	local highlight: number? = nil
	local scale = make("UIScale", {}, b)

	local function specs()
		if opts.Rarity and V4.Rarity[opts.Rarity] then
			return V4.Rarity[opts.Rarity].Frame, nil
		elseif isRound then
			return B4.Round, nil
		elseif isTab then
			return (if selected then P4.TabOn else P4.TabOff), nil
		end
		return style[3].Normal, style[3].Pressed
	end
	local normalSpec, pressedSpec = specs()

	-- Layers: Skin (z1) under Icon (z2) under Label (z3); Ring above all.
	local img = make("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Image = "", Active = false }, b)
	skin(img, normalSpec, "Uniform", nil, nil)
	for _, s in { pressedSpec, C4.ButtonDisabled } do
		if s and Sprites.Ok(s.Id) then
			task.spawn(function() -- warm the other states so the first press does not flash
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ s.Id })
				end)
			end)
		end
	end
	local ring = Kit.Ring(b, if isTab then 2 else 8)

	local function show(spec: any)
		if spec and Sprites.Ok(spec.Id) and img.Image ~= spec.Id then
			img.Image = spec.Id
			if spec.SliceCenter then
				img.ScaleType, img.SliceCenter = Enum.ScaleType.Slice, spec.SliceCenter
				if fitters[img] then fitters[img](spec) else fit(img, spec, "Uniform", nil, nil) end
			else
				img.ScaleType = if spec.Stretch then Enum.ScaleType.Stretch else Enum.ScaleType.Fit
			end
		end
	end

	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Text = baseText,
		TextColor3 = style[2],
		TextSize = opts.TextSize or Theme.TextSize.Button,
		FontFace = Theme.HeadingFont,
		TextWrapped = true,
	}, b)
	local pad = make("UIPadding", {}, label)

	local icon: any = nil
	if opts.Icon then
		local row = opts.IconLayout == "Row"
		-- Square icon: as tall as the fraction of the button, never wider than the button.
		icon = Kit.Icon(b, opts.Icon, UDim2.new(1, 0, if row then 0.6 else (opts.IconScale or 0.5), 0), style[2])
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, icon)
		local centred = not row and baseText == ""
		icon.AnchorPoint = if row then Vector2.new(0, 0.5) elseif centred then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 0)
		icon.Position = if row then UDim2.new(0, 14, 0.5, 0) elseif centred then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.5, 0, 0.07, 0)
		icon.ZIndex = 2
		if row then
			pad.PaddingLeft = UDim.new(0, 44)
		else
			label.TextYAlignment = Enum.TextYAlignment.Bottom
			pad.PaddingBottom = UDim.new(0, if opts.Style == "Primary" then 12 else 5)
		end
		self.Icon = icon
	end

	local function paint()
		local text = style[2]
		normalSpec, pressedSpec = specs()
		local plainStyle = not opts.Rarity and not isRound and not isTab
		if not enabled then
			text = Theme.DisabledText
		end
		label.TextColor3 = text
		if isTab then
			show(normalSpec)
			img.ImageColor3 = if selected then Color3.new(1, 1, 1) elseif hover then Color3.fromRGB(215, 205, 235) else Color3.fromRGB(190, 180, 215)
			label.TextColor3 = if selected and enabled then Theme.Gold else text
		elseif not enabled then
			if plainStyle then
				show(C4.ButtonDisabled)
				img.ImageColor3 = Color3.new(1, 1, 1)
			else
				show(normalSpec)
				img.ImageColor3 = Color3.fromRGB(150, 142, 165)
			end
		else
			show(if pressed and pressedSpec then pressedSpec else normalSpec)
			img.ImageColor3 = if pressed then Color3.fromRGB(235, 235, 235) elseif hover then Color3.new(1, 1, 1) else Color3.fromRGB(250, 250, 250)
		end
		-- The ring marks selection (not tabs: they swap to the lit tab art) and the tutorial highlight.
		local showRing = (selected and not isTab) or highlight ~= nil
		ring.Visible = showRing
		ring.ImageTransparency = if highlight then math.clamp((6 - highlight) * 0.35, 0, 0.6) else 0
		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = if enabled then 0 else 0.55
		end
		local target = if not enabled then 1 elseif pressed then 0.96 elseif hover then 1.03 else 1
		Settings.Tween(scale, TweenInfo.new(pressed and 0.06 or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
	end

	b.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			hover = true
			paint()
		end
	end)
	b.MouseLeave:Connect(function()
		hover = false
		pressed = false
		paint()
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		paint()
	end)
	b.MouseButton1Up:Connect(function()
		pressed = false
		paint()
	end)
	b.Activated:Connect(function()
		if enabled and opts.OnClick then
			Sound.Play("Click")
			opts.OnClick()
		end
	end)

	local lock: any = nil
	function self.SetText(text: string)
		baseText = text
		label.Text = text
	end
	function self.SetTextSize(n: number)
		label.TextSize = n
	end
	function self.SetEnabled(on: boolean, reason: string?, locked: boolean?)
		enabled = on
		b.Active = on
		label.Text = if not on and reason then reason else baseText
		-- Lock icon beside the reason ("Need 50 more").
		local showLock = locked == true and not on and not icon
		if showLock and not lock then
			lock = Kit.Icon(b, "Lock", UDim2.fromOffset(18, 18), Theme.DisabledText)
			lock.AnchorPoint = Vector2.new(0, 0.5)
			lock.Position = UDim2.new(0, 12, 0.5, 0)
			lock.ZIndex = 2
		end
		if lock then
			lock.Visible = showLock
			pad.PaddingLeft = UDim.new(0, if showLock then 32 else 0)
		end
		paint()
	end
	function self.SetSelected(on: boolean)
		selected = on
		paint()
	end
	function self.SetStyle(name: string)
		style = STYLES[name]
		paint()
	end
	function self.SetEdge(_color: Color3?) end
	-- Tutorial ring (thickness in px, pulses 4..6) or nil to clear.
	function self.SetHighlight(thickness: number?)
		highlight = thickness
		local showRing = (selected and not isTab) or thickness ~= nil
		ring.Visible = showRing
		ring.ImageTransparency = if thickness then math.clamp((6 - thickness) * 0.35, 0, 0.6) else 0
	end
	function self.Shimmer()
		Kit.Prismatic(img)
	end
	local badge: any = nil
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
			Kit.PillLabel(badge).ZIndex = 6
		end
		badge.Visible = true
		Kit.SetText(badge, if n > 99 then "99+" else tostring(n))
	end
	paint()
	return self
end

-- Progress bar from the v4 Bar sprites: the Track frame with the Fill sprite clipped inside it and centred text with
-- padding at both ends. The fill never gets narrower than its own height, so it always reads as a rounded pill (instead
-- of a sliver), and is hidden at 0.
-- color tints the fill (nil = the sprite's gold). Returns { Instance, Set(fraction, text, tint?) } where tint is a
-- Color3, or true for the danger red.
function Kit.Bar(parent: Instance, size: UDim2, color: Color3?)
	local bar = make("ImageLabel", { Name = "Bar", BackgroundTransparency = 1, Size = size, Image = "", BorderSizePixel = 0 }, parent)
	skin(bar, V4.Bars.Track, "Uniform", nil, nil)
	local track = make("Frame", { Name = "Track", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ClipsDescendants = true }, bar)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), Visible = false, Image = "", ZIndex = 2 }, track)
	skinByHeight(fill, V4.Bars.Fill)
	local minW = make("UISizeConstraint", {}, fill)
	local function measure()
		-- The track follows the bar's height (about 14% of it each side); the fill is never narrower than it is tall.
		local h = bar.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		local inset = math.max(2, math.floor(h * 0.14 + 0.5))
		track.Position, track.Size = UDim2.fromOffset(inset, inset), UDim2.new(1, -inset * 2, 1, -inset * 2)
		minW.MinSize = Vector2.new(math.max(h - inset * 2, 1), 0)
	end
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
	measure()
	local label = Kit.Label(bar, "", 16, Theme.TextPrimary, true)
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.TextWrapped = false
	label.TextScaled = true
	label.TextStrokeColor3 = Theme.Stroke
	label.TextStrokeTransparency = 0.35
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, label)
	make("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 18 }, label)
	local self = { Instance = bar, Fill = fill }
	function self.Set(fraction: number, text: string, tint: any?)
		fraction = math.clamp(fraction, 0, 1)
		fill.Visible = fraction > 0
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		local c = if tint == true then Theme.Danger elseif typeof(tint) == "Color3" then tint else color
		fill.ImageColor3 = c or Color3.new(1, 1, 1)
		label.Text = text
	end
	return self
end

-- Switch 96x48 (the v4 ToggleOn / ToggleOff sprites) with the word "On" / "Off" opposite the knob.
-- Returns { Instance, Set(on) }.
function Kit.Toggle(parent: Instance, initial: boolean, onChange: (boolean) -> ())
	local on = initial
	local b = make("ImageButton", {
		Size = UDim2.fromOffset(96, 48),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Image = "",
		BorderSizePixel = 0,
	}, parent)
	Kit.MinTouch(b)
	local label = Kit.Label(b, "", 18, Theme.DangerText, true)
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = false
	label.ZIndex = 3
	local lpad = make("UIPadding", {}, label)
	b.ScaleType = Enum.ScaleType.Fit
	local function paint()
		label.Text = if on then "On" else "Off"
		local spec = if on then V4.Bars.ToggleOn else V4.Bars.ToggleOff
		if Sprites.Ok(spec.Id) then
			b.Image = spec.Id
		else
			neutral(b)
		end
		-- Word on the side the knob has left; the knob is at the right when on.
		label.TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
		label.TextColor3 = if on then Theme.DangerText else Theme.TextPrimary
	end
	for _, spec in { V4.Bars.ToggleOn, V4.Bars.ToggleOff } do
		Sprites.Watch(spec.Id, paint)
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

-- Horizontal slider 0..1 with a percent readout: SliderTrack + SliderFill sprites and the Knob sprite. Fills the
-- width of its parent (height 48): track with 20 px of room for the knob at both ends, readout on the right.
-- Returns { Instance, Set(v) }.
function Kit.Slider(parent: Instance, initial: number, onChange: (number) -> (), onRelease: ((number) -> ())?)
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48) }, parent)
	local track = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(40 + 72), 0, 26),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		BorderSizePixel = 0,
		Image = "",
	}, root)
	skin(track, V4.Bars.SliderTrack, "Uniform", nil, nil)
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 1), Size = UDim2.new(1, -8, 1, -2), ClipsDescendants = true }, track)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, Image = "", ZIndex = 2 }, inner)
	skinByHeight(fill, C4.SliderFill)
	local thumb = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Image = "",
		ZIndex = 3,
	}, track)
	skin(thumb, V4.Bars.Knob, nil, nil, nil)
	local readout = Kit.Label(root, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	readout.AnchorPoint = Vector2.new(1, 0.5)
	readout.Position = UDim2.new(1, 0, 0.5, 0)
	readout.Size = UDim2.fromOffset(68, 40)
	readout.TextWrapped = false

	local value = initial
	local function paint()
		fill.Size = UDim2.new(value, 0, 1, 0)
		fill.Visible = value > 0.02
		thumb.Position = UDim2.new(value, 0, 0.5, 0)
		readout.Text = math.floor(value * 100 + 0.5) .. "%"
	end
	paint()

	-- >= 48 px hit area over the track and thumb.
	local hitH = if Scale.Phone or UserInputService.TouchEnabled then math.max(48, 48 / math.max(Scale.Value, 0.1)) else 48
	local hit = make("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 40, 0, hitH),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -20, 0.5, 0),
		ZIndex = 5,
	}, track)
	local dragging = false
	local locked = false
	local function setFrom(x: number)
		value = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		value = math.floor(value * 100 + 0.5) / 100
		paint()
		onChange(value)
	end
	hit.InputBegan:Connect(function(input)
		if locked then
			return
		end
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
			if dragging and onRelease then
				onRelease(value)
			end
			dragging = false
		end
	end)
	return {
		Instance = root,
		-- Locked: not draggable and dimmed (the caller shows why).
		SetLocked = function(on: boolean)
			locked = on
			if on then
				dragging = false
			end
			hit.Active = not on
			track.ImageTransparency = 0
			thumb.ImageTransparency = if on then 0.5 else 0
			fill.ImageTransparency = if on then 0.5 else 0
		end,
		IsDragging = function()
			return dragging
		end,
		Set = function(v: number)
			if not dragging then
				value = v
				paint()
			end
		end,
	}
end

return Kit
