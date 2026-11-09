-- Treasure vault body: vaulted coins, the exchange "x% of coins -> +y% luck" (VaultRate), the resulting
-- rare-visitor chance and the thief risk, with a 0-100% slider. The slider debounces (0.3 s) and sends the final
-- value on release; the server validates (EncounterActive while a visitor is inside) and is the truth. The
-- numbers shown while dragging are local estimates from the server's rate; the State snapshot replaces them.
local Badges = require(script.Parent.Badges)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local P = require(script.Parent.PanelsKit)
local Plots = require(script.Parent.Plots)
local ReasonText = require(script.Parent.ReasonText)
local Scale = require(script.Parent.Scale)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make

local Vault = {}

local DEBOUNCE = 0.3

local function hrow(parent: Instance, padding: number, props: { [string]: any }): Frame
	local f = make("Frame", props, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding),
	}, f)
	return f
end

-- A labelled section: a Row.Well (514x126, ONE whole sprite) with a gold-rimmed label pill (Hud.PillGold, whole) on its top
-- edge. Every well is the same width (set by Layout) and exactly 4.08 times as wide as tall; content goes inside its Inner rect.
local ROW = Kit.Spec("Row.Well")
local PILL = Kit.Spec("Hud.PillGold")
local ROW_R = ROW.Size.X / ROW.Size.Y
local LABEL_H = 38
local wells: { { Well: any, Label: any } } = {}

local function placeWell(entry: { Well: any, Label: any }, rowW: number)
	local well, label = entry.Well, entry.Label
	well.Size = UDim2.fromOffset(rowW, rowW / ROW_R)
	-- The pill sits fully ABOVE the well (its own row of space), never half outside a clipped edge.
	label.Position = UDim2.new(0.5, 0, 0, -(LABEL_H / 2 + 4))
end

local function section(parent: Instance, title: string, order: number)
	local rowW = 520
	local well = Kit.Panel(parent, { Sprite = "Row", Size = UDim2.fromOffset(rowW, rowW / ROW_R), LayoutOrder = order })
	well.ClipsDescendants = false
	local label = Kit.Panel(well, { Sprite = "PillGold", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(LABEL_H * PILL.Size.X / PILL.Size.Y, LABEL_H), ZIndex = 5 })
	local text = Kit.Label(label, title, 18, Theme.TextPrimary, true)
	text.Size, text.TextWrapped, text.ZIndex = UDim2.fromScale(1, 1), false, 6
	Kit.FixedText(text, Theme.TextSize.Label)
	-- The pill is made wide enough for its (fixed-size) title.
	local need = Kit.Measure(title, Theme.TextSize.Label, Theme.HeadingFont, 2000).X / 0.8 + 16
	label.Size = UDim2.fromOffset(math.max(LABEL_H * PILL.Size.X / PILL.Size.Y, need), LABEL_H)
	Kit.Stroke(text, Theme.Stroke, 2)
	local entry = { Well = well, Label = label }
	table.insert(wells, entry)
	placeWell(entry, rowW)
	return well
end

