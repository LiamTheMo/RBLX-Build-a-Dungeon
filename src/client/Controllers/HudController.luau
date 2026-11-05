-- HUD, encounter panel, shop, settings, toasts and the blocking load-failure
-- message. Presents server state only; every button is a request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Definitions.Balance)
local Rooms = require(Shared.Definitions.Rooms)
local Visitors = require(Shared.Definitions.Visitors)
local Economy = require(Shared.Rules.Economy)
local Progression = require(Shared.Rules.Progression)
local ReasonText = require(Shared.UI.ReasonText)

local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Kit = require(Ui.Kit)
local Net = require(Ui.Net)
local Plots = require(Ui.Plots)
local Scale = require(Ui.Scale)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)

local make = Kit.Make

local Hud = {}

local ROLE_ICON = { Defender = "Shield", Trap = "Sword", Treasure = "Vault", Support = "Upgrade" }
local X = Enum.AutomaticSize.X

local function request(name: string, ...: any): boolean
	local ok, reason = Net.Invoke(name, ...)
	if not ok then
		Toast.Show(ReasonText.Get(reason), "Bad")
		Sound.Play("Error")
	end
	return ok
end

-- Horizontal list (children ordered by LayoutOrder, centred vertically).
local function hlist(parent: Instance, padding: number?, props: { [string]: any }?)
	local l = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 8),
	}, parent)
	for k, v in props or {} do
		l[k] = v
	end
	return l
end

local function pad(parent: Instance, h: number, v: number?)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		PaddingTop = UDim.new(0, v or 0),
		PaddingBottom = UDim.new(0, v or 0),
	}, parent)
end

local function pct(x: number?): number
	return math.floor((x or 0) * 100 + 0.5)
end

-- Icon + caption above a number that tweens (instant when reduced) and pops on gain.
local function cell(parent: Instance, iconName: string, caption: string, order: number)
	local root = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 44), LayoutOrder = order }, parent)
	hlist(root, 6)
	Kit.Icon(root, iconName, UDim2.fromOffset(32, 32)).LayoutOrder = 1
	local stack = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 44), LayoutOrder = 2 }, root)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, stack)
	local cap = Kit.Label(stack, caption, Theme.TextSize.Caption, Theme.TextMuted, true)
	cap.AutomaticSize, cap.Size, cap.TextWrapped, cap.TextXAlignment, cap.LayoutOrder = X, UDim2.fromOffset(0, 14), false, Enum.TextXAlignment.Left, 1
	local number = Kit.Label(stack, "0", Theme.TextSize.Number, Theme.TextPrimary, true)
	number.AutomaticSize, number.Size, number.TextWrapped, number.TextXAlignment, number.LayoutOrder = X, UDim2.fromOffset(0, 28), false, Enum.TextXAlignment.Left, 2
	local popScale = make("UIScale", {}, number)
	local value = make("NumberValue", {}, number)
	value.Changed:Connect(function()
		number.Text = tostring(math.floor(value.Value + 0.5))
	end)
	local last = 0
	local function set(n: number)
		if n == last then
			return
		end
		if n > last and not Settings.Reduced() then
			popScale.Scale = 1.1
			Settings.Tween(popScale, TweenInfo.new(0.25), { Scale = 1 })
		end
		last = n
		Settings.Tween(value, TweenInfo.new(0.25), { Value = n })
	end
	return { Root = root, Number = number, Set = set }
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Modal panel with a title bar. Returns { Group, Body, Open, Close }.
local modals = {}
local function modal(gui: ScreenGui, title: string, desktop: Vector2, phone: Vector2)
	local group = make("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.BgDeep,
		BorderSizePixel = 0,
		Visible = false,
		GroupTransparency = 1,
	}, gui)
	Kit.Corner(group, Theme.CornerPanel)
	Kit.Stroke(group)
	local head = Kit.Label(group, title, Theme.TextSize.Heading, Theme.Gold, true)
	head.Position = UDim2.fromOffset(16, 0)
	head.Size = UDim2.new(1, -96, 0, 56)
	head.TextXAlignment = Enum.TextXAlignment.Left
	local self: any = { Group = group, IsOpen = false }
	Kit.Button(group, {
		Text = "X",
		Size = UDim2.fromOffset(56, 44),
		Style = "Cancel",
		OnClick = function()
			self.Close()
		end,
	}).Instance.Position = UDim2.new(1, -64, 0, 6)
	local body = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 56) }, group)
	self.Body = body

	function self.Layout()
		local size = if Scale.Phone then phone else desktop
		group.Size = UDim2.fromOffset(size.X, size.Y)
		body.Size = UDim2.new(1, 0, 1, -56)
	end
	local gen = 0
	function self.Open()
		for _, m in modals do
			if m ~= self and m.IsOpen then
				m.Close()
			end
		end
		gen += 1
		self.IsOpen = true
		self.Layout()
		group.Visible = true
		group.Position = UDim2.new(0.5, 0, 0.5, 24)
		Settings.Tween(group, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
			GroupTransparency = 0,
		})
		if self.OnOpen then
			self.OnOpen()
		end
	end
	function self.Close()
		if not self.IsOpen then
			return
		end
		gen += 1
		local mine = gen
		self.IsOpen = false
		local t = Settings.Tween(group, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.5, 24),
			GroupTransparency = 1,
		})
		if t then
			t.Completed:Once(function()
				if gen == mine then
					group.Visible = false
				end
			end)
		else
			group.Visible = false
		end
	end
	self.Layout()
	table.insert(modals, self)
	return self
