-- Small UI kit: Screen, Panel, Label, Pill, Icon, Rarity, Perks, Button, Bar, Toggle, Slider.
-- Owner rule: every UI visual is a generated sprite. Frames, buttons, bars, chips, badges, toasts, tooltips and
-- feedback art all come from SpriteIds6 (the unified purple and gold kit); icons come from the icon sheets
-- (SpriteIds6.Icons first, then SpriteIds / SpriteIds3 / IconIds). Code only lays things out and tints/fades the art; when a sprite is
-- unusable the piece shows the minimal neutral image (Sprites.FallbackId), never a code-drawn replacement shape.
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

local V6: any = Sprites.Ids6
local V4: any = Sprites.Ids4 -- icons and in-world (World.*) art only; every frame / control comes from V6
local Kit = {}

-- Scroll bars: every ScrollingFrame wears the v6 thumb sprite as its middle image (Roblox has no track image property).
local THUMB = V6.Scroll.Thumb.Id

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
		(i :: any).FontFace = Theme.BodyFont -- the one UI family; a prop below may still override it
	elseif class == "ScrollingFrame" then
		local s: any = i
		s.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		s.ScrollBarImageTransparency = 0
		-- One whole thumb sprite as the middle image; no top / bottom caps (nothing is spliced).
		s.TopImage, s.MidImage, s.BottomImage = "", THUMB, ""
		s.ScrollBarThickness = 10
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
-- Every sprite is ONE whole image (Stretch) locked to its native aspect by a UIAspectRatioConstraint, so the art is
-- never cut, tiled or distorted. A spec is { Id, Size = native px, Inner? = Rect of native px where content may sit }.
-- "Fit" (default) = the largest aspect-correct rectangle inside the Size the caller gave (AspectType FitWithinMaxSize).
-- Fit "Width" / "Height" = the other side follows (set that side of Size to 0): ScaleWithParentSize on that axis.
local ASPECT = "Aspect"

local function setAspect(img: any, spec: any, fitMode: string?)
	local c = img:FindFirstChild(ASPECT)
	if not c then
		c = Instance.new("UIAspectRatioConstraint")
		c.Name = ASPECT
		c.Parent = img
	end
	c.AspectRatio = spec.Size.X / spec.Size.Y
	if fitMode == "Width" then
		c.AspectType, c.DominantAxis = Enum.AspectType.ScaleWithParentSize, Enum.DominantAxis.Width
	elseif fitMode == "Height" then
		c.AspectType, c.DominantAxis = Enum.AspectType.ScaleWithParentSize, Enum.DominantAxis.Height
	else
		c.AspectType, c.DominantAxis = Enum.AspectType.FitWithinMaxSize, Enum.DominantAxis.Width
	end
end
Kit.SetAspect = setAspect

-- Native-px Rect -> UIPadding scale values (fractions of the sprite's own size). Specs without Inner get `fallback`.
local function innerPadding(spec: any, fallback: number?): (number, number, number, number)
	local r = spec.Inner
	if r then
		return r.Min.X / spec.Size.X, r.Min.Y / spec.Size.Y, (spec.Size.X - r.Max.X) / spec.Size.X, (spec.Size.Y - r.Max.Y) / spec.Size.Y
	end
	local f = fallback or 0.04
	return f, f, f, f
end
Kit.InnerPadding = innerPadding

local function applyPadding(pad: UIPadding, spec: any, extraX: number?, extraY: number?)
	local l, t, r, b = innerPadding(spec)
	pad.PaddingLeft, pad.PaddingTop = UDim.new(l, extraX or 0), UDim.new(t, extraY or 0)
	pad.PaddingRight, pad.PaddingBottom = UDim.new(r, extraX or 0), UDim.new(b, extraY or 0)
end
Kit.ApplyPadding = applyPadding

-- Neutral image shown in place of an unusable sprite.
local function neutral(img: any)
	img.Image = Sprites.FallbackId
	img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
	img.ScaleType = Enum.ScaleType.Stretch
	setAspect(img, Sprites.Fallback, nil)
end
Kit.Neutral = neutral

-- Draws spec on img (ImageLabel/ImageButton) as one whole image locked to its aspect. A missing or unloadable id shows the
-- neutral image and returns false. mode / cap are accepted for old callers and ignored.
local function skin(img: any, spec: any, fitMode: string?, _cap: number?, onFail: (() -> ())?, _onScale: ((number) -> ())?): boolean
	if not spec or not Sprites.Ok(spec.Id) then
		neutral(img)
		return false
	end
	img.Image = spec.Id
	img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
	img.ScaleType = Enum.ScaleType.Stretch
	setAspect(img, spec, if fitMode == "Width" or fitMode == "Height" then fitMode else nil)
	Sprites.Watch(spec.Id, function()
		if img.Image == spec.Id then
			neutral(img)
			if onFail then onFail() end
		end
	end, img)
	return true
end
Kit.Skin = skin

-- Swaps the sprite of an image already skinned (toast kinds, tab states) and re-locks its aspect.
function Kit.Reskin(img: any, spec: any, fitMode: string?)
	if not Sprites.Ok(spec.Id) then
		neutral(img)
		return
	end
	img.Image = spec.Id
	img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
	img.ScaleType = Enum.ScaleType.Stretch
	local c = img:FindFirstChild(ASPECT) :: UIAspectRatioConstraint?
	setAspect(img, spec, if fitMode then fitMode elseif c and c.AspectType == Enum.AspectType.ScaleWithParentSize then (if c.DominantAxis == Enum.DominantAxis.Width then "Width" else "Height") else nil)
end

-- Progress fill: the Bar.Fill* pill (one image, its own outline and round caps) grown from the left of `holder` (the track's
-- window, the art's Inner area) to the progress. The pill's height matches the window and its caps keep their round shape
-- at any length: only the pill's flat, horizontally uniform middle widens, so no seam shows. Below one cap-width of progress it shows as the round end alone. Returns { Clip, Fill,
-- SetProgress(fraction), SetSpec(spec) } (Clip is the fill itself; kept for callers). `unscaled` = the holder is not under the
-- HUD's UIScale (a BillboardGui).
local FILL_PAD = 4 -- transparent margin around the Bar.Fill* pills (native px)
function Kit.ProgressFill(holder: GuiObject, spec: any, fallback: any?, unscaled: boolean?)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, ZIndex = 2, Image = "", Visible = false, ScaleType = Enum.ScaleType.Slice }, holder)
	local current = spec
	local fraction = 0
	local function size()
		local sc = if unscaled then 1 else math.max(Scale.Value, 0.01)
		local w, h = holder.AbsoluteSize.X / sc, holder.AbsoluteSize.Y / sc
		if w < 1 or h < 1 then
			return
		end
		local nw, nh = current.Size.X, current.Size.Y
		local k = h / (nh - 2 * FILL_PAD) -- native px -> units, so the pill body is exactly the window height
		local cap = nh / 2 -- cap width incl. margin (native px): the pill's radius plus its margin
		-- A thin mid-height centre band: the art keeps its own height (a full-height centre renders black in Roblox).
		fill.SliceCenter = Rect.new(cap + 1, nh / 2 - 1, nw - cap - 1, nh / 2 + 1)
		fill.SliceScale = k * sc -- SliceScale is in screen pixels: the UIScale does not apply to it
		local body = math.max(fraction * w, h) -- never narrower than one round end
		fill.Size = UDim2.fromOffset(body + 2 * FILL_PAD * k, nh * k)
		fill.Position = UDim2.fromOffset(-FILL_PAD * k, -FILL_PAD * k)
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(size)
	local self: any = { Clip = fill, Fill = fill }
	function self.SetSpec(next: any)
		if not Sprites.Ok(next.Id) then
			if fallback and next ~= fallback then
				self.SetSpec(fallback)
			else
				neutral(fill)
				local c = fill:FindFirstChild(ASPECT)
				if c then c:Destroy() end
			end
			return
		end
		current = next
		fill.Image, fill.ImageRectOffset, fill.ImageRectSize = next.Id, Vector2.zero, Vector2.zero
		size()
		Sprites.Watch(next.Id, function()
			if fill.Image == next.Id then
				if fallback and next ~= fallback then self.SetSpec(fallback) else neutral(fill) end
			end
		end, fill)
	end
	function self.SetProgress(f: number)
		fraction = math.clamp(f, 0, 1)
		fill.Visible = fraction > 0
		size()
	end
	self.SetSpec(spec)
	return self
