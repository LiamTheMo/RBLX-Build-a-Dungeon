-- Loot tab: boxes with real odds + pity, open reveal, blueprints, scrap. The odds
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
local confirming: { [string]: number } = {} -- instanceId -> expiry (os.clock)

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

local function run(remote: string, arg: string, onOk: (any) -> (), onFail: (() -> ())?)
	if busy then
		if onFail then
			onFail()
		end
		return
	end
	busy = true
	local ok, res = Net.Invoke(remote, arg)
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

	P.Section(scroll, "Chests", nxt())
	local cols = P.Columns(scroll)
	local chestGrid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nxt() }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / cols, -8 * (cols - 1) / cols - 1, 0, if Scale.Phone then 370 else 330), SortOrder = Enum.SortOrder.LayoutOrder }, chestGrid)
	for order, boxType in catalog.Loot.BoxTypes do
		local count = (state.Boxes or {})[boxType] or 0
		local card = Kit.Panel(chestGrid, { LayoutOrder = order, Pad = Vector2.new(4, 4) })
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, card)
		Kit.Icon(card, if boxType == "Crystal" then "CrystalBox" elseif boxType == "Rare" then "RareBox" else "Box", UDim2.fromOffset(62, 62)).LayoutOrder = 1
		local name = Kit.Label(card, string.format("%s  x%d", if boxType == "Crystal" then "Crystal Chest" elseif boxType == "Rare" then "Royal Chest" else "Dungeon Chest", count), 17, Theme.TextPrimary, true)
		name.Size, name.LayoutOrder, name.TextScaled = UDim2.new(1, 0, 0, 25), 2, true
		make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 17 }, name)
		local odds = (state.BoxOdds or {})[boxType]
		if odds then
			local rf = P.ChipFlow(card, 3)
			rf.AutomaticSize, rf.Size = Enum.AutomaticSize.None, UDim2.new(1, 0, 0, if Scale.Phone then 180 else 140)
			local layout = rf:FindFirstChildOfClass("UIListLayout")
			layout.Padding = UDim.new(0, 2)
			layout.VerticalAlignment = Enum.VerticalAlignment.Top
			for i, e in odds.Rarities do
				local lines = { e.Id .. " - " .. P.Pct(e.Chance) }
				for _, room in odds.Rooms do
					if room.Rarity == e.Id then table.insert(lines, roomName(room.Id) .. " " .. P.Pct(room.Chance)) end
				end
				local color = P.RarityColor[e.Id] or Theme.TextPrimary
				local chip = P.Chip(rf, i, function(p) return Kit.Gem(p, e.Id, UDim2.fromOffset(22, 22)) end, P.Pct(e.Chance), color, table.concat(lines, "\n"), color, e.Id)
				chip.Size = UDim2.fromOffset(0, 44)
				Kit.MinTouch(chip)
			end
		end
		local open = Kit.Button(card, { Text = "Open", Style = "Primary", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 4, OnClick = function()
			State.Hold(true)
			run("OpenBox", boxType, function(res)
				if type(res) == "table" then
					reveal(boxType, res, function() State.Hold(false); Bus.RoomAwarded:Fire(res) end)
				else State.Hold(false) end
			end, function() State.Hold(false) end)
		end })
		open.SetEnabled(count > 0)
	end

	P.Section(scroll, "Blueprints", nxt())
	local bpGrid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = nxt() }, scroll)
	make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1 / cols, -8 * (cols - 1) / cols - 1, 0, 235), SortOrder = Enum.SortOrder.LayoutOrder }, bpGrid)
	for order, id in catalog.RoomOrder do
		local def = catalog.Rooms[id]
		local cost = def and def.CraftCost
		if def and def.Craftable and cost then
			local n = (state.Blueprints or {})[id] or 0
			local card = Kit.Panel(bpGrid, { LayoutOrder = order, Rarity = def.Rarity, Pad = Vector2.new(4, 3) })
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
				run("CraftBlueprint", id, function() Toast.Show(roomName(id) .. " crafted.", "Good") end)
			end })
			craft.SetEnabled(n >= cost)
		end
	end

	P.Section(scroll, "Unplaced rooms", nxt())
	local placed = {}
	for _, instanceId in state.Layout or {} do
		placed[instanceId] = true
	end
	local list = {}
	for instanceId, room in state.Rooms or {} do
		local def = catalog.Rooms[room.Id]
		if not placed[instanceId] and def and def.Craftable then
			table.insert(list, { InstanceId = instanceId, Room = room })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Catalog.RarityRank(a.Room.Rarity) or 0, Catalog.RarityRank(b.Room.Rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.Room.Id ~= b.Room.Id then
			return a.Room.Id < b.Room.Id
		end
		return a.InstanceId < b.InstanceId
	end)
	if #list == 0 then
		P.Empty(scroll, "No unplaced rooms", nxt())
	end
	for _, e in list do
		local room = e.Room
		local perks = P.PerkText(room.Perks)
		local text = string.format("%s %s  Lv %d%s", roomName(room.Id), P.Rich("[" .. tostring(room.Rarity) .. "]", room.Rarity), room.Level or 1, if perks ~= "" then "\n" .. perks else "")
		local card = P.Card(scroll, nxt(), room.Rarity)
		local btn
		_, _, btn = P.Row(card, text, { Text = "Scrap", Icon = "Blueprint", IconLayout = "Row", Style = "Danger", Width = 150, Tip = string.format("+%d blueprints", (catalog.Rooms[room.Id] or {}).ScrapReturn or 0), OnClick = function()
			if (confirming[e.InstanceId] or 0) < os.clock() then
				confirming[e.InstanceId] = os.clock() + 3
				btn.SetText("Tap again")
				task.delay(3.1, function()
					if btn.Instance.Parent then
						btn.SetText("Scrap")
					end
				end)
				return
			end
			confirming[e.InstanceId] = nil
			run("ScrapRoom", e.InstanceId, function()
				Toast.Show(string.format("+%d blueprints", (catalog.Rooms[room.Id] or {}).ScrapReturn or 0), "Good")
			end)
		end }, { Room = room.Id, Kind = (catalog.Rooms[room.Id] or {}).Kind })
		if (confirming[e.InstanceId] or 0) > os.clock() then
			btn.SetText("Tap again")
		end
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return L
