-- Treasure vault body: vaulted coins, the exchange "x% of coins -> +y% visits" (VaultRate), the resulting
-- visitor interval and the thief risk, with a 0-100% slider. The slider debounces (0.3 s) and sends the final
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

-- A labelled section: a Panel.Section well with a gold-rimmed label pill (Hud.PillGold) on its top edge.
local function section(parent: Instance, title: string, order: number, height: number)
	local well = Kit.Panel(parent, { Sprite = "Small", Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Pad = Vector2.new(6, 6) })
	well.ClipsDescendants = false
	local label = Kit.Panel(well, { Sprite = "PillGold", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -4), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), ZIndex = 5 })
	local text = Kit.Label(label, title, 18, Theme.TextPrimary, true)
	text.AutomaticSize, text.Size, text.TextWrapped, text.ZIndex = Enum.AutomaticSize.X, UDim2.fromOffset(0, 30), false, 6
	make("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, text)
	Kit.Stroke(text, Theme.Stroke, 2)
	return well
end

-- body: the modal body Frame. Returns { Refresh, Layout }.
function Vault.Build(body: Frame)
	local self: any = {}
	local root = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 12 }, body)
	-- Left: the treasure room's art with the vaulted coin total in a gold-rimmed pill.
	local art = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.36, -8, 0, 250) }, root)
	local artImage = make("Frame", { Name = "ArtImage", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -66) }, art)
	local coinPill = Kit.Panel(art, { Sprite = "PillGold", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(230, 56), Active = true })
	local coinRow = hrow(coinPill, 8, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	Kit.Icon(coinRow, "CoinStack", UDim2.fromOffset(40, 40)).LayoutOrder = 1
	local vaultedLabel = Kit.Label(coinRow, "", Theme.TextSize.Number + 4, Theme.TextPrimary, true)
	vaultedLabel.Size, vaultedLabel.TextWrapped, vaultedLabel.TextScaled, vaultedLabel.LayoutOrder = UDim2.new(0, 130, 0, 40), false, true, 2
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = Theme.TextSize.Number + 4 }, vaultedLabel)
	Kit.Stroke(vaultedLabel, Theme.Stroke, 2)
	Kit.Tip(coinPill, "Vaulted coins")
	-- Right: Allocation, Exchange Rate and the stat strip.
	local rows = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0) }, root)
	make("UIListLayout", { Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, rows)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingRight = UDim.new(0, 16) }, rows)
	local shownRoom = ""

	-- Allocation: slider (padlock instead of the % icon while an adventurer is inside).
	local allocation = section(rows, "Allocation", 1, 82)
	local sliderRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true }, allocation)
	local sliderIcon = Kit.Icon(sliderRow, "VaultPercent", UDim2.fromOffset(44, 44))
	sliderIcon.AnchorPoint, sliderIcon.Position = Vector2.new(0, 0.5), UDim2.new(0, 4, 0.5, 6)
	local lockIcon = Kit.Sprite(sliderRow, "Round.Lock", { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 6), Visible = false, ZIndex = 5 })
	local sliderHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -60, 1, 0) }, sliderRow)
	Kit.Tip(sliderRow, "Share of your coins in the vault")

	-- Exchange Rate: vaulted coins <-> extra visits.
	local exchange = section(rows, "Exchange Rate", 2, 82)
	local exchRow = hrow(exchange, 14, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 1, -8) })
	Kit.Icon(exchRow, "CoinStack", UDim2.fromOffset(46, 46)).LayoutOrder = 1
	Kit.Icon(exchRow, "Exchange", UDim2.fromOffset(40, 40)).LayoutOrder = 2
	Kit.Icon(exchRow, "Speed", UDim2.fromOffset(46, 46)).LayoutOrder = 3
	local bonusLabel = Kit.Label(exchRow, "", Theme.TextSize.Number, Theme.Success, true)
	bonusLabel.Size, bonusLabel.TextWrapped, bonusLabel.TextScaled, bonusLabel.LayoutOrder = UDim2.fromOffset(120, 44), false, true, 4
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = Theme.TextSize.Number }, bonusLabel)
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

	-- Stat strip: thief risk, resulting interval, vault luck.
	local bottom = Kit.Panel(rows, { Sprite = "Small", Size = UDim2.new(1, 0, 0, 74), LayoutOrder = 3, Pad = Vector2.new(6, 4) })
	local bottomGrid = make("UIGridLayout", { CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, bottom)
	local function chip(order: number, icon: string, color: Color3, tip: string)
		local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 44), LayoutOrder = order, Active = true }, bottom)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		Kit.Icon(f, icon, UDim2.fromOffset(38, 38)).LayoutOrder = 1
		local l = Kit.Label(f, "", Theme.TextSize.Number - 4, color, true)
		l.Size, l.TextWrapped, l.TextScaled, l.LayoutOrder = UDim2.new(1, -46, 0, 36), false, true, 2
		make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = Theme.TextSize.Number - 4 }, l)
		Kit.Stroke(l, Theme.Stroke, 2)
		Kit.Tip(f, tip)
		return l
	end
	local riskLabel = chip(1, "Thief", Theme.Danger, "Most a thief could steal")
	local intervalLabel = chip(2, "Clock", Theme.TextPrimary, "Wait after an escape; defeated adventurers are replaced immediately")
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
		intervalLabel.Text = if confirmed then string.format("%.1fs", s.VisitorInterval or 0) else "…"
		luckLabel.Text = if confirmed then string.format("x%.2f luck", s.VaultLuck or 1) else "…"
	end

	function self.Layout()
		local width = body.AbsoluteSize.X / math.max(Scale.Value, 0.01)
		local wide = width >= 600
		local rowWidth = if wide then width * 0.64 else width
		local narrow = rowWidth < 430
		art.Visible = wide
		rows.Position, rows.Size = if wide then UDim2.fromScale(0.36, 0) else UDim2.new(), UDim2.new(if wide then 0.64 else 1, 0, 0, 0)
		local columns = if narrow then 2 else 3
		bottom.Size = UDim2.new(1, 0, 0, if narrow then 118 else 74)
		bottomGrid.FillDirectionMaxCells = columns
		bottomGrid.CellSize = UDim2.new(1 / columns, -6 * (columns - 1) / columns - 2, 0, 44)
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