end

local function closeModals()
	for _, m in modals do
		m.Close()
	end
	Bus.OpenPanel:Fire("Close")
end

local function buildShop(gui: ScreenGui)
	local shop = modal(gui, "Shop", Vector2.new(900, 560), Vector2.new(640, 320))
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		BorderSizePixel = 0,
	}, shop.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local grid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 1 }, scroll)
	local gl = make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local upHead = Kit.Label(scroll, "Upgrades", Theme.TextSize.Heading, Theme.Gold, true)
	upHead.Size = UDim2.new(1, 0, 0, 32)
	upHead.LayoutOrder = 2
	upHead.TextXAlignment = Enum.TextXAlignment.Left
	local upList = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 3 }, scroll)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, upList)
	local upEmpty = Kit.Label(scroll, "Place a room in your dungeon to upgrade it.", Theme.TextSize.Body, Theme.TextMuted)
	upEmpty.Size = UDim2.new(1, 0, 0, 40)
	upEmpty.LayoutOrder = 4
	upEmpty.TextXAlignment = Enum.TextXAlignment.Left

	local cards = {}
	local order = 0
	for _, id in Rooms.Order do
		local def = Rooms.Get(id)
		local cost = Balance.Rooms[id] and Balance.Rooms[id].Cost
		if def and def.Source == "Shop" and cost then
			order += 1
			local card = Kit.Panel(grid, { BackgroundColor3 = Theme.BgPanel, LayoutOrder = order })
			pad(card, 12, 8)
			make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, card)
			local roleRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 }, card)
			hlist(roleRow, 6)
			Kit.Icon(roleRow, ROLE_ICON[def.Kind] or "Shield", UDim2.fromOffset(20, 20)).LayoutOrder = 1
			Kit.Pill(roleRow, def.Kind, Theme.BgRaised, Theme.TextPrimary, 20).LayoutOrder = 2
			local name = Kit.Label(card, def.DisplayName, Theme.TextSize.Button, Theme.TextPrimary, true)
			name.Size, name.LayoutOrder = UDim2.new(1, 0, 0, 26), 2
			name.TextXAlignment = Enum.TextXAlignment.Left
			local costRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3 }, card)
			hlist(costRow, 6)
			Kit.Icon(costRow, "Coin", UDim2.fromOffset(20, 20)).LayoutOrder = 1
			local costLabel = Kit.Label(costRow, tostring(cost), Theme.TextSize.Body, Theme.Gold, true)
			costLabel.Size, costLabel.LayoutOrder = UDim2.fromOffset(80, 22), 2
			costLabel.TextXAlignment = Enum.TextXAlignment.Left
			local owned = Kit.Label(card, "Owned: 0", 16, Theme.TextMuted)
			owned.Size, owned.LayoutOrder = UDim2.new(1, 0, 0, 20), 4
			owned.TextXAlignment = Enum.TextXAlignment.Left
			local entry = { Id = id, Cost = cost, Owned = owned, Name = name, Confirm = 0, Level = Progression.ShopLevel(id) }
			entry.Button = Kit.Button(card, {
				Text = "Buy",
				Style = "Primary",
				TextSize = 16,
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 44),
				OnClick = function()
					if entry.Confirm == 0 then
						entry.Confirm = 1
						shop.Refresh()
						task.delay(3, function()
							if entry.Confirm == 1 then
								entry.Confirm = 0
								shop.Refresh()
							end
						end)
					else
						entry.Confirm = 0
						if request("Buy", id) then
							Sound.Play("Purchase")
						end
						shop.Refresh()
					end
				end,
			})
			table.insert(cards, entry)
		end
	end

	local upRows: { [string]: any } = {}
	local upSignature = ""

	function shop.Refresh()
		gl.CellSize = if Scale.Phone then UDim2.fromOffset(180, 170) else UDim2.fromOffset(200, 220)
		local s = State.Current
		if not s then
			return
		end
		local coins = s.Coins or 0
		local level = s.Level or 1
		for _, e in cards do
			local count = 0
			for _, room in s.Rooms or {} do
				if room.Id == e.Id then
					count += 1
				end
			end
			e.Owned.Text = "Owned: " .. count
			local locked = level < e.Level
			e.Name.TextColor3 = if locked then Theme.TextMuted else Theme.TextPrimary
			e.Button.SetText(if e.Confirm == 1 then "Confirm " .. e.Cost .. "?" else "Buy")
			if locked then
				e.Confirm = 0
				e.Button.SetEnabled(false, "Unlocks at level " .. e.Level, true)
			else
				e.Button.SetEnabled(coins >= e.Cost, "Need " .. (e.Cost - coins) .. " more", true)
			end
		end

		-- Upgradable: every placed room (cost and cap depend on its rarity).
		local rows = {}
		for cellKey, instanceId in s.Layout or {} do
			local room = s.Rooms and s.Rooms[instanceId]
			local def = room and Rooms.Get(room.Id)
			if def and def.Upgradable then
				table.insert(rows, { Cell = cellKey, Id = instanceId, Def = def, Level = room.Level or 1, Rarity = room.Rarity or "Common", Perks = room.Perks })
			end
		end
		table.sort(rows, function(a, b)
			return a.Id < b.Id
		end)
		local sig = {}
		for _, r in rows do
			table.insert(sig, r.Id .. ":" .. r.Level .. ":" .. r.Rarity)
		end
		local signature = table.concat(sig, "|")
		if signature ~= upSignature then
			upSignature = signature
			for _, row in upRows do
				row.Frame:Destroy()
			end
			table.clear(upRows)
			for i, r in rows do
				local f = Kit.Panel(upList, { BackgroundColor3 = Theme.BgPanel, Size = UDim2.new(1, 0, 0, 68), LayoutOrder = i })
				local left = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -190, 1, 0) }, f)
				make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, left)
				local line1 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 }, left)
				hlist(line1, 8)
				local nm = Kit.Label(line1, r.Def.DisplayName, Theme.TextSize.Button, Theme.TextPrimary, true)
				nm.AutomaticSize, nm.Size, nm.TextWrapped, nm.LayoutOrder = X, UDim2.fromOffset(0, 24), false, 1
				Kit.Rarity(line1, r.Rarity).LayoutOrder = 2
				local nextCost = Economy.UpgradeCost(r.Level, r.Rarity)
				local line2 = Kit.Label(left, if nextCost then ("Lv %d -> %d  |  %d coins"):format(r.Level, r.Level + 1, nextCost) else ("Lv %d (max for %s)"):format(r.Level, r.Rarity), 16, Theme.TextMuted)
				line2.Size, line2.LayoutOrder = UDim2.new(1, 0, 0, 20), 2
				line2.TextXAlignment = Enum.TextXAlignment.Left
				local btn = Kit.Button(f, {
					Text = "Upgrade",
					Style = "Success",
					Icon = "Upgrade",
					IconLayout = "Row",
					TextSize = 18,
					Size = UDim2.fromOffset(170, 48),
					OnClick = function()
						if request("Upgrade", r.Id) then
							Sound.Play("Purchase")
						end
					end,
				})
				btn.Instance.AnchorPoint = Vector2.new(1, 0.5)
				btn.Instance.Position = UDim2.new(1, -8, 0.5, 0)
				upRows[r.Id] = { Frame = f, Button = btn, Cost = nextCost }
			end
		end
		upEmpty.Visible = #rows == 0
		for _, row in upRows do
			if not row.Cost then
				row.Button.SetEnabled(false, "Max")
			else
				row.Button.SetEnabled(coins >= row.Cost, "Need " .. (row.Cost - coins) .. " more")
			end
		end
	end
	shop.OnOpen = shop.Refresh
	State.Changed:Connect(function()
		if shop.IsOpen then
			shop.Refresh()
		end
	end)
	return shop
