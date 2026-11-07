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
	Kit.Sprite(gui, "Feedback.Scrim", { Name = "Scrim", Size = UDim2.fromScale(1, 1), ImageTransparency = 0.1, ScaleType = Enum.ScaleType.Stretch, ZIndex = 10 })
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
		local c = Kit.Panel(gui, { Sprite = "Large", Pad = Vector2.new(6, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -16), Size = UDim2.fromOffset(340, if rarity then 380 else 320), ZIndex = 11 })
		local col = make("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12 }, c)
		make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, col)
		return c, col
	end
	local col
	local scale = make("UIScale", {})

	-- "Tap" hint under the card: a pulsing check mark, no sentence.
	local hint = make("Frame", { Name = "Hint", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 190 * revealScale + 4), Size = UDim2.fromOffset(120, 44), ZIndex = 12, Visible = false }, gui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }, hint)
	local hintIcon = Kit.Icon(hint, "Check", UDim2.fromOffset(36, 36), Theme.Success)
	local hintText = Kit.Label(hint, "Tap", Theme.TextSize.Body, Theme.TextPrimary, true)
	hintText.AutomaticSize, hintText.Size, hintText.TextWrapped = Enum.AutomaticSize.X, UDim2.fromOffset(0, 36), false
	hintIcon.ZIndex, hintText.ZIndex = 13, 13
	hintText.TextTransparency = 0.15

	local function resizeReveal()
		view = workspace.CurrentCamera.ViewportSize / math.max(Scale.Value, 0.01)
		revealScale = math.min(1, math.max(0.1, (view.X - 24) / 340), math.max(0.1, (view.Y - 32) / 460))
		hint.Position = UDim2.new(0.5, 0, 0.5, 190 * revealScale + 4)
		if card and scale.Parent then scale.Scale = revealScale end
		if revealGlow then revealGlow.Size = UDim2.fromOffset(646 * revealScale, 722 * revealScale) end
		if window then
			local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
			window.Size = UDim2.fromOffset(math.max(120, math.min(if phone then 520 else 660, view.X - 24)), 190)
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
		-- Light behind the card in the tier colour, and a burst that blooms once (Reel.Burst).
		revealGlow = Kit.Glow(gui, color, 0.45)
		revealGlow.AnchorPoint, revealGlow.Position = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, -16)
		revealGlow.Size, revealGlow.ZIndex = UDim2.fromOffset(646 * revealScale, 722 * revealScale), 10
		local burst = Kit.Sprite(gui, "Reel.Burst", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -16), Size = UDim2.fromOffset(300, 300), ImageColor3 = color, ImageTransparency = 0.2, ZIndex = 11 })
		if reduced then
			burst.ImageTransparency = 1
		else
			Settings.Tween(burst, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(620, 620), ImageTransparency = 1 })
		end
		if RarityColors.Shimmer[result.Rarity] then
			Kit.Prismatic(card)
		end
		-- Rarity: gem + name, inside the frame's inset (never on the rim).
		local top = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), LayoutOrder = 1, ZIndex = 12 }, col)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, top)
		Kit.Gem(top, result.Rarity, UDim2.fromOffset(32, 32)).LayoutOrder = 1
		local rl = Kit.Label(top, string.upper(tostring(result.Rarity)), Theme.TextSize.Heading, color, true)
		rl.AutomaticSize, rl.Size, rl.TextWrapped, rl.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 36), false, 2
		if result.Rarity == "Secret" then Kit.Prismatic(rl) end
		local room = P.RoomImage(col, result.RoomId, 150)
		room.LayoutOrder, room.ZIndex = 2, 12
		local nm = Kit.Label(col, roomName(result.RoomId), Theme.TextSize.Title, Theme.TextPrimary, true)
		nm.Size, nm.LayoutOrder, nm.ZIndex, nm.TextWrapped, nm.TextScaled = UDim2.new(1, 0, 0, 40), 3, 12, false, true
		make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = Theme.TextSize.Title }, nm)
		if result.Rarity == "Secret" then Kit.Prismatic(nm) end
		if result.Perks and #result.Perks > 0 then
			local perks = Kit.Perks(col, result.Perks, false)
			perks.LayoutOrder = 4
			perks.Size = UDim2.fromOffset(0, 26)
		end
		if result.Modifier then
			local mod = Badges.Modifier(col, result.Modifier, 36)
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
	local slotW, pitch = 112, 122
	local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local winW = math.max(120, math.min(if phone then 520 else 660, view.X - 24))
	window = Kit.Panel(gui, { Sprite = "ReelWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(winW, 190), ZIndex = 11 })
	window.Active = true
	window.ClipsDescendants = false
	window:FindFirstChild("Inset"):Destroy() -- pointers, selector and the skip button are placed against the whole frame
	local clip = make("Frame", { Name = "Clip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(26, 22), Size = UDim2.new(1, -52, 1, -44), ZIndex = 12 }, window)
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
		local slot = Kit.Panel(strip, { Sprite = "Small", Rarity = rarity, Size = UDim2.fromOffset(slotW, 118), Position = UDim2.fromOffset((i - 1) * pitch + (pitch - slotW) / 2, 4), Pad = 0, ZIndex = 12 })
		local img = P.RoomImage(slot, room, 64)
		img.AnchorPoint, img.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.45)
		local gem = Kit.Gem(slot, rarity, UDim2.fromOffset(22, 22))
		gem.AnchorPoint, gem.Position = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4)
	end
	-- Pointers (Reel.PointerTop above, Reel.PointerBottom below the centre slot) and the selector frame (Reel.Slot).
	local pointer = Kit.Sprite(window, "Reel.PointerTop", { Size = UDim2.fromOffset(44, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), ZIndex = 14 })
	local pointerB = Kit.Sprite(window, "Reel.PointerBottom", { Size = UDim2.fromOffset(44, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 6), ZIndex = 14 })
	local selector = Kit.Sprite(window, "Reel.Slot", { Size = UDim2.fromOffset(slotW + 8, 126), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageTransparency = 0.6, ZIndex = 13 })
	-- Skip button (Reel.SpinButton art) under the window.
	local skipBtn = make("ImageButton", { Name = "Skip", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 18), Size = UDim2.fromOffset(160, 60), Image = "", ZIndex = 14 }, window)
	Kit.MinTouch(skipBtn)
	Kit.Skin(skipBtn, Kit.Spec("Reel.SpinButton"), "Uniform", nil, nil)
	local skipLabel = Kit.Label(skipBtn, "Skip", Theme.TextSize.Button, Theme.TextOnGold, true)
	skipLabel.Size, skipLabel.ZIndex = UDim2.fromScale(1, 1), 15
	skipBtn.Activated:Connect(function()
		if skipReel then
			skipReel()
		end
	end)
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
	Kit.Sprite(scrim, "Feedback.Scrim", { Size = UDim2.fromScale(1, 1), ImageTransparency = 0.1, ScaleType = Enum.ScaleType.Stretch })
	local panel = Kit.Panel(scrim, { Sprite = "Large", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.84), Pad = Vector2.new(8, 6) })
	make("UISizeConstraint", { MaxSize = Vector2.new(760, 620) }, panel)
	local title = Kit.Label(panel, string.format("Opened %d %s chests", #rewards, box), Theme.TextSize.Title, Theme.TextPrimary, true)
	title.Position, title.Size = UDim2.fromOffset(8, 4), UDim2.new(1, -76, 0, 52)
	local closed = false
	local function close()
		if closed then return end
		closed = true
		gui:Destroy()
		State.Hold(false)
		for _, reward in rewards do Bus.RoomAwarded:Fire(reward) end
	end
	local closeButton = Kit.CloseButton(panel, UDim2.fromOffset(56, 56), close)
	closeButton.Instance.AnchorPoint, closeButton.Instance.Position = Vector2.new(1, 0), UDim2.new(1, -4, 0, 0)
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(4, 64), Size = UDim2.new(1, -8, 1, -72), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 8, ScrollingDirection = Enum.ScrollingDirection.Y }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }, list)
	for i, reward in rewards do
		local rarity = tostring(reward.Rarity or "Common")
		local details = string.format("%s  %s", roomName(reward.RoomId), P.Rich("[" .. rarity .. "]", rarity))
		if reward.Modifier then details ..= "\n" .. tostring(reward.Modifier) end
		local card = P.Card(list, i, rarity)
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50) }, card)
		local image = P.RoomImage(row, reward.RoomId, 44)
		image.Position = UDim2.fromOffset(2, 3)
		local label = P.Text(row, details, Theme.TextSize.Body, Theme.TextPrimary, true)
		label.Position, label.Size = UDim2.fromOffset(54, 0), UDim2.new(1, -58, 0, 50)
		if reward.Modifier then
			local badge = Badges.Modifier(row, reward.Modifier, 34)
			if badge then badge.AnchorPoint, badge.Position = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4) end
		end
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

