-- Small UI kit: Screen, Panel, Label, Pill, Icon, Rarity, Perks, Button, Bar, Toggle, Slider.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local IconIds = require(script.Parent.IconIds)
local RarityColors = require(script.Parent.RarityColors)
local SpriteIds = require(script.Parent.SpriteIds)
local Sprites = require(script.Parent.Sprites)
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

-- Sprite skins ---------------------------------------------------------------
-- A skin is a SpriteIds entry (Id, optional SliceCenter, Size) drawn on an image
-- object. Sliced skins get a SliceScale kept in step with the object's size:
-- "Uniform" scales the whole sprite to fit (pills, buttons, bars, rarity frames),
-- "Border" keeps the border near `cap` reference px (big panels). Reference px =
-- screen px / UIScale, so desktop and phone scales look alike.
local function fit(img: GuiObject, spec: any, mode: string?, cap: number?)
	local c = spec.SliceCenter
	local function apply()
		local a = img.AbsoluteSize / math.max(Scale.Value, 0.01)
		if a.X < 2 or a.Y < 2 then
			return
		end
		local s
		if mode == "Border" then
			s = (cap or 14) / ((c.Min.X + c.Min.Y) / 2)
		else
			s = math.min(a.X / spec.Size.X, a.Y / spec.Size.Y)
		end
		-- The two borders must never overlap.
		s = math.min(s, 0.98 * a.X / (c.Min.X + spec.Size.X - c.Max.X + 0.001), 0.98 * a.Y / (c.Min.Y + spec.Size.Y - c.Max.Y + 0.001))
		local target: any = img
		target.SliceScale = s
	end
	apply()
	img:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

-- Draws spec on img (ImageLabel/ImageButton). Returns false (and does nothing) when the
-- id is unusable; onFail runs if it later fails to load.
local function skin(img: any, spec: any, mode: string?, cap: number?, onFail: (() -> ())?): boolean
	if not spec or not Sprites.Ok(spec.Id) then
		return false
	end
	img.Image = spec.Id
	if spec.SliceCenter then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = spec.SliceCenter
		fit(img, spec, mode, cap)
	else
		img.ScaleType = Enum.ScaleType.Fit
	end
	Sprites.Watch(spec.Id, function()
		img.Image = ""
		if onFail then
			onFail()
		end
	end)
	return true
end
Kit.Skin = skin

local PANELS = {
	Large = { SpriteIds.Kit.PanelLarge, "Border", 15 },
	Small = { SpriteIds.Kit.PanelSmall, "Border", 12 },
	Pill = { SpriteIds.Kit.ProgressFrame, "Uniform", nil },
}

