-- Bag: chest drops and owned room items. The odds
-- are the server's (State.BoxOdds: exactly what the next open rolls from).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Badges = require(script.Parent.Badges)
local Bus = require(script.Parent.Bus)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local P = require(script.Parent.PanelsKit)
local RarityColors = require(script.Parent.RarityColors)
local ReasonText = require(script.Parent.ReasonText)
local Settings = require(script.Parent.Settings)
local Scale = require(script.Parent.Scale)
local Sound = require(script.Parent.Sound)
local Sprites = require(script.Parent.Sprites)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local L = {}

local busy = false
local currentTab = "Drops"
local selectedBox = "Dungeon"
local selectedQty: { [string]: number } = {}
local openConfirmUntil = 0
local openConfirmKey = ""
local selectedItems: { [string]: number } = {}
local sellConfirmUntil = 0
local sellConfirmKey = ""
local inventoryTabs = setmetatable({}, { __mode = "k" })

-- The tooltip holds two lines at its fixed size: a description is cut to its first sentence.
local function firstSentence(text: string): string
	local s = string.match(text, "^(.-[%.!?])%s") or text
	return s
end

local function roomName(id: string): string
	local def = Catalog.Room(id)
	return def and def.DisplayName or P.Spaced(id)
end

-- Reveal: shake a closed box (~0.8 s), then show room, rarity and perks. Instant when motion is reduced.
-- The result card shows the tier by gem and colour (Secret keeps a shimmer; static under reduced motion).
-- Tapping anywhere (or Esc / B) skips the shake, then closes the card. The catcher is its own full-screen
-- ScreenGui (no safe insets), so nothing of the panel underneath can be hit while it is up.
-- Reel pieces: weighted pick from the box's displayed odds (State.BoxOdds), so the roll looks honest.
local function pickWeighted(list: any, rng: Random): any
	local total = 0
	for _, e in list or {} do
		total += math.max(e.Chance or 0, 0)
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber() * total
	for _, e in list do
		r -= math.max(e.Chance or 0, 0)
		if r <= 0 then
			return e
		end
	end
	return list[#list]
end

local REEL_SLOTS, REEL_STOP = 38, 33
local REEL_SECONDS = 5

local function reveal(box: string, result: any, onDone: (() -> ())?)
	local rg = Kit.Screen("Reveal", 30)
	rg.ScreenInsets = Enum.ScreenInsets.None
	local gui = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 10 }, rg)
	Kit.Scrim(gui, 0.25, { Size = UDim2.fromScale(1, 1), Position = UDim2.new(), ZIndex = 10 })
	local reduced = Settings.Reduced()
	local color = P.RarityColor[result.Rarity] or Theme.TextPrimary
	local card
	local phase, readyAt = "reel", 0
	local reelConn: RBXScriptConnection? = nil
	local skipReel: (() -> ())? = nil
	local keyConn: RBXScriptConnection? = nil
	local closed = false
	local sizeConn: any = nil

	local function close()
		if closed then
			return
		end
		closed = true
		if sizeConn then sizeConn:Disconnect() end
		if keyConn then
			keyConn:Disconnect()
		end
		if reelConn then
			reelConn:Disconnect()
		end
		rg:Destroy()
		if onDone then
			onDone() -- applies the held State snapshot: counts, new room, badge
		end
	end

	-- Card frame (square-ish, so the tier frame keeps its proportions) with a centred content column.
	local view = workspace.CurrentCamera.ViewportSize / math.max(Scale.Value, 0.01)
	local revealScale = math.min(1, math.max(0.1, (view.X - 24) / 340), math.max(0.1, (view.Y - 32) / 460))
	local window: any = nil
	local revealGlow: any = nil

	local function makeCard(rarity: string?): (Frame, Frame)
		local c = Kit.Panel(gui, { Sprite = "Card", Rarity = rarity, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -16), Size = UDim2.fromOffset(340, 460), ZIndex = 11 })
		local col = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12 }, c)
		make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, col)
		return c, col
	end
	local col
	local scale = make("UIScale", {})

	-- "Tap" hint under the card: a pulsing check mark, no sentence.
	local collect = Kit.Button(gui, { Text = "Collect", Style = "Primary", Icon = "Check", IconLayout = "Row", TextSize = 30, Size = UDim2.fromOffset(260, 68), OnClick = function()
		if phase == "shown" and os.clock() >= readyAt then
			close()
		end
	end })
	local hint, hintIcon = collect.Instance, collect.Icon
	hint.Name, hint.AnchorPoint, hint.Position, hint.ZIndex, hint.Visible = "Hint", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.5, 190 * revealScale + 8), 20, false
	-- The reveal screen uses global z-ordering: lift the button's own layers above the scrim and card.
	for _, d in hint:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 19
		end
	end

	local function resizeReveal()
		view = workspace.CurrentCamera.ViewportSize / math.max(Scale.Value, 0.01)
		revealScale = math.min(1, math.max(0.1, (view.X - 24) / 340), math.max(0.1, (view.Y - 32) / 460))
		hint.Position = UDim2.new(0.5, 0, 0.5, 190 * revealScale + 4)
		if card and scale.Parent then scale.Scale = revealScale end
		if revealGlow then revealGlow.Size = UDim2.fromOffset(646 * revealScale, 722 * revealScale) end
		if window then
			local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
			local w = math.max(120, math.min(if phone then 520 else 660, view.X - 24))
			window.Size = UDim2.fromOffset(w, math.floor(w * 248 / 706))
		end
	end
	sizeConn = Scale.Changed:Connect(resizeReveal)

	local function show()
		phase = "shown"
		if reelConn then
			reelConn:Disconnect()
			reelConn = nil
		end
		if card then
			card:Destroy()
		end
		card, col = makeCard(result.Rarity)
		scale = make("UIScale", { Scale = revealScale }, card)
		-- Light behind the card in the tier colour, and a burst that blooms once (Fx.Burst).
		revealGlow = Kit.Glow(gui, color, 0.45)
		revealGlow.AnchorPoint, revealGlow.Position = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, -16)
		revealGlow.Size, revealGlow.ZIndex = UDim2.fromOffset(646 * revealScale, 722 * revealScale), 10
		local burst = Kit.Sprite(gui, "Fx.Burst", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -16), Size = UDim2.fromOffset(300, 300), ImageColor3 = color, ImageTransparency = 0.2, ZIndex = 11 })
		if reduced then
			burst.ImageTransparency = 1
		else
			Settings.Tween(burst, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(620, 620), ImageTransparency = 1 })
		end
		if RarityColors.Shimmer[result.Rarity] then
			Kit.Prismatic(card)
		end
		-- Rarity: the tier's RarityBadge, inside the frame's inset (never on the rim).
		local top = Kit.Rarity(col, result.Rarity)
		top.LayoutOrder = 1
		Kit.SetPillHeight(top, 44)
		local room = P.RoomImage(col, result.RoomId, 112)
		room.LayoutOrder, room.ZIndex = 2, 12
		local nm = Kit.Label(col, roomName(result.RoomId), Theme.TextSize.Title, Theme.TextPrimary, true)
		nm.AutomaticSize, nm.Size, nm.LayoutOrder, nm.ZIndex, nm.TextWrapped = Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0), 3, 12, true
		Kit.FixedText(nm, Theme.TextSize.Heading) -- one name size for every result; a long name wraps to two lines
		if result.Rarity == "Secret" then Kit.Prismatic(nm) end
		if result.Perks and #result.Perks > 0 then
			local perks = Kit.Perks(col, result.Perks, false)
			perks.LayoutOrder = 4
		end
		if result.Modifier then
			local mod = Badges.Modifier(col, result.Modifier, 28)
			if mod then
				mod.LayoutOrder = 5
				local name = Kit.Label(col, tostring(result.Modifier), Theme.TextSize.Body, Badges.ModifierColor[result.Modifier] or Theme.TextPrimary, true)
				name.LayoutOrder, name.Size, name.TextWrapped = 6, UDim2.new(1, 0, 0, 24), false
			end
		end
		-- Siblings draw by ZIndex across whole subtrees: lift every part of the card to the card's level.
		for _, d in col:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 12
			end
		end
		hint.Visible = true
		readyAt = os.clock() + 0.4
		if not reduced then
			scale.Scale = 0.7 * revealScale
			Settings.Tween(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = revealScale })
			Settings.Tween(hintIcon, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = 0.55 })
		end
	end

	gui.Activated:Connect(function()
		if phase == "reel" then
			if skipReel then
				skipReel()
			end
		elseif os.clock() >= readyAt then
			close()
		end
	end)
	keyConn = UserInputService.InputBegan:Connect(function(input)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.ButtonB) and not UserInputService:GetFocusedTextBox() then
			if phase == "reel" then
				if skipReel then
					skipReel()
				end
			elseif os.clock() >= readyAt then
				close()
			end
		end
	end)

	if reduced then
		show()
		return
	end

	-- Reel: a window with a pointer; slots (rarity frame + room) slide past and stop on the server's result.
	local rng = Random.new()
	local odds = State.Current and State.Current.BoxOdds and State.Current.BoxOdds[box]
	local slotW, pitch = 86, 98 -- rarity frames are whole 0.72:1 images: 86 x 118
	local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local winW = math.max(120, math.min(if phone then 520 else 660, view.X - 24))
	local winH = math.floor(winW * 248 / 706)
	window = Kit.Panel(gui, { Sprite = "ReelWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(winW, winH), ZIndex = 11 })
	window.Active = true
	window.ClipsDescendants = false
	window:FindFirstChild("Inset"):Destroy() -- pointers, selector and the skip button are placed against the whole frame
	local clip = make("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromScale(29 / 706, 36 / 248), Size = UDim2.fromScale(649 / 706, 179 / 248), ZIndex = 12 }, window)
	local strip = make("Frame", { Name = "Strip", BackgroundTransparency = 1, Size = UDim2.fromOffset(REEL_SLOTS * pitch, 126), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 12 }, clip)
	for i = 1, REEL_SLOTS do
		local room, rarity
		if i == REEL_STOP then
			room, rarity = result.RoomId, result.Rarity
		else
			-- BoxOdds.Rooms entries are { Id, Rarity, Chance }: a room always carries its own fixed rarity.
			local pick = pickWeighted(odds and odds.Rooms, rng)
			room = if pick then pick.Id else result.RoomId
			rarity = if pick and pick.Rarity then pick.Rarity else (Catalog.RoomRarity(room))
		end
		local slot = Kit.Panel(strip, { Sprite = "Card", Rarity = rarity, Size = UDim2.fromOffset(slotW, 118), Position = UDim2.fromOffset((i - 1) * pitch + (pitch - slotW) / 2, 4), ZIndex = 12 })
		local img = P.RoomImage(slot, room, 64)
		img.AnchorPoint, img.Position, img.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 0.62)
	end
	-- Pointers (Pointer.Down above, Pointer.Up below the centre slot) and the selector frame (Frame.Highlight).
	local pointer = Kit.Sprite(window, "Pointer.Down", { Size = UDim2.fromOffset(44, 36), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 2), ZIndex = 14 })
	local pointerB = Kit.Sprite(window, "Pointer.Up", { Size = UDim2.fromOffset(44, 36), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -2), ZIndex = 14 })
	local selector = pointer -- the two pointers mark the centre slot (a whole 2:1 ring cannot frame a 0.72:1 card)
	-- Skip button (yellow) under the window.
	local skipBtn = Kit.Button(window, { Text = "Skip", Style = "Primary", Size = UDim2.fromOffset(200, 94), TextSize = 32, OnClick = function()
		if skipReel then
			skipReel()
		end
	end }).Instance
	skipBtn.AnchorPoint, skipBtn.Position, skipBtn.ZIndex = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 1, 22), 14
	for _, d in skipBtn:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 13
		end
	end
	for _, d in window:GetDescendants() do
		if d:IsA("GuiObject") and d ~= pointer and d ~= pointerB and d ~= selector and d ~= skipBtn and d.Parent ~= skipBtn then
			d.ZIndex = math.max(d.ZIndex, 12)
		end
	end
	-- Centre of slot k sits at the window's centre; the strip's x shifts left as it rolls.
	local function stripX(progress: number): number
		local centre = (clip.AbsoluteSize.X / math.max(window.AbsoluteSize.X / window.Size.X.Offset, 0.01)) / 2
		local finalX = centre - ((REEL_STOP - 1) * pitch + pitch / 2)
		local startX = centre - pitch / 2
		return startX + (finalX - startX) * progress
	end
	local function ease(t: number): number -- fast, decelerating, small overshoot then settle
		if t >= 1 then
			return 1
		end
		if t < 0.88 then
			local u = t / 0.88
			return (1 - (1 - u) ^ 4) * 1.012
		end
		local u = (t - 0.88) / 0.12
		return 1.012 - 0.012 * (u * u * (3 - 2 * u))
	end
	local startClock = os.clock()
	local lastSlot = 0
	local function place(progress: number)
		local x = stripX(progress)
		strip.Position = UDim2.fromOffset(x, clip.AbsoluteSize.Y / math.max(window.AbsoluteSize.Y / window.Size.Y.Offset, 0.01) / 2)
		return x
	end
	local landing = false
	local function land(hold: number)
		if landing then
			return
		end
		landing = true
		phase = "landing"
		if reelConn then
			reelConn:Disconnect()
			reelConn = nil
		end
		place(1)
		task.delay(hold, function()
			if not closed then
				window:Destroy()
				window = nil
				show()
			end
		end)
	end
	skipReel = function()
		skipReel = nil
		land(0.2)
	end
	reelConn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - startClock) / REEL_SECONDS
		local x = place(ease(t))
		local centre = (clip.AbsoluteSize.X / math.max(window.AbsoluteSize.X / window.Size.X.Offset, 0.01)) / 2
		local slotAtPointer = math.floor((centre - x) / pitch) + 1
		if slotAtPointer ~= lastSlot then
			lastSlot = slotAtPointer
			Sound.Play("ReelTick") -- tick as a slot passes the pointer
		end
		if t >= 1 then
			skipReel = nil
			land(0.5)
		end
	end)
	place(0)