-- body: the modal body Frame. Returns { Refresh, Layout }.
function Vault.Build(body: Frame)
	local self: any = {}
	table.clear(wells)
	local root = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 12 }, body)
	-- Left: the treasure room's art with the vaulted coin total in a gold-rimmed pill.
	local art = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.36, -8, 0, 250) }, root)
	local artImage = make("Frame", { Name = "ArtImage", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -66) }, art)
	local coinPill = Kit.Panel(art, { Sprite = "PillGold", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(252, 70), Active = true })
	local coinRow = hrow(coinPill, 8, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Kit.Icon(coinRow, "CoinStack", UDim2.fromOffset(34, 34)).LayoutOrder = 1
	local vaultedLabel = Kit.Label(coinRow, "", Theme.TextSize.Number + 4, Theme.TextPrimary, true)
	vaultedLabel.Size, vaultedLabel.TextWrapped, vaultedLabel.LayoutOrder = UDim2.new(0, 130, 0, 34), false, 2
	Kit.FixedText(vaultedLabel, Theme.TextSize.Number)
	Kit.Stroke(vaultedLabel, Theme.Stroke, 2)
	Kit.Tip(coinPill, "Vaulted coins")
	-- Right: Allocation, Exchange Rate and the stat strip.
	local rows = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) }, root)
	local rowsList = make("UIListLayout", { Padding = UDim.new(0, LABEL_H + 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, rows)
	-- Allocation and Exchange Rate: stacked on desktop, side by side on a phone (so all three wells fit the short well).
	local top = make("Frame", { Name = "Top", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 1 }, rows)
	local topList = make("UIListLayout", { Padding = UDim.new(0, LABEL_H + 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, top)
	make("UIPadding", { PaddingTop = UDim.new(0, LABEL_H + 10), PaddingRight = UDim.new(0, 16), PaddingBottom = UDim.new(0, 24) }, rows)
	local shownRoom = ""

	-- Allocation: slider (padlock instead of the % icon while an adventurer is inside).
	local allocation = section(top, "Allocation", 1)
	local sliderRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true }, allocation)
	local sliderIcon = Kit.Icon(sliderRow, "VaultPercent", UDim2.fromOffset(44, 44))
	sliderIcon.AnchorPoint, sliderIcon.Position = Vector2.new(0, 0.5), UDim2.new(0, 4, 0.5, 0)
	local lockIcon = Kit.Sprite(sliderRow, "Round.Lock", { Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Visible = false, ZIndex = 5 })
	local sliderHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -60, 1, 0) }, sliderRow)
	Kit.Tip(sliderRow, function() return if lockIcon.Visible then "Locked while an adventurer is inside" else "Share of your coins in the vault" end)

	-- Exchange Rate: vaulted coins <-> extra visits.
	local exchange = section(top, "Exchange Rate", 2)
	local exchRow = hrow(exchange, 14, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Kit.Icon(exchRow, "CoinStack", UDim2.fromOffset(46, 46)).LayoutOrder = 1
	Kit.Icon(exchRow, "Exchange", UDim2.fromOffset(40, 40)).LayoutOrder = 2
	Kit.Icon(exchRow, "Speed", UDim2.fromOffset(46, 46)).LayoutOrder = 3
	local bonusLabel = Kit.Label(exchRow, "", Theme.TextSize.Number, Theme.Success, true)
	bonusLabel.Size, bonusLabel.TextWrapped, bonusLabel.LayoutOrder = UDim2.fromOffset(120, 44), false, 4
	Kit.FixedText(bonusLabel, Theme.TextSize.Heading)
	Kit.Stroke(bonusLabel, Theme.Stroke, 2)
	Kit.Tip(exchange, "More adventurers")

local pending: number? = nil -- value the player chose that the server has not confirmed yet
	local sending, want = false, nil :: number?
	local gen = 0

	local function send()
		if sending or want == nil then
			return
		end
		sending = true
		task.spawn(function()
			while want ~= nil do
				local value = want
				want = nil
				local s = State.Current
				if s and s.VaultPercent == value then
					if pending == value then
						pending = nil
					end
					continue
				end
				local ok, reason = Net.Invoke("SetVaultPercent", value)
				if not ok then
					Toast.Show(ReasonText.Get(reason), "Bad")
					Sound.Play("Error")
					pending = nil
					self.Refresh()
				end
			end
			sending = false
		end)
	end

	local slider
	local percentNow = 0
	local function preview(percent: number)
		percentNow = percent
		self.Preview(percent)
	end
	slider = Kit.Slider(sliderHolder, 0, function(v)
		local percent = math.floor(v * 100 + 0.5)
		pending = percent
		preview(percent)
		gen += 1
		local mine = gen
		task.delay(DEBOUNCE, function()
			if gen == mine then
				want = percent
				send()
			end
		end)
	end, function(v)
		local percent = math.floor(v * 100 + 0.5)
		gen += 1
		pending = percent
		want = percent
		send()
	end)
	slider.Instance.Position = UDim2.fromScale(0, 0.5)
	slider.Instance.AnchorPoint = Vector2.new(0, 0.5)
	-- The slider is fixed art (about 360 wide): on a narrow well it is scaled down as a whole (one scale for the control).
	local sliderScale = make("UIScale", {}, slider.Instance)
	local function fitSlider()
		local w = sliderHolder.AbsoluteSize.X / math.max(Scale.Value, 0.01)
		if w < 10 then
			return
		end
		local s = math.min(1, w / 360)
		sliderScale.Scale = s
		slider.Instance.Size = UDim2.new(1 / s, 0, 0, 56)
	end
	sliderHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSlider)
	fitSlider()

	-- Stat strip: thief risk, rare-visitor chance, vault luck: one Row.Well (whole sprite) with three equal cells.
	local bottom = Kit.Panel(rows, { Sprite = "Row", Size = UDim2.fromOffset(520, 520 / ROW_R), LayoutOrder = 3 })
	bottom.ClipsDescendants = false
	table.insert(wells, { Well = bottom, Label = nil :: any, Strip = true })
	local bottomRow = hrow(bottom, 0, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local function chip(order: number, icon: string, color: Color3, tip: string)
		local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1 / 3, 1), LayoutOrder = order, Active = true }, bottomRow)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		Kit.Icon(f, icon, UDim2.fromOffset(34, 34)).LayoutOrder = 1
		local l = Kit.Label(f, "", Theme.TextSize.Number - 4, color, true)
		l.Size, l.TextWrapped, l.LayoutOrder = UDim2.new(1, -42, 0, 36), false, 2
		Kit.FixedText(l, Theme.TextSize.Label + 2)
		Kit.Stroke(l, Theme.Stroke, 2)
		Kit.Tip(f, tip)
		return l
	end
	local riskLabel = chip(1, "Thief", Theme.Danger, "Most a thief could steal")
	local rareLabel = chip(2, "Crown", Theme.TextPrimary, "Chance multiplier for Elite, Shiny and Gilded adventurers")
	local luckLabel = chip(3, "Exchange", Theme.TextPrimary, "Vault luck multiplier for drops and rare finds")

	local function locked(): boolean
		local ok, plot = pcall(Plots.WaitOwn)
		return ok and plot:GetAttribute("State") == "Encounter"
	end

	-- Shows the numbers for `percent` (the confirmed value, or the slider while dragging).
	function self.Preview(percent: number)
		local s = State.Current
		if not s then
			return
		end
		local confirmed = percent == (s.VaultPercent or 0)
		-- The bonus is server-calculated; pending values are not guessed locally.
		vaultedLabel.Text = if confirmed then Badges.Comma(s.Vaulted or 0) else "…"
		bonusLabel.Text = if confirmed then "+" .. tostring(math.floor((s.VaultBonus or 0) * 10 + 0.5) / 10) .. "%" else "…"
		riskLabel.Text = if confirmed then "-" .. Badges.Comma(s.VaultRisk or 0) else "…"
		rareLabel.Text = if confirmed then string.format("x%.2f rare", s.VariantChance or 1) else "…"
		luckLabel.Text = if confirmed then string.format("x%.2f luck", s.VaultLuck or 1) else "…"
	end

	function self.Layout()
		local width = body.AbsoluteSize.X / math.max(Scale.Value, 0.01)
		local phone = Scale.Phone
		local wide = width >= 600 and not phone
		local rowAvail = (if wide then width * 0.64 else width) - 30
		local rowW = math.floor(math.clamp(rowAvail, 300, if phone then 520 else 430))
		art.Visible = wide
		rows.Position, rows.Size = if wide then UDim2.fromScale(0.36, 0) else UDim2.new(), UDim2.new(if wide then 0.64 else 1, 0, 0, 0)
		-- Phone: the two section wells share one row, the stat strip sits under them with a small gap.
		topList.FillDirection = if phone then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		topList.Padding = UDim.new(0, if phone then 14 else LABEL_H + 8)
		topList.VerticalAlignment = Enum.VerticalAlignment.Top
		rowsList.Padding = UDim.new(0, if phone then 14 else LABEL_H + 8)
		local secW = if phone then math.floor((rowAvail - 14) / 2) else rowW
		for _, e in wells do
			local w = if e.Strip then (if phone then math.min(rowAvail, 440) else rowW) else secW
			if e.Label then
				placeWell(e, w)
			else
				e.Well.Size = UDim2.fromOffset(w, w / ROW_R)
			end
		end
	end

	function self.Refresh()
		local s = State.Current
		if not s then
			return
		end
		local roomId = ""
		for _, instanceId in s.Layout or {} do
			local room = s.Rooms and s.Rooms[instanceId]
			local def = room and Catalog.Room(room.Id)
			if def and def.Kind == "Treasure" then roomId = room.Id; break end
		end
		if roomId ~= shownRoom then
			shownRoom = roomId
			for _, child in artImage:GetChildren() do child:Destroy() end
			if roomId ~= "" then
				local image = P.RoomImage(artImage, roomId, 180, "Treasure")
				image.AnchorPoint, image.Position, image.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
			end
		end
		local isLocked = locked()
		lockIcon.Visible = isLocked
		sliderIcon.Visible = not isLocked
		slider.SetLocked(isLocked)
		-- Locked keeps the normal yellow look (only a light dim); the padlock badge says why.
		for _, d in slider.Instance:GetDescendants() do
			if d:IsA("ImageLabel") and d.ImageTransparency == 0.5 then
				d.ImageTransparency = 0.12
			end
		end
		local server = s.VaultPercent or 0
		if pending ~= nil and pending == server then
			pending = nil
		end
		if pending == nil and not slider.IsDragging() then
			slider.Set(server / 100)
			preview(server)
		else
			preview(percentNow)
		end
	end

	State.Changed:Connect(function()
		if body.Parent and body.Parent.Visible then
			self.Refresh()
		end
	end)
	-- The lock follows the plot's encounter state.
	task.spawn(function()
		local plot = Plots.WaitOwn()
		plot:GetAttributeChangedSignal("State"):Connect(function()
			if body.Parent and body.Parent.Visible then
				self.Refresh()
			end
		end)
	end)
	self.Layout()
	return self
end

return Vault
