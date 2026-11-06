-- Threat picker body: six tier cards (lock + "Lv N" when locked, ring + check when selected), the
-- multiplier chips of the focused tier and the next tier to unlock. Display and requests only: SetThreat
-- is validated by the server (ThreatLocked / EncounterActive come back as reason toasts).
local Badges = require(script.Parent.Badges)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local ReasonText = require(script.Parent.ReasonText)
local Scale = require(script.Parent.Scale)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local X = Enum.AutomaticSize.X

local Threat = {}

local LOCKED_TINT = Color3.fromRGB(70, 64, 92)

-- body: the modal body Frame. Returns { Refresh, Layout }.
function Threat.Build(body: Frame)
	local focus: number? = nil
	local self: any = {}

	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, root)

	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 1 }, root)
	make("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 0),
		CellSize = UDim2.new(1 / 6, -7, 1, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, row)

	local cards = {}
	local tiers = Catalog.Current.Threat
	for tier = 1, #tiers do
		local btn
		btn = Kit.Button(row, {
			Text = "",
			Style = "Secondary",
			Icon = "T" .. tier,
			IconScale = 0.62,
			LayoutOrder = tier,
			Tip = "T" .. tier,
			OnClick = function()
				focus = tier
				local ok, reason = Net.Invoke("SetThreat", tier)
				if not ok then
					Toast.Show(ReasonText.Get(reason), "Bad")
					Sound.Play("Error")
				end
				self.Refresh()
			end,
		})
		local card = { Button = btn }
		-- One check marks the selected tier; keep it inside the card bounds.
		card.Check = Kit.Icon(btn.Instance, "ThreatCheck", UDim2.fromScale(0.26, 0.26))
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, card.Check)
		card.Check.AnchorPoint, card.Check.Position, card.Check.ZIndex, card.Check.Visible = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), 5, false
		-- Locked: padlock over the badge and the level it needs.
		card.Lock = Kit.Icon(btn.Instance, "ThreatLock", UDim2.fromScale(0.36, 0.36))
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, card.Lock)
		card.Lock.AnchorPoint, card.Lock.Position, card.Lock.ZIndex, card.Lock.Visible = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.66), 5, false
		card.Level = Kit.Pill(btn.Instance, "Lv " .. tiers[tier].UnlockLevel, Theme.BgDeep, Theme.TextPrimary, 24)
		card.Level.AnchorPoint, card.Level.Position, card.Level.ZIndex = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), 5
		for _, d in card.Level:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 5
			end
		end
		card.Level.Visible = false
		cards[tier] = card
	end

	-- Multiplier chips of the focused tier.
	local chipPanel = Kit.Panel(root, { Sprite = "Pill", Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2 })
	local chipRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, chipPanel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 16),
	}, chipRow)
	local CHIPS = { { "Coin", "Coins", "Coins" }, { "Xp", "Xp", "XP" }, { "DropChance", "Drops", "Drop chance" }, { "Heal", "Health", "Adventurer health" }, { "Sword", "Damage", "Adventurer damage" } }
	local chipLabels = {}
	for i, c in CHIPS do
		local f = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 36), LayoutOrder = i, Active = true }, chipRow)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		Kit.Icon(f, c[1], UDim2.fromOffset(28, 28)).LayoutOrder = 1
		local l = Kit.Label(f, "", Theme.TextSize.Body, if i <= 3 then Theme.TextPrimary else Theme.Warning, true)
		l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 32), false, 2
		Kit.Tip(f, c[3])
		chipLabels[c[2]] = l
	end

	-- Next tier to unlock.
	local goal = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 3, Active = true }, root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, goal)
	Kit.Icon(goal, "Flag", UDim2.fromOffset(32, 32)).LayoutOrder = 1
	local goalTier = Kit.Icon(goal, "T2", UDim2.fromOffset(34, 34))
	goalTier.LayoutOrder = 2
	local goalText = Kit.Label(goal, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	goalText.AutomaticSize, goalText.Size, goalText.TextWrapped, goalText.LayoutOrder = X, UDim2.fromOffset(0, 34), false, 3
	Kit.Tip(goal, "Next tier")

	function self.Layout()
		local phone = Scale.Phone
		row.Size = UDim2.new(1, 0, 0, if phone then 112 else 156)
		chipPanel.Size = UDim2.new(1, 0, 0, if phone then 44 else 54)
		for _, c in cards do
			c.Level.Size = UDim2.fromOffset(0, if phone then 20 else 24)
		end
	end

	function self.Refresh()
		local s = State.Current
		if not s then
			return
		end
		local selected = s.Threat or 1
		local unlocked = s.ThreatUnlocked or 1
		local shown = focus or selected
		for tier, c in cards do
			local locked = tier > unlocked
			local icon = c.Button.Icon
			if icon and icon:IsA("ImageLabel") then
				icon.ImageColor3 = if locked then LOCKED_TINT else Color3.new(1, 1, 1)
			end
			c.Lock.Visible, c.Level.Visible = locked, locked
			c.Check.Visible = tier == selected
		end
		local info = Catalog.Current.Threat[shown]
		if info then
			chipLabels.Coins.Text = Badges.Mult(info.Coins)
			chipLabels.Xp.Text = Badges.Mult(info.Xp)
			chipLabels.Drops.Text = Badges.Mult(info.Drops)
			chipLabels.Health.Text = Badges.Mult(info.Health)
			chipLabels.Damage.Text = Badges.Mult(info.Damage)
		end
		local nextTier = s.NextUnlocks and s.NextUnlocks.Threat
		goal.Visible = nextTier ~= nil
		if nextTier then
			goalTier.Name = "T" .. nextTier.Tier
			if goalTier:IsA("ImageLabel") then
				goalTier.Image = Kit.Sprites3["T" .. nextTier.Tier] or ""
			end
			goalText.Text = "Lv " .. nextTier.Level
		end
	end

	State.Changed:Connect(function()
		if body.Parent and body.Parent.Visible then
			self.Refresh()
		end
	end)
	self.Layout()
	return self
end

return Threat