end

local function showBatch(box: string, rewards: { any })
	local gui = Kit.Screen("BatchRewards", 31)
	gui.ScreenInsets = Enum.ScreenInsets.None
	local scrim = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, gui)
	Kit.Scrim(scrim, 0.25, { Position = UDim2.new(), Size = UDim2.fromScale(1, 1) })
	local closed = false
	local function close()
		if closed then return end
		closed = true
		gui:Destroy()
		State.Hold(false)
		for _, reward in rewards do Bus.RoomAwarded:Fire(reward) end
	end
	local chrome = Kit.ModalChrome(scrim, string.format("Opened %d chests", #rewards), close)
	local panel = chrome.Root
	panel.AnchorPoint = Vector2.new(0.5, 0)
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, list)
	make("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6) }, list)
	local rowWidth = 560
	local rows = {}
	local function place()
		local view = gui.AbsoluteSize / math.max(Scale.Value, 0.01)
		local w = math.min(900, view.X - 24)
		local overhang = chrome.Layout(w)
		local top = if Scale.Phone then 72 else 24
		w = math.min(w, (view.Y - overhang - top - 12) * chrome.Ratio)
		overhang = chrome.Layout(w)
		local h = w / chrome.Ratio
		panel.Size = UDim2.fromOffset(w, h)
		panel.Position = UDim2.new(0.5, 0, 0, top + overhang + math.max(0, (view.Y - top - overhang - 12 - h) / 2))
		local bx, by, bw, bh = chrome.BodyRect(w, h)
		list.Position, list.Size = UDim2.fromOffset(bx, by), UDim2.fromOffset(bw, bh)
		rowWidth = math.min(560, bw - 30)
		for _, row in rows do
			row.Size = UDim2.fromOffset(rowWidth, 0)
		end
	end
	place()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	for i, reward in rewards do
		local rarity = tostring(reward.Rarity or "Common")
		-- One Row.Well (whole sprite, height follows its width): room image, name + rarity, modifier badge.
		local row = Kit.Panel(list, { Sprite = "Row", Fit = "Width", Size = UDim2.fromOffset(rowWidth, 0), LayoutOrder = i })
		table.insert(rows, row)
		local content = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, row)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		local image = P.RoomImage(content, reward.RoomId, 56)
		image.LayoutOrder = 1
		image.Size = UDim2.new(0.16, 0, 0.9, 0)
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }, image)
		local label = P.Text(content, string.format("%s\n%s", roomName(reward.RoomId), P.Rich(rarity .. (if reward.Modifier then "  -  " .. tostring(reward.Modifier) else ""), rarity)), Theme.TextSize.Body, Theme.TextPrimary, true, 2)
		label.AutomaticSize, label.Size = Enum.AutomaticSize.None, UDim2.new(0.62, 0, 0.95, 0)
		Kit.FixedText(label, Theme.TextSize.Body)
	end
	scrim.Activated:Connect(close)
