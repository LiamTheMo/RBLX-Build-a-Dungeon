-- HUD, encounter panel, shop, settings, toasts and the blocking load-failure
-- message. Presents server state only (State snapshot, Catalog, plot
-- attributes); every button is a request. Icons carry the meaning wherever one is
-- clear (coins, vault, clock, level, role); names show on hover / long-press.
local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Badges = require(Ui.Badges)
local Catalog = require(Ui.Catalog)
local DropCard = require(Ui.DropCard)
local EventBanner = require(Ui.EventBanner)
local Kit = require(Ui.Kit)
local Modal = require(Ui.Modal)
local Net = require(Ui.Net)
local Plots = require(Ui.Plots)
local ReasonText = require(Ui.ReasonText)
local Scale = require(Ui.Scale)
local Sprites = require(Ui.Sprites)
local SpriteIds = require(Ui.SpriteIds)
local IconIds = require(Ui.IconIds)
local P = require(Ui.PanelsKit)
local PanelsThreat = require(Ui.PanelsThreat)
local PanelsVault = require(Ui.PanelsVault)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)

local make = Kit.Make

local Hud = {}

local ROLE_ICON = { Defender = "Defender", Trap = "Trap", Treasure = "CoinStack", Support = "Support" }
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

-- Tap / click on a GuiObject without a child button (auto-sized chips must not hold full-size children).
local function onTap(obj: GuiObject, fn: () -> ())
	obj.Active = true
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Sound.Play("Click")
			fn()
		end
	end)
end

local function pct(x: number?): number
	return math.floor((x or 0) * 100 + 0.5)
end

-- Icon + a number that tweens (instant when reduced) and pops on gain. Name on hover.
local function cell(parent: Instance, iconName: string, tip: string, order: number)
	local root = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40), LayoutOrder = order, Active = true }, parent)
	hlist(root, 6)
	local icon = Kit.Icon(root, iconName, UDim2.fromOffset(32, 32))
	icon.LayoutOrder = 1
	local number = Kit.Label(root, "0", Theme.TextSize.Number, Theme.TextPrimary, true)
	number.AutomaticSize, number.Size, number.TextWrapped, number.TextXAlignment, number.LayoutOrder = X, UDim2.fromOffset(0, 36), false, Enum.TextXAlignment.Left, 2
	Kit.Tip(root, tip)
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
	return { Root = root, Icon = icon, Number = number, Set = set }
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function modal(gui: ScreenGui, title: string, titleIcon: string, desktop: Vector2, phone: Vector2)
	return Modal.New(gui, title, titleIcon, desktop, phone)
end

local modals = Modal.All

local function closeModals()
	for _, m in modals do
		m.Close()
	end
	Bus.OpenPanel:Fire("Close")
end