-- props: any property of the panel plus Sprite ("Large" | "Small" (default) | "Pill" |
-- false for the plain drawn panel; its stroke may carry state colour) and Rarity (tier
-- name: draws that tier's card frame instead). The panel is an ImageLabel; without a
-- usable sprite it is the drawn rounded rectangle (BackgroundColor3 + stroke).
function Kit.Panel(parent: Instance, props: { [string]: any }?): any
	local f = make("ImageLabel", { BackgroundColor3 = Theme.BgDeep, BorderSizePixel = 0, Image = "" }, parent)
	local kind, rarity, bgT = "Small", nil, 0
	for k, v in props or {} do
		if k == "Sprite" then
			kind = v
		elseif k == "Rarity" then
			rarity = v
		else
			f[k] = v
			if k == "BackgroundTransparency" then
				bgT = v
			end
		end
	end
	local pill = kind == "Pill"
	local corner = Kit.Corner(f, if pill then Theme.CornerPill else Theme.CornerPanel)
	local stroke = Kit.Stroke(f)
	local function drawn()
		f.BackgroundTransparency, stroke.Enabled, corner.CornerRadius = bgT, true, if pill then Theme.CornerPill else Theme.CornerPanel
	end
	local spec, mode, cap
	if rarity and SpriteIds.Rarity[rarity] then
		spec, mode, cap = SpriteIds.Rarity[rarity].Frame, "Uniform", nil
	elseif kind and PANELS[kind] then
		spec, mode, cap = PANELS[kind][1], PANELS[kind][2], PANELS[kind][3]
	end
	if spec and skin(f, spec, mode, cap, drawn) then
		f.BackgroundTransparency, stroke.Enabled, corner.CornerRadius = 1, false, UDim.new(0, 0)
	end
	return f
end

-- Rarity gem (small diamond/jewel) of a tier; a drawn dot in the tier colour without the sprite.
function Kit.Gem(parent: Instance, rarity: string?, size: UDim2?): any
	local r = if rarity and SpriteIds.Rarity[rarity] then rarity else "Common"
	local gem = make("ImageLabel", { Name = "Gem", BackgroundTransparency = 1, Size = size or UDim2.fromOffset(24, 24), ScaleType = Enum.ScaleType.Fit }, parent)
	local function drawn()
		gem.BackgroundTransparency = 0
		gem.BackgroundColor3 = RarityColors.Accent[r] or RarityColors.Accent.Common
		gem.Rotation = 45
		Kit.Corner(gem, UDim.new(0.2, 0))
	end
	if not skin(gem, { Id = SpriteIds.Rarity[r].Gem }, nil, nil, drawn) then
		drawn()
	end
	return gem
end

-- Close "X" button: the Close sprite (drawn "X" button without it). Returns { Instance }.
function Kit.CloseButton(parent: Instance, size: UDim2?, onClick: () -> ())
	local sz = size or UDim2.fromOffset(52, 52)
	local b = make("ImageButton", { Name = "Close", BackgroundTransparency = 1, AutoButtonColor = false, Size = sz, Image = "" }, parent)
	Kit.MinTouch(b)
	local label = Kit.Label(b, "", Theme.TextSize.Button, Theme.TextPrimary, true)
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = false
	local scale = make("UIScale", {}, b)
	local function drawn()
		b.BackgroundTransparency, b.BackgroundColor3 = 0, Theme.BgRaised
		label.Text = "X"
		Kit.Corner(b)
		Kit.Stroke(b)
	end
	if not skin(b, SpriteIds.Kit.Close, nil, nil, drawn) then
		drawn()
	end
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

-- Pill label that grows with its text. Neutral pills (BgRaised/BgPanel/BgDeep fill) wear the
-- Pill sprite (the object is then an ImageLabel with a child TextLabel "Label": set text with
-- Kit.SetText); coloured pills (gold counts, rarity names, status) stay flat colour.
local function neutral(c: Color3): boolean
	return c == Theme.BgRaised or c == Theme.BgPanel or c == Theme.BgDeep
end
function Kit.Pill(parent: Instance, text: string, bg: Color3, fg: Color3, height: number?): any
	local h = height or 20
	if neutral(bg) and Sprites.Ok(SpriteIds.Kit.Pill.Id) then
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
		}, root)
		make("UIPadding", { PaddingLeft = UDim.new(0, math.max(10, h * 0.45)), PaddingRight = UDim.new(0, math.max(10, h * 0.45)) }, label)
		local function drawn()
			root.BackgroundTransparency, root.BackgroundColor3 = 0, bg
			Kit.Corner(root, Theme.CornerPill)
		end
		if skin(root, SpriteIds.Kit.Pill, "Uniform", nil, drawn) then
			-- Dark tint so the light sprite reads as a plum chip behind cream text.
			root.ImageColor3 = if bg == Theme.BgDeep then Color3.fromRGB(70, 60, 95) else Color3.fromRGB(120, 105, 160)
		else
			drawn()
		end
		return root
	end
	local p = make("TextLabel", {
		BackgroundColor3 = bg,
		TextColor3 = fg,
		Text = text,
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.HeadingFont,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		BorderSizePixel = 0,
	}, parent)
	Kit.Corner(p, Theme.CornerPill)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, p)
	return p
end

-- Sets the text of a Kit.Pill (either kind).
function Kit.SetText(pill: any, text: string)
	local l = pill:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then
		l.Text = text
	else
		pill.Text = text
	end
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

-- Icon-name aliases onto SpriteIds.Icons (the sprite wins; IconIds / drawn glyphs are the fallback).
local ICON_ALIAS = { Loot = "Box", Cross = false }

local function legacyIcon(parent: Instance, name: string, sz: UDim2, color: Color3?): any
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