end

local function run(remote: string, args: { any }, onOk: (any) -> (), onFail: (() -> ())?)
	if busy then
		if onFail then
			onFail()
		end
		return
	end
	busy = true
	local ok, res = Net.Invoke(remote, table.unpack(args))
	busy = false
	if ok then
		onOk(res)
	else
		Toast.Show(ReasonText.Get(res), "Bad")
		if onFail then
			onFail()
		end
	end
end

-- Bag grids ---------------------------------------------------------------------------------------------------------
-- Both tabs are a grid of square slots (Card.Normal, Card.Glow when hovered / selected, Slot.Empty fillers), 5 columns,
-- with a hover tooltip (Panel.TooltipLeft) and a pinned action row under the grid. Every sprite is one whole image.
local COLUMNS, GAP = 5, 10
-- Height of the pinned action row: >= 44 real px on phones (Kit.MinTouch), roomy on desktop.
local function actionH(): number
	return if Scale.Phone then 50 else 76
end
-- Wide button art on desktop; the 2:1 button on phones, where the well is narrow.
local function openSize(): UDim2
	local h = actionH() - 4
	return UDim2.fromOffset(math.floor(h * 4.06), h) -- wide art on phone too, so a one-line label fits at its fixed size
end
local function openVariant(): string?
	return "Wide"
end
local BOX_NAMES = { Dungeon = "Dungeon Chest", Rare = "Royal Chest", Crystal = "Crystal Chest" }
local BOX_ICONS = { Dungeon = "Box", Rare = "RareBox", Crystal = "CrystalBox" }
local BOX_TEXT = {
	Dungeon = "A sturdy chest of dungeon finds. Every keeper starts here.",
	Rare = "Fit for a royal vault. Better odds of rare rooms inside.",
	Crystal = "Humming with crystal magic. The best shot at epic rooms.",
}
local KIND_NAMES = { Defender = "Defender room", Trap = "Trap room", Treasure = "Treasure room", Support = "Support room" }

local function bagGui(scroll: Instance): ScreenGui?
	return scroll:FindFirstAncestorOfClass("ScreenGui")
end