end

local function buildSettings(gui: ScreenGui)
	local panel = modal(gui, "Settings", Vector2.new(520, 420), Vector2.new(460, 300))
	local list = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, panel.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8) }, list)
	pad(list, 16)
	local function row(text: string)
		local r = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) }, list)
		local l = Kit.Label(r, text, Theme.TextSize.Body, Theme.TextPrimary)
		l.Size = UDim2.new(0, 150, 1, 0)
		l.TextXAlignment = Enum.TextXAlignment.Left
		return r
	end
	local v = Settings.Values
	local toggle = Kit.Toggle(row("Reduced motion"), v.ReducedMotion, function(on)
		Settings.Set("ReducedMotion", on)
	end)
	toggle.Instance.Position = UDim2.fromOffset(160, 6)
	local music = Kit.Slider(row("Music"), v.MusicVolume, function(x)
		Settings.Set("MusicVolume", x)
	end)
	music.Instance.Position = UDim2.fromOffset(160, 6)
	local sfx = Kit.Slider(row("Sound effects"), v.SfxVolume, function(x)
		Settings.Set("SfxVolume", x)
	end)
	sfx.Instance.Position = UDim2.fromOffset(160, 6)
	Settings.Changed:Connect(function()
		toggle.Set(Settings.Values.ReducedMotion)
		music.Set(Settings.Values.MusicVolume)
		sfx.Set(Settings.Values.SfxVolume)
	end)
	return panel
