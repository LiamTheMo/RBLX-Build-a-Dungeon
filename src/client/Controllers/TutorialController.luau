-- Shows the server-owned tutorial step as a prompt bubble with an optional
-- highlight. The server advances the step; this only renders it and sends
-- TutorialAction requests.
local RunService = game:GetService("RunService")

local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Kit = require(Ui.Kit)
local Net = require(Ui.Net)
local Scale = require(Ui.Scale)
local Settings = require(Ui.Settings)
local Sprites = require(Ui.Sprites)
local SpriteIds = require(Ui.SpriteIds)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)
local ReasonText = require(Ui.ReasonText)

local make = Kit.Make

-- Step names are owned by the server (docs/PHASE0.md "First five minutes").
-- Target: Bus.Targets key to point at when not building; Cell: grid cell to
-- highlight while building.
local STEPS = {
	Welcome = {
		Text = "Welcome to your dungeon! Adventurers walk in and your monsters fight them for coins.",
		Next = true,
	},
	PracticeEncounter = {
		Text = "A practice adventurer is arriving. Watch your slime knock it out!",
	},
	PlaceSpike = {
		Text = "Add the Spike Hall behind your slime. Tap Build, pick the Spike Hall, then tap the gold square.",
		Target = "Build",
		Cell = "3,3",
	},
	WatchNovice = {
		Text = "A novice is coming. The slime slows it, so the spikes hit more. Room order matters!",
	},
	TreasureOffer = {
		Text = "Optional: a Treasure Room brings visitors faster and grows a vault bonus, but thieves can steal from the vault.",
		Place = true,
		Decline = true,
		Cell = "3,4",
	},
	BankVault = {
		-- Step id kept (it is saved); the step now teaches the vault share slider.
		Text = "Tap the vault and slide in some coins: visitors come faster, but thieves can steal.",
		Target = "Vault",
	},
	BuyGuard = {
		Text = "Open the Shop and buy a Guard Room, then place it in your dungeon.",
		Target = "Shop",
	},
	Done = {
		Text = "You're all set. Keep growing your dungeon!",
		Next = true,
		NoSkip = true,
	},
}

local Tutorial = {}

local ui: any = nil
local currentStep: string? = nil
local target: any = nil
local lastHint: string? = nil

local function action(name: string)
	local ok, reason = Net.Invoke("TutorialAction", name)
	if not ok then
		Toast.Show(ReasonText.Get(reason), "Bad")
	end
end

local function clearTarget()
	if target and target.Button then
		target.Button.SetHighlight(nil)
	end
	target = nil
end

local function setHint(key: string?)
	if key ~= lastHint then
		lastHint = key
		Bus.CellHint:Fire(key)
	end
end

local function layout()
	local phone = Scale.Phone
	-- Above the bottom bar (3 buttons: 76 / 108 px tall) and its margin.
	-- The bubble sprite's tail stretches, so the bubble stays near its native width (<= ~1.4x at the 0.5 slice scale).
	local available = ui.Root.AbsoluteSize.X / math.max(Scale.Value, 0.01)
	local width = math.max(220, math.min(if phone then 340 else 350, available - 40))
	ui.Bubble.Position = UDim2.new(0.5, 0, 1, if phone then -92 else -144)
	ui.Bubble.Size = UDim2.fromOffset(width, if phone then 170 else 196)
	ui.Buttons.Size = UDim2.fromOffset(width, 48)
	ui.TextLimit.MaxTextSize = if phone then 15 else 18
	local m = if phone then 64 else 84
	ui.Mascot.Size = UDim2.fromOffset(m, m)
	-- Text sits inside the bubble body: 34 px of border at the sides and top, 66 px at the bottom (tail band).
	ui.Text.Position = UDim2.fromOffset(32, 24)
	ui.Text.Size = UDim2.new(1, -64, 1, -(24 + 58))
end