-- Hover / selection tooltip of the bag grids: Panel.TooltipLeft (tail on the left, pointing at the slot) with a crown, the
-- name in gold, a purple tag, a divider line and a description. One per grid, parented to the screen so it may overhang the
-- modal. info = { Name, Tag, Text, Icon?, Color? }.
local function newTooltip(gui: ScreenGui)
	local spec = Sprites.Ids6.Panel.TooltipLeft
	local tip = Kit.Panel(gui, { Sprite = "TooltipLeft", Visible = false, ZIndex = 60, Active = false, Pad = Vector2.new(28, 4) })
	tip.ClipsDescendants = false
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 61 }, tip)
	local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.66), ZIndex = 61 }, content)
	local crown = Kit.Icon(head, "Crown", UDim2.fromScale(0.2, 0.9))
	crown.AnchorPoint, crown.Position, crown.ZIndex = Vector2.new(0, 0), UDim2.fromScale(0, 0.1), 62
	make("UIAspectRatioConstraint", { AspectRatio = 1.25, AspectType = Enum.AspectType.FitWithinMaxSize }, crown)
	local name = Kit.Label(head, "", 30, Theme.Gold, true)
	name.AnchorPoint, name.Position, name.Size, name.ZIndex = Vector2.new(0, 0), UDim2.fromScale(0.23, 0), UDim2.fromScale(0.77, 0.4), 62
	name.TextXAlignment, name.TextWrapped = Enum.TextXAlignment.Left, false
	Kit.FixedText(name, Theme.TextSize.Heading)
	Kit.Stroke(name, Theme.Stroke, 2)
	local tag = Kit.Tag(head, "Loot Chest", "Chip.Purple", Theme.TextPrimary, 34)
	tag.AnchorPoint, tag.Position, tag.ZIndex = Vector2.new(0, 1), UDim2.fromScale(0.23, 1), 62
	Kit.PillLabel(tag).ZIndex = 63
	-- The tag keeps the 16 px chip size; a long role name widens the chip (it never shrinks the text).
	local text = Kit.Label(content, "", 17, Theme.TextPrimary, true)
	text.Position, text.Size, text.ZIndex = UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), 62
	text.TextXAlignment, text.TextYAlignment, text.TextWrapped = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, true
	Kit.FixedText(text, Theme.TextSize.Label) -- one description size; two lines fit the box
	Kit.Stroke(text, Theme.Stroke, 1.5)
	local api = {}
	local width = 640 -- reference px; the sprite's own aspect gives the height
	local function layout()
		tip.Size = UDim2.fromOffset(width, width * spec.Size.Y / spec.Size.X)
	end
	layout()
	local currentKind = "TooltipLeft"
	local function useSprite(kind: string)
		if currentKind ~= kind then
			currentKind = kind
			Kit.RepaintPanel(tip, kind)
			Kit.ApplyPadding(tip.Inset, Sprites.Ids6.Panel[if kind == "Tooltip" then "Tooltip" else "TooltipLeft"], 28, 4)
		end
	end
	function api.Show(info: any, slot: GuiObject)
		name.Text = info.Name
		name.TextColor3 = info.Color or Theme.Gold
		Kit.SetIcon(crown, info.Icon or "Crown")
		Kit.SetText(tag, info.Tag or "Loot Chest")
		-- The phone tip is narrower than the tag + name row needs: no role tag, and the description is cut to its first
		-- sentence so two lines of the fixed size always hold it.
		tag.Visible = not Scale.Phone
		name.Size = UDim2.fromScale(0.77, if Scale.Phone then 1 else 0.46)
		name.TextYAlignment = Enum.TextYAlignment.Top
		-- Phone: a shorter head and a taller description box, so the whole description (two lines) fits and is never clipped.
		head.Size = UDim2.fromScale(1, if Scale.Phone then 0.42 else 0.62)
		text.Position = UDim2.fromScale(0, if Scale.Phone then 0.46 else 0.66)
		text.Size = UDim2.fromScale(1, if Scale.Phone then 0.54 else 0.34)
		text.Text = if Scale.Phone then firstSentence(info.Text or "") else (info.Text or "")
		local sc = math.max(Scale.Value, 0.01)
		local view = gui.AbsoluteSize / sc
		if Scale.Phone then
			-- Phone: one fixed spot (the free corner left of the bottom nav, below the modal), so the tip never covers a tile
			-- or the action row. The nav row is ~600 wide and centred.
			-- The taller tail-down sprite (1.58:1): room for the name and two description lines at their fixed sizes.
			useSprite("Tooltip")
			local pw = math.clamp(view.X / 2 - 300 - 14, 230, 340)
			local upSpec = Sprites.Ids6.Panel.Tooltip
			tip.Size = UDim2.fromOffset(pw, pw * upSpec.Size.Y / upSpec.Size.X)
			tip.AnchorPoint = Vector2.new(0, 1)
			tip.Position = UDim2.fromOffset(10, view.Y - 8)
			tip.Visible = true
			return
		end
		local c = (slot.AbsolutePosition + slot.AbsoluteSize / 2 - gui.AbsolutePosition) / sc
		local half = slot.AbsoluteSize / sc / 2
		width = math.min(if Scale.Phone then 400 else 640, view.X - 16)
		-- Beside the tile (tail on the left, pointing at its edge) when there is room to the right, shifted down onto the
		-- row below (or up on the last row) so the rest of the tile's own row stays visible; otherwise above it, tail down.
		if c.X + half.X + width <= view.X - 6 then
			useSprite("TooltipLeft")
			layout()
			local h = width * spec.Size.Y / spec.Size.X
			local cy = c.Y + half.Y + h * 0.22
			if cy + h / 2 > view.Y - 150 then
				cy = c.Y - half.Y - h * 0.22
			end
			tip.AnchorPoint = Vector2.new(0, 0.5)
			tip.Position = UDim2.fromOffset(c.X + half.X - 2, math.clamp(cy, h / 2 + 6, math.max(h / 2 + 6, view.Y - h / 2 - 6)))
		else
			useSprite("Tooltip")
			local upSpec = Sprites.Ids6.Panel.Tooltip
			local w2 = math.min(if Scale.Phone then 340 else 400, view.X - 16)
			local h2 = w2 * upSpec.Size.Y / upSpec.Size.X
			tip.Size = UDim2.fromOffset(w2, h2)
			tip.AnchorPoint = Vector2.new(0.5, 1)
			tip.Position = UDim2.fromOffset(math.clamp(c.X, w2 / 2 + 6, view.X - w2 / 2 - 6), math.max(h2 + 6, c.Y - half.Y - 4))
		end
		tip.Visible = true
	end
	function api.Hide()
		tip.Visible = false
	end
	api.Instance = tip
	return api
end

-- A square slot: transparent hit box holding Card.Normal / Card.Glow (one whole image) with the art inside its Inner rect.
-- Returns { Button, Card, Content, SetGlow(on) }.
local function slotCard(parent: Instance, cell: number, order: number): any
	local button = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(cell, cell), LayoutOrder = order }, parent)
	Kit.MinTouch(button)
	local card = Kit.Panel(button, { Sprite = "Card", Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Active = false })
	card.ClipsDescendants = false
	local content = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, card)
	local glow = false
	local api = { Button = button, Card = card, Content = content }
	function api.SetGlow(on: boolean)
		if on ~= glow then
			glow = on
			Kit.RepaintPanel(card, if on then "CardGlow" else "Card")
		end
	end
	return api
end

local function emptySlot(parent: Instance, cell: number, order: number)
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(cell, cell), LayoutOrder = order }, parent)
	Kit.Panel(f, { Sprite = "Slot", Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	return f
end

-- x18 badge on a slot's top-right corner (Badge.Count, whole sprite).
local function countBadge(slotButton: GuiObject, n: number, cell: number)
	local badge = Kit.Count(slotButton, "x" .. n, true, math.clamp(cell * 0.2, 22, 40))
	badge.AnchorPoint, badge.Position, badge.ZIndex = Vector2.new(1, 0), UDim2.new(1, -1, 0, -3), 8
	Kit.PillLabel(badge).ZIndex = 9
	return badge
end

-- Grid frame of square cells: width of `scroll` (minus its padding), 5 columns. Returns frame, cell px.
local function gridFrame(scroll: ScrollingFrame, order: number, cellOverride: number?): (Frame, number)
	local width = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01) - 22
	if width < 100 then
		width = 560
	end
	local cell = cellOverride or math.floor((width - GAP * (COLUMNS - 1)) / COLUMNS)
	-- Phone: a row and a half are visible, so the cut always falls through the second row's art, never through a name.
	local visH = scroll.AbsoluteSize.Y / math.max(Scale.Value, 0.01)
	if Scale.Phone and visH > 90 and not cellOverride then
		cell = math.min(cell, math.floor((visH - 16 - GAP) / 1.5))
	end
	local grid = make("Frame", { Name = "Grid", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(cell * COLUMNS + GAP * (COLUMNS - 1), 0), LayoutOrder = order }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(GAP, GAP), CellSize = UDim2.fromOffset(cell, cell), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
	return grid, cell
end

-- The pinned action row at the bottom of the bag's well. Created once per scroll; rebuilt by each tab.
local footers = setmetatable({}, { __mode = "k" })
local function footerFor(scroll: ScrollingFrame): Frame
	local f = footers[scroll]
	if f and f.Parent then
		for _, c in f:GetChildren() do c:Destroy() end
		return f
	end
	f = make("Frame", { Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, actionH()) }, scroll.Parent)
	scroll.Size = UDim2.new(1, 0, 1, -(actionH() + 6))
	footers[scroll] = f
	return f
end

-- A horizontal action row: left to right controls, centred.
local function actionRow(footer: Frame): Frame
	local row = make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, footer)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, if Scale.Phone then 6 else 12), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	return row
end

local function roundButton(parent: Instance, text: string, style: string, order: number, onClick: () -> ()): any
	local b = Kit.Button(parent, { Text = text, Style = style, Round = true, TextSize = 36, Size = UDim2.fromOffset(actionH() - 4, actionH() - 4), LayoutOrder = order, OnClick = onClick })
	return b
