-- Treasure vault body: vaulted coins, the exchange "x% of coins -> +y% visits" (VaultRate), the resulting
-- visitor interval and the thief risk, with a 0-100% slider. The slider debounces (0.3 s) and sends the final
-- value on release; the server validates (EncounterActive while a visitor is inside) and is the truth. The
-- numbers shown while dragging are local estimates from the server's rate; the State snapshot replaces them.
local Badges = require(script.Parent.Badges)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Plots = require(script.Parent.Plots)
local ReasonText = require(script.Parent.ReasonText)
local Scale = require(script.Parent.Scale)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local X = Enum.AutomaticSize.X

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

-- A rounded stat plate: icon + text, `color` for the text.
local function plate(parent: Instance, order: number, icon: string, color: Color3, tip: string)
	local f = Kit.Panel(parent, { Sprite = "Pill", Size = UDim2.new(0.4, 0, 1, 0), LayoutOrder = order, Active = true })
	local row = hrow(f, 8, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local ic = Kit.Icon(row, icon, UDim2.fromOffset(40, 40))
	ic.LayoutOrder = 1
	local l = Kit.Label(row, "", Theme.TextSize.Number, color, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 40), false, 2
	Kit.Tip(f, tip)
	return l, f, ic
end

-- body: the modal body Frame. Returns { Refresh, Layout }.
function Vault.Build(body: Frame)
	local self: any = {}
	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, root)

	-- Row 1: vaulted coins <-> extra visits.
	local top = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 1 }, root)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}, top)
	local vaultedLabel = plate(top, 1, "CoinStack", Theme.TextPrimary, "Vaulted coins")
	local exch = Kit.Icon(top, "Exchange", UDim2.fromOffset(44, 44))
	exch.LayoutOrder = 2
	local bonusLabel = plate(top, 3, "Speed", Theme.Success, "More adventurers")

	-- Row 2: slider (padlock instead of the % icon while an adventurer is inside).
	local sliderRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2, Active = true }, root)
	local sliderIcon = Kit.Icon(sliderRow, "VaultPercent", UDim2.fromOffset(44, 44))
	sliderIcon.AnchorPoint, sliderIcon.Position = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5)
	local lockIcon = Kit.Icon(sliderRow, "Lock", UDim2.fromOffset(34, 34))
	lockIcon.AnchorPoint, lockIcon.Position, lockIcon.Visible, lockIcon.ZIndex = Vector2.new(0, 0.5), UDim2.new(0, 5, 0.5, 0), false, 5
	local sliderHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -52, 1, 0) }, sliderRow)
	Kit.Tip(sliderRow, "Share of your coins in the vault")

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

	-- Row 3: thief risk, resulting interval.
	local bottom = hrow(root, 18, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 3 })
	local function chip(order: number, icon: string, color: Color3, tip: string)
		local f = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 44), LayoutOrder = order, Active = true }, bottom)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		Kit.Icon(f, icon, UDim2.fromOffset(40, 40)).LayoutOrder = 1
		local l = Kit.Label(f, "", Theme.TextSize.Number - 2, color, true)
		l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 40), false, 2
		Kit.Tip(f, tip)
		return l
	end
	local riskLabel = chip(1, "Thief", Theme.Danger, "Most a thief could steal")
	local intervalLabel = chip(2, "Clock", Theme.TextPrimary, "Time between adventurers")
	local rateLabel = chip(3, "Exchange", Theme.TextMuted, "Vault exchange multiplier")

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
		rateLabel.Text = string.format("x%.2g", s.VaultRate or 0)
	end

	function self.Layout()
		local phone = Scale.Phone
		top.Size = UDim2.new(1, 0, 0, if phone then 52 else 64)
		sliderRow.Size = UDim2.new(1, 0, 0, if phone then 48 else 52)
		bottom.Size = UDim2.new(1, 0, 0, if phone then 40 else 48)
	end

	function self.Refresh()
		local s = State.Current
		if not s then
			return
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
