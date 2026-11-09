-- Small UI kit: Screen, Panel, Label, Pill, Icon, Rarity, Perks, Button, Bar, Toggle, Slider.
-- Owner rule: every UI visual is a generated sprite. Frames, buttons, bars, chips, badges, toasts, tooltips and
-- feedback art all come from SpriteIds6 (the unified purple and gold kit); icons come from the icon sheets
-- (Atlas / SpriteIds / SpriteIds3 / IconIds). Code only lays things out and tints/fades the art; when a sprite is
-- unusable the piece shows the minimal neutral image (Sprites.FallbackId), never a code-drawn replacement shape.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local IconIds = require(script.Parent.IconIds)
local Atlas = require(script.Parent.Atlas)
local RarityColors = require(script.Parent.RarityColors)
local SpriteIds = require(script.Parent.SpriteIds)
local SpriteIds3 = require(script.Parent.SpriteIds3)
local Sprites = require(script.Parent.Sprites)
local Theme = require(script.Parent.Theme)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Sound = require(script.Parent.Sound)

local V6: any = Sprites.Ids6
local V4: any = Sprites.Ids4 -- icons and in-world (World.*) art only; every frame / control comes from V6
local Kit = {}

-- Scroll bars: every ScrollingFrame wears the v6 thumb sprite (Roblox has no track image property).
local THUMB = V6.Scroll.Thumb.Id

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
		(i :: any).FontFace = Theme.BodyFont -- the one UI family; a prop below may still override it
	elseif class == "ScrollingFrame" then
		local s: any = i
		s.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		s.ScrollBarImageTransparency = 0
		s.TopImage, s.MidImage, s.BottomImage = THUMB, THUMB, THUMB
		s.ScrollBarThickness = 12
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
	-- Text gets an outline of its glyphs; everything else a border around the object.
	local isText = parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox")
	return make("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = if isText then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
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
	img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
	local f = Sprites.Fallback
	if f and f.SliceCenter then
		img.ScaleType, img.SliceCenter = Enum.ScaleType.Slice, f.SliceCenter
		img.SliceScale = 0.15
	else
		img.ScaleType = Enum.ScaleType.Fit
	end
end
Kit.Neutral = neutral

local atlasImages: { [string]: any } = {}
local function checkAtlas(img: any, id: string, offset: Vector2)
	local images = atlasImages[id]
	if not images then images = setmetatable({}, { __mode = "k" }); atlasImages[id] = images end
	images[img] = true
	task.spawn(function()
		local visibleSince: number? = nil
		repeat
			task.wait(2)
			local visible = img.Parent ~= nil and img.AbsoluteSize.X > 1 and img.AbsoluteSize.Y > 1
			local low, high = img.AbsolutePosition, img.AbsolutePosition + img.AbsoluteSize
			local viewport = workspace.CurrentCamera.ViewportSize
			visible = visible and high.X > 0 and high.Y > 0 and low.X < viewport.X and low.Y < viewport.Y
			local ancestor: Instance? = img
			while ancestor do
				if (ancestor:IsA("GuiObject") and not ancestor.Visible) or (ancestor:IsA("ScreenGui") and not ancestor.Enabled) then visible = false; break end
				if ancestor:IsA("GuiObject") and ancestor.ClipsDescendants then
					local a, b = ancestor.AbsolutePosition, ancestor.AbsolutePosition + ancestor.AbsoluteSize
					if high.X <= a.X or high.Y <= a.Y or low.X >= b.X or low.Y >= b.Y then visible = false; break end
				end
				ancestor = ancestor.Parent
			end
			visibleSince = if visible then (visibleSince or os.clock()) else nil
			if visibleSince and os.clock() - visibleSince >= 5 and img.Image == id and img.ImageRectOffset == offset and not img.IsLoaded then
				for other in images do if other.Image == id and other.IsLoaded then return end end
				Sprites.Fail(id)
				return
			end
		until not img.Parent or img.Image ~= id or img.ImageRectOffset ~= offset or img.IsLoaded
	end)
end

-- Draws spec on img (ImageLabel/ImageButton). A missing or unloadable id shows the neutral image and returns false.
local function skin(img: any, spec: any, mode: string?, cap: number?, onFail: (() -> ())?, onScale: ((number) -> ())?): boolean
	if not spec or not Sprites.Ok(spec.Id) then
		neutral(img)
		return false
	end
	img.Image = spec.Id
	img.ImageRectOffset, img.ImageRectSize = spec.Offset or Vector2.zero, if spec.Offset then spec.Size else Vector2.zero
	if spec.SliceCenter then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = spec.SliceCenter
		fit(img, spec, mode, cap, onScale)
	else
		img.ScaleType = if spec.Stretch then Enum.ScaleType.Stretch else Enum.ScaleType.Fit
	end
	Sprites.Watch(spec.Id, function()
		if img.Image == spec.Id then
			neutral(img)
			if onFail then onFail() end
		end
	end, img)
	if spec.Offset then checkAtlas(img, spec.Id, spec.Offset) end
	return true
end
Kit.Skin = skin

-- Swaps the sprite of an image already skinned with a sliced spec (toast kinds, tab states) and re-fits its slice scale.
function Kit.Reskin(img: any, spec: any)
	if not Sprites.Ok(spec.Id) then
		neutral(img)
		return
	end
	img.Image = spec.Id
	img.ImageRectOffset, img.ImageRectSize = spec.Offset or Vector2.zero, if spec.Offset then spec.Size else Vector2.zero
	if spec.SliceCenter then
		img.ScaleType, img.SliceCenter = Enum.ScaleType.Slice, spec.SliceCenter
		if fitters[img] then fitters[img](spec) else fit(img, spec, "Uniform", nil, nil) end
	else
		img.ScaleType = Enum.ScaleType.Fit
	end
end

-- Sliced image whose SliceScale follows its HEIGHT only (bar fills / slider fills: their width changes with the value).
-- Returns a setter that swaps the sprite (bar fills change colour variant with the value).
local function skinByHeight(img: any, spec: any, fallback: any?): (any) -> ()
	local current = spec
	local nudge = 0
	local function apply()
		if img.Image ~= current.Id or not current.SliceCenter then
			return
		end
		local h = img.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		if h < 2 then
			return
		end
		local s = math.min(h / current.Size.Y, 0.5)
		img.SliceScale = s
		nudge += 1
		local mine = nudge
		task.delay(0.1, function()
			if mine == nudge and img.Parent then
				img.SliceScale = math.max(0.001, s - 0.001)
			end
		end)
	end
	local assign
	assign = function(nextSpec: any)
		current = nextSpec
		if not Sprites.Ok(nextSpec.Id) then
			if fallback and nextSpec ~= fallback then
				assign(fallback)
			else
				neutral(img)
			end
			return
		end
		img.Image, img.ScaleType, img.SliceCenter = nextSpec.Id, Enum.ScaleType.Slice, nextSpec.SliceCenter
		img.ImageRectOffset, img.ImageRectSize = nextSpec.Offset or Vector2.zero, if nextSpec.Offset then nextSpec.Size else Vector2.zero
		apply()
		Sprites.Watch(nextSpec.Id, function()
			if img.Image == nextSpec.Id then
				if fallback and nextSpec ~= fallback then assign(fallback) else neutral(img) end
			end
		end, img)
		if nextSpec.Offset then checkAtlas(img, nextSpec.Id, nextSpec.Offset) end
	end
	img:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	assign(spec)
	return assign
end
Kit.SkinByHeight = skinByHeight

-- Spec lookup by dotted path ("Fx.Burst", "Rarity.Common"): the v6 kit first; the v4 set only answers for the
-- in-world art ("World.CellValid") and the older icon sheet ("Icons.Slow"). nil when missing.
function Kit.Spec(path: string): any
	local first = string.match(path, "^[^%.]+")
	local node: any = if V6[first] then V6 elseif first == "World" or first == "Icons" then V4 else nil
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

-- A decorative sprite image (no input): path is a spec path ("Fx.Burst"); props are ImageLabel properties.
-- Sliced specs stay "Uniform"-fitted to the object.
function Kit.Sprite(parent: Instance?, path: string, props: { [string]: any }?): any
	local img = make("ImageLabel", { Name = (string.match(path, "[^%.]+$")), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Image = "" }, nil)
	for k, v in props or {} do
		img[k] = v
	end
	skin(img, Kit.Spec(path), "Uniform", nil, nil)
	if props and props.ScaleType then
		img.ScaleType = props.ScaleType -- skin() picks Fit/Slice; an explicit choice wins
	end
	img.Parent = parent
	return img
end

-- Dimming layer behind a modal / reveal: a flat deep-purple veil (the only non-sprite surface; it is a screen tint,
-- not UI art). props are Frame properties; transparency 0..1.
function Kit.Scrim(parent: Instance, transparency: number, props: { [string]: any }?): Frame
	local f = make("Frame", {
		Name = "Scrim",
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Active = false,
		Position = UDim2.fromOffset(-400, -400),
		Size = UDim2.new(1, 800, 1, 800),
	}, nil)
	for k, v in props or {} do
		f[k] = v
	end
	f.Parent = parent
	return f
end

-- Soft light behind something (Fx.Burst). Returns the image; size and place it.
function Kit.Glow(parent: Instance, color: Color3?, transparency: number?): any
	return Kit.Sprite(parent, "Fx.Burst", {
		ImageColor3 = color or Theme.Gold,
		ImageTransparency = transparency or 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 0,
	})
end

-- Tutorial / selection ring (Frame.Highlight) around an object, outset by `outset` reference px.
function Kit.Ring(parent: Instance, outset: number?): any
	local o = outset or 8
	return Kit.Sprite(parent, "Frame.Highlight", {
		Size = UDim2.new(1, o * 2, 1, o * 2),
		Position = UDim2.fromOffset(-o, -o),
		ZIndex = 8,
		Visible = false,
	})
end

-- Panels ---------------------------------------------------------------------
-- kind = { spec, mode, cap, noInset }.
local PANELS: { [string]: { any } } = {
	Large = { V6.Panel.Modal, "Border", 58 }, -- slice scale 0.5: 12 px gold rim, 58 px header band (tab row), dark well below
	Small = { V6.Panel.Section, "Border", 12 },
	Pill = { V6.Hud.Pill, "Uniform", nil, true },
	PillGold = { V6.Hud.PillGold, "Uniform", nil, true },
	Row = { V6.Panel.Section, "Border", 10 },
	Chip = { V6.Chip.Purple, "Uniform", nil, true },
	Tooltip = { V6.Chip.Dark, "Uniform", nil, true }, -- hover tips wear the dark v6 chip
	TitleBar = { V6.Panel.SectionPlate, "Uniform", nil, true },
	ToastInfo = { V6.Toast.Info, "Border", 20 },
	ToastGood = { V6.Toast.Good, "Border", 20 },
	ToastBad = { V6.Toast.Bad, "Border", 20 },
	Bubble = { V6.Bubble.Tutorial, "Border", 28 }, -- below 0.5 slice scale the tail band renders cleanly
	LoadFail = { V6.Panel.Modal, "Border", 30 },
	ReelWindow = { V6.Panel.Section, "Border", 16 },
	Card = { V6.Card.Normal, "Border", 14 },
	CardSelected = { V6.Card.Selected, "Border", 14 },
	Slot = { V6.Slot.Empty, "Border", 12 },
}
Kit.PanelKinds = PANELS

-- props: any property of the panel plus
--   Sprite  a PANELS kind ("Large" = Panel.Modal, "Small" (default) = Panel.Section, "Pill", "PillGold", "Row", "Chip",
--           "Tooltip", "TitleBar" = Panel.SectionPlate, "ToastInfo/Good/Bad", "Bubble", "LoadFail", "Card",
--           "CardSelected", "Slot")
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
	if rarity and V6.Rarity[rarity] then
		spec, mode, cap, noInset = V6.Rarity[rarity], "Uniform", nil, false
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

-- Close "X" button (Round.Close). Returns { Instance }.
function Kit.CloseButton(parent: Instance, size: UDim2?, onClick: () -> ())
	local sz = size or UDim2.fromOffset(52, 52)
	local b = make("ImageButton", { Name = "Close", BackgroundTransparency = 1, AutoButtonColor = false, Size = sz, Image = "" }, parent)
	Kit.MinTouch(b)
	local scale = make("UIScale", {}, b)
	skin(b, V6.Round.Close, nil, nil, nil)
	b.MouseButton1Down:Connect(function()
		Settings.Tween(scale, TweenInfo.new(0.06), { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		Settings.Tween(scale, TweenInfo.new(0.12), { Scale = 1 })
	end)
	b.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			Settings.Tween(scale, TweenInfo.new(0.1), { Scale = 1.06 })
		end
	end)
	b.MouseLeave:Connect(function()
		Settings.Tween(scale, TweenInfo.new(0.12), { Scale = 1 })
	end)
	b.Activated:Connect(function()
		Sound.Play("Click")
		onClick()
	end)
	return { Instance = b }
end

-- Modal chrome shared by every popup (Modal.New) and the Bag / Index / Upgrades shell: Panel.Modal back, the
-- Panel.SectionPlate title plate straddling the top edge (centred, cream title with a dark outline) and Round.Close
-- overlapping the top-right corner. Returns { Root, Back, Plate, Title, Close, Layout(width) -> overhang } where Root is
-- the modal rectangle (the caller sizes and places it), the plate and the close button hang above / over its top edge and
-- Layout(width) (reference px) returns how far the plate rises above Root, so the caller can leave room for it.
function Kit.ModalChrome(parent: Instance, title: string, onClose: () -> ()): any
	local root = make("Frame", { Name = "Modal", BackgroundTransparency = 1, BorderSizePixel = 0 }, parent)
	local back = Kit.Panel(root, { Sprite = "Large", Size = UDim2.fromScale(1, 1), ZIndex = 0, Active = true })
	back.ClipsDescendants = false
	local inset = back:FindFirstChild("Inset")
	if inset then inset:Destroy() end -- content is placed explicitly by the caller
	local plate = Kit.Panel(root, { Sprite = "TitleBar", AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Active = false })
	local label = Kit.Label(plate, title, Theme.TextSize.Title, Theme.TextPrimary, true)
	label.ZIndex, label.TextWrapped, label.TextScaled, label.TextTruncate = 4, false, true, Enum.TextTruncate.AtEnd
	make("UIStroke", { Color = Theme.Stroke, Thickness = 3 }, label)
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 40 }, label)
	local closeButton = Kit.CloseButton(root, UDim2.fromOffset(54, 54), onClose)
	local close = closeButton.Instance
	close.AnchorPoint, close.ZIndex = Vector2.new(0.5, 0.5), 5
	local self = { Root = root, Back = back, Plate = plate, Title = label, Close = close }
	function self.Layout(width: number): number
		local phone = Scale.Phone
		local h = if phone then 58 else 100
		local s = h / 210 -- SectionPlate is 712 x 210 native; its laurels are 178 px each side
		local w = math.clamp(width * 0.46, if phone then 300 else 380, math.max(width - 130, 120))
		local rise = math.floor(h * 0.62)
		plate.Size, plate.Position = UDim2.fromOffset(w, h), UDim2.new(0.5, 0, 0, -rise)
		label.Position = UDim2.fromOffset(178 * s, h * 0.26)
		label.Size = UDim2.fromOffset(math.max(w - 356 * s, 20), h * 0.46)
		local size = if phone then 56 else 74
		close.Size, close.Position = UDim2.fromOffset(size, size), UDim2.new(1, -(size * 0.7), 0, size * 0.28)
		return rise + 6
	end
	return self
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
-- art, other plum fills use Chip.Purple.
local function chipSpec(bg: Color3): any
	local C = V6.Chip
	if bg == Theme.Gold then
		return C.Gold
	elseif bg == Theme.Success then
		return C.Green
	elseif bg == Theme.Danger then
		return C.Red
	elseif bg == Theme.Disabled then
		return C.Grey
	elseif bg == Theme.BgDeep then
		return C.Dark
	end
	return C.Purple