end

-- Readable odds of a chest as a page inside the Bag frame (one title, one close button): rarity badge + chance, then the
-- tier rooms with their chances, in Row.Well rows; a Back button in the footer returns to the chest grid.
local oddsBox: string? = nil
local function buildOdds(scroll: ScrollingFrame, state: any, nxt: () -> number)
	local box = oddsBox :: string
	local odds = (state.BoxOdds or {})[box]
	local footer = footerFor(scroll)
	local row = actionRow(footer)
	Kit.Button(row, { Text = "Back", Style = "Secondary", Icon = "Back", IconLayout = "Row", TextSize = 28, Size = UDim2.fromOffset(if Scale.Phone then 150 else 200, actionH() - 4), OnClick = function()
		oddsBox = nil
		L.Build(scroll, State.Current or state, true)
	end })
	local note = P.Text(scroll, (BOX_NAMES[box] or box) .. ": odds of the next chest. Pity can change later rolls in a batch.", if Scale.Phone then 16 else Theme.TextSize.Body, Theme.TextMuted, true, nxt())
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Visible = not Scale.Phone -- a phone well is short: the rows get the room (the title says it is the next chest)
	if not odds then
		return
	end
	local width = scroll.AbsoluteSize.X / math.max(Scale.Value, 0.01) - 34
	if width < 100 then width = 560 end
	local rowW = math.min(if Scale.Phone then 470 else 660, width)
	for i, rarity in odds.Rarities do
		local card = Kit.Panel(scroll, { Sprite = "Row", Fit = "Width", Size = UDim2.fromOffset(rowW, 0), LayoutOrder = nxt() })
		local color = P.RarityColor[rarity.Id] or Theme.TextPrimary
		local content = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, card)
		local left = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.4, 1) }, content)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, left)
		local badge = Kit.Rarity(left, rarity.Id, if Scale.Phone then 30 else 44)
		badge.LayoutOrder = 1
		local pct = Kit.Label(left, P.Pct(rarity.Chance), if Scale.Phone then 20 else Theme.TextSize.Heading, color, true)
		pct.AutomaticSize, pct.Size, pct.TextWrapped, pct.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromScale(0, 1), false, 2
		Kit.Stroke(pct, Theme.Stroke, 2)
		local names = {}
		for _, room in odds.Rooms do
			if room.Rarity == rarity.Id then
				table.insert(names, string.format("%s %s", roomName(room.Id), P.Pct(room.Chance)))
			end
		end
		local rooms = Kit.Label(content, if #names > 0 then table.concat(names, "  -  ") else "-", Theme.TextSize.Body, Theme.TextPrimary, true)
		rooms.Position, rooms.Size = UDim2.fromScale(0.44, 0), UDim2.fromScale(0.56, 1)
		rooms.TextXAlignment, rooms.TextWrapped = Enum.TextXAlignment.Left, true
		Kit.FixedText(rooms, Theme.TextSize.Label + 2)
	end
	make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 16), LayoutOrder = nxt() }, scroll)
end

-- Free spare-room slots, from the server's State.RoomStorage (placed rooms never count).
local function storageLeft(state: any): number
	local storage = state.RoomStorage
	if type(storage) ~= "table" then return 0 end
	return math.max(0, (storage.Max or 0) - (storage.Used or 0))
end