local function buildShop(gui: ScreenGui)
	local shop = modal(gui, "Shop", "Shop", Vector2.new(900, 560), Vector2.new(660, 330))
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
	}, shop.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 4) }, scroll)
	local grid = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 1 }, scroll)
	-- Four cards per row at any width: each cell is a quarter of the row minus its share of the gaps.
	local gl = make("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
	local upHead = P.IconLine(scroll, "Upgrade", "", 2, Theme.Gold)
	upHead.Size = UDim2.new(1, 0, 0, 34)
	local upList = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromScale(1, 0), LayoutOrder = 3 }, scroll)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, upList)
	upHead:FindFirstChildOfClass("TextLabel").Text = "Upgrades"
	upHead:FindFirstChildOfClass("TextLabel").TextColor3 = Theme.Gold
	upHead.Visible = false

	local cards = {}
	local order = 0
	for _, id in Catalog.Current.RoomOrder do
		local def = Catalog.Room(id)
		local cost = def and def.Cost
		if def and def.Source == "Shop" and cost then
			order += 1
			local card = Kit.Panel(grid, { BackgroundColor3 = Theme.BgPanel, LayoutOrder = order, Pad = Vector2.new(4, 2), Rarity = def.Rarity })
			make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, card)
			local art = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 0 }, card)
			local artImg = P.RoomImage(art, id, 64, def.Kind)
			artImg.AnchorPoint, artImg.Position, artImg.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
			make("UIAspectRatioConstraint", { AspectRatio = 1 }, artImg)
			local name = Kit.Label(card, def.DisplayName, 18, Theme.TextPrimary, true)
			name.Size, name.LayoutOrder, name.TextTruncate = UDim2.new(1, 0, 0, 40), 2, Enum.TextTruncate.AtEnd
			make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 18 }, name)
			name.TextScaled = true
			local costRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3 }, card)
			hlist(costRow, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
			Kit.Icon(costRow, "CoinStack", UDim2.fromOffset(22, 22)).LayoutOrder = 1
			local costLabel = Kit.Label(costRow, tostring(cost), Theme.TextSize.Body, Theme.Gold, true)
			costLabel.AutomaticSize, costLabel.Size, costLabel.TextWrapped, costLabel.LayoutOrder = X, UDim2.fromOffset(0, 24), false, 2
			-- Role icon and how many you own.
			local metaRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 4, Active = true }, card)
			hlist(metaRow, 10, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
			Kit.Icon(metaRow, ROLE_ICON[def.Kind] or "Defender", UDim2.fromOffset(22, 22)).LayoutOrder = 1
			Kit.Tip(metaRow, def.Kind .. " - owned" .. (if def.Ability and def.Ability ~= "" then "\n" .. def.Ability else ""))
			if type(def.Exchange) == "number" then
				Kit.Icon(metaRow, "Exchange", UDim2.fromOffset(22, 22)).LayoutOrder = 3
			end
			local owned = Kit.Label(metaRow, "x0", 16, Theme.TextMuted, true)
			owned.AutomaticSize, owned.Size, owned.TextWrapped, owned.LayoutOrder = X, UDim2.fromOffset(0, 24), false, 2
			local entry = { Id = id, Cost = cost, Owned = owned, Name = name, Confirm = 0, Level = def.ShopLevel, Art = art }
			entry.Button = Kit.Button(card, {
				Text = "Buy",
				Style = "Primary",
				TextSize = 18,
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
		local phone = Scale.Phone
		gl.CellSize = UDim2.new(0.25, -6, 0, if phone then 226 else 262)
		for _, e in cards do
			e.Art.Size = UDim2.new(1, 0, 0, if phone then 44 else 64)
			e.Button.SetTextSize(if phone then 16 else 18)
		end
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
			e.Owned.Text = "x" .. count
			local locked = level < e.Level
			e.Name.TextColor3 = if locked then Theme.TextMuted else Theme.TextPrimary
			e.Button.SetText(if e.Confirm == 1 then "Confirm" else "Buy")
			if locked then
				e.Confirm = 0
				e.Button.SetEnabled(false, "Lv " .. e.Level, true)
			else
				e.Button.SetEnabled(coins >= e.Cost, "Buy", true)
			end
		end

		-- Upgradable: every placed room (cost and cap depend on its rarity).
		local rows = {}
		for cellKey, instanceId in s.Layout or {} do
			local room = s.Rooms and s.Rooms[instanceId]
			local def = room and Catalog.Room(room.Id)
			if def and def.Upgradable then
				table.insert(rows, { Cell = cellKey, Id = instanceId, Def = def, Level = room.Level or 1, Rarity = room.Rarity or "Common", Perks = room.Perks, NextCost = room.NextUpgradeCost })
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
				local f = Kit.Panel(upList, { BackgroundColor3 = Theme.BgPanel, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = i, Rarity = r.Rarity, Pad = Vector2.new(8, 0) })
				local roomImg = P.RoomImage(f, r.Def.Id, 52, r.Def.Kind)
				roomImg.AnchorPoint, roomImg.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
				local left = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 0), Size = UDim2.new(1, -(64 + 156), 1, 0) }, f)
				make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, left)
				local line1 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 }, left)
				hlist(line1, 8)
				local nm = Kit.Label(line1, r.Def.DisplayName, Theme.TextSize.Button, Theme.TextPrimary, true)
				nm.AutomaticSize, nm.Size, nm.TextWrapped, nm.LayoutOrder = X, UDim2.fromOffset(0, 26), false, 1
				Kit.Gem(line1, r.Rarity, UDim2.fromOffset(22, 22)).LayoutOrder = 2
				Kit.Rarity(line1, r.Rarity).LayoutOrder = 3
				-- Level line: "Lv 2" arrow "3" (or "Lv 4 | Max").
				local nextCost = r.NextCost -- server-computed (nil at the rarity's max level)
				local line2 = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2 }, left)
				hlist(line2, 6)
				local lv = Kit.Label(line2, "Lv " .. r.Level, 16, Theme.TextMuted, true)
				lv.AutomaticSize, lv.Size, lv.TextWrapped, lv.LayoutOrder = X, UDim2.fromOffset(0, 22), false, 1
				if nextCost then
					Kit.Icon(line2, "Upgrade", UDim2.fromOffset(18, 18)).LayoutOrder = 2
					local nl = Kit.Label(line2, tostring(r.Level + 1), 16, Theme.Success, true)
					nl.AutomaticSize, nl.Size, nl.TextWrapped, nl.LayoutOrder = X, UDim2.fromOffset(0, 22), false, 3
				end
				local btn = Kit.Button(f, {
					Text = if nextCost then tostring(nextCost) else "Max",
					Style = "Success",
					Icon = if nextCost then "CoinStack" else nil,
					IconLayout = "Row",
					TextSize = 20,
					Size = UDim2.fromOffset(148, 52),
					Tip = "Upgrade",
					OnClick = function()
						if request("Upgrade", r.Id) then
							Sound.Play("Purchase")
						end
					end,
				})
				btn.Instance.AnchorPoint = Vector2.new(1, 0.5)
				btn.Instance.Position = UDim2.new(1, 0, 0.5, 0)
				upRows[r.Id] = { Frame = f, Button = btn, Cost = nextCost }
			end
		end
		upHead.Visible = #rows > 0
		for _, row in upRows do
			if not row.Cost then
				row.Button.SetEnabled(false, "Max")
			else
				row.Button.SetEnabled(coins >= row.Cost)
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
	local panel = modal(gui, "Settings", "Settings", Vector2.new(580, 360), Vector2.new(560, 300))
	local list = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, panel.Body)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	pad(list, 6, 4)
	-- Icon at the left, the control filling the rest of the row.
	local function row(icon: string, tip: string, order: number): Frame
		local r = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = order }, list)
		local ic = Kit.Icon(r, icon, UDim2.fromOffset(36, 36))
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
		local holder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -52, 1, 0), Active = true }, r)
		Kit.Tip(r, tip)
		return holder
	end
	local v = Settings.Values
	local motion = row("ReducedMotion", "Reduced motion", 1)
	local ml = Kit.Label(motion, "Reduced motion", Theme.TextSize.Body, Theme.TextPrimary)
	ml.Size, ml.TextXAlignment = UDim2.new(1, -110, 1, 0), Enum.TextXAlignment.Left
	local toggle = Kit.Toggle(motion, v.ReducedMotion, function(on)
		Settings.Set("ReducedMotion", on)
	end)
	toggle.Instance.AnchorPoint, toggle.Instance.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)
	local music = Kit.Slider(row("Music", "Music", 2), v.MusicVolume, function(x)
		Settings.Set("MusicVolume", x)
	end)
	music.Instance.AnchorPoint, music.Instance.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
	local sfx = Kit.Slider(row("SoundOn", "Sound effects", 3), v.SfxVolume, function(x)
		Settings.Set("SfxVolume", x)
	end)
	sfx.Instance.AnchorPoint, sfx.Instance.Position = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0)
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
			if State.IsHeld() then -- a box is opening: show it after the reveal
				local c
				c = State.Released:Connect(function()
					c:Disconnect()
					Toast.Show(n.Text, n.Kind)
				end)
				return
			end
			Toast.Show(n.Text, n.Kind)
		end
	end)

	-- Currency pill: coins, and the vault (with bonus) once a treasure room exists.
	local currency = Kit.Panel(gui, { Sprite = "Pill", AutomaticSize = X })
	-- Pills hold one row frame (their dark face is a child too, so no layout sits on the pill itself).
	local function pillRow(pill: Instance, padding: number, gap: number): Frame
		local r = make("Frame", { Name = "Row", BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromScale(0, 1) }, pill)
		pad(r, padding)
		hlist(r, gap)
		return r
	end
	local currencyRow = pillRow(currency, 26, 14)
	local banked = cell(currencyRow, "Coin", "Coins", 1)
	local vault = cell(currencyRow, "Vault", "Vault", 2)
	-- The vault share (%) as a gold pill; the whole chip opens the vault slider.
	local bonus = Kit.Pill(vault.Root, "", Theme.Gold, Theme.TextOnGold, 26)
	Kit.PillLabel(bonus).TextSize, bonus.LayoutOrder = 16, 3
	bonus.Size = UDim2.fromOffset(0, 26)
	-- Keep the tutorial ring out of the auto-sized currency row.
	local vaultRing = Kit.Ring(gui, 6)
	local function positionVaultRing()
		local scale = math.max(Scale.Value, 0.01)
		local pos = (vault.Root.AbsolutePosition - gui.AbsolutePosition) / scale
		local size = vault.Root.AbsoluteSize / scale
		vaultRing.Position = UDim2.fromOffset(pos.X - 6, pos.Y - 6)
		vaultRing.Size = UDim2.fromOffset(size.X + 12, size.Y + 12)
	end
	vault.Root:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionVaultRing)
	vault.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionVaultRing)
	Scale.Changed:Connect(positionVaultRing)

	-- Keeper level and XP.
	local levelPanel = Kit.Panel(gui, { Sprite = "Pill" })
	local levelRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, levelPanel)
	pad(levelRow, 16, 6)
	hlist(levelRow, 8)
	local levelIcon = Kit.Icon(levelRow, "Level", UDim2.fromOffset(30, 30))
	levelIcon.LayoutOrder = 0
	local levelPill = Kit.Pill(levelRow, "Lv 1", Theme.Gold, Theme.TextOnGold, 28)
	Kit.PillLabel(levelPill).TextSize, levelPill.LayoutOrder = 18, 1
	local xpBar = Kit.Bar(levelRow, UDim2.fromOffset(170, 28))
	xpBar.Instance.LayoutOrder = 2
	local levelGlow = Kit.Glow(levelPanel, Theme.Gold, 1)
	levelGlow.Size, levelGlow.ZIndex = UDim2.new(1.4, 0, 3, 0), 10
	local levelPop = make("UIScale", {}, levelPanel)
	local levelRing = Kit.Ring(levelPanel, 6)
	-- Level-up (and reduced-motion) mark: the highlight ring shows.
	local function levelMark(on: boolean)
		levelRing.Visible = on
	end
	-- Level-up banner (Feedback.LevelUpBanner) with its glow, shown briefly top-centre.
	local lvlBanner = make("Frame", { Name = "LevelUp", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(300, 98), Visible = false, ZIndex = 30 }, gui)
	local lvlGlow = Kit.Glow(lvlBanner, Theme.Gold, 0.35)
	lvlGlow.Size, lvlGlow.ZIndex = UDim2.new(2, 0, 3, 0), 30
	local lvlArt = Kit.Sprite(lvlBanner, "Feedback.LevelUpBanner", { Size = UDim2.fromScale(1, 1), ZIndex = 31 })
	local lvlText = Kit.Label(lvlBanner, "LEVEL UP!", 28, Theme.TextOnGold, true)
	lvlText.Size, lvlText.ZIndex, lvlText.TextWrapped = UDim2.new(0.68, 0, 1, -14), 32, false
	lvlText.AnchorPoint, lvlText.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	lvlText.TextScaled = true
	make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 30 }, lvlText)
	local lvlScale = make("UIScale", {}, lvlBanner)
	local lvlId = 0

	-- Under the level pill: the next goal chip, then the active bonuses.
	local leftStack = make("Frame", { Name = "LeftStack", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, leftStack)
	local goal = Kit.Panel(leftStack, { Sprite = "Pill", AutomaticSize = X, Size = UDim2.fromOffset(0, 34), LayoutOrder = 1, Active = true, Visible = false })
	local goalRow = pillRow(goal, 12, 6)
	Kit.Icon(goalRow, "Flag", UDim2.fromOffset(24, 24)).LayoutOrder = 1
	local goalArt = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), LayoutOrder = 2 }, goalRow)
	local goalText = Kit.Label(goalRow, "", 16, Theme.TextPrimary, true)
	goalText.AutomaticSize, goalText.Size, goalText.TextWrapped, goalText.LayoutOrder = X, UDim2.fromOffset(0, 26), false, 3
	local goalKind, goalSig = "", ""
	Kit.Tip(goal, "Next goal")
	-- Active bonuses: one small chip per bonus (icon + percent).
	local bonusRow = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 32), Visible = false, LayoutOrder = 2 }, leftStack)
	hlist(bonusRow, 6)
	local bonusSig = ""

	-- Settings gear: small, top-left under the Roblox menu buttons.
	local gear = Kit.Button(gui, { Text = "", Icon = "Gear", IconScale = 0.7, Style = "Secondary", Round = true, Size = UDim2.fromOffset(52, 52), Tip = "Settings", Shadow = true })

	-- Next visitor chip: clock + countdown, portrait and trait icons.
	local chipBar = make("Frame", { Name = "ChipBar", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, gui)
	hlist(chipBar, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	local chip = Kit.Panel(chipBar, { Sprite = "Pill", AutomaticSize = X, LayoutOrder = 1 })
	local chipRowF = pillRow(chip, 22, 8)
	local chipIcon = Kit.Icon(chipRowF, "Clock", UDim2.fromOffset(28, 28))
	chipIcon.LayoutOrder = 1
	local status = Kit.Label(chipRowF, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	status.AutomaticSize, status.Size, status.TextWrapped, status.LayoutOrder = X, UDim2.fromOffset(0, 32), false, 2
	local nextPortrait = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(36, 36), ScaleType = Enum.ScaleType.Fit, Visible = false, LayoutOrder = 3, Image = "", Active = true }, chipRowF)
	local nextName = ""
	Kit.Tip(nextPortrait, function()
		return nextName
	end)
	local traitRow = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 5 }, chipRowF)
	hlist(traitRow, 6)
	local shownNext: string? = nil
	local nextInfoId: string? = nil
	local threatButton = Kit.Button(chipBar, { Text = "", Icon = "T1", IconScale = 0.82, Style = "Secondary", Round = true, Size = UDim2.fromOffset(46, 46), LayoutOrder = 2, Tip = "Threat" })
	local infoButton = Kit.Button(chipBar, { Text = "", Icon = "DropChance", IconScale = 0.6, Style = "Secondary", Round = true, Size = UDim2.fromOffset(46, 46), LayoutOrder = 3, Tip = "Drops" })

	-- Bottom bar: three big icon buttons.
	local bar = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(0.5, 1) }, gui)
	hlist(bar, 14, { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom })
	local buttons = {}
	local function action(key: string, icon: string, text: string, style: string, order: number, onClick: () -> ())
		local b = Kit.Button(bar, { Text = text, Icon = icon, IconScale = 0.58, Style = style, LayoutOrder = order, Shadow = true, Tip = text, OnClick = onClick })
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
	action("Build", "Build", "Build", "Primary", 1, function()
		closeModals()
		Bus.BuildRequested:Fire()
	end)
	action("Shop", "Shop", "Shop", "Secondary", 2, function()
		toggle(shop)
	end)
	-- The Bag opens the tabbed Loot / Collection / Keeper panel (built by LootController, Bus "OpenPanel").
	action("Bag", "Bag", "Bag", "Secondary", 3, function()
		closeModals()
		Bus.OpenPanel:Fire("Loot")
	end)
	gear.Instance.Activated:Connect(function()
		toggle(settingsPanel)
	end)
	for _, key in { "Build", "Shop" } do
		Bus.Targets[key] = { Instance = buttons[key].Instance, Stroke = buttons[key].Stroke, Button = buttons[key] }
	end
	for _, key in { "Loot", "Collection", "Keeper" } do
		Bus.Targets[key] = { Instance = buttons.Bag.Instance, Stroke = buttons.Bag.Stroke, Button = buttons.Bag }
	end
	Bus.ShopRequested:Connect(function()
		shop.Open()
	end)

	shop = buildShop(gui)
	settingsPanel = buildSettings(gui)

	-- Threat picker, vault slider and drop card popups (bodies in Ui/PanelsThreat, PanelsVault, DropCard).
	local threatModal = modal(gui, "Threat", "T1", Vector2.new(760, 430), Vector2.new(660, 330))
	local threatPanel = PanelsThreat.Build(threatModal.Body)
	threatModal.OnOpen = threatPanel.Refresh
	local vaultModal = modal(gui, "Vault", "Vault", Vector2.new(700, 340), Vector2.new(640, 300))
	local vaultPanel = PanelsVault.Build(vaultModal.Body)
	vaultModal.OnOpen = vaultPanel.Refresh
	Bus.VaultRequested:Connect(function()
		if State.HasPlacedKind("Treasure") then
			Bus.OpenPanel:Fire("Close")
			vaultModal.Open()
		end
	end)
	local dropModal = modal(gui, "Drops", "DropChance", Vector2.new(640, 520), Vector2.new(620, 330))
	local dropScroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
	}, dropModal.Body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, dropScroll)
	make("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 4) }, dropScroll)
	local dropId: string? = nil
	local function fillDrops()
		for _, c in dropScroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local def = dropId and Catalog.Visitor(dropId)
		dropModal.Title.Text = def and def.DisplayName or "Drops"
		if dropId and State.Current then
			DropCard.Fill(dropScroll, dropId, State.Current, true)
		end
	end
	dropModal.OnOpen = fillDrops
	local function showDrops(visitorId: any)
		if type(visitorId) ~= "string" or visitorId == "" then
			return
		end
		if dropModal.IsOpen and dropId == visitorId then
			dropModal.Close()
			return
		end
		dropId = visitorId
		Bus.OpenPanel:Fire("Close")
		dropModal.Open()
	end
	State.Changed:Connect(function()
		if dropModal.IsOpen then
			fillDrops()
		end
	end)
	threatButton.Instance.Activated:Connect(function()
		toggle(threatModal)
	end)
	infoButton.Instance.Activated:Connect(function()
		showDrops(nextInfoId)
	end)
	onTap(vault.Root, function()
		toggle(vaultModal)
	end)
	Bus.Targets.Vault = {
		Instance = vault.Root,
		Button = {
			SetHighlight = function(t: number?)
				vaultRing.Visible = t ~= nil
				if t ~= nil then positionVaultRing() end
			end,
		},
	}
	EventBanner.Start()

	-- Encounter panel.
	local enc = Kit.Panel(gui, { Visible = false, AutomaticSize = Enum.AutomaticSize.Y, Pad = Vector2.new(6, 4) })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, enc)
	local nameRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1 }, enc)
	hlist(nameRow, 10)
	-- Tags: threat tier shield and the rare-variant nameplate, with the drop-table button at the right.
	local tagRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2 }, enc)
	local tagLeft = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40) }, tagRow)
	hlist(tagLeft, 8)
	local encTier = Kit.Icon(tagLeft, "T1", UDim2.fromOffset(36, 36))
	encTier.LayoutOrder = 1
	local encVariantHolder = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2 }, tagLeft)
	hlist(encVariantHolder, 0)
	local encInfo = Kit.Button(tagRow, { Text = "", Icon = "DropChance", IconScale = 0.7, Style = "Secondary", Round = true, Size = UDim2.fromOffset(44, 44), Tip = "Drops" })
	encInfo.Instance.AnchorPoint, encInfo.Instance.Position = Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0)
	local shownVariant = ""
	local portrait = make("ImageLabel", { BackgroundTransparency = 1, Image = IconIds.Visitor, Size = UDim2.fromOffset(52, 52), ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, nameRow)
	local encName = Kit.Label(nameRow, "", Theme.TextSize.Heading, Theme.TextPrimary, true)
	encName.Size, encName.LayoutOrder, encName.TextXAlignment, encName.TextWrapped = UDim2.new(1, -62, 1, 0), 2, Enum.TextXAlignment.Left, false
	make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = 30 }, encName)
	encName.TextScaled = true
	-- Health: heart + bar with "5/70" centred, coloured by remaining health.
	local hpRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3 }, enc)
	hlist(hpRow, 8)
	Kit.Icon(hpRow, "Heal", UDim2.fromOffset(28, 28)).LayoutOrder = 1
	local hp = Kit.Bar(hpRow, UDim2.new(1, -36, 0, 28), Theme.Success)
	hp.Instance.LayoutOrder = 2
	local chipRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 4 }, enc)
	hlist(chipRow, 6)
	local slowChip = Kit.Icon(chipRow, "Slow", UDim2.fromOffset(24, 24))
	slowChip.LayoutOrder = 1
	slowChip.Active = true
	Kit.Tip(slowChip, "Slowed")
	local sporeChip = Kit.Icon(chipRow, "Spores", UDim2.fromOffset(24, 24))
	sporeChip.LayoutOrder = 2
	local rewardRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 5, Active = true }, enc)
	hlist(rewardRow, 6)
	local rewardIcon = Kit.Icon(rewardRow, "CoinRange", UDim2.fromOffset(26, 26))
	rewardIcon.LayoutOrder = 1
	local encReward = Kit.Label(rewardRow, "", Theme.TextSize.Body, Theme.Gold, true)
	encReward.AutomaticSize, encReward.Size, encReward.LayoutOrder, encReward.TextWrapped = X, UDim2.fromOffset(0, 28), 2, false
	Kit.Tip(rewardRow, "Reward")
	local riskRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 6, Active = true }, enc)
	hlist(riskRow, 6)
	Kit.Icon(riskRow, "Thief", UDim2.fromOffset(26, 26)).LayoutOrder = 1
	local encRisk = Kit.Label(riskRow, "", Theme.TextSize.Body, Theme.Danger, true)
	encRisk.AutomaticSize, encRisk.Size, encRisk.LayoutOrder, encRisk.TextWrapped = X, UDim2.fromOffset(0, 26), 2, false
	Kit.Tip(riskRow, "Stolen if it reaches the vault")

	-- Blocking load failure.
	local fail = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 100, Active = true }, gui)
	Kit.Sprite(fail, "Feedback.Scrim", { Position = UDim2.fromOffset(-400, -400), Size = UDim2.new(1, 800, 1, 800), ImageTransparency = 0, ScaleType = Enum.ScaleType.Stretch, ZIndex = 100 })
	Kit.Sprite(fail, "Feedback.Scrim", { Position = UDim2.fromOffset(-400, -400), Size = UDim2.new(1, 800, 1, 800), ImageTransparency = 0, ScaleType = Enum.ScaleType.Stretch, ZIndex = 100 })
	local failPanel = Kit.Panel(fail, { Sprite = "LoadFail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 260), ZIndex = 101 })
	local failIcon = Kit.Icon(failPanel, "Warn", UDim2.fromOffset(64, 64))
	failIcon.AnchorPoint, failIcon.Position, failIcon.ZIndex = Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), 102
	local failText = Kit.Label(failPanel, "Your progress could not load. Please rejoin.", Theme.TextSize.Heading, Theme.TextPrimary, true)
	failText.Position, failText.Size, failText.ZIndex = UDim2.fromOffset(0, 72), UDim2.new(1, 0, 1, -72), 102

	local plot = Plots.WaitOwn()

	local function layout()
		local phone = Scale.Phone
		local cs = if phone then 22 else Theme.TextSize.Number
		levelIcon.Visible = not phone
		banked.Number.TextSize, vault.Number.TextSize = cs, cs
		for _, c in { banked, vault } do
			c.Icon.Size = UDim2.fromOffset(if phone then 26 else 32, if phone then 26 else 32)
		end
		if phone then
			gear.Instance.AnchorPoint, gear.Instance.Position, gear.Instance.Size = Vector2.new(0, 0), UDim2.fromOffset(8, 4), UDim2.fromOffset(46, 46)
			levelPanel.AnchorPoint, levelPanel.Position, levelPanel.Size = Vector2.new(0, 0), UDim2.fromOffset(62, 4), UDim2.fromOffset(262, 46)
			xpBar.Instance.Size = UDim2.fromOffset(158, 24)
			leftStack.AnchorPoint, leftStack.Position = Vector2.new(0, 0), UDim2.fromOffset(62, 54)
			currency.AnchorPoint, currency.Position, currency.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 4), UDim2.fromOffset(0, 46)
			chipBar.AnchorPoint, chipBar.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 54)
			chip.Size = UDim2.fromOffset(0, 38)
			threatButton.Instance.Size, infoButton.Instance.Size = UDim2.fromOffset(44, 44), UDim2.fromOffset(44, 44)
			bar.Position = UDim2.new(0.5, 0, 1, -8)
			enc.AnchorPoint, enc.Position, enc.Size = Vector2.new(1, 0), UDim2.new(1, -8, 0, 52), UDim2.fromOffset(250, 0)
		else
			gear.Instance.AnchorPoint, gear.Instance.Position, gear.Instance.Size = Vector2.new(0, 0), UDim2.fromOffset(16, 8), UDim2.fromOffset(52, 52)
			levelPanel.AnchorPoint, levelPanel.Position, levelPanel.Size = Vector2.new(0, 0), UDim2.fromOffset(78, 6), UDim2.fromOffset(340, 58)
			xpBar.Instance.Size = UDim2.fromOffset(170, 28)
			leftStack.AnchorPoint, leftStack.Position = Vector2.new(0, 0), UDim2.fromOffset(78, 72)
			currency.AnchorPoint, currency.Position, currency.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(0, 64)
			chipBar.AnchorPoint, chipBar.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 78)
			chip.Size = UDim2.fromOffset(0, 46)
			threatButton.Instance.Size, infoButton.Instance.Size = UDim2.fromOffset(46, 46), UDim2.fromOffset(46, 46)
			bar.Position = UDim2.new(0.5, 0, 1, -16)
			enc.AnchorPoint, enc.Position, enc.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 96), UDim2.fromOffset(340, 0)
		end
		for key, b in buttons do
			local big = key == "Build"
			b.Instance.Size = if phone then UDim2.fromOffset(if big then 112 else 88, 76) else UDim2.fromOffset(if big then 140 else 112, 108)
			b.SetTextSize(if phone then 13 else 16)
		end
		encName.TextSize = if phone then 20 else Theme.TextSize.Heading
		shop.Layout()
		settingsPanel.Layout()
		threatModal.Layout()
		threatPanel.Layout()
		vaultModal.Layout()
		vaultPanel.Layout()
		dropModal.Layout()
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
		local def = Catalog.Visitor(visitorId)
		encName.Text = def and def.DisplayName or visitorId
		local pid = SpriteIds.Portraits[visitorId]
		portrait.Image = if Sprites.Ok(pid) then pid else IconIds.Visitor
		local health = plot:GetAttribute("VisitorHealth") or 0
		local max = math.max(plot:GetAttribute("VisitorMaxHealth") or 1, 1)
		local frac = math.clamp(health / max, 0, 1)
		hp.Set(frac, ("%d/%d"):format(health, max), if frac > 0.6 then Theme.Success elseif frac > 0.3 then Theme.Warning else Theme.Danger)
		local slowed, spored = plot:GetAttribute("VisitorSlowed") == true, plot:GetAttribute("VisitorSpored") == true
		slowChip.Visible, sporeChip.Visible, chipRow.Visible = slowed, spored, slowed or spored
		-- The coin range and theft are computed by the server (plot attributes, refreshed each step); the
		-- actual payout only appears in the End effect.
		local hasTreasure = State.HasPlacedKind("Treasure")
		encReward.Text = Badges.Range({ Min = plot:GetAttribute("VisitorRewardMin") or 0, Max = plot:GetAttribute("VisitorRewardMax") or 0 })
		local theft = plot:GetAttribute("VisitorTheft") or 0
		riskRow.Visible = hasTreasure and theft > 0
		encRisk.Text = "-" .. Badges.Comma(theft)
		-- Tier shield (hidden at T1) and the rare-variant nameplate.
		local tier = plot:GetAttribute("Threat")
		tier = if type(tier) == "number" then tier else 1
		encTier.Visible = tier > 1
		if encTier:IsA("ImageLabel") then
			encTier.Image = Kit.Sprites3["T" .. math.clamp(tier, 1, 6)] or ""
		end
		local variant = plot:GetAttribute("VisitorVariant")
		variant = if type(variant) == "string" then variant else ""
		if variant ~= shownVariant then
			shownVariant = variant
			for _, c in encVariantHolder:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			if variant ~= "" then
				Badges.Variant(encVariantHolder, variant, 36)
			end
		end
	end
	encInfo.Instance.Activated:Connect(function()
		showDrops(plot:GetAttribute("VisitorId"))
	end)
	for _, attr in { "VisitorId", "VisitorHealth", "VisitorMaxHealth", "VisitorSlowed", "VisitorSpored", "VisitorRewardMin", "VisitorRewardMax", "VisitorVariant", "Threat", "VisitorTheft" } do
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
	local function levelUp(level: number)
		glowId += 1
		local mine = glowId
		lvlId += 1
		local bid = lvlId
		lvlText.Text = "LEVEL UP! " .. level
		lvlBanner.Visible = true
		lvlScale.Scale = if Settings.Reduced() then 1 else 0.6
		Settings.Tween(lvlScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		task.delay(2.4, function()
			if lvlId == bid then
				lvlBanner.Visible = false
			end
		end)
		if Settings.Reduced() then
			levelMark(true)
			task.delay(1.5, function()
				if glowId == mine then
					levelMark(false)
				end
			end)
			return
		end
		levelGlow.ImageTransparency, levelPop.Scale = 0.3, 1.1
		Settings.Tween(levelGlow, TweenInfo.new(0.9), { ImageTransparency = 1 })
		Settings.Tween(levelPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end

	local BONUS_ICON = { { "Coins", "Coin", "Coins" }, { "Loot", "Loot", "Loot chance" }, { "Xp", "Xp", "XP" } }
	local function refresh()
		local s = State.Current
		if not s then
			return
		end
		fail.Visible = s.LoadState == "Failed"
		local coins = s.Coins or 0
		banked.Set(coins)
		if coins > lastCoins and lastCoins > 0 then
			Sound.Play("CoinGain")
		end
		lastCoins = coins
		vault.Set(s.Vaulted or 0)
		local hasTreasure = State.HasPlacedKind("Treasure")
		vault.Root.Visible = hasTreasure
		local share = s.VaultPercent or 0
		bonus.Visible = hasTreasure
		Kit.SetText(bonus, share .. "%")

		-- Threat button: the tier visitors use now. Hidden until the tutorial is done.
		local tier = s.ThreatActive or s.Threat or 1
		threatButton.Instance.Visible = s.Tutorial ~= nil and s.Tutorial.Done == true
		if threatButton.Icon and threatButton.Icon:IsA("ImageLabel") then
			threatButton.Icon.Image = Kit.Sprites3["T" .. math.clamp(tier, 1, 6)] or ""
		end

		-- Next goal: an affordable permanent upgrade, else the nearest threat tier or shop room.
		local nu = s.NextUnlocks or {}
		local kind, sig, level
		if nu.Permanent and nu.Permanent.Affordable then
			kind, sig = "Perm", "Perm:" .. tostring(nu.Permanent.Id)
		else
			local t, r = nu.Threat, nu.ShopRoom
			if t and (not r or t.Level <= r.Level) then
				kind, sig, level = "Threat", "T" .. t.Tier, t.Level
			elseif r then
				kind, sig, level = "Room", "R" .. r.RoomId, r.Level
			end
		end
		goal.Visible = kind ~= nil
		goalKind = kind or ""
		if kind and sig .. ":" .. tostring(level) ~= goalSig then
			goalSig = sig .. ":" .. tostring(level)
			for _, c in goalArt:GetChildren() do
				c:Destroy()
			end
			local art: any
			if kind == "Perm" then
				art = Kit.Icon(goalArt, "Upgrade", UDim2.fromOffset(28, 28))
				goalText.Text = "!"
				goalText.TextColor3 = Theme.Gold
			elseif kind == "Threat" then
				art = Badges.Tier(goalArt, nu.Threat.Tier, UDim2.fromOffset(28, 28))
				goalText.Text = "Lv " .. level
				goalText.TextColor3 = Theme.TextPrimary
			else
				local def = Catalog.Room(nu.ShopRoom.RoomId)
				art = P.RoomImage(goalArt, nu.ShopRoom.RoomId, 28, def and def.Kind)
				goalText.Text = "Lv " .. level
				goalText.TextColor3 = Theme.TextPrimary
			end
			art.Size = UDim2.fromScale(1, 1)
		end

		local level = s.Level or 1
		Kit.SetText(levelPill, "Lv " .. level)
		if level >= Catalog.Current.MaxKeeperLevel then
			xpBar.Set(1, "MAX")
		else
			local need = math.max(s.XpToNext or 1, 1)
			xpBar.Set((s.Xp or 0) / need, ("%d/%d"):format(s.Xp or 0, need))
		end
		if lastLevel and level > lastLevel then
			levelUp(level)
		end
		lastLevel = level

		-- Bonus chips (rebuilt only when the values change).
		local b = s.Bonuses or {}
		local sigParts = {}
		for _, e in BONUS_ICON do
			table.insert(sigParts, pct(b[e[1]]))
		end
		local sig = table.concat(sigParts, ",")
		if sig ~= bonusSig then
			bonusSig = sig
			for _, c in bonusRow:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			for i, e in BONUS_ICON do
				local v = pct(b[e[1]])
				if v > 0 then
					local c = Kit.Panel(bonusRow, { Sprite = "Pill", AutomaticSize = X, Size = UDim2.fromOffset(0, 32), LayoutOrder = i, Active = true })
					local cr = pillRow(c, 12, 4)
					Kit.Icon(cr, e[2], UDim2.fromOffset(20, 20)).LayoutOrder = 1
					local l = Kit.Label(cr, "+" .. v .. "%", 15, Theme.TextPrimary, true)
					l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 24), false, 2
					Kit.Tip(c, e[3])
				end
			end
		end
		bonusRow.Visible = bonusSig ~= "0,0,0" and not (s.Building and Scale.Phone)

		local boxes = s.Boxes or {}
		buttons.Bag.SetBadge((boxes.Dungeon or 0) + (boxes.Rare or 0))
		buttons.Build.SetStyle(if next(s.Layout or {}) == nil then "Success" else "Primary")

		bar.Visible = not s.Building
		gear.Instance.Visible = not s.Building
		chipBar.Visible = not s.Building
		goal.Visible = goal.Visible and not s.Building
		levelPanel.Visible = not (s.Building and Scale.Phone)
		refreshEncounter()
	end
	State.Changed:Connect(refresh)
	refresh()
	onTap(goal, function()
		if goalKind == "Perm" then
			Bus.OpenPanel:Fire("Keeper")
		elseif goalKind == "Room" then
			toggle(shop)
		elseif goalKind == "Threat" then
			toggle(threatModal)
		end
	end)

	-- Next visitor: portrait and trait icons (rebuilt when the id changes).
	local function showNext(id: string?)
		if id == shownNext then
			return
		end
		shownNext = id
		for _, c in traitRow:GetChildren() do
			if c:IsA("TextLabel") or c:IsA("Frame") or c:IsA("ImageLabel") then
				c:Destroy()
			end
		end
		local def = id and Catalog.Visitor(id)
		nextName = def and def.DisplayName or ""
		local pid = id and SpriteIds.Portraits[id]
		nextPortrait.Visible = Sprites.Ok(pid)
		nextPortrait.Image = if nextPortrait.Visible then pid else ""
		for i, info in def and def.Traits or {} do
			if info.Id == "Mender" or info.Id == "SureFooted" then
				local ic = Kit.Icon(traitRow, if info.Id == "Mender" then "Heal" else "SureFooted", UDim2.fromOffset(26, 26))
				ic.LayoutOrder = i
				ic.Active = true
				Kit.Tip(ic, info.Name)
			else
				Kit.Pill(traitRow, info.Name, Theme.BgRaised, Theme.TextPrimary, 24).LayoutOrder = i
			end
		end
	end

	task.spawn(function()
		while true do
			local s = State.Current
			local text, upcoming, icon = "", nil, IconIds.Clock
			if s and s.Building then
				text = ""
			elseif plot:GetAttribute("State") == "Encounter" or (plot:GetAttribute("VisitorId") or "") ~= "" then
				text, icon = "", IconIds.Sword -- a visitor is inside: crossed swords instead of the countdown
			else
				local at = plot:GetAttribute("NextVisitorAt")
				text = if type(at) == "number" and at > 0 then formatTime(at - workspace:GetServerTimeNow()) else "-:--"
				local id = plot:GetAttribute("NextVisitorId")
				upcoming = if type(id) == "string" and id ~= "" then id else nil
			end
			status.Text = text
			status.Visible = text ~= ""
			if chipIcon:IsA("ImageLabel") and icon ~= IconIds.Clock then
				chipIcon.Image = icon
			elseif chipIcon:IsA("ImageLabel") then
				chipIcon.Image = (SpriteIds.Icons :: any).Clock or IconIds.Clock
			end
			showNext(upcoming)
			infoButton.Instance.Visible = upcoming ~= nil
			nextInfoId = upcoming
			task.wait(0.25)
		end
	end)
end

function Hud.Init()
	State.Start()
	Settings.Start()
end

function Hud.Start()
	-- Loading spinner (Feedback.LoadingSpinner) until the catalog and the first State snapshot are here.
	local spinGui = Kit.Screen("Loading", 90)
	local spin = Kit.Sprite(spinGui, "Feedback.LoadingSpinner", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(72, 72) })
	local spinConn = game:GetService("RunService").RenderStepped:Connect(function(dt)
		spin.Rotation = (spin.Rotation + dt * 360) % 360
	end)
	task.spawn(function()
		Catalog.Wait() -- open to every player, so the load-failure screen still appears
		build()
		local t0 = os.clock()
		while not State.Current and os.clock() - t0 < 15 do
			task.wait(0.1)
		end
		spinConn:Disconnect()
		spinGui:Destroy()
	end)
end

return Hud