-- Icon by name as an ImageLabel: a SpriteIds.Icons entry ("Loot"/"Box", "Collection", "Keeper",
-- "Xp", "Level", "Lock", "Check", "Spores", "Heal", "Trap", "Defender", "Support", "CoinStack",
-- "SoundOn", "Music", ...), else an IconIds one ("Coin", "Vault", "Build", ...). The drawn glyph
-- (check, padlock) or short text is the fallback when the sprite id is missing or fails to load.
function Kit.Icon(parent: Instance, name: string, size: UDim2?, color: Color3?): any
	local sz = size or UDim2.fromOffset(32, 32)
	local alias = ICON_ALIAS[name]
	local id = if name == "Cross" then SpriteIds.Kit.Close.Id else (SpriteIds.Icons :: any)[if alias == nil then name else alias]
	if id and Sprites.Ok(id) then
		local img = make("ImageLabel", { Name = name, BackgroundTransparency = 1, Image = id, Size = sz, ScaleType = Enum.ScaleType.Fit }, parent)
		Sprites.Watch(id, function()
			if not img.Parent then
				return
			end
			local fb = legacyIcon(img.Parent, name, img.Size, color)
			fb.AnchorPoint, fb.Position, fb.LayoutOrder, fb.ZIndex = img.AnchorPoint, img.Position, img.LayoutOrder, img.ZIndex
			img:Destroy()
		end)
		return img
	end
	return legacyIcon(parent, name, sz, color)
end