end

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

-- A decorative sprite image (no input): path is a spec path ("Fx.Burst"); props are ImageLabel properties. Kit sprites keep
-- their aspect ("fitMode" prop Fit = "Width" / "Height" lets one side follow); in-world art (World.*) keeps its own scale type.
function Kit.Sprite(parent: Instance?, path: string, props: { [string]: any }?): any
	local img = make("ImageLabel", { Name = (string.match(path, "[^%.]+$")), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Image = "" }, nil)
	local fitMode
	for k, v in props or {} do
		if k == "Fit" then
			fitMode = v
		else
			img[k] = v
		end
	end
	local spec = Kit.Spec(path)
	if string.sub(path, 1, 6) == "World." then
		skin(img, spec, nil) -- in-world art: the caller sizes it, so no aspect lock
		local c = img:FindFirstChild(ASPECT)
		if c then c:Destroy() end
		img.ScaleType = if props and props.ScaleType then props.ScaleType else Enum.ScaleType.Stretch
	else
		skin(img, spec, fitMode)
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

-- Tutorial / selection ring around an object, outset by `outset` reference px. Wide targets wear Frame.Highlight (2:1),
-- round / square ones Fx.Ring; the ring is one whole image centred on the object (never stretched).
function Kit.Ring(parent: Instance, outset: number?, round: boolean?): any
	local o = outset or 8
	local ring = Kit.Sprite(parent, if round then "Fx.Ring" else "Frame.Highlight", {
		Size = UDim2.new(1, o * 2, 1, o * 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 8,
		Visible = false,
	})
	return ring
end

-- Panels ---------------------------------------------------------------------
-- kind = { spec, noInset }. Every panel is one whole sprite; its UIPadding "Inset" is the sprite's Inner rect as scale.
local PANELS: { [string]: { any } } = {
	Large = { V6.Panel.Modal },
	Compact = { V6.Panel.ModalCompact },
	Plain = { V6.Panel.ModalPlain },
	PlainCompact = { V6.Panel.ModalPlainCompact },
	PlainSquare = { V6.Panel.ModalPlainSquare },
	Small = { V6.Panel.Section },
	Pill = { V6.Hud.Pill },
	PillGold = { V6.Hud.PillGold },
	Bar = { V6.Hud.BarWide },
	BarGold = { V6.Hud.BarWideGold },
	Row = { V6.Row.Well },
	Chip = { V6.Chip.Purple },
	Tooltip = { V6.Panel.Tooltip },
	TooltipLeft = { V6.Panel.TooltipLeft },
	TitleBar = { V6.Panel.SectionPlate, true },
	Tray = { V6.Panel.Tray },
	ToastInfo = { V6.Toast.Info },
	ToastGood = { V6.Toast.Good },
	ToastBad = { V6.Toast.Bad },
	ToastWideInfo = { V6.ToastWide.Info },
	ToastWideGood = { V6.ToastWide.Good },
	ToastWideBad = { V6.ToastWide.Bad },
	Bubble = { V6.Bubble.Tutorial },
	BubbleWide = { V6.Bubble.Wide },
	LoadFail = { V6.Panel.ModalCompact },
	ReelWindow = { V6.Panel.Section },
	Card = { V6.Card.Normal },
	CardSelected = { V6.Card.Selected },
	CardGlow = { V6.Card.Glow },
	CardShop = { V6.Card.Shop },
	CardInfo = { V6.Card.Info },
	Slot = { V6.Slot.Empty },
}
Kit.PanelKinds = PANELS

-- props: any property of the panel plus
--   Sprite  a PANELS kind ("Large" = Panel.Modal, "Compact" = Panel.ModalCompact, "Small" (default) = Panel.Section, "Row" =
--           Row.Well, "Pill" / "PillGold" = Hud.Pill, "Bar" = Hud.BarWide, "Tooltip(Left)", "Tray", "Toast*", "Bubble(Wide)",
--           "Card" / "CardSelected" / "CardGlow" / "CardShop" / "CardInfo", "Slot", ...)
--   Rarity  tier name: draws that tier's card frame instead
--   Pad     extra content padding in px (number or Vector2) added to the sprite's Inner inset.
--   Fit     "Width" (height follows the width: give Size (x, 0, 0, 0)) / "Height" (width follows the height) / default: the
--           largest aspect-correct rectangle inside the Size given.
-- The panel is an ImageLabel wearing ONE whole sprite (ScaleType Stretch + UIAspectRatioConstraint = Size.X / Size.Y), with a
-- UIPadding "Inset" equal to the sprite's Inner rect (as scale) plus Pad, so children sit inside the art's content area.
function Kit.Panel(parent: Instance, props: { [string]: any }?): any
	local f = make("ImageLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, Image = "" }, parent)
	local kind, rarity, fitMode = "Small", nil, nil
	local padX, padY = 0, 0
	for k, v in props or {} do
		if k == "Sprite" then
			kind = if type(v) == "string" then v else "Small"
		elseif k == "Rarity" then
			rarity = v
		elseif k == "Fit" then
			fitMode = v
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
	local spec, noInset = entry[1], entry[2]
	if rarity and V6.Rarity[rarity] then
		spec, noInset = V6.Rarity[rarity], false
	end
	skin(f, spec, fitMode)
	if not noInset then
		local inset = make("UIPadding", { Name = "Inset" }, f)
		applyPadding(inset, spec, padX, padY)
		f.ClipsDescendants = true
	end
	if rarity == "Secret" then Kit.Prismatic(f) end
	return f
end

-- Swaps the art of a Kit.Panel to another PANELS kind (selection / hover states), keeping its Inset in step.
function Kit.RepaintPanel(panel: any, kind: string, rarity: string?)
	local entry = PANELS[kind] or PANELS.Small
	local spec = if rarity and V6.Rarity[rarity] then V6.Rarity[rarity] else entry[1]
	Kit.Reskin(panel, spec)
	local inset = panel:FindFirstChild("Inset")
	if inset then applyPadding(inset, spec) end
end

-- Rarity gem (small diamond/jewel) of a tier.
function Kit.Gem(parent: Instance, rarity: string?, size: UDim2?): any
	local r = if rarity and SpriteIds.Rarity[rarity] then rarity else "Common"
	local gem = make("ImageLabel", { Name = "Gem", BackgroundTransparency = 1, Size = size or UDim2.fromOffset(24, 24), ScaleType = Enum.ScaleType.Fit }, parent)
	local gemId = SpriteIds.Rarity[r].Gem -- an icon-sized whole image: Fit keeps its aspect
	if Sprites.Ok(gemId) then
		gem.Image = gemId
		Sprites.Watch(gemId, function()
			if gem.Image == gemId then neutral(gem); gem.ScaleType = Enum.ScaleType.Fit end
		end, gem)
	else
		neutral(gem)
		gem.ScaleType = Enum.ScaleType.Fit
	end
	local ac = gem:FindFirstChild(ASPECT)
	if ac then ac:Destroy() end
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

-- Modal chrome shared by every popup (Modal.New) and the Bag / Index / Upgrades shell: Panel.Modal (or Panel.ModalCompact)
-- back, the Panel.SectionPlate title plate straddling the top edge (centred, cream title with a dark outline) and
-- Round.Close overlapping the top-right corner. The back is ONE whole image, so the modal rectangle has the art's own aspect:
-- callers size Root as (width, width / self.Ratio). Returns { Root, Back, Plate, Title, Close, Ratio, Spec,
-- Layout(width) -> overhang, BodyRect(width, height) } where Root is the modal rectangle (the caller sizes and places it),
-- the plate and the close button hang above / over its top edge and Layout(width) (reference px) returns how far the plate
-- rises above Root, so the caller can leave room for it. Spec.Inner (native px) is the content rectangle.
-- kind: "Tabbed" (Panel.Modal: header strip for a tab row), "Plain" (default, Panel.ModalPlain: no header strip, the well fills the
-- window), "PlainCompact" (also `true`), "PlainSquare".
function Kit.ModalChrome(parent: Instance, title: string, onClose: () -> (), kind: any?): any
	local k = if kind == true then "PlainCompact" elseif kind == nil or kind == false then "Plain" else kind
	local compact = k == "PlainCompact"
	local root = make("Frame", { Name = "Modal", BackgroundTransparency = 1, BorderSizePixel = 0 }, parent)
	local back = Kit.Panel(root, { Sprite = if k == "Tabbed" then "Large" else k, Size = UDim2.fromScale(1, 1), ZIndex = 0, Active = true })
	local backSpec = (PANELS[if k == "Tabbed" then "Large" else k] :: any)[1]
	back.ClipsDescendants = false
	local inset = back:FindFirstChild("Inset")
	if inset then inset:Destroy() end -- content is placed explicitly by the caller
	local plate = Kit.Panel(root, { Sprite = "TitleBar", AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Active = false })
	local label = Kit.Label(plate, title, Theme.TextSize.Title, Theme.TextPrimary, true)
	-- The plate's laurels take 25% of the width each side; the title sits in the band between them.
	-- One fixed title size for every modal (the plate widens to fit the text in Layout, the text never shrinks).
	label.ZIndex, label.TextWrapped, label.TextScaled, label.TextTruncate = 4, false, false, Enum.TextTruncate.None
	label.TextSize = Theme.TextSize.Title
	label.Position, label.Size = UDim2.fromScale(0.25, 0.26), UDim2.fromScale(0.5, 0.46)
	make("UIStroke", { Color = Theme.Stroke, Thickness = 3 }, label)
	local closeButton = Kit.CloseButton(root, UDim2.fromOffset(54, 54), onClose)
	local close = closeButton.Instance
	close.AnchorPoint, close.ZIndex = Vector2.new(0.5, 0.5), 5
	local self = { Root = root, Back = back, Plate = plate, Title = label, Close = close, Ratio = backSpec.Size.X / backSpec.Size.Y, Spec = backSpec }
	function self.Layout(width: number): number
		local phone = Scale.Phone
		local plateSpec = V6.Panel.SectionPlate
		local w = math.clamp(width * (if compact then 0.62 else 0.36), if phone then 230 else 300, if compact then 360 else 470)
		-- A long title gets a wider plate (the title band is half of the plate width), never crammed into a small one.
		do
			local tw = Kit.Measure(label.Text, Theme.TextSize.Title, Theme.HeadingFont, 2000).X
			w = math.min(math.max(w, tw / 0.5 + 24), math.max(width - 120, 200))
		end
		local h = w * plateSpec.Size.Y / plateSpec.Size.X
		local rise = math.floor(h * 0.6)
		plate.Size, plate.Position = UDim2.fromOffset(w, h), UDim2.new(0.5, 0, 0, -rise)
		local size = if phone then 56 else 72
		close.Size, close.Position = UDim2.fromOffset(size, size), UDim2.new(1, -(size * 0.62), 0, size * 0.3)
		return rise + 6
	end
	-- The content rectangle (reference px, relative to Root) of a modal of this width x height.
	function self.BodyRect(width: number, height: number): (number, number, number, number)
		local r = backSpec.Inner :: Rect
		local sx, sy = width / backSpec.Size.X, height / backSpec.Size.Y
		-- Inset a little inside the art's inner rim so scrolled content never overlaps it.
		local ix, iy = 10, 12
		return r.Min.X * sx + ix, r.Min.Y * sy + iy, (r.Max.X - r.Min.X) * sx - ix * 2, (r.Max.Y - r.Min.Y) * sy - iy * 2
	end
	return self
end

-- One fixed size for a label (typography rule: a size per role, never per item): no TextScaled, no size constraint.
function Kit.FixedText(label: TextLabel, size: number): TextLabel
	label.TextScaled = false
	for _, c in label:GetChildren() do
		if c:IsA("UITextSizeConstraint") then
			c:Destroy()
		end
	end
	label.TextSize = size
	return label
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
local TextService = game:GetService("TextService")
local pillFit = setmetatable({}, { __mode = "k" }) :: { [any]: (number?) -> () }

-- A chip / badge: ONE whole sprite with the text inside its Inner rect. `height` is the wanted chip height (px); the chip
-- is as wide as the art's aspect gives, and grows (still at the art's aspect) when the text needs more room.
local function pillWith(parent: Instance, text: string, spec: any, fg: Color3, height: number?): any
	local ratio = spec.Size.X / spec.Size.Y
	local baseH = height or 30
	local root = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(baseH * ratio, baseH), Image = "" }, parent)
	local label = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		TextColor3 = fg,
		Text = text,
		TextSize = Theme.TextSize.Caption,
		FontFace = Theme.HeadingFont,
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
		ZIndex = 2,
	}, root)
	applyPadding(make("UIPadding", { Name = "Inset" }, label), spec)
	if fg == Theme.TextPrimary then
		make("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, label)
	end
	skin(root, spec, nil)
	local inner = spec.Inner
	local fracW = if inner then (inner.Max.X - inner.Min.X) / spec.Size.X else 0.9
	local fracH = if inner then (inner.Max.Y - inner.Min.Y) / spec.Size.Y else 0.9
	local function refit(h: number?)
		baseH = h or baseH
		-- Chip text never drops below the 16 px counter size: a short chip grows to hold it instead.
		local ts = math.clamp(math.floor(baseH * fracH * 0.88), Theme.TextSize.Tiny, 44)
		baseH = math.max(baseH, math.ceil(ts / (fracH * 0.88)))
		label.TextSize = ts
		local ok, bounds = pcall(function()
			local params = Instance.new("GetTextBoundsParams")
			params.Text, params.Font, params.Size, params.Width = label.Text, Theme.HeadingFont, ts, 2000
			return TextService:GetTextBoundsAsync(params)
		end)
		local tw = if ok then bounds.X else #label.Text * ts * 0.6
		local w = math.max(baseH * ratio, (tw + 6) / fracW)
		root.Size = UDim2.fromOffset(w, w / ratio)
	end
	pillFit[root] = refit
	refit()
	return root
end

function Kit.Pill(parent: Instance, text: string, bg: Color3, fg: Color3, height: number?): any
	return pillWith(parent, text, chipSpec(bg), fg, height)
end

-- Count badge ("x50"): Badge.Count (yellow) with dark text; a grey chip when the count is zero (enabled = false).
function Kit.Count(parent: Instance, text: string, enabled: boolean?, height: number?): any
	if enabled == false then
		return pillWith(parent, text, V6.Chip.Grey, GREY_COUNT_TEXT, height or 34)
	end
	return pillWith(parent, text, V6.Badge.Count, Theme.TextOnGold, height or 34)
end

-- A Kit.Pill / Count / Rarity chip of an explicit sprite (spec path "Tag.Label", "Chip.Gold", ...).
function Kit.Tag(parent: Instance, text: string, specPath: string, fg: Color3?, height: number?): any
	return pillWith(parent, text, Kit.Spec(specPath) or V6.Chip.Purple, fg or Theme.TextPrimary, height)
end

-- Re-sizes a chip to a new height (px); it keeps the art's aspect.
function Kit.SetPillHeight(pill: any, height: number)
	local f = pillFit[pill]
	if f then f(height) end
end

-- The text label of a Kit.Pill.
function Kit.PillLabel(pill: any): TextLabel
	return pill:FindFirstChild("Label") or pill
end

-- Sets the text of a Kit.Pill (the chip re-fits its width).
function Kit.SetText(pill: any, text: string)
	local l = pill:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then
		l.Text = text
		local f = pillFit[pill]
		if f then f() end
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

-- Icon-name aliases onto the kit's Icons.
local ICON_ALIAS = { Loot = "DropChance", Cross = false }

-- Icon by name as an ImageLabel: a whole SpriteIds6.Icons image first, then a SpriteIds.Icons entry, a SpriteIds3 one, a v4
-- icon, else an IconIds one. Nothing usable shows the neutral image. Icons are drawn whole (ScaleType Fit): never cropped.
function Kit.SetIcon(img: ImageLabel, name: string)
	local alias = ICON_ALIAS[name]
	local kit = (V6.Icons :: any)[name] or (if type(alias) == "string" then (V6.Icons :: any)[alias] else nil)
	local id = if kit and Sprites.Ok(kit.Id) then kit.Id elseif name == "Cross" then V6.Round.Close.Id else ((SpriteIds.Icons :: any)[if alias == nil then name else alias] or FLAT3[if type(alias) == "string" then alias else name] or V4ICONS[name] or (IconIds :: any)[name] or SpriteIds.Rooms[name])
	if id and Sprites.Ok(id) then
		if img.Image == id then return end
		img.Image = id
		img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
		Sprites.Watch(id, function()
			if img.Image == id then
				neutral(img)
			end
		end, img)
	else
		neutral(img)
	end
	img.ScaleType = Enum.ScaleType.Fit
	local c = img:FindFirstChild(ASPECT)
	if c then c:Destroy() end
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
	local pill = pillWith(parent, r, V6.RarityBadge[r], Theme.TextPrimary, height or 34)
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
	Primary = { Theme.Gold, Theme.TextOnGold, "Yellow" },
	Secondary = { Theme.BgRaised, Theme.TextPrimary, "Purple" },
	Success = { Theme.Success, Theme.TextPrimary, "Green" },
	Danger = { Theme.Danger, Theme.TextPrimary, "Red" },
	Cancel = { Theme.BgRaised, Theme.TextPrimary, "Purple" },
	Tab = { Theme.BgRaised, Theme.TextPrimary, nil },
	Nav = { Theme.BgRaised, Theme.TextPrimary, nil },
	Card = { Theme.BgRaised, Theme.TextPrimary, nil }, -- selectable card (Card.Normal / Card.Selected), e.g. threat tiers
}
-- Wide / price variants have no red art: danger wears the purple one tinted red.
local DANGER_TINT = Color3.fromRGB(255, 120, 130)