end

local function build()
	local gui = Kit.Screen("Hud", 1)

	Net.OnEvent("Notice", function(n)
		if type(n) == "table" and type(n.Text) == "string" then
			-- The box reveal card already shows this result.
			if string.sub(n.Text, 1, 10) == "You found " then
				return
			end
			Toast.Show(n.Text, n.Kind)
		end
	end)

	-- Currency pill: banked coins, vault (with bonus) once a treasure room exists.
	local currency = Kit.Panel(gui, { BackgroundColor3 = Theme.BgPanel, AutomaticSize = X })
	currency:FindFirstChildOfClass("UICorner").CornerRadius = Theme.CornerPill
	pad(currency, 16)
	hlist(currency, 12)
	local banked = cell(currency, "Coin", "Banked", 1)
	local vault = cell(currency, "Vault", "Vault", 2)
	local bonus = Kit.Pill(vault.Root, "", Theme.Gold, Theme.TextOnGold, 26)
	bonus.TextSize, bonus.LayoutOrder = 16, 3
	bonus.Size = UDim2.fromOffset(0, 26)

	-- Keeper level and XP.
	local levelPanel = Kit.Panel(gui, { BackgroundColor3 = Theme.BgPanel })
	-- The glow overlay must not sit inside the list layout, so the row is its own frame.
	local levelRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, levelPanel)
	pad(levelRow, 10)
	hlist(levelRow, 8)
	local levelPill = Kit.Pill(levelRow, "Lv 1", Theme.Gold, Theme.TextOnGold, 28)
	levelPill.TextSize, levelPill.LayoutOrder = 18, 1
	local xpBar = Kit.Bar(levelRow, UDim2.fromOffset(200, 22), Theme.Accent)
	xpBar.Instance.LayoutOrder = 2
	local levelGlow = make("Frame", { BackgroundColor3 = Theme.Gold, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Active = false }, levelPanel)
	Kit.Corner(levelGlow, Theme.CornerPanel)
	local levelPop = make("UIScale", {}, levelPanel)
	local levelStroke = levelPanel:FindFirstChildOfClass("UIStroke")

	-- Active bonuses chip.
	local bonusChip = Kit.Pill(gui, "", Theme.BgPanel, Theme.Gold, 28)
	Kit.Stroke(bonusChip, Theme.Stroke, 2)
	bonusChip.Visible = false

	-- Next visitor chip: clock, countdown, name and trait chips.
	local chip = Kit.Panel(gui, { BackgroundColor3 = Theme.BgPanel, AutomaticSize = X })
	chip:FindFirstChildOfClass("UICorner").CornerRadius = Theme.CornerPill
	pad(chip, 14)
	hlist(chip, 8)
	Kit.Icon(chip, "Clock", UDim2.fromOffset(28, 28)).LayoutOrder = 1
	local status = Kit.Label(chip, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	status.AutomaticSize, status.Size, status.TextWrapped, status.LayoutOrder = X, UDim2.fromOffset(0, 32), false, 2
	local nextName = Kit.Label(chip, "", Theme.TextSize.Body, Theme.Gold, true)
	nextName.AutomaticSize, nextName.Size, nextName.TextWrapped, nextName.LayoutOrder = X, UDim2.fromOffset(0, 32), false, 3
	local traitRow = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 24), LayoutOrder = 4 }, chip)
	hlist(traitRow, 6)
	local shownNext: string? = nil

	-- Action buttons (grid: one row on desktop, two columns on phones).
	local bar = make("Frame", { BackgroundTransparency = 1 }, gui)
	local grid = make("UIGridLayout", { SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(8, 8) }, bar)
	local buttons = {}
	local function action(key: string, icon: string, text: string, order: number, onClick: () -> ())
		local b = Kit.Button(bar, { Text = text, Icon = icon, Style = "Secondary", LayoutOrder = order, OnClick = onClick })
		buttons[key] = b
		return b
	end
	local shop, settingsPanel
	local function toggle(panel: any)
		if panel.IsOpen then
			panel.Close()
		else
			Bus.OpenPanel:Fire("Close")
			panel.Open()
		end
	end
	local bankedAt = 0
	action("Build", "Build", "Build", 1, function()
		closeModals()
		Bus.BuildRequested:Fire()
	end)
	action("Bank", "Vault", "Bank", 2, function()
		if request("Bank") then
			bankedAt = os.clock()
			Sound.Play("Bank")
		end
	end)
	action("Shop", "Shop", "Shop", 3, function()
		toggle(shop)
	end)
	action("Challenger", "Challenger", "Challenger", 4, function()
		request("InviteChallenger")
	end)
	-- Loot, Collection and Keeper panels are built by LootController (Bus "OpenPanel").
	for i, p in { { "Loot", "Vault" }, { "Collection", "Shield" }, { "Keeper", "Upgrade" } } do
		action(p[1], p[2], p[1], 4 + i, function()
			closeModals()
			Bus.OpenPanel:Fire(p[1])
		end)
	end
	action("Settings", "Settings", "Settings", 8, function()
		toggle(settingsPanel)
	end)
	for _, key in { "Build", "Bank", "Shop", "Loot", "Collection", "Keeper" } do
		Bus.Targets[key] = { Instance = buttons[key].Instance, Stroke = buttons[key].Stroke }
	end
	Bus.ShopRequested:Connect(function()
		shop.Open()
	end)

	shop = buildShop(gui)
	settingsPanel = buildSettings(gui)

	-- Encounter panel.
	local enc = Kit.Panel(gui, { Visible = false, AutomaticSize = Enum.AutomaticSize.Y })
	pad(enc, 12, 8)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, enc)
	local nameRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 1 }, enc)
	hlist(nameRow, 8)
	Kit.Icon(nameRow, "Visitor", UDim2.fromOffset(30, 30)).LayoutOrder = 1
	local encName = Kit.Label(nameRow, "", Theme.TextSize.Heading, Theme.TextPrimary, true)
	encName.Size, encName.LayoutOrder, encName.TextXAlignment, encName.TextWrapped = UDim2.new(1, -40, 1, 0), 2, Enum.TextXAlignment.Left, false
	local hp = Kit.Bar(enc, UDim2.new(1, 0, 0, 22))
	hp.Instance.LayoutOrder = 2
	local chipRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3 }, enc)
	hlist(chipRow, 6)
	local slowChip = Kit.Pill(chipRow, "Slowed", Theme.Success, Theme.DangerText, 22)
	slowChip.LayoutOrder = 1
	local sporeChip = Kit.Pill(chipRow, "Spored", Theme.Warning, Theme.DangerText, 22)
	sporeChip.LayoutOrder = 2
	local rewardRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 4 }, enc)
	hlist(rewardRow, 6)
	Kit.Icon(rewardRow, "Coin", UDim2.fromOffset(24, 24)).LayoutOrder = 1
	local encReward = Kit.Label(rewardRow, "", Theme.TextSize.Body, Theme.Gold, true)
	encReward.Size, encReward.LayoutOrder, encReward.TextXAlignment, encReward.TextWrapped = UDim2.new(1, -32, 1, 0), 2, Enum.TextXAlignment.Left, false
	local encRisk = Kit.Label(enc, "", Theme.TextSize.Body, Theme.Danger, true)
	encRisk.Size, encRisk.LayoutOrder, encRisk.TextXAlignment = UDim2.new(1, 0, 0, 24), 5, Enum.TextXAlignment.Left

	-- Blocking load failure.
	local fail = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.BgDeep, Visible = false, ZIndex = 100, Active = true }, gui)
	local failText = Kit.Label(fail, "Your progress couldn't load. Please rejoin.", Theme.TextSize.Title, Theme.TextPrimary, true)
	failText.Size = UDim2.fromScale(1, 1)
	failText.ZIndex = 101

	local plot = Plots.WaitOwn()

	local function layout()
		local phone = Scale.Phone
		local cs = if phone then 22 else Theme.TextSize.Number
		banked.Number.TextSize, vault.Number.TextSize = cs, cs
		if phone then
			currency.AnchorPoint, currency.Position, currency.Size = Vector2.new(0, 0), UDim2.new(0, 8, 0, 0), UDim2.fromOffset(0, 48)
			levelPanel.AnchorPoint, levelPanel.Position, levelPanel.Size = Vector2.new(0, 0), UDim2.new(0, 8, 0, 52), UDim2.fromOffset(300, 40)
			bonusChip.AnchorPoint, bonusChip.Position = Vector2.new(0, 0), UDim2.new(0, 8, 0, 96)
			chip.AnchorPoint, chip.Position, chip.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.fromOffset(0, 40)
			bar.AnchorPoint, bar.Position, bar.Size = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0), UDim2.fromOffset(2 * 78 + 8, 4 * 64 + 3 * 8)
			grid.CellSize, grid.FillDirection, grid.FillDirectionMaxCells, grid.StartCorner = UDim2.fromOffset(78, 64), Enum.FillDirection.Vertical, 4, Enum.StartCorner.TopRight
			enc.AnchorPoint, enc.Position, enc.Size = Vector2.new(1, 0), UDim2.new(1, -176, 0, 48), UDim2.fromOffset(260, 0)
		else
			currency.AnchorPoint, currency.Position, currency.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8), UDim2.fromOffset(0, 64)
			levelPanel.AnchorPoint, levelPanel.Position, levelPanel.Size = Vector2.new(0, 0), UDim2.new(0, 16, 0, 8), UDim2.fromOffset(320, 52)
			bonusChip.AnchorPoint, bonusChip.Position = Vector2.new(0, 0), UDim2.new(0, 16, 0, 68)
			chip.AnchorPoint, chip.Position, chip.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 80), UDim2.fromOffset(0, 44)
			bar.AnchorPoint, bar.Position, bar.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(8 * 140 + 7 * 8, 72)
			grid.CellSize, grid.FillDirection, grid.FillDirectionMaxCells, grid.StartCorner = UDim2.fromOffset(140, 72), Enum.FillDirection.Horizontal, 8, Enum.StartCorner.TopLeft
			enc.AnchorPoint, enc.Position, enc.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 96), UDim2.fromOffset(340, 0)
		end
		for _, b in buttons do
			b.Instance.TextSize = if phone then 14 else 18
		end
		encName.TextSize = if phone then 20 else Theme.TextSize.Heading
		shop.Layout()
		settingsPanel.Layout()
		if shop.IsOpen then
			shop.Refresh()
		end
	end
	Scale.Changed:Connect(layout)
	layout()

	local function refreshEncounter()
		local s = State.Current
		local visitorId = plot:GetAttribute("VisitorId")
		local show = type(visitorId) == "string" and visitorId ~= ""
		-- Hidden while a modal panel (Shop/Settings/Loot/Collection/Keeper) is open so they never overlap.
		local covered = false
		for _, m in modals do
			covered = covered or m.Group.Visible
		end
		local panels = gui.Parent and gui.Parent:FindFirstChild("Panels")
		covered = covered or (panels ~= nil and panels:IsA("ScreenGui") and panels.Enabled)
		enc.Visible = show and not covered
		if not show then
			return
		end
		local def = Visitors.Get(visitorId)
		encName.Text = def and def.DisplayName or visitorId
		local health = plot:GetAttribute("VisitorHealth") or 0
		local max = math.max(plot:GetAttribute("VisitorMaxHealth") or 1, 1)
		hp.Set(health / max, ("HP %d/%d"):format(health, max), health / max < 0.3)
		local slowed, spored = plot:GetAttribute("VisitorSlowed") == true, plot:GetAttribute("VisitorSpored") == true
		slowChip.Visible, sporeChip.Visible, chipRow.Visible = slowed, spored, slowed or spored
		local vaultGold = s and s.Vault or 0
		local hasTreasure = State.HasPlaced("TreasureRoom")
		local coinBonus = s and s.Bonuses and s.Bonuses.Coins or 0
		local extraCap = math.max(0, (s and s.VaultBonusCap or Balance.Economy.VaultBonusCap) - Balance.Economy.VaultBonusCap)
		local amount, dest = Economy.WinPayout(visitorId, vaultGold, hasTreasure, coinBonus, extraCap)
		local suffix = if coinBonus > 0 then (" (+%d%%)"):format(pct(coinBonus)) else ""
		encReward.Text = (if dest == "Vault" then "Reward: +%d to vault" else "Reward: +%d coins"):format(amount) .. suffix
		local theft = if hasTreasure then Economy.Theft(visitorId, vaultGold) else 0
		encRisk.Visible = hasTreasure
		encRisk.Text = ("! Vault risk: %d gold"):format(theft)
	end
	for _, attr in { "VisitorId", "VisitorHealth", "VisitorMaxHealth", "VisitorSlowed", "VisitorSpored" } do
		plot:GetAttributeChangedSignal(attr):Connect(refreshEncounter)
	end
	for _, m in modals do
		m.Group:GetPropertyChangedSignal("Visible"):Connect(refreshEncounter)
	end
	task.spawn(function()
		local panels = gui.Parent and gui.Parent:WaitForChild("Panels", 30)
		if panels and panels:IsA("ScreenGui") then
			panels:GetPropertyChangedSignal("Enabled"):Connect(refreshEncounter)
		end
	end)

	local lastLevel: number? = nil
	local lastCoins = 0
	local glowId = 0
	local function levelUp()
		glowId += 1
		local mine = glowId
		if Settings.Reduced() then
			levelStroke.Color = Theme.Gold
			task.delay(1.5, function()
				if glowId == mine then
					levelStroke.Color = Theme.Stroke
				end
			end)
			return
		end
		levelGlow.BackgroundTransparency, levelPop.Scale = 0.3, 1.1
		Settings.Tween(levelGlow, TweenInfo.new(0.9), { BackgroundTransparency = 1 })
		Settings.Tween(levelPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end

	local function refresh()
		local s = State.Current
		if not s then
			return
		end
		fail.Visible = s.LoadState == "Failed"
		local coins = s.Coins or 0
		banked.Set(coins)
		if coins > lastCoins and os.clock() - bankedAt > 1 and lastCoins > 0 then
			Sound.Play("CoinGain")
		end
		lastCoins = coins
		vault.Set(s.Vault or 0)
		local hasTreasure = State.HasPlaced("TreasureRoom")
		vault.Root.Visible = hasTreasure
		local vb = pct(s.VaultBonus)
		bonus.Visible = hasTreasure and vb > 0
		bonus.Text = "+" .. vb .. "%"

		local level = s.Level or 1
		levelPill.Text = "Lv " .. level
		if level >= Balance.Progression.MaxLevel then
			xpBar.Set(1, "Max level")
		else
			local need = math.max(s.XpToNext or Progression.XpToNext(level), 1)
			xpBar.Set((s.Xp or 0) / need, ("XP %d/%d"):format(s.Xp or 0, need))
		end
		if lastLevel and level > lastLevel then
			levelUp()
		end
		lastLevel = level

		local b = s.Bonuses or {}
		local parts = {}
		for _, p in { { "Coins", "coins" }, { "Loot", "loot" }, { "Xp", "XP" } } do
			if pct(b[p[1]]) > 0 then
				table.insert(parts, ("+%d%% %s"):format(pct(b[p[1]]), p[2]))
			end
		end
		bonusChip.Text = "Bonus: " .. table.concat(parts, "  ")
		bonusChip.Visible = #parts > 0 and not (s.Building and Scale.Phone)

		local boxes = s.Boxes or {}
		buttons.Loot.SetBadge((boxes.Dungeon or 0) + (boxes.Rare or 0))
		buttons.Build.SetStyle(if next(s.Layout or {}) == nil then "Success" else "Secondary")

		bar.Visible = not s.Building
		chip.Visible = not s.Building
		levelPanel.Visible = not (s.Building and Scale.Phone)
		buttons.Bank.SetEnabled((s.Vault or 0) > 0)
		if not s.ChallengerUnlocked then
			buttons.Challenger.SetEnabled(false, "Locked")
		elseif s.ChallengerQueued then
			buttons.Challenger.SetEnabled(false, "Queued")
		else
			buttons.Challenger.SetEnabled(true)
			buttons.Challenger.SetText("Challenger")
		end
		refreshEncounter()
	end
	State.Changed:Connect(refresh)
	refresh()

	-- Next visitor name and trait chips (rebuilt when the id changes).
	local function showNext(id: string?)
		if id == shownNext then
			return
		end
		shownNext = id
		for _, c in traitRow:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local def = id and Visitors.Get(id)
		nextName.Text = def and def.DisplayName or ""
		for i, t in def and def.Traits or {} do
			local info = Visitors.TraitText[t]
			if info then
				Kit.Pill(traitRow, info.Name, Theme.BgRaised, Theme.TextPrimary, 24).LayoutOrder = i
			end
		end
	end

	task.spawn(function()
		while true do
			local s = State.Current
			local text, upcoming = "", nil
			if s and s.Building then
				text = "Building: visitors paused"
			elseif plot:GetAttribute("State") == "Encounter" or (plot:GetAttribute("VisitorId") or "") ~= "" then
				text = "Visitor inside!"
			else
				local at = plot:GetAttribute("NextVisitorAt")
				text = if type(at) == "number" and at > 0 then "Next visitor in " .. formatTime(at - workspace:GetServerTimeNow()) else "Waiting for visitors"
				local id = plot:GetAttribute("NextVisitorId")
				upcoming = if type(id) == "string" and id ~= "" then id else nil
			end
			status.Text = text
			showNext(upcoming)
			task.wait(0.25)
		end
	end)
end

function Hud.Init()
	State.Start()
	Settings.Start()
end

function Hud.Start()
	task.spawn(build)
end

return Hud