local function refresh()
	local s = State.Current
	local step = s and s.Tutorial and s.Tutorial.Step
	local cfg = if type(step) == "string" then STEPS[step] else nil
	if not s or s.LoadState == "Failed" or (s.Tutorial and s.Tutorial.Done and step ~= "Done") or not cfg or (step == "Done" and s.Tutorial.Done) then
		ui.Bubble.Visible = false
		ui.Arrow.Visible = false
		clearTarget()
		setHint(nil)
		currentStep = nil
		return
	end
	currentStep = step
	-- Placement mode supplies its own cell hint and controls.
	ui.Bubble.Visible = not s.Building
	ui.Text.Text = cfg.Text
	ui.Next.Instance.Visible = cfg.Next == true
	ui.Place.Instance.Visible = cfg.Place == true
	ui.Decline.Instance.Visible = cfg.Decline == true
	ui.Skip.Instance.Visible = not cfg.NoSkip
	ui.Next.SetText(if step == "Done" then "Got it" else "Next")

	clearTarget()
	if s.Building then
		setHint(cfg.Cell)
		ui.Arrow.Visible = false
	else
		setHint(nil)
		local t = cfg.Target and Bus.Targets[cfg.Target]
		if t and t.Instance.Parent and t.Instance.Visible then
			target = t
		else
			ui.Arrow.Visible = false
		end
	end
end

local function buildUi()
	local gui = Kit.Screen("Tutorial", 3)
	ui = {}
	ui.Root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	-- Cream bubble (drawn, dark text) with the Keeper portrait as the mascot at the left.
	ui.Bubble = Kit.Panel(ui.Root, { Sprite = "Bubble", AnchorPoint = Vector2.new(0.5, 1), Visible = false })
	ui.Bubble:FindFirstChild("Inset"):Destroy() -- text and buttons are placed explicitly
	ui.Bubble.ClipsDescendants = false
	-- The Keeper mascot stands left of the bubble.
	ui.Mascot = make("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), ScaleType = Enum.ScaleType.Fit, Image = "" }, ui.Bubble)
	ui.Mascot.Position = UDim2.new(0, 10, 1, 0)
	local portrait = SpriteIds.Portraits.Keeper
	if Sprites.Ok(portrait) then
		ui.Mascot.Image = portrait
		Sprites.Watch(portrait, function()
			Kit.Neutral(ui.Mascot)
		end)
	else
		ui.Mascot.Visible = false
	end
	ui.Text = Kit.Label(ui.Bubble, "", 20, Theme.BgDeep)
	ui.Text.ZIndex = 3
	ui.Text.TextXAlignment = Enum.TextXAlignment.Left
	ui.Text.TextYAlignment = Enum.TextYAlignment.Center
	ui.Text.TextScaled = true -- long steps shrink to fit instead of running out of the bubble
	ui.TextLimit = make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = 20 }, ui.Text)

	-- Buttons sit just above the bubble, right-aligned.
	ui.Buttons = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -8),
		Size = UDim2.fromOffset(420, 48),
	}, ui.Bubble)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ui.Buttons)
	local function btn(text: string, style: string, order: number, fn: () -> ())
		return Kit.Button(ui.Buttons, { Text = text, Style = style, LayoutOrder = order, Size = UDim2.fromOffset(if Scale.Phone then 104 else 120, 48), TextSize = 18, OnClick = fn })
	end
	ui.Place = btn("Place", "Primary", 1, function()
		Bus.BuildRequested:Fire()
	end)
	ui.Decline = btn("No thanks", "Secondary", 2, function()
		action("DeclineTreasure")
	end)
	ui.Next = btn("Next", "Primary", 3, function()
		action("Next")
	end)
	ui.Skip = btn("Skip", "Secondary", 4, function()
		action("Skip")
	end)

	-- Pointer arrow (Feedback.TutorialArrow) above the highlighted button.
	ui.Arrow = Kit.Sprite(ui.Root, "Feedback.TutorialArrow", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(40, 44), Visible = false, ZIndex = 5 })

	ui.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	Scale.Changed:Connect(layout)
	layout()
end

function Tutorial.Init()
	State.Start()
end

function Tutorial.Start()
	buildUi()
	State.Changed:Connect(refresh)
	Settings.Changed:Connect(refresh)
	refresh()

	-- Arrow and stroke follow the target button; static when motion is reduced.
	RunService.RenderStepped:Connect(function()
		if not target or not target.Instance.Parent then
			return
		end
		local inst = target.Instance
		local origin = ui.Root.AbsolutePosition
		local centre = inst.AbsolutePosition + Vector2.new(inst.AbsoluteSize.X / 2, 0)
		local p = (centre - origin) / Scale.Value
		local pulse = if Settings.Reduced() then 0 else math.sin(os.clock() * 5)
		ui.Arrow.Position = UDim2.fromOffset(p.X, p.Y - 4 + pulse * 4)
		ui.Arrow.Visible = inst.Visible
		if target.Button then
			target.Button.SetHighlight(5 + pulse)
		end
	end)
end

return Tutorial