-- Loot Chests tab ---------------------------------------------------------------------------------------------------
local hoverBox: string? = nil
local function buildChests(scroll: ScrollingFrame, state: any, catalog: any, nxt: () -> number)
	local gui = bagGui(scroll)
	local footer = footerFor(scroll)
	local boxes = {}
	for _, boxType in catalog.Loot.BoxTypes do
		local count = (state.Boxes or {})[boxType] or 0
		if count > 0 then
			table.insert(boxes, { Type = boxType, Count = count })
		end
	end
	local selectedValid = false
	for _, b in boxes do if b.Type == selectedBox then selectedValid = true end end
	if not selectedValid and boxes[1] then selectedBox = boxes[1].Type end

	-- Cell size: 2 rows when they fit the visible grid at a readable size, else 1 row.
	local sc = math.max(Scale.Value, 0.01)
	local width = scroll.AbsoluteSize.X / sc - 22
	local height = scroll.AbsoluteSize.Y / sc
	if width < 100 then width, height = 560, 300 end
	local fromWidth = math.floor((width - GAP * (COLUMNS - 1)) / COLUMNS)
	local two = math.floor((height - GAP - 18) / 2)
	local rows, cell = 1, math.min(fromWidth, math.max(60, height - 18))
	if two >= 96 then
		rows, cell = 2, math.min(fromWidth, two)
	end
	local grid
	grid, cell = gridFrame(scroll, nxt(), cell)
	local slots = {}
	local tooltip = if gui then newTooltip(gui) else nil
	grid.Destroying:Connect(function()
		if tooltip then tooltip.Instance:Destroy() end
	end)

	local function paintSlots()
		for _, s in slots do
			s.Slot.SetGlow(s.Type == selectedBox or s.Type == hoverBox)
		end
	end
	local function showTip(boxType: string?)
		if not tooltip then return end
		if not boxType then tooltip.Hide() return end
		for _, s in slots do
			if s.Type == boxType then
				tooltip.Show({ Name = BOX_NAMES[boxType] or boxType, Tag = "Loot Chest", Text = BOX_TEXT[boxType] or "A chest full of mysteries." }, s.Slot.Button)
			end
		end
	end

	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local actions: any = nil
	local function paintActions() end
	for i, b in boxes do
		local slot = slotCard(grid, cell, i)
		local art = Kit.Icon(slot.Content, BOX_ICONS[b.Type] or "Box", UDim2.fromScale(0.96, 0.96))
		art.AnchorPoint, art.Position, art.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), 4
		countBadge(slot.Button, b.Count, cell)
		table.insert(slots, { Type = b.Type, Slot = slot })
		slot.Button.MouseEnter:Connect(function()
			if UserInputService.MouseEnabled then
				hoverBox = b.Type
				paintSlots()
				showTip(b.Type)
			end
		end)
		slot.Button.MouseLeave:Connect(function()
			if hoverBox == b.Type then
				hoverBox = nil
				paintSlots()
				showTip(if touchOnly then selectedBox else nil)
			end
		end)
		slot.Button.Activated:Connect(function()
			Sound.Play("Click")
			selectedBox, openConfirmUntil = b.Type, 0
			paintSlots()
			paintActions()
			if touchOnly then showTip(b.Type) end
		end)
	end
	-- Empty cells (Slot.Empty) fill the visible grid, like the reference.
	local wanted = math.max(rows * COLUMNS, math.ceil(#boxes / COLUMNS) * COLUMNS)
	for i = #boxes + 1, wanted do
		emptySlot(grid, cell, i)
	end
	paintSlots()
	if touchOnly and #boxes > 0 then showTip(selectedBox) end

	-- Action row: [-] x3 [+]  [Open x3]  (i) odds
	local row = actionRow(footer)
	if #boxes == 0 then
		local msg = Kit.Label(row, "No chests yet - win them from visitors.", Theme.TextSize.Body, Theme.TextMuted, true)
		msg.Size, msg.TextWrapped = UDim2.fromScale(1, 0.8), false
		msg.TextXAlignment = Enum.TextXAlignment.Center
		return
	end
	local controls = {}
	local function refreshControls()
		local stock = (state.Boxes or {})[selectedBox] or 0
		local maxOpen = math.min(stock, storageLeft(state))
		selectedQty[selectedBox] = math.clamp(selectedQty[selectedBox] or 1, if maxOpen > 0 then 1 else 0, maxOpen)
		return selectedQty[selectedBox], maxOpen
	end
	local qty0, max0 = refreshControls()
	controls.Minus = roundButton(row, "-", "Secondary", 1, function()
		local q = refreshControls()
		selectedQty[selectedBox] = math.max(1, q - 1)
		openConfirmUntil = 0
		paintActions()
	end)
	local qtyChip = Kit.Tag(row, "x" .. qty0, "Tag.Label", Theme.TextPrimary, if Scale.Phone then 30 else actionH() - 22)
	qtyChip.LayoutOrder = 2
	controls.Plus = roundButton(row, "+", "Primary", 3, function()
		local q, m = refreshControls()
		selectedQty[selectedBox] = math.min(m, q + 1)
		openConfirmUntil = 0
		paintActions()
	end)
	local openButton
	openButton = Kit.Button(row, { Text = "Open", Style = "Primary", DisabledText = Theme.TextPrimary, Variant = openVariant(), TextSize = 26, Size = openSize(), LayoutOrder = 4, OnClick = function()
		local qty = refreshControls()
		if busy or qty < 1 then return end
		local openKey = selectedBox .. ":" .. tostring(qty)
		if openConfirmUntil <= os.clock() or openConfirmKey ~= openKey then
			openConfirmKey = openKey
			openConfirmUntil = os.clock() + 3
			paintActions()
			task.delay(3.1, function()
				if openConfirmUntil > 0 and openConfirmUntil <= os.clock() then
					openConfirmUntil = 0
					if scroll.Parent then paintActions() end
				end
			end)
			return
		end
		openConfirmUntil = 0
		State.Hold(true)
		local box = selectedBox
		run("OpenBoxes", { box, qty }, function(rewards)
			if type(rewards) == "table" and #rewards == 1 then
				reveal(box, rewards[1], function() State.Hold(false); Bus.RoomAwarded:Fire(rewards[1]) end)
			elseif type(rewards) == "table" and #rewards > 1 then
				showBatch(box, rewards)
			else State.Hold(false); L.Build(scroll, State.Current or state, true) end
		end, function()
			State.Hold(false)
			L.Build(scroll, State.Current or state, true)
		end)
	end })
	controls.Odds = Kit.Button(row, { Text = "?", Style = "Secondary", Round = true, TextSize = 36, Size = UDim2.fromOffset(actionH() - 8, actionH() - 8), LayoutOrder = 5, Tip = "Chest odds and pity", OnClick = function()
		local odds = (state.BoxOdds or {})[selectedBox]
		if odds then
			oddsBox = selectedBox
			L.Build(scroll, State.Current or state, true)
		else
			Toast.Show("Odds are not available yet.", "Info")
		end
	end })
	paintActions = function()
		local qty, maxOpen = refreshControls()
		local confirming = openConfirmUntil > os.clock() and openConfirmKey == selectedBox .. ":" .. tostring(qty)
		Kit.SetText(qtyChip, "x" .. qty)
		controls.Minus.SetEnabled(qty > 1)
		controls.Plus.SetEnabled(qty < maxOpen)
		openButton.SetText(if confirming then string.format("Confirm x%d", qty) elseif qty > 1 then string.format("Open x%d", qty) else "Open")
		openButton.SetEnabled(maxOpen > 0, if maxOpen == 0 then "Storage full" else nil)
	end
	paintActions()
end

-- Rooms tab -----------------------------------------------------------------------------------------------------------
local focusKey: string? = nil
local function buildRooms(scroll: ScrollingFrame, state: any, catalog: any, nxt: () -> number)
	local gui = bagGui(scroll)
	local footer = footerFor(scroll)
	-- Two rows are visible when they fit at a readable size; more rows scroll.
	local sc0 = math.max(Scale.Value, 0.01)
	local w0, h0 = scroll.AbsoluteSize.X / sc0 - 22, scroll.AbsoluteSize.Y / sc0
	local cellH
	if w0 > 100 and h0 > 100 then
		local two0 = math.floor((h0 - GAP - 18) / 2)
		cellH = if two0 >= 96 then two0 else math.max(60, math.floor((h0 - 12 - GAP) / 1.35))
	end
	local grid, cell = gridFrame(scroll, nxt(), if cellH then math.min(cellH, math.floor((w0 - GAP * (COLUMNS - 1)) / COLUMNS)) else nil)
	local tooltip = if gui then newTooltip(gui) else nil
	grid.Destroying:Connect(function()
		if tooltip then tooltip.Instance:Destroy() end
	end)

	-- Unplaced rooms, grouped by identical stats.
	local placed = {}
	for _, instanceId in state.Layout or {} do placed[instanceId] = true end
	local groups, byKey = {}, {}
	for instanceId, room in state.Rooms or {} do
		local def = catalog.Rooms[room.Id]
		if not placed[instanceId] and def then
			local key = table.concat({ room.Id, tostring(room.Level or 1), tostring(room.Rarity or "Common"), tostring(room.Modifier or ""), P.PerkText(room.Perks) }, "|")
			local group = byKey[key]
			if not group then
				group = { Key = key, Id = room.Id, Level = room.Level or 1, Rarity = room.Rarity or "Common", Modifier = room.Modifier, Perks = room.Perks, Def = def, Instances = {} }
				byKey[key] = group
				table.insert(groups, group)
			end
			table.insert(group.Instances, instanceId)
		end
	end
	table.sort(groups, function(a, b)
		local ra, rb = Catalog.RarityRank(a.Rarity) or 0, Catalog.RarityRank(b.Rarity) or 0
		if ra ~= rb then return ra > rb end
		if a.Id ~= b.Id then return a.Id < b.Id end
		return a.Key < b.Key
	end)
	local selectedCount, selectedValue, selectedIds = 0, 0, {}
	for _, group in groups do
		table.sort(group.Instances)
		local picked = if group.Def.Craftable then math.clamp(selectedItems[group.Key] or 0, 0, math.min(#group.Instances, 30 - selectedCount)) else 0
		selectedItems[group.Key] = picked
		if group.Def.Craftable then
			for i = 1, picked do
				if selectedCount >= 30 then break end
				selectedCount += 1
				selectedValue += (catalog.Loot.SaleCoins or {})[group.Rarity] or 0
				table.insert(selectedIds, group.Instances[i])
			end
		end
	end
	local alive = {}
	for _, group in groups do alive[group.Key] = true end
	for key in selectedItems do if not alive[key] then selectedItems[key] = nil end end

	-- Blueprints the player can craft from (kept from the old tab): one slot each, after the rooms.
	local blueprints = {}
	for _, id in catalog.RoomOrder do
		local def = catalog.Rooms[id]
		local cost = def and def.CraftCost
		if def and def.Craftable and cost and ((state.Blueprints or {})[id] or 0) > 0 then
			table.insert(blueprints, { Key = "bp:" .. id, Id = id, Def = def, Have = (state.Blueprints or {})[id] or 0, Cost = cost })
		end
	end
	local entries = {}
	for _, g in groups do table.insert(entries, { Key = g.Key, Group = g }) end
	for _, bp in blueprints do table.insert(entries, { Key = bp.Key, Blueprint = bp }) end
	local focusValid = false
	for _, e in entries do if e.Key == focusKey then focusValid = true end end
	if not focusValid then focusKey = if entries[1] then entries[1].Key else nil end

	local slots = {}
	local hover: string? = nil
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local paintActions = function() end
	local function paintSlots()
		for _, s in slots do
			local chosen = if s.Group then (selectedItems[s.Group.Key] or 0) else 0
			s.Slot.SetGlow(s.Key == focusKey or s.Key == hover or chosen > 0)
			if s.Chosen then
				s.Chosen.Visible = chosen > 0
				Kit.SetText(s.Chosen, "sell " .. chosen)
			end
		end
	end
	local function infoFor(e: any): any
		if e.Group then
			local g = e.Group
			local stats = {}
			if type(g.Def.BaseHealth) == "number" then table.insert(stats, "HP " .. g.Def.BaseHealth) end
			if type(g.Def.BaseDamage) == "number" then table.insert(stats, "DMG " .. g.Def.BaseDamage) end
			if type(g.Def.UnitCount) == "number" then table.insert(stats, "x" .. g.Def.UnitCount .. " units") end
			if type(g.Def.SupportDamage) == "number" then table.insert(stats, "DMG +" .. P.Pct(g.Def.SupportDamage)) end
			if type(g.Def.SupportHealth) == "number" then table.insert(stats, "HP +" .. P.Pct(g.Def.SupportHealth)) end
			if type(g.Def.Exchange) == "number" then table.insert(stats, string.format("Exchange x%.2g", g.Def.Exchange)) end
			table.insert(stats, "Lv " .. g.Level)
			local extra = if g.Modifier then " (" .. tostring(g.Modifier) .. ")" else ""
			local perks = P.PerkText(g.Perks)
			return { Name = roomName(g.Id), Tag = (KIND_NAMES[g.Def.Kind or ""] or "Room") .. extra, Text = table.concat(stats, "  ") .. " - " .. (if perks ~= "" then perks else firstSentence(tostring(g.Def.Description or ""))), Icon = "Crown", Color = P.RarityColor[g.Rarity] or Theme.Gold }
		end
		local bp = e.Blueprint
		return { Name = roomName(bp.Id) .. " blueprint", Tag = "Blueprint", Text = string.format("%d of %d blueprints. %s", bp.Have, bp.Cost, tostring(bp.Def.Description or "Craft a new room.")), Icon = "Blueprint", Color = P.RarityColor[bp.Def.Rarity] or Theme.Gold }
	end
	local function showTip(key: string?)
		if not tooltip then return end
		if not key then tooltip.Hide() return end
		for _, s in slots do
			if s.Key == key then tooltip.Show(infoFor(s.Entry), s.Slot.Button) end
		end
	end

	-- Name rows: one line when every name fits the tile at the fixed size, else two (one count for the whole layout).
	local nameLines = 1
	for _, e in entries do
		local nid = if e.Group then e.Group.Id else e.Blueprint.Id
		if Kit.Measure(roomName(nid), Theme.TextSize.Label, Theme.HeadingFont, 2000).X > cell - 36 then
			nameLines = 2
		end
	end
	local nameZone = math.ceil(Theme.TextSize.Label * 1.2 * nameLines) + 4
	for i, e in entries do
		local slot = slotCard(grid, cell, i)
		local id = if e.Group then e.Group.Id else e.Blueprint.Id
		local def = if e.Group then e.Group.Def else e.Blueprint.Def
		local art
		if e.Blueprint then
			art = Kit.Icon(slot.Content, "BlueprintCard", UDim2.fromScale(0.78, 0.62))
			art.AnchorPoint, art.Position, art.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.4), 4
			local room = P.RoomImage(art, id, 40, def.Kind)
			room.AnchorPoint, room.Position, room.Size, room.ZIndex = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.62, 0.62), 5
		else
			-- The art fills the tile (up to 78% of its width, the whole cell is the canvas, not just the card's Inner rect); the
			-- name row below holds the layout's line count, so nothing overlaps the art.
			local artPx = math.min(cell * 1.0, cell - nameZone + 2)
			art = P.RoomImage(slot.Button, id, math.floor(artPx), def.Kind)
			art.AnchorPoint, art.Position, art.Size, art.ZIndex = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.fromOffset(artPx, artPx), 4
		end
		-- Name under the art, on the card's dark base.
		local name = Kit.Label(slot.Button, roomName(id), Theme.TextSize.Label, if e.Group then (P.RarityColor[e.Group.Rarity] or Theme.TextPrimary) else Theme.TextPrimary, true)
		name.AnchorPoint, name.Position, name.Size, name.ZIndex = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -6), UDim2.new(1, -16, 0, nameZone), 6
		-- One fixed size (18) for every tile on desktop and phone; the row (half of the card's Inner rect, 0.5 of it is 45+ px on a
		-- phone) holds two lines, so a long name wraps and never truncates.
		name.TextScaled, name.TextWrapped, name.TextTruncate, name.TextYAlignment = false, true, Enum.TextTruncate.None, Enum.TextYAlignment.Bottom
		Kit.Stroke(name, Theme.Stroke, 2)
		local entry = { Key = e.Key, Slot = slot, Entry = e, Group = e.Group }
		if e.Group then
			countBadge(slot.Button, #e.Group.Instances, cell)
			local chosen = Kit.Tag(slot.Button, "", "Chip.Gold", Theme.TextOnGold, math.clamp(cell * 0.2, 22, 38))
			chosen.AnchorPoint, chosen.Position, chosen.ZIndex = Vector2.new(0, 0), UDim2.fromScale(0.04, 0.2), 8
			Kit.PillLabel(chosen).ZIndex = 9
			chosen.Visible = false
			entry.Chosen = chosen
		else
			countBadge(slot.Button, e.Blueprint.Have, cell)
		end
		table.insert(slots, entry)
		slot.Button.MouseEnter:Connect(function()
			if UserInputService.MouseEnabled then
				hover = e.Key
				paintSlots()
				showTip(e.Key)
			end
		end)
		slot.Button.MouseLeave:Connect(function()
			if hover == e.Key then
				hover = nil
				paintSlots()
				showTip(if touchOnly then focusKey else nil)
			end
		end)
		slot.Button.Activated:Connect(function()
			Sound.Play("Click")
			focusKey = e.Key
			sellConfirmUntil = 0
			paintSlots()
			paintActions()
			if touchOnly then showTip(e.Key) end
		end)
	end
	local wanted = math.max(2 * COLUMNS, math.ceil(#entries / COLUMNS) * COLUMNS)
	for i = #entries + 1, wanted do
		emptySlot(grid, cell, i)
	end
	paintSlots()
	if touchOnly and focusKey then showTip(focusKey) end

	-- Actions of the focused slot: rooms -> [-] sell n/stack [+] and Sell; blueprints -> Craft.
	local row = actionRow(footer)
	local saleKey = table.concat(selectedIds, ",")
	local function focusEntry(): any
		for _, e in entries do if e.Key == focusKey then return e end end
		return nil
	end
	local remove = roundButton(row, "-", "Secondary", 1, function()
		local e = focusEntry()
		if e and e.Group then
			selectedItems[e.Group.Key] = math.max(0, (selectedItems[e.Group.Key] or 0) - 1)
			sellConfirmUntil = 0
			L.Build(scroll, State.Current or state, true)
		end
	end)
	local qtyChip = Kit.Tag(row, "0/0", "Tag.Label", Theme.TextPrimary, if Scale.Phone then 30 else actionH() - 22)
	qtyChip.LayoutOrder = 2
	local add = roundButton(row, "+", "Primary", 3, function()
		local e = focusEntry()
		if e and e.Group then
			selectedItems[e.Group.Key] = math.min(#e.Group.Instances, (selectedItems[e.Group.Key] or 0) + 1)
			sellConfirmUntil = 0
			L.Build(scroll, State.Current or state, true)
		end
	end)
	local confirming = sellConfirmUntil > os.clock() and sellConfirmKey == saleKey
	local sellText = if Scale.Phone then string.format("%s %d", if confirming then "Sure?" else "Sell", selectedCount) elseif confirming then string.format("Confirm %d: %s", selectedCount, Badges.Comma(selectedValue)) else string.format("Sell %d: %s coins", selectedCount, Badges.Comma(selectedValue))
	local sell = Kit.Button(row, { Text = sellText, Style = "Danger", Variant = openVariant(), Icon = "CoinStack", IconLayout = "Row", TextSize = 22, Size = openSize(), LayoutOrder = 4, OnClick = function()
		if busy or #selectedIds == 0 then return end
		if sellConfirmUntil <= os.clock() or sellConfirmKey ~= saleKey then
			sellConfirmKey = saleKey
			sellConfirmUntil = os.clock() + 3
			L.Build(scroll, State.Current or state, true)
			task.delay(3.1, function()
				if sellConfirmUntil > 0 and sellConfirmUntil <= os.clock() then
					sellConfirmUntil = 0
					if scroll.Parent then L.Build(scroll, State.Current or state, true) end
				end
			end)
			return
		end
		sellConfirmUntil = 0
		State.Hold(true)
		run("SellRooms", { selectedIds }, function(result)
			State.Hold(false)
			table.clear(selectedItems)
			local sold = if type(result) == "table" then result.Sold or {} else {}
			local coins = if type(result) == "table" then result.Coins or 0 else 0
			Toast.Show(string.format("Sold %d rooms for %s coins.", #sold, Badges.Comma(coins)), "Good")
		end, function()
			State.Hold(false)
			L.Build(scroll, State.Current or state, true)
		end)
	end })
	sell.SetEnabled(selectedCount > 0)
	local craft = Kit.Button(row, { Text = "Craft", Style = "Primary", Variant = openVariant(), TextSize = 28, Size = openSize(), LayoutOrder = 5, OnClick = function()
		local e = focusEntry()
		if e and e.Blueprint and not busy then
			run("CraftBlueprint", { e.Blueprint.Id }, function() Toast.Show(roomName(e.Blueprint.Id) .. " crafted.", "Good") end)
		end
	end })
	paintActions = function()
		local e = focusEntry()
		local bp = e ~= nil and e.Blueprint ~= nil
		remove.Instance.Visible, add.Instance.Visible, qtyChip.Visible, sell.Instance.Visible, craft.Instance.Visible = not bp, not bp, not bp, not bp, bp
		if e and e.Group then
			local chosen = selectedItems[e.Group.Key] or 0
			Kit.SetText(qtyChip, string.format("%d/%d", chosen, #e.Group.Instances))
			remove.SetEnabled(chosen > 0)
			add.SetEnabled(e.Group.Def.Craftable and chosen < #e.Group.Instances and selectedCount < 30)
		elseif bp then
			craft.SetText(string.format("Craft %d/%d", e.Blueprint.Have, e.Blueprint.Cost))
			craft.SetEnabled(e.Blueprint.Have >= e.Blueprint.Cost)
		else
			remove.SetEnabled(false)
			add.SetEnabled(false)
			Kit.SetText(qtyChip, "0/0")
		end
	end
	paintActions()
	if #entries == 0 then
		P.Empty(scroll, "No unplaced rooms", nxt())
	end
end

local resizeHooked = setmetatable({}, { __mode = "k" })
local lastSignature = setmetatable({}, { __mode = "k" })

-- What the bag draws, as text: state arrives every second (coins, xp), and rebuilding the grid would drop hover and
-- tooltips, so a rebuild only happens when this changes (or a handler / resize forces it).
local function signature(state: any): string
	local parts = { currentTab, selectedBox, tostring(focusKey), tostring(oddsBox) }
	for _, boxType in { "Dungeon", "Rare", "Crystal" } do table.insert(parts, tostring((state.Boxes or {})[boxType])) end
	local rooms = {}
	for instanceId, room in state.Rooms or {} do table.insert(rooms, instanceId .. ":" .. tostring(room.Level) .. tostring(room.Modifier)) end
	table.sort(rooms)
	table.insert(parts, table.concat(rooms, ","))
	table.insert(parts, table.concat(state.Layout or {}, ","))
	local bps = {}
	for id, n in state.Blueprints or {} do table.insert(bps, id .. n) end
	table.sort(bps)
	table.insert(parts, table.concat(bps, ","))
	return table.concat(parts, "|")
end

function L.Build(scroll: ScrollingFrame, state: any, force: boolean?)
	local sig = signature(state)
	if not force and lastSignature[scroll] == sig and #scroll:GetChildren() > 2 then
		return
	end
	lastSignature[scroll] = sig
	local catalog = Catalog.Wait()
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end
	local tabs = inventoryTabs[scroll]
	if not tabs then
		local row = P.TabRow(scroll) :: Frame
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local rooms = P.TabButton(row, { Text = "Rooms", Icon = "Rooms", Wide = true, Size = UDim2.fromOffset(250, 60), OnClick = function()
			currentTab = "Items"
			oddsBox = nil
			scroll.CanvasPosition = Vector2.zero
			L.Build(scroll, State.Current or state, true)
		end })
		local chests = P.TabButton(row, { Text = "Loot Chests", Icon = "Box", Wide = true, Size = UDim2.fromOffset(250, 60), OnClick = function()
			currentTab = "Drops"
			oddsBox = nil
			scroll.CanvasPosition = Vector2.zero
			L.Build(scroll, State.Current or state, true)
		end })
		rooms.Instance.LayoutOrder, chests.Instance.LayoutOrder = 1, 2
		P.CentreTabs(row, { rooms, chests })
		tabs = { Rooms = rooms, Chests = chests }
		inventoryTabs[scroll] = tabs
	end
	tabs.Rooms.SetSelected(currentTab == "Items")
	tabs.Chests.SetSelected(currentTab == "Drops")
	-- Rebuild once the well has its real size (the grid sizes its cells from it).
	if not resizeHooked[scroll] then
		resizeHooked[scroll] = true
		local pending = false
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if pending then return end
			pending = true
			task.delay(0.05, function()
				pending = false
				if scroll.Parent and scroll.Visible and State.Current then L.Build(scroll, State.Current, true) end
			end)
		end)
	end
	if currentTab == "Drops" and oddsBox then
		buildOdds(scroll, state, nxt)
	elseif currentTab == "Drops" then
		buildChests(scroll, state, catalog, nxt)
	else
		buildRooms(scroll, state, catalog, nxt)
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return L