-- Soft prismatic gradient on a stroke that slowly turns (static under reduced
-- motion); the stroke's own colour should be near white.
local PRISM = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("#FF9AD5")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("#FFE79A")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("#9AFFC8")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("#9AC8FF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("#FF9AD5")),
})
function Kit.Prismatic(stroke: Instance): UIGradient -- a UIStroke, or an image to tint
	local g = make("UIGradient", { Color = PRISM }, stroke)
	if not Settings.Reduced() then
		TweenService:Create(g, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
	end
	return g
end

-- Rarity badge: name on the rarity colour (text always names the rarity). Dark
-- tier colours get light text; shimmer tiers get a prismatic edge.
function Kit.Rarity(parent: Instance, rarity: string?): TextLabel
	local r = if rarity and RarityColors.Fill[rarity] then rarity else "Common"
	local fill = RarityColors.Fill[r]
	local dark = fill.R * 0.3 + fill.G * 0.59 + fill.B * 0.11 < 0.35
	local pill = Kit.Pill(parent, r, fill, if dark then Theme.TextPrimary else Theme.DangerText, 18)
	if RarityColors.Shimmer[r] then
		Kit.Prismatic(Kit.Stroke(pill, RarityColors.Accent[r], 2))
	end
	return pill
end

local PERK_ICON = { Coins = "Coin", Loot = "Loot", Xp = "Xp" }
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
	Primary = { Theme.Gold, Theme.TextOnGold, "ButtonPrimary" },
	Secondary = { Theme.BgRaised, Theme.TextPrimary, "ButtonSecondary" },
	Success = { Theme.Success, Theme.DangerText, "ButtonSuccess" },
	Danger = { Theme.Danger, Theme.DangerText, "ButtonDanger" },
	Cancel = { Theme.BgRaised, Theme.TextPrimary, "ButtonSecondary" },
	Tab = { Theme.BgRaised, Theme.TextPrimary, "Tab" },
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

local DISABLED_TINT = Color3.fromRGB(150, 142, 165)
local TAB_DIM = Color3.fromRGB(165, 150, 195)

-- opts: Text, Style (Primary/Secondary/Success/Danger/Cancel/Tab), Size (UDim2, default 140x56;
-- never below 44 px), OnClick, Icon (icon name, see Kit.Icon), IconLayout ("Column" = icon above
-- the label, default; "Row" = icon at the left), Edge (stroke colour), Rarity (tier name: the
-- button is that tier's card frame instead of a styled button).
-- The button is a TextButton (transparent when a sprite is used) holding the sprite "Skin", an
-- optional "Icon" and the text "Label". Without a usable sprite it is the drawn rounded button.
-- Returns { Instance, Stroke, Icon, SetText, SetTextSize, SetEnabled(on, reasonText?, locked?),
-- SetSelected (visual only), SetStyle, SetEdge, SetBadge(n), SetHighlight(thickness?), Shimmer }.
function Kit.Button(parent: Instance, opts: { [string]: any })
	local style = STYLES[opts.Style or "Secondary"]
	local isTab = opts.Style == "Tab"
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
		BackgroundColor3 = style[1],
		BorderSizePixel = 0,
		LayoutOrder = opts.LayoutOrder or 0,
	}, parent)
	Kit.Corner(b)
	local stroke = Kit.Stroke(b)
	Kit.MinTouch(b)

	local self: any = { Instance = b, Stroke = stroke }
	local enabled, selected, hover, pressed, baseText = true, false, false, false, opts.Text or ""
	local edge: Color3? = opts.Edge
	local highlight: number? = nil
	local scale = make("UIScale", {}, b)

	local normalSpec, pressedSpec = nil, nil
	local function pickSpecs()
		if opts.Rarity and SpriteIds.Rarity[opts.Rarity] then
			normalSpec, pressedSpec = SpriteIds.Rarity[opts.Rarity].Frame, nil
		else
			local kit = SpriteIds.Kit
			normalSpec, pressedSpec = kit[style[3]], kit[style[3] .. "Pressed"]
		end
	end
	pickSpecs()

	-- Layers: Skin (z1) under Icon (z2) under Label (z3).
	local img = make("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Image = "", Active = false }, b)
	local useSprite = false
	local function drawn()
		useSprite = false
		img.Image = ""
		b.BackgroundTransparency = 0
	end
	useSprite = skin(img, normalSpec, "Uniform", nil, drawn)
	b.BackgroundTransparency = if useSprite then 1 else 0
	if pressedSpec and Sprites.Ok(pressedSpec.Id) then
		task.spawn(function() -- warm the pressed art so the first press does not flash
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ pressedSpec.Id })
			end)
		end)
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
		icon = Kit.Icon(b, opts.Icon, UDim2.new(1, 0, if row then 0.6 else 0.5, 0), style[2])
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Width }, icon)
		icon.AnchorPoint = if row then Vector2.new(0, 0.5) else Vector2.new(0.5, 0)
		icon.Position = if row then UDim2.new(0, 14, 0.5, 0) else UDim2.new(0.5, 0, 0.07, 0)
		icon.ZIndex = 2
		if row then
			pad.PaddingLeft = UDim.new(0, 44)
		else
			label.TextYAlignment = Enum.TextYAlignment.Bottom
			pad.PaddingBottom = UDim.new(0, 5)
		end
		self.Icon = icon
	end

	local function paint()
		local fill, text = style[1], style[2]
		if not enabled then
			fill, text = Theme.Disabled, Theme.DisabledText
		elseif pressed then
			fill = shade(fill, -0.1)
		elseif hover then
			fill = shade(fill, 0.08)
		end
		label.TextColor3 = text
		if useSprite then
			if isTab then
				img.ImageColor3 = if selected then Color3.new(1, 1, 1) else TAB_DIM
				label.TextColor3 = if selected and enabled then Theme.Gold else text
			elseif not enabled then
				img.ImageColor3 = DISABLED_TINT
			else
				img.ImageColor3 = if pressed then Color3.fromRGB(235, 235, 235) elseif hover then Color3.new(1, 1, 1) else Color3.fromRGB(250, 250, 250)
			end
			if pressedSpec and enabled and Sprites.Ok(pressedSpec.Id) then
				local want = if pressed then pressedSpec else normalSpec
				if img.Image ~= want.Id then
					img.Image = want.Id
					img.SliceCenter = want.SliceCenter
				end
			end
			b.BackgroundTransparency = 1
			-- Gold outline marks selection / the tutorial highlight; Edge only tints drawn buttons.
			local ring = (selected and not isTab) or highlight ~= nil
			stroke.Enabled = ring
			stroke.Color = Theme.Gold
			stroke.Thickness = highlight or 4
		else
			b.BackgroundColor3 = fill
			stroke.Enabled = true
			stroke.Color = if selected or highlight then Theme.Gold else (edge or Theme.Stroke)
			stroke.Thickness = highlight or 3
		end
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
		pickSpecs()
		if useSprite and normalSpec and normalSpec.Id ~= img.Image then
			img.Image = normalSpec.Id
			img.SliceCenter = normalSpec.SliceCenter
		end
		paint()
	end
	function self.SetEdge(color: Color3?)
		edge = color
		paint()
	end
	-- Tutorial ring (thickness in px) or nil to clear.
	function self.SetHighlight(thickness: number?)
		highlight = thickness
		-- Stroke only (called every frame while pulsing): no scale tween.
		if useSprite then
			stroke.Enabled = (selected and not isTab) or thickness ~= nil
			stroke.Color = Theme.Gold
			stroke.Thickness = thickness or 4
		else
			stroke.Color = if selected or thickness then Theme.Gold else (edge or Theme.Stroke)
			stroke.Thickness = thickness or 3
		end
	end
	function self.Shimmer()
		if useSprite then
			Kit.Prismatic(img)
		else
			Kit.Prismatic(stroke)
		end
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
			Kit.Stroke(badge, Theme.Stroke, 2)
		end
		badge.Visible = true
		badge.Text = if n > 99 then "99+" else tostring(n)
	end
	paint()
	return self