-- The art of a plain button: family "Normal" = Button.*, "Wide" = ButtonWide.*, "Price" = ButtonPrice.* (yellow / grey only).
local function buttonArt(color: string, family: string, pressed: boolean): any
	if family == "Wide" then
		local W = V6.ButtonWide
		return W[color] or W.Purple
	elseif family == "Price" then
		local P = V6.ButtonPrice
		return P[color] or V6.ButtonWide[color] or P.Yellow
	end
	return if pressed then (B6[color .. "Pressed"] or B6[color]) else B6[color]
end

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

-- Tooltip: hover (mouse) or press-and-hold (touch) shows a short label above the object (Panel.Tooltip, tail down), beside it
-- (Panel.TooltipLeft, tail left) when there is no room above, or below near the top edge. The tip is ONE whole sprite
-- sized from the text: wide enough for the wrapped text inside its Inner rect, at the art's own aspect.
-- For icon-only UI whose meaning is not obvious.
local tipGui: ScreenGui? = nil
local tipFrame: any = nil
local tipText: TextLabel? = nil
local tipId = 0
local TIP_WRAP = 300
local TIP_SIZE = 20

-- Size (px) of a sprite whose Inner rect has to hold a cw x ch content block.
local function spriteFor(spec: any, cw: number, ch: number): (number, number)
	local r = spec.Inner :: Rect
	local fracW, fracH = (r.Max.X - r.Min.X) / spec.Size.X, (r.Max.Y - r.Min.Y) / spec.Size.Y
	local ratio = spec.Size.X / spec.Size.Y
	local w = math.max(cw / fracW, (ch / fracH) * ratio)
	return w, w / ratio