function L.Build(scroll: ScrollingFrame, state: any)
	local catalog = Catalog.Wait()
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end
	local tabs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = nxt() }, scroll)
	local dropTab = Kit.Button(tabs, { Text = "Drops", Icon = "DropChance", IconLayout = "Row", Style = "Tab", Size = UDim2.new(0.5, -4, 1, 0), OnClick = function()
		currentTab = "Drops"
		L.Build(scroll, State.Current or state)
	end })
	dropTab.SetSelected(currentTab == "Drops")
	local itemsTab = Kit.Button(tabs, { Text = "Items", Icon = "Bag", IconLayout = "Row", Style = "Tab", Size = UDim2.new(0.5, -4, 1, 0), Position = UDim2.new(0.5, 4, 0, 0), OnClick = function()
		currentTab = "Items"
		L.Build(scroll, State.Current or state)
	end })
	itemsTab.Instance.Position = UDim2.new(0.5, 4, 0, 0)
	itemsTab.SetSelected(currentTab == "Items")

	if currentTab == "Drops" then
		P.Section(scroll, "Choose a chest", nxt())
		local chestRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = nxt() }, scroll)
		for i, boxType in catalog.Loot.BoxTypes do
			local icon = if boxType == "Crystal" then "CrystalBox" elseif boxType == "Rare" then "RareBox" else "Box"
			local count = (state.Boxes or {})[boxType] or 0
			local button = Kit.Button(chestRow, { Text = string.format("%s x%d", boxType, count), Icon = icon, IconLayout = "Row", Style = "Tab", Size = UDim2.new(1 / #catalog.Loot.BoxTypes, -6, 1, 0), Position = UDim2.new((i - 1) / #catalog.Loot.BoxTypes, (i - 1) * 6, 0, 0), OnClick = function()
				selectedBox, openConfirmUntil = boxType, 0
				L.Build(scroll, State.Current or state)
			end })
			button.Instance.Position = UDim2.new((i - 1) / #catalog.Loot.BoxTypes, (i - 1) * 6, 0, 0)
			button.SetSelected(selectedBox == boxType)
		end
		local boxNames = { Dungeon = "Dungeon Chest", Rare = "Royal Chest", Crystal = "Crystal Chest" }
		P.Section(scroll, boxNames[selectedBox] or selectedBox, nxt())
		local controlsOrder, openOrder = nxt(), nxt()
		local odds = (state.BoxOdds or {})[selectedBox]
		if odds then
			local oddsCard = P.Card(scroll, nxt())
			P.Text(oddsCard, "Next chest odds; pity can change later rolls in a batch.", Theme.TextSize.Body, Theme.TextMuted, true, 1)
			for i, rarity in odds.Rarities do
				local color = P.RarityColor[rarity.Id] or Theme.TextPrimary
				local lines = { string.format("%s — %s", rarity.Id, P.Pct(rarity.Chance)) }
				for _, room in odds.Rooms do
					if room.Rarity == rarity.Id then
						table.insert(lines, string.format("%s  %s", roomName(room.Id), P.Pct(room.Chance)))
					end
				end
				P.Text(oddsCard, table.concat(lines, "\n"), Theme.TextSize.Body, color, true, i + 1)
			end
		end
		local stock = (state.Boxes or {})[selectedBox] or 0
		local owned = 0
		for _ in state.Rooms or {} do owned += 1 end
		local maxOpen = math.min(stock, math.max(0, 30 - owned))
		selectedQty[selectedBox] = math.clamp(selectedQty[selectedBox] or 1, if maxOpen > 0 then 1 else 0, maxOpen)
		local controls = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.65, 0, 0, 52), LayoutOrder = controlsOrder }, scroll)
		local qty = selectedQty[selectedBox]
		local minus = Kit.Button(controls, { Text = "−", Style = "Secondary", Size = UDim2.fromOffset(48, 48), OnClick = function()
			selectedQty[selectedBox] = math.max(1, qty - 1)
			openConfirmUntil = 0
			L.Build(scroll, State.Current or state)
		end })
		local qtyLabel = Kit.Label(controls, string.format("Open %d", qty), Theme.TextSize.Body, Theme.TextPrimary, true)
		qtyLabel.AnchorPoint, qtyLabel.Position, qtyLabel.Size = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0), UDim2.fromOffset(130, 48)
		local plus = Kit.Button(controls, { Text = "+", Style = "Secondary", Size = UDim2.fromOffset(48, 48), Position = UDim2.new(1, -48, 0, 0), OnClick = function()
			selectedQty[selectedBox] = math.min(maxOpen, qty + 1)
			openConfirmUntil = 0
			L.Build(scroll, State.Current or state)
		end })
		plus.Instance.Position = UDim2.new(1, -48, 0, 0)
		minus.SetEnabled(qty > 1)
		plus.SetEnabled(qty < maxOpen)
		local openKey = selectedBox .. ":" .. tostring(qty)
		local openButton = Kit.Button(scroll, { Text = if openConfirmUntil > os.clock() and openConfirmKey == openKey then string.format("Confirm opening %d", qty) else string.format("Open %d", qty), Style = "Primary", Size = UDim2.new(0.65, 0, 0, 48), LayoutOrder = openOrder, OnClick = function()
			if busy or qty < 1 then return end
			if openConfirmUntil <= os.clock() or openConfirmKey ~= openKey then
				openConfirmKey = openKey
				openConfirmUntil = os.clock() + 3
				L.Build(scroll, State.Current or state)
				task.delay(3.1, function()
					if openConfirmUntil > 0 and openConfirmUntil <= os.clock() then
						openConfirmUntil = 0
						if scroll.Parent then L.Build(scroll, State.Current or state) end
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
				else State.Hold(false); L.Build(scroll, State.Current or state) end
			end, function()
				State.Hold(false)
				L.Build(scroll, State.Current or state)
			end)
		end })
		openButton.SetEnabled(maxOpen > 0)
	else
		local cols = P.Columns(scroll)
		P.Section(scroll, "Blueprints", 1000)
		local bpGrid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 1001 }, scroll)
		make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / cols, -8 * (cols - 1) / cols - 1, 0, 235), SortOrder = Enum.SortOrder.LayoutOrder }, bpGrid)
		for itemOrder, id in catalog.RoomOrder do
			local def = catalog.Rooms[id]
			local cost = def and def.CraftCost
			if def and def.Craftable and cost and ((state.Blueprints or {})[id] or 0) > 0 then
				local n = (state.Blueprints or {})[id] or 0
				local card = Kit.Panel(bpGrid, { LayoutOrder = itemOrder, Rarity = def.Rarity, Pad = Vector2.new(4, 3) })
				make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, card)
				local art = Kit.Icon(card, "BlueprintCard", UDim2.fromOffset(90, 90))
				art.LayoutOrder = 1
				local room = P.RoomImage(art, id, 58, def.Kind)
				room.AnchorPoint, room.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
				local name = Kit.Label(card, roomName(id), 16, Theme.TextPrimary, true)
				name.Size, name.LayoutOrder, name.TextScaled = UDim2.new(1, 0, 0, 24), 2, true
				make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 16 }, name)
				local count = Kit.Label(card, string.format("%d/%d", n, cost), 16, Theme.TextMuted, true)
				count.Size, count.LayoutOrder = UDim2.new(1, 0, 0, 22), 3
				local craft = Kit.Button(card, { Text = "Craft", Style = "Primary", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, OnClick = function()
					run("CraftBlueprint", { id }, function() Toast.Show(roomName(id) .. " crafted.", "Good") end)
				end })
				craft.SetEnabled(n >= cost)
			end
		end

		P.Section(scroll, "Unplaced rooms", nxt())
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
		local saleKey = table.concat(selectedIds, ",")
		local sellButton = Kit.Button(scroll, { Text = if sellConfirmUntil > os.clock() and sellConfirmKey == saleKey then string.format("Confirm %d for %s coins", selectedCount, Badges.Comma(selectedValue)) else string.format("Sell %d for %s coins", selectedCount, Badges.Comma(selectedValue)), Icon = "CoinStack", IconLayout = "Row", Style = "Danger", Size = UDim2.new(1, 0, 0, 48), LayoutOrder = nxt(), OnClick = function()
			if busy or #selectedIds == 0 then return end
			if sellConfirmUntil <= os.clock() or sellConfirmKey ~= saleKey then
				sellConfirmKey = saleKey
				sellConfirmUntil = os.clock() + 3
				L.Build(scroll, State.Current or state)
				task.delay(3.1, function()
					if sellConfirmUntil > 0 and sellConfirmUntil <= os.clock() then
						sellConfirmUntil = 0
						if scroll.Parent then L.Build(scroll, State.Current or state) end
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
				L.Build(scroll, State.Current or state)
			end)
		end })
		sellButton.SetEnabled(selectedCount > 0)
		for _, group in groups do
			local stackCount = #group.Instances
			local chosen = selectedItems[group.Key] or 0
			local card = P.Card(scroll, nxt(), group.Rarity)
			local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52) }, card)
			local image = P.RoomImage(row, group.Id, 46, group.Def.Kind)
			image.Position = UDim2.fromOffset(0, 3)
			local text = string.format("%s  %s  Lv %d  x%d%s", roomName(group.Id), P.Rich("[" .. group.Rarity .. "]", group.Rarity), group.Level, stackCount, if group.Modifier then "\n" .. tostring(group.Modifier) else "")
			if P.PerkText(group.Perks) ~= "" then text ..= "\n" .. P.PerkText(group.Perks) end
			local label = P.Text(row, text, Theme.TextSize.Body, Theme.TextPrimary, true)
			label.Position, label.Size = UDim2.fromOffset(52, 0), UDim2.new(1, -158, 0, 52)
			local qtyLabel = Kit.Label(row, string.format("%d/%d", chosen, stackCount), Theme.TextSize.Body, Theme.TextPrimary, true)
			qtyLabel.AnchorPoint, qtyLabel.Position, qtyLabel.Size = Vector2.new(1, 0.5), UDim2.new(1, -44, 0.5, 0), UDim2.fromOffset(50, 40)
			local remove = Kit.Button(row, { Text = "−", Style = "Secondary", Size = UDim2.fromOffset(40, 44), Position = UDim2.new(1, -132, 0.5, -22), OnClick = function()
				selectedItems[group.Key] = math.max(0, chosen - 1)
				sellConfirmUntil = 0
				L.Build(scroll, State.Current or state)
			end })
			local add = Kit.Button(row, { Text = "+", Style = "Secondary", Size = UDim2.fromOffset(40, 44), Position = UDim2.new(1, -84, 0.5, -22), OnClick = function()
				selectedItems[group.Key] = math.min(stackCount, chosen + 1)
				sellConfirmUntil = 0
				L.Build(scroll, State.Current or state)
			end })
			remove.Instance.Position = UDim2.new(1, -132, 0.5, -22)
			add.Instance.Position = UDim2.new(1, -84, 0.5, -22)
			remove.SetEnabled(chosen > 0)
			add.SetEnabled(group.Def.Craftable and chosen < stackCount and selectedCount < 30)
		end
		if #groups == 0 then P.Empty(scroll, "No unplaced rooms", nxt()) end
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return L