end

-- Progress bar with text over it: the ProgressFrame sprite with a ProgressFill sprite inside
-- (drawn pill frame + colour fill without them). color tints the fill (nil = the sprite's gold).
-- Returns { Instance, Set(fraction, text, danger?) }.
function Kit.Bar(parent: Instance, size: UDim2, color: Color3?)
	local bar = make("ImageLabel", { BackgroundColor3 = Theme.BgPanel, Size = size, BorderSizePixel = 0, Image = "" }, parent)
	local corner = Kit.Corner(bar, Theme.CornerPill)
	local stroke = Kit.Stroke(bar, Theme.Stroke, 2)
	-- The fill lives in an inset box so it stays inside the frame's rim.
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, ZIndex = 2 }, bar)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundColor3 = color or Theme.Gold, BorderSizePixel = 0, Image = "", ZIndex = 2 }, inner)
	local fillCorner = Kit.Corner(fill, Theme.CornerPill)
	local fillSprite, frameSprite = false, false
	local function insetBox()
		local h = bar.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		local k = if frameSprite then math.floor(h * 0.17 + 0.5) else 0
		inner.Position = UDim2.fromOffset(k, k)
		inner.Size = UDim2.new(1, -2 * k, 1, -2 * k)
	end
	local function frameDrawn()
		frameSprite = false
		bar.BackgroundTransparency, stroke.Enabled, corner.CornerRadius = 0, true, Theme.CornerPill
		insetBox()
	end
	local function fillDrawn()
		fillSprite = false
		fill.BackgroundTransparency = 0
		fillCorner.CornerRadius = Theme.CornerPill
	end
	frameSprite = skin(bar, SpriteIds.Kit.ProgressFrame, "Uniform", nil, frameDrawn)
	if frameSprite then
		bar.BackgroundTransparency, stroke.Enabled, corner.CornerRadius = 1, false, UDim.new(0, 0)
	end
	fillSprite = skin(fill, SpriteIds.Kit.ProgressFill, "Uniform", nil, fillDrawn)
	fill.BackgroundTransparency = if fillSprite then 1 else 0
	if fillSprite then
		fillCorner.CornerRadius = UDim.new(0, 0)
	end
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(insetBox)
	insetBox()
	local label = Kit.Label(bar, "", 14, Theme.TextPrimary, true)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.TextStrokeColor3 = Theme.Stroke
	label.TextStrokeTransparency = 0.3
	local self = { Instance = bar }
	function self.Set(fraction: number, text: string, danger: boolean?)
		fraction = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		-- A sliced sprite narrower than its borders would tear; hide the sliver instead.
		fill.Visible = fraction > (if fillSprite then 0.04 else 0)
		local tint = if danger then Theme.Danger else color
		if fillSprite then
			fill.ImageColor3 = tint or Color3.new(1, 1, 1)
		else
			fill.BackgroundColor3 = tint or Theme.Gold
		end
		label.Text = text
	end
	return self
end