end
Kit.SpriteFor = spriteFor

local function measure(text: string, size: number, font: Font, width: number): Vector2
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text, params.Font, params.Size, params.Width = text, font, size, width
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok then return bounds end
	return Vector2.new(math.min(#text * size * 0.55, width), size * 1.2 * (1 + math.floor(#text * size * 0.55 / width)))
end
Kit.Measure = measure

local function ensureTip()
	if tipGui and tipGui.Parent then
		return
	end
	local gui = make("ScreenGui", { Name = "Tips", ResetOnSpawn = false, DisplayOrder = 80, ScreenInsets = Enum.ScreenInsets.None }, nil)
	Scale.Attach(gui)
	local f = Kit.Panel(gui, { Sprite = "Tooltip", Visible = false, Size = UDim2.fromOffset(0, 0), Active = false })
	f.ClipsDescendants = false
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, content)
	local t = Kit.Label(content, "", TIP_SIZE, Theme.TextPrimary, true)
	t.LayoutOrder = 1
	t.Size, t.TextWrapped = UDim2.fromOffset(TIP_WRAP, 0), true
	Kit.Stroke(t, Theme.Stroke, 2)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	tipGui, tipFrame, tipText = gui, f, t
end

local function showTip(obj: GuiObject, text: string, color: Color3?, rarity: string?)
	ensureTip()
	local f, t, gui = tipFrame :: any, tipText :: TextLabel, tipGui :: ScreenGui
	local content = f.Content
	t.Text = text
	-- Rarity tip: the tier's RarityBadge sits above the text.
	local old = content:FindFirstChild("RarityTag")
	if old then old:Destroy() end
	local tagH = 0
	if rarity then
		local tag = Kit.Rarity(content, rarity, 34)
		tag.Name, tag.LayoutOrder = "RarityTag", 0
		tagH = tag.Size.Y.Offset + 2
	end
	t.TextColor3 = color or Theme.TextPrimary
	local bounds = measure(text, TIP_SIZE, Theme.HeadingFont, TIP_WRAP)
	local tw = math.min(bounds.X + 6, TIP_WRAP)
	t.Size = UDim2.fromOffset(tw, bounds.Y + 4)
	local cw, ch = math.max(tw, 120), bounds.Y + 4 + tagH
	-- Placement: above (tail down) > right (tail left) > below.
	local sc = math.max(Scale.Value, 0.01)
	local view = gui.AbsoluteSize / sc
	local c = (obj.AbsolutePosition + obj.AbsoluteSize / 2 - gui.AbsolutePosition) / sc
	local half = obj.AbsoluteSize / sc / 2
	local up = V6.Panel.Tooltip
	local w, h = spriteFor(up, cw, ch)
	local side = nil
	if c.Y - half.Y - 8 < h + 6 then
		local lw, lh = spriteFor(V6.Panel.TooltipLeft, cw, ch)
		if c.X + half.X + 8 + lw + 6 <= view.X then
			side = { lw, lh }
		end
	end
	if side then
		Kit.Reskin(f, V6.Panel.TooltipLeft)
		Kit.ApplyPadding(f.Inset, V6.Panel.TooltipLeft)
		f.Size = UDim2.fromOffset(side[1], side[2])
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = UDim2.fromOffset(c.X + half.X + 8, math.clamp(c.Y, side[2] / 2 + 6, math.max(side[2] / 2 + 6, view.Y - side[2] / 2 - 6)))
	else
		Kit.Reskin(f, up)
		Kit.ApplyPadding(f.Inset, up)
		f.Size = UDim2.fromOffset(w, h)
		local above = c.Y - half.Y - 8
		local y = if above >= h + 6 then above - h else c.Y + half.Y + 8
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.fromOffset(math.clamp(c.X, w / 2 + 6, math.max(w / 2 + 6, view.X - w / 2 - 6)), math.clamp(y, 6, math.max(6, view.Y - h - 6)))
	end
	f.Visible = true
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

-- opts: Text, Style (Primary/Secondary/Success/Danger/Cancel/Tab/Nav/Card), Size (UDim2, default 140x56; never below 44 px:
-- the art is the largest aspect-correct rectangle inside it, centred), OnClick, Icon (icon name, see Kit.Icon), IconLayout
-- ("Column" = icon above the label, default; "Row" = icon at the left), Round (the round icon-button sprite), Variant
-- ("Wide" = ButtonWide / Tab.Wide*, "Price" = ButtonPrice; default picked from the Size's aspect), Rarity (tier name: the
-- button is that tier's card frame instead of a styled button).
-- The button is a TextButton (transparent hit box) holding the sprite "Skin" (one whole image: normal / pressed / disabled
-- art) with a "Content" frame inside its Inner rect holding an optional "Icon" and the text "Label". Selection and the
-- tutorial highlight show a ring sprite (Frame.Highlight / Fx.Ring), whole and centred.
-- Returns { Instance, Stroke (always disabled; kept for callers), Icon, Content, Label, SetText, SetTextSize, SetEnabled(on,
-- reasonText?, locked?), SetSelected (visual only), SetStyle, SetEdge, SetBadge(n), SetHighlight(thickness?), Shimmer }.
function Kit.Button(parent: Instance, opts: { [string]: any })
	local style = STYLES[opts.Style or "Secondary"]
	local isTab = opts.Style == "Tab"
	local isNav = opts.Style == "Nav" or opts.Style == "Card" -- states swap the art instead of tinting it
	local isCard = opts.Style == "Card"
	local size: UDim2 = opts.Size or UDim2.fromOffset(140, 56)
	-- A square box on a plain style is an icon button: the round art fits it (the wide button art would shrink to a sliver).
	local isRound = opts.Round == true
	if not isRound and not opts.Rarity and not isTab and not isNav and size.X.Scale == 0 and size.Y.Scale == 0 and size.Y.Offset > 0 then
		local r = size.X.Offset / size.Y.Offset
		isRound = r >= 0.8 and r <= 1.3 and (opts.Style == "Primary" or opts.Style == "Secondary" or opts.Style == nil)
	end
	size = UDim2.new(
		size.X.Scale,
		if size.X.Scale == 0 then math.max(size.X.Offset, 44) else size.X.Offset,
		size.Y.Scale,
		if size.Y.Scale == 0 then math.max(size.Y.Offset, 44) else size.Y.Offset
	)
	-- Family: explicit Variant, else from the aspect of a fixed pixel Size.
	local family = opts.Variant or "Normal"
	if not opts.Variant and size.X.Scale == 0 and size.Y.Scale == 0 and size.Y.Offset > 0 then
		local r = size.X.Offset / size.Y.Offset
		if r >= 3.3 then
			family = "Wide"
		elseif r >= 2.75 and opts.Price then
			family = "Price"
		end
	end

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
	local tint: Color3? = nil -- wide danger: the purple art tinted red

	local function specs(): (any, any)
		if opts.Rarity and V6.Rarity[opts.Rarity] then
			return V6.Rarity[opts.Rarity], nil
		elseif isRound then
			return (if opts.Style == "Primary" then V6.Round.Yellow else V6.Round.Purple), nil
		elseif isTab then
			if family == "Wide" then
				return (if selected then V6.Tab.WideOn else V6.Tab.WideOff), nil
			end
			return (if selected then V6.Tab.On else V6.Tab.Off), nil
		elseif isCard then
			return (if selected then V6.Card.Selected else V6.Card.Normal), nil
		elseif isNav then
			return (if selected then V6.Nav.On else V6.Nav.Off), nil
		end
		local color = style[3]
		tint = if family ~= "Normal" and color == "Red" then DANGER_TINT else nil
		return buttonArt(color, family, false), buttonArt(color, family, true)
	end
	local normalSpec, pressedSpec = specs()

	-- Layers: Skin (one whole image, aspect-locked) holds Content (inside its Inner rect): Icon under Label; Ring above.
	local img = make("ImageLabel", { Name = "Skin", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 1, Image = "", Active = false }, b)
	local paint
	skin(img, normalSpec, nil, nil, function()
		if paint then
			paint()
		end
	end)
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, img)
	local contentPad = make("UIPadding", {}, content)
	applyPadding(contentPad, normalSpec)
	for _, s in { pressedSpec, buttonArt("Grey", family, false), V6.Tab.On, V6.Tab.Off, V6.Tab.WideOn, V6.Tab.WideOff, V6.Nav.On, V6.Nav.Off } do
		if s and Sprites.Ok(s.Id) then
			task.spawn(function() -- warm the other states so the first press does not flash
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ s.Id })
				end)
			end)
		end
	end
	local ring = Kit.Ring(img, if isTab then 3 else 6, isNav or isRound)

	local shownSpec = normalSpec
	local function show(spec: any)
		if spec and Sprites.Ok(spec.Id) and shownSpec ~= spec then
			shownSpec = spec
			Kit.Reskin(img, spec)
			-- Nav art keeps one content area across states, so labels do not jump when it lights up.
			applyPadding(contentPad, if isNav and not isCard then V6.Nav.Off else spec)
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
		TextScaled = false,
	}, content)
	-- Fixed size per role (opts.TextSize, never below the 18 px label minimum): the box is made to fit the text, the text
	-- never shrinks per button.
	label.TextSize = math.max(opts.TextSize or Theme.TextSize.Button, Theme.TextSize.Label)
	local pad = make("UIPadding", {}, label)
	-- Cream labels on purple / green / red art carry the dark outline; dark labels on yellow and grey do not.
	local labelStroke = make("UIStroke", { Color = Theme.Stroke, Thickness = 2, Enabled = style[2] == Theme.TextPrimary }, label)

	local icon: any = nil
	if opts.Icon then
		local row = opts.IconLayout == "Row"
		-- Square icon: as tall as the fraction of the content area, never wider than it.
		icon = Kit.Icon(content, opts.Icon, UDim2.new(1, 0, if row then (if isTab then 0.9 else 0.8) else (opts.IconScale or 0.55), 0), style[2])
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, icon)
		local centred = not row and baseText == ""
		icon.AnchorPoint = if row then Vector2.new(0, 0.5) elseif centred then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 0)
		icon.Position = if row then UDim2.new(0, 2, 0.5, 0) elseif centred then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.5, 0, 0, -2)
		icon.ZIndex = 2
		if row then
			pad.PaddingLeft = UDim.new(0.25, 0) -- a clear gap between the icon and the text
		elseif not centred then
			label.TextYAlignment = Enum.TextYAlignment.Bottom
			pad.PaddingTop = UDim.new(0.55, 0)
		end
		self.Icon = icon
	end
	self.Content, self.Label = content, label

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
			text = if plainStyle then (opts.DisabledText or GREY_TEXT) else Theme.DisabledText
		end
		label.TextColor3 = text
		labelStroke.Enabled = text == Theme.TextPrimary
		local base = tint or Color3.new(1, 1, 1)
		if isTab or isNav then
			show(normalSpec)
			img.ImageColor3 = if not enabled then Color3.fromRGB(150, 142, 165) elseif hover and not selected then Color3.fromRGB(235, 228, 255) else Color3.new(1, 1, 1)
		elseif not enabled then
			if plainStyle then
				show(buttonArt("Grey", family, false))
				img.ImageColor3 = Color3.new(1, 1, 1)
			else
				show(normalSpec)
				img.ImageColor3 = Color3.fromRGB(150, 142, 165)
			end
		else
			show(if pressed and pressedSpec and family == "Normal" then pressedSpec else normalSpec)
			img.ImageColor3 = if pressed then base:Lerp(Color3.new(0.9, 0.9, 0.9), 0.5) elseif hover then base:Lerp(Color3.fromRGB(255, 252, 245), 0.4) else base
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
	Sprites.Watch(buttonArt("Grey", family, false).Id, function()
		if paint then
			paint()
		end
	end, img)

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
		label.TextSize = math.max(n, Theme.TextSize.Label)
	end
	function self.SetEnabled(on: boolean, reason: string?, locked: boolean?)
		enabled = on
		b.Active = on
		label.Text = if not on and reason then reason else baseText
		-- Lock icon beside the reason ("Need 50 more").
		local showLock = locked == true and not on and not icon
		if showLock and not lock then
			lock = Kit.Icon(content, "Lock", UDim2.fromScale(0.2, 0.8), Theme.DisabledText)
			make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }, lock)
			lock.AnchorPoint = Vector2.new(0, 0.5)
			lock.Position = UDim2.new(0, 0, 0.5, 0)
			lock.ZIndex = 2
		end
		if lock then
			lock.Visible = showLock
			pad.PaddingLeft = UDim.new(if showLock then 0.16 else 0, 0)
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
			badge = pillWith(b, "", V6.Badge.Count, Theme.TextOnGold, 32)
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

