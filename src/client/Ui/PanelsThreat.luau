-- Threat picker body: six tier cards (lock + "Lv N" when locked, ring + check when selected), the
-- multiplier chips of the focused tier and the next tier to unlock. Display and requests only: SetThreat
-- is validated by the server (locked tiers come back as reason toasts).
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
function Threat.Build(body: GuiObject)
	local focus: number? = nil
	local self: any = {}

	local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, root)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 22), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, root)

	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 1 }, root)
	local tierGrid = make("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		CellSize = UDim2.fromOffset(140, 140), -- square: Card.Normal / Card.Selected are 1:1 whole sprites
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, row)

	local cards = {}
	local tiers = Catalog.Current.Threat
	for tier = 1, #tiers do
		local btn
		btn = Kit.Button(row, {
			Text = "",
			Style = "Card",
			Icon = "T" .. tier,
			IconScale = 0.58,
			LayoutOrder = tier,
			Tip = "T" .. tier,
			OnClick = function()
				focus = tier
				local ok, reason = Net.Invoke("SetThreat", tier)
				if not ok then
					Toast.Show(ReasonText.Get(reason), "Bad")
					Sound.Play("Error")
				else
					Toast.Show("Threat selection saved for upcoming visitors.", "Info")
				end
				self.Refresh()
			end,
		})
		local card = { Button = btn }
		-- One check marks the selected tier; keep it inside the card bounds.
		card.Check = Kit.Sprite(btn.Instance, "Round.Confirm", { Size = UDim2.fromScale(0.26, 0.26) })
		card.Check.AnchorPoint, card.Check.Position, card.Check.ZIndex, card.Check.Visible = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), 5, false
		-- Locked: padlock over the badge and the level it needs.
		card.Lock = Kit.Sprite(btn.Instance, "Round.Lock", { Size = UDim2.fromScale(0.36, 0.36) })
		card.Lock.AnchorPoint, card.Lock.Position, card.Lock.ZIndex, card.Lock.Visible = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.66), 5, false
		card.Level = Kit.Pill(btn.Instance, "Lv " .. tiers[tier].UnlockLevel, Theme.BgDeep, Theme.TextPrimary, 30)
		card.Level.AnchorPoint, card.Level.Position, card.Level.ZIndex = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), 5
		for _, d in card.Level:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 5
			end
		end
		card.Level.Visible = false
		cards[tier] = card
	end

	-- Multiplier strip of the focused tier: Hud.Pill (540x150) as ONE whole sprite; five icon + value cells inside its Inner rect.
	local PILL = Kit.Spec("Hud.Pill")
	local STRIP_W = 560
	local STRIP_H = STRIP_W * PILL.Size.Y / PILL.Size.X
	local chipPanel = Kit.Panel(root, { Sprite = "Pill", Size = UDim2.fromOffset(STRIP_W, STRIP_H), LayoutOrder = 2 })
	local chipRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, chipPanel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, chipRow)
	local CHIPS = { { "Coin", "Coins", "Coins" }, { "Xp", "Xp", "XP" }, { "DropChance", "Drops", "Drop chance" }, { "Heal", "Health", "Adventurer health" }, { "Sword", "Damage", "Adventurer damage" } }
	local chipLabels = {}
	for i, c in CHIPS do
		-- Each cell is a fifth of the strip: icon over value (value text scales to fit).
		local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1 / #CHIPS, 1), LayoutOrder = i, Active = true }, chipRow)
		make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
		local icon = Kit.Icon(f, c[1], UDim2.fromScale(0.55, 0.52))
		icon.LayoutOrder = 1
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize }, icon)
		local l = Kit.Label(f, "", Theme.TextSize.Number - 2, if i <= 3 then Theme.TextPrimary else Theme.Warning, true)
		l.Size, l.TextWrapped, l.LayoutOrder = UDim2.new(1, 0, 0, 30), false, 2
		Kit.FixedText(l, 22) -- one fixed multiplier size for all five cells
		Kit.Stroke(l, Theme.Stroke, 2)
		Kit.Tip(f, c[3])
		chipLabels[c[2]] = l
	end

	-- Next tier to unlock.
	local goal = make("Frame", { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromOffset(0, 48), LayoutOrder = 3, Active = true }, root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, goal)
	Kit.Icon(goal, "Flag", UDim2.fromOffset(32, 32)).LayoutOrder = 1
	local goalTier = Kit.Icon(goal, "T2", UDim2.fromOffset(34, 34))
	goalTier.LayoutOrder = 2
	local goalText = Kit.Label(goal, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	goalText.AutomaticSize, goalText.Size, goalText.TextWrapped, goalText.LayoutOrder = X, UDim2.fromOffset(0, 34), false, 3
	Kit.Tip(goal, "Next tier")

	-- Short description under the strip (fills the panel and explains the multipliers).
	local desc = Kit.Label(root, "", Theme.TextSize.Body, Theme.TextMuted, true)
	desc.Size, desc.AutomaticSize, desc.LayoutOrder = UDim2.new(1, -16, 0, 0), Enum.AutomaticSize.Y, 4

	function self.Layout()
		local sc = math.max(Scale.Value, 0.01)
		local width = body.AbsoluteSize.X / sc - 44
		if width < 200 then
			width = 800
		end
		-- Six square tier cards in a row when they stay >= 60 px (44 real px on a phone), else three per row. Never stretched: cells are square.
		local columns = if width >= 6 * 62 + 40 then 6 else 3
		local cell = math.floor(math.clamp((width - 8 * (columns - 1)) / columns - 1, 60, if Scale.Phone then 62 else 176))
		local rows = math.ceil(#cards / columns)
		row.Size = UDim2.new(1, 0, 0, rows * cell + (rows - 1) * 8)
		tierGrid.FillDirectionMaxCells = columns
		tierGrid.CellSize = UDim2.fromOffset(cell, cell)
		for _, c in cards do
			Kit.SetPillHeight(c.Level, math.clamp(cell * 0.22, 26, 34))
		end
		-- Phone: a shorter tier row and strip, so the whole strip shows in the short well (the note scrolls under it).
		local stripW = math.min(if Scale.Phone then 400 else math.max(STRIP_W, cell * 4), width)
		chipPanel.Size = UDim2.fromOffset(stripW, stripW * PILL.Size.Y / PILL.Size.X)
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
			c.Button.SetSelected(tier == selected)
		end
		desc.Text = if Scale.Phone then string.format("Tier %d: applies to the next visitors.", shown) else string.format("Tier %d is shown. The multipliers above apply to the visitors that arrive next.", shown)
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
				Kit.SetIcon(goalTier, "T" .. nextTier.Tier)
			end
			goalText.Text = "Next Threat Tier Unlock: Lv " .. nextTier.Level
		end
	end

	self.Layout()
	return self
end

return Threat