-- Switch 96x48 (the ToggleOn / ToggleOff sprites) with the word "On" / "Off" opposite the knob
-- (a drawn check + colour fill without the sprites). Returns { Instance, Set(on) }.
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
	local check = Kit.Check(b, UDim2.fromOffset(22, 22), Theme.DangerText)
	check.AnchorPoint = Vector2.new(0, 0.5)
	check.Position = UDim2.new(0, 12, 0.5, 0)
	check.ZIndex = 3
	local sprite = Sprites.Ok(SpriteIds.Kit.ToggleOn.Id) and Sprites.Ok(SpriteIds.Kit.ToggleOff.Id)
	local corner, stroke
	local paint
	local function drawn()
		sprite = false
		b.Image = ""
		b.BackgroundTransparency = 0
		corner = corner or Kit.Corner(b, Theme.CornerPill)
		stroke = stroke or Kit.Stroke(b)
		if paint then
			paint()
		end
	end
	if sprite then
		for _, spec in { SpriteIds.Kit.ToggleOn, SpriteIds.Kit.ToggleOff } do
			Sprites.Watch(spec.Id, drawn)
		end
	else
		drawn()
	end
	function paint()
		label.Text = if on then "On" else "Off"
		if sprite then
			b.Image = (if on then SpriteIds.Kit.ToggleOn else SpriteIds.Kit.ToggleOff).Id
			-- Word on the side the knob has left; the knob is at the right when on.
			label.TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
			lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
			label.TextColor3 = if on then Theme.DangerText else Theme.TextPrimary
			check.Visible = false
		else
			b.BackgroundColor3 = if on then Theme.Success else Theme.Disabled
			label.TextColor3 = if on then Theme.DangerText else Theme.DisabledText
			label.TextXAlignment = Enum.TextXAlignment.Right
			lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0, 12), UDim.new(0, 14)
			check.Visible = on
		end
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

-- Horizontal slider 0..1 with a percent readout: SliderTrack + ProgressFill sprites and the
-- SliderKnob (drawn track/knob without them). Returns { Instance, Set(v) }.
function Kit.Slider(parent: Instance, initial: number, onChange: (number) -> ())
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(340, 48) }, parent)
	local track = make("ImageLabel", {
		BackgroundColor3 = Theme.BgRaised,
		Size = UDim2.fromOffset(260, 24),
		Position = UDim2.fromOffset(0, 12),
		BorderSizePixel = 0,
		Image = "",
	}, root)
	local tCorner = Kit.Corner(track, Theme.CornerPill)
	local tStroke = Kit.Stroke(track, Theme.Stroke, 2)
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) }, track)
	local fill = make("ImageLabel", { BackgroundColor3 = Theme.Gold, BorderSizePixel = 0, Image = "" }, inner)
	local fCorner = Kit.Corner(fill, Theme.CornerPill)
	local thumb = make("ImageLabel", {
		BackgroundColor3 = Theme.TextPrimary,
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Image = "",
		ZIndex = 3,
	}, track)
	local kCorner = Kit.Corner(thumb, Theme.CornerPill)
	local kStroke = Kit.Stroke(thumb)
	local function trackDrawn()
		track.BackgroundTransparency, tStroke.Enabled, tCorner.CornerRadius = 0, true, Theme.CornerPill
		inner.Position, inner.Size = UDim2.new(), UDim2.fromScale(1, 1)
	end
	if skin(track, SpriteIds.Kit.SliderTrack, "Uniform", nil, trackDrawn) then
		track.BackgroundTransparency, tStroke.Enabled, tCorner.CornerRadius = 1, false, UDim.new(0, 0)
	else
		trackDrawn()
	end
	if skin(fill, SpriteIds.Kit.ProgressFill, "Uniform", nil, function()
		fill.BackgroundTransparency, fCorner.CornerRadius = 0, Theme.CornerPill
	end) then
		fill.BackgroundTransparency, fCorner.CornerRadius = 1, UDim.new(0, 0)
	end
	local function knobDrawn()
		thumb.BackgroundTransparency, kStroke.Enabled, kCorner.CornerRadius = 0, true, Theme.CornerPill
	end
	if skin(thumb, SpriteIds.Kit.SliderKnob, nil, nil, knobDrawn) then
		thumb.BackgroundTransparency, kStroke.Enabled, kCorner.CornerRadius = 1, false, UDim.new(0, 0)
	else
		knobDrawn()
	end
	local readout = Kit.Label(root, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	readout.Position = UDim2.fromOffset(272, 0)
	readout.Size = UDim2.fromOffset(68, 48)

	local value = initial
	local function paint()
		fill.Size = UDim2.new(value, 0, 1, 0)
		fill.Visible = value > 0.04
		thumb.Position = UDim2.new(value, 0, 0.5, 0)
		readout.Text = math.floor(value * 100 + 0.5) .. "%"
	end
	paint()

	-- 48 px hit area over the track and thumb.
	local hitH = if Scale.Phone or UserInputService.TouchEnabled then math.max(48, 48 / math.max(Scale.Value, 0.1)) else 48
	local hit = make("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(260 + 40, hitH),
		Position = UDim2.fromOffset(-20, 12 - hitH / 2),
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