-- Progress bar from the v6 sprites: Bar.Track (or Hud.BarWide with wide = true), whole and aspect-locked, with a whole Bar.Fill*
-- sprite at the full size of the track's window inside a clipping frame whose width is the progress (the fill is never
-- stretched to the progress). Centred text sits over the window.
-- color picks the fill variant (Theme.Success = green, Theme.Danger = red, Theme.Accent = purple, anything else /
-- nil = yellow). Size is the bounding box (the art fits inside it, centred). Returns { Instance, Fill, Set(fraction, text,
-- tint?) } where tint is a Color3, or true for the danger red.
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

function Kit.Bar(parent: Instance, size: UDim2, color: Color3?, wide: boolean?)
	local trackSpec = if wide then V6.Hud.BarWide else V6.Bar.Track
	local bar = make("ImageLabel", { Name = "Bar", BackgroundTransparency = 1, Size = size, Image = "", BorderSizePixel = 0 }, parent)
	skin(bar, trackSpec, nil)
	local l, t, r, b = innerPadding(trackSpec)
	local window = make("Frame", { Name = "Track", BackgroundTransparency = 1, Position = UDim2.fromScale(l, t), Size = UDim2.fromScale(1 - l - r, 1 - t - b) }, bar)
	local progress = Kit.ProgressFill(window, fillSpec(color), V6.Bar.FillYellow)
	local label = Kit.Label(window, "", 16, Theme.TextPrimary, true)
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.TextWrapped = false
	label.TextScaled = false
	label.TextSize = Theme.TextSize.Tiny -- one fixed counter size for every bar
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }, label)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 1) }, label)
	local self = { Instance = bar, Fill = progress.Fill, Clip = progress.Clip }
	function self.Set(fraction: number, text: string, tint: any?)
		progress.SetProgress(fraction)
		local c = if tint == true then Theme.Danger elseif typeof(tint) == "Color3" then tint else color
		-- Warning amber has no fill of its own: it shows the yellow one.
		progress.SetSpec(fillSpec(c))
		label.Text = text
	end
	return self