end

local GREY_COUNT_TEXT = Color3.fromRGB(62, 54, 84)
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
	if fg == Theme.TextPrimary then
		make("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, label)
	end
	skin(root, spec, "Uniform", nil, nil)
	return root
end

function Kit.Pill(parent: Instance, text: string, bg: Color3, fg: Color3, height: number?): any
	return pillWith(parent, text, chipSpec(bg), fg, height)
end

-- Count badge ("x50"): Badge.Count (yellow) with dark text; a grey chip when the count is zero (enabled = false).
function Kit.Count(parent: Instance, text: string, enabled: boolean?, height: number?): any
	if enabled == false then
		return pillWith(parent, text, V6.Chip.Grey, GREY_COUNT_TEXT, height or 24)
	end
	return pillWith(parent, text, V6.Badge.Count, Theme.TextOnGold, height or 24)
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
V4ICONS.Info, V4ICONS.Good, V4ICONS.Warn = V4.Feedback.IconInfo.Id, V4.Feedback.IconGood.Id, V4.Feedback.IconWarn.Id
Kit.Icons4 = V4ICONS

-- Icon-name aliases onto SpriteIds.Icons.
local ICON_ALIAS = { Loot = "DropChance", Rooms = "Defender", Cross = false }

-- Icon by name as an ImageLabel: a SpriteIds.Icons entry, a SpriteIds3 one, a v4 icon, else an IconIds one ("Coin",
-- "Vault", ...). Nothing usable shows the neutral image.
function Kit.SetIcon(img: ImageLabel, name: string)
	local alias = ICON_ALIAS[name]
	local candidate = (Atlas :: any)[name] or (if type(alias) == "string" then (Atlas :: any)[alias] else nil)
	local atlas = if candidate and Sprites.Ok(candidate.Id) then candidate else nil
	local id = if atlas then atlas.Id elseif name == "Cross" then V6.Round.Close.Id else ((SpriteIds.Icons :: any)[if alias == nil then name else alias] or FLAT3[if type(alias) == "string" then alias else name] or V4ICONS[name] or (IconIds :: any)[name] or SpriteIds.Rooms[name])
	if id and Sprites.Ok(id) then
		if img.Image == id and img.ImageRectOffset == (if atlas then atlas.Offset else Vector2.zero) then return end
		img.Image = id
		img.ImageRectOffset, img.ImageRectSize = if atlas then atlas.Offset else Vector2.zero, if atlas then atlas.Size else Vector2.zero
		Sprites.Watch(id, function()
			if img.Image == id and (not atlas or img.ImageRectOffset == atlas.Offset) then
				if atlas then Kit.SetIcon(img, name) else neutral(img) end
			end
		end, img)
		if atlas then checkAtlas(img, id, atlas.Offset) end
	else
		neutral(img)
	end
	img.ScaleType = Enum.ScaleType.Fit
end

function Kit.Icon(parent: Instance, name: string, size: UDim2?, color: Color3?): any
	local sz = size or UDim2.fromOffset(32, 32)
	local img = make("ImageLabel", { Name = name, BackgroundTransparency = 1, Size = sz, ScaleType = Enum.ScaleType.Fit, Image = "" }, parent)
	Kit.SetIcon(img, name)
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
function Kit.Rarity(parent: Instance, rarity: string?, height: number?): any
	local r = if rarity and RarityColors.Fill[rarity] and V6.RarityBadge[rarity] then rarity else "Common"
	local pill = pillWith(parent, r, V6.RarityBadge[r], Theme.TextPrimary, height or 22)
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
local B6 = V6.Button
local STYLES = {
	Primary = { Theme.Gold, Theme.TextOnGold, { Normal = B6.Yellow, Pressed = B6.YellowPressed } },
	Secondary = { Theme.BgRaised, Theme.TextPrimary, { Normal = B6.Purple, Pressed = B6.PurplePressed } },
	Success = { Theme.Success, Theme.TextPrimary, { Normal = B6.Green, Pressed = B6.GreenPressed } },
	Danger = { Theme.Danger, Theme.TextPrimary, { Normal = B6.Red, Pressed = B6.RedPressed } },
	Cancel = { Theme.BgRaised, Theme.TextPrimary, { Normal = B6.Purple, Pressed = B6.PurplePressed } },
	Tab = { Theme.BgRaised, Theme.TextPrimary, nil },
	Nav = { Theme.BgRaised, Theme.TextPrimary, nil },
	Card = { Theme.BgRaised, Theme.TextPrimary, nil }, -- selectable card (Card.Normal / Card.Selected), e.g. threat tiers
}
-- Label colour on the grey (disabled) button.
local GREY_TEXT = Color3.fromRGB(62, 54, 84)

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
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, f)
	local t = Kit.Label(f, "", Theme.TextSize.Body + 2, Theme.TextPrimary, true)
	t.LayoutOrder = 1
	t.AutomaticSize, t.Size, t.TextWrapped = Enum.AutomaticSize.XY, UDim2.fromOffset(0, 0), false
	make("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, t)
	Kit.Stroke(t, Theme.Stroke, 2)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tipGui, tipFrame, tipText = gui, f, t
end

local function showTip(obj: GuiObject, text: string, color: Color3?, rarity: string?)
	ensureTip()
	local f, t, gui = tipFrame :: GuiObject, tipText :: TextLabel, tipGui :: ScreenGui
	t.Text = text
	-- Rarity tip: the tier's RarityBadge sits above the text.
	local old = f:FindFirstChild("RarityTag")
	if old then old:Destroy() end
	if rarity then
		local tag = Kit.Rarity(f, rarity)
		tag.Name, tag.LayoutOrder = "RarityTag", 0
	end
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

function Kit.Tip(obj: GuiObject, text: string | () -> string, color: Color3?, rarity: string?)
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
				showTip(obj, if type(text) == "function" then text() else text, color, rarity)
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
	local isNav = opts.Style == "Nav" or opts.Style == "Card" -- states swap the art instead of tinting it
	local isCard = opts.Style == "Card"
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
	if opts.Tip then
		Kit.Tip(b, opts.Tip, opts.Rarity and Theme.Rarity[opts.Rarity], opts.Rarity)
	end

	local self: any = { Instance = b, Stroke = make("UIStroke", { Enabled = false, Thickness = 0 }, b) }
	local enabled, selected, hover, pressed, baseText = true, false, false, false, opts.Text or ""
	local highlight: number? = nil
	local scale = make("UIScale", {}, b)

	local function specs()
		if opts.Rarity and V6.Rarity[opts.Rarity] then
			return V6.Rarity[opts.Rarity], nil
		elseif isRound then
			return (if opts.Style == "Primary" then V6.Round.Yellow else V6.Round.Purple), nil
		elseif isTab then
			return (if selected then V6.Tab.On else V6.Tab.Off), nil
		elseif isCard then
			return (if selected then V6.Card.Selected else V6.Card.Normal), nil
		elseif isNav then
			return (if selected then V6.Nav.On else V6.Nav.Off), nil
		end
		return style[3].Normal, style[3].Pressed
	end
	local normalSpec, pressedSpec = specs()

	-- Layers: Skin (z1) under Icon (z2) under Label (z3); Ring above all.
	local img = make("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Image = "", Active = false }, b)
	local paint
	skin(img, normalSpec, "Uniform", nil, function() if paint then paint() end end)
	for _, s in { pressedSpec, B6.Grey, V6.Tab.On, V6.Tab.Off, V6.Nav.On, V6.Nav.Off } do
		if s and Sprites.Ok(s.Id) then
			task.spawn(function() -- warm the other states so the first press does not flash
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ s.Id })
				end)
			end)
		end
	end
	local ring = Kit.Ring(b, if isTab or isNav then 2 else 8)

	local shownSpec = normalSpec
	local function show(spec: any)
		if spec and Sprites.Ok(spec.Id) and shownSpec ~= spec then
			shownSpec = spec
			img.Image = spec.Id
			img.ImageRectOffset, img.ImageRectSize = spec.Offset or Vector2.zero, if spec.Offset then spec.Size else Vector2.zero
			if spec.SliceCenter then
				img.ScaleType, img.SliceCenter = Enum.ScaleType.Slice, spec.SliceCenter
				if fitters[img] then fitters[img](spec) else fit(img, spec, "Uniform", nil, nil) end
			else
				img.ScaleType = if spec.Stretch then Enum.ScaleType.Stretch else Enum.ScaleType.Fit
			end
			if spec.Offset then checkAtlas(img, spec.Id, spec.Offset) end
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
	-- Cream labels on purple / green / red art carry the dark outline; dark labels on yellow and grey do not.
	local labelStroke = make("UIStroke", { Color = Theme.Stroke, Thickness = 2, Enabled = style[2] == Theme.TextPrimary }, label)

	local icon: any = nil
	if opts.Icon then
		local row = opts.IconLayout == "Row"
		-- Square icon: as tall as the fraction of the button, never wider than the button.
		icon = Kit.Icon(b, opts.Icon, UDim2.new(1, 0, if row then (if isTab then 0.8 else 0.6) else (opts.IconScale or 0.5), 0), style[2])
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, icon)
		local centred = not row and baseText == ""
		icon.AnchorPoint = if row then Vector2.new(0, 0.5) elseif centred then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 0)
		icon.Position = if row then UDim2.new(0, 14, 0.5, 0) elseif centred then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.5, 0, 0.07, 0)
		icon.ZIndex = 2
		if row then
			pad.PaddingLeft = UDim.new(0, if isTab then 70 else 44)
		else
			label.TextYAlignment = Enum.TextYAlignment.Bottom
			pad.PaddingBottom = UDim.new(0, if opts.Style == "Primary" then 12 elseif opts.Style == "Nav" then 18 else 5)
		end
		self.Icon = icon
	end

	paint = function()
		local text = style[2]
		normalSpec, pressedSpec = specs()
		local plainStyle = not opts.Rarity and not isRound and not isTab and not isNav
		local lit = (isTab or isNav) and selected -- yellow tab / nav art: dark label
		if lit then
			text = Theme.TextOnGold
		elseif isTab or isNav then
			text = Theme.TextPrimary
		end
		if not enabled then
			text = if plainStyle then GREY_TEXT else Theme.DisabledText
		end
		label.TextColor3 = text
		labelStroke.Enabled = text == Theme.TextPrimary
		if isTab or isNav then
			show(normalSpec)
			img.ImageColor3 = if not enabled then Color3.fromRGB(150, 142, 165) elseif hover and not selected then Color3.fromRGB(235, 228, 255) else Color3.new(1, 1, 1)
		elseif not enabled then
			if plainStyle then
				show(B6.Grey)
				img.ImageColor3 = Color3.new(1, 1, 1)
			else
				show(normalSpec)
				img.ImageColor3 = Color3.fromRGB(150, 142, 165)
			end
		else
			show(if pressed and pressedSpec then pressedSpec else normalSpec)
			img.ImageColor3 = if pressed then Color3.fromRGB(235, 235, 235) elseif hover then Color3.fromRGB(255, 252, 245) else Color3.new(1, 1, 1)
		end
		-- The ring marks selection (not tabs / nav: they swap to the lit art) and the tutorial highlight.
		local showRing = (selected and not isTab and not isNav) or highlight ~= nil
		ring.Visible = showRing
		ring.ImageTransparency = if highlight then math.clamp((6 - highlight) * 0.35, 0, 0.6) else 0
		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = if enabled then 0 else 0.55
		end
		local target = if not enabled then 1 elseif pressed then 0.96 elseif hover then 1.03 else 1
		Settings.Tween(scale, TweenInfo.new(pressed and 0.06 or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
	end
	Sprites.Watch(B6.Grey.Id, function() if paint then paint() end end, img)

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
		local showRing = (selected and not isTab and not isNav) or thickness ~= nil
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
			badge = pillWith(b, "", V6.Badge.Count, Theme.TextOnGold, 24)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 8, 0, -8)
			badge.ZIndex = 5
			Kit.PillLabel(badge).ZIndex = 6
		end
		badge.Visible = true
		Kit.SetText(badge, if n > 99 then "99+" else tostring(n))
	end
	paint()
	return self
end

-- Progress bar from the v6 Bar sprites: Bar.Track with a Bar.Fill* sprite clipped inside it and centred text with
-- padding at both ends. The fill never gets narrower than its own height, so it always reads as a rounded pill (instead
-- of a sliver), and is hidden at 0.
-- color picks the fill variant (Theme.Success = green, Theme.Danger = red, Theme.Accent = purple, anything else /
-- nil = yellow). Returns { Instance, Set(fraction, text, tint?) } where tint is a Color3, or true for the danger red.
local function fillSpec(color: Color3?): any
	if color == Theme.Success then
		return V6.Bar.FillGreen
	elseif color == Theme.Danger then
		return V6.Bar.FillRed
	elseif color == Theme.Accent then
		return V6.Bar.FillPurple
	end
	return V6.Bar.FillYellow
end

function Kit.Bar(parent: Instance, size: UDim2, color: Color3?)
	local bar = make("ImageLabel", { Name = "Bar", BackgroundTransparency = 1, Size = size, Image = "", BorderSizePixel = 0 }, parent)
	skin(bar, V6.Bar.Track, "Uniform", nil, nil)
	local track = make("Frame", { Name = "Track", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ClipsDescendants = true }, bar)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), Visible = false, Image = "", ZIndex = 2 }, track)
	local setFill = skinByHeight(fill, fillSpec(color), V6.Bar.FillYellow)
	local minW = make("UISizeConstraint", {}, fill)
	local function measure()
		-- The track window follows the bar's height (about 22% of it each side); the fill is never narrower than it is tall.
		local h = bar.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
		local inset = math.max(2, math.floor(h * 0.22 + 0.5))
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
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, label)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, label)
	make("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 18 }, label)
	local self = { Instance = bar, Fill = fill }
	function self.Set(fraction: number, text: string, tint: any?)
		fraction = math.clamp(fraction, 0, 1)
		fill.Visible = fraction > 0
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		local c = if tint == true then Theme.Danger elseif typeof(tint) == "Color3" then tint else color
		-- Warning amber has no fill of its own: it shows the yellow one.
		setFill(fillSpec(c))
		label.Text = text
	end
	return self
end

-- Switch 90x48 (the v6 Toggle.On / Toggle.Off sprites) with the word "On" / "Off" opposite the knob.
-- Returns { Instance, Set(on) }.
function Kit.Toggle(parent: Instance, initial: boolean, onChange: (boolean) -> ())
	local on = initial
	local b = make("ImageButton", {
		Size = UDim2.fromOffset(90, 48),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Image = "",
		BorderSizePixel = 0,
	}, parent)
	Kit.MinTouch(b)
	local label = Kit.Label(b, "", 16, Theme.TextPrimary, true)
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = false
	label.ZIndex = 3
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, label)
	local lpad = make("UIPadding", {}, label)
	b.ScaleType = Enum.ScaleType.Fit
	local function paint()
		label.Text = if on then "On" else "Off"
		local spec = if on then V6.Toggle.On else V6.Toggle.Off
		if Sprites.Ok(spec.Id) then
			b.Image = spec.Id
		else
			neutral(b)
		end
		-- Word on the side the knob has left; the knob is at the right when on.
		label.TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	end
	for _, spec in { V6.Toggle.On, V6.Toggle.Off } do
		Sprites.Watch(spec.Id, paint, b)
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

-- Horizontal slider 0..1 with a percent readout: Bar.Track + Bar.FillYellow and the Badge.Round knob. Fills the
-- width of its parent (height 48): track with 20 px of room for the knob at both ends, readout on the right.
-- Returns { Instance, Set(v) }.
function Kit.Slider(parent: Instance, initial: number, onChange: (number) -> (), onRelease: ((number) -> ())?)
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48) }, parent)
	local track = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(40 + 72), 0, 30),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 20, 0.5, 0),
		BorderSizePixel = 0,
		Image = "",
	}, root)
	skin(track, V6.Bar.Track, "Uniform", nil, nil)
	local inner = make("Frame", { Name = "Inner", BackgroundTransparency = 1, Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 1, -14), ClipsDescendants = true }, track)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, Image = "", ZIndex = 2 }, inner)
	skinByHeight(fill, V6.Bar.FillYellow)
	local thumb = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Image = "",
		ZIndex = 3,
	}, track)
	skin(thumb, V6.Badge.Round, nil, nil, nil)
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