end

-- Switch 90x48 (the v6 Toggle.On / Toggle.Off sprites, 278:148 whole) with the word "On" / "Off" opposite the knob.
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
	local function paint()
		label.Text = if on then "On" else "Off"
		local spec = if on then V6.Toggle.On else V6.Toggle.Off
		if Sprites.Ok(spec.Id) then
			Kit.Skin(b, spec, nil)
		else
			neutral(b)
		end
		-- Word on the side the knob has left; the knob is at the right when on.
		label.TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		lpad.PaddingLeft, lpad.PaddingRight = UDim.new(0.14, 0), UDim.new(0.14, 0)
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

-- Horizontal slider 0..1 with a percent readout: Bar.Track whole (height 44, width at the art's aspect), the Bar.FillYellow
-- fill clipped to the value, and the Badge.Round knob. Fills the width of its parent (height 56): track centred-left, readout
-- on the right. Returns { Instance, Set(v) }.
function Kit.Slider(parent: Instance, initial: number, onChange: (number) -> (), onRelease: ((number) -> ())?)
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) }, parent)
	local trackH = 44
	local trackW = math.floor(trackH * V6.Bar.Track.Size.X / V6.Bar.Track.Size.Y + 0.5)
	local track = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(trackW, trackH),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 28, 0.5, 0),
		BorderSizePixel = 0,
		Image = "",
	}, root)
	skin(track, V6.Bar.Track, nil)
	local l, t, r, b = innerPadding(V6.Bar.Track)
	local window = make("Frame", { Name = "Inner", BackgroundTransparency = 1, Position = UDim2.fromScale(l, t), Size = UDim2.fromScale(1 - l - r, 1 - t - b) }, track)
	local progress = Kit.ProgressFill(window, V6.Bar.FillYellow)
	local thumb = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Image = "",
		ZIndex = 3,
	}, window)
	skin(thumb, V6.Badge.Round, nil)
	local readout = Kit.Label(root, "", 24, Theme.TextPrimary, true)
	readout.AnchorPoint = Vector2.new(0, 0.5)
	readout.Position = UDim2.new(0, 28 + trackW + 24, 0.5, 0)
	readout.Size = UDim2.fromOffset(68, 40)
	readout.TextWrapped = false
	readout.TextXAlignment = Enum.TextXAlignment.Left

	local value = initial
	local function paint()
		progress.SetProgress(value)
		thumb.Position = UDim2.fromScale(value, 0.5)
		readout.Text = math.floor(value * 100 + 0.5) .. "%"
	end
	paint()

	-- >= 48 px hit area over the track and thumb.
	local hitH = if Scale.Phone or UserInputService.TouchEnabled then math.max(48, 48 / math.max(Scale.Value, 0.1)) else 48
	local hit = make("TextButton", {
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 56, 0, hitH),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -28, 0.5, 0),
		ZIndex = 5,
	}, track)
	local dragging = false
	local locked = false
	local function setFrom(x: number)
		value = math.clamp((x - window.AbsolutePosition.X) / math.max(window.AbsoluteSize.X, 1), 0, 1)
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
			progress.Fill.ImageTransparency = if on then 0.5 else 0
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
