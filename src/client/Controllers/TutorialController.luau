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
		Text = "Optional: a Treasure Room grows a vault bonus for luck, but thieves can steal from the vault.",
		Place = true,
		Decline = true,
		Cell = "3,4",
	},
	BankVault = {
		-- Step id kept (it is saved); the step now teaches the vault share slider.
		Text = "Tap the vault and slide in some coins for extra luck, but thieves can steal.",
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
	-- Bubble.Wide is one whole image (590:214, tail along the bottom), so its height follows its width. It sits above the
	-- bottom bar; the text fills the art's Inner rect (above the tail band).
	local spec = Kit.Spec("Bubble.Wide")
	local available = ui.Root.AbsoluteSize.X / math.max(Scale.Value, 0.01)
	local width = math.max(240, math.min(if phone then 420 else 560, available - 40))
	ui.Bubble.Position = UDim2.new(0.5, 0, 1, if phone then -104 else -190)
	ui.Bubble.Size = UDim2.fromOffset(width, width * spec.Size.Y / spec.Size.X)
	-- The buttons stack in a column beside the bubble (bottom aligned with it): they never sit over the player or the player's
	-- name tag above the bubble, the visitor card or the buff chips.
	ui.Buttons.Size = UDim2.fromOffset(if phone then 128 else 170, 3 * (if phone then 64 else 76) + 16)
	ui.Buttons.AnchorPoint = Vector2.new(0, 1)
	ui.Buttons.Position = UDim2.new(1, 14, 1, -34)
	local lay = ui.Buttons:FindFirstChildOfClass("UIListLayout")
	if lay then
		lay.FillDirection, lay.HorizontalAlignment, lay.VerticalAlignment = Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom
	end
	for _, b in ui.Buttons:GetChildren() do
		if b:IsA("GuiButton") then b.Size = UDim2.fromOffset(if phone then 128 else 170, if phone then 64 else 76) end
	end
	ui.Text.TextSize = Theme.TextSize.Body
	local m = if phone then 64 else 84
	ui.Mascot.Size = UDim2.fromOffset(m, m)
	local l, t, r, b = Kit.InnerPadding(spec)
	ui.Text.Position = UDim2.fromScale(l, t)
	ui.Text.Size = UDim2.fromScale(1 - l - r, 1 - t - b)
	-- The text sits inside the Inner rect with its own padding (never against the art's edge).
	local pad = ui.Text:FindFirstChildOfClass("UIPadding") or make("UIPadding", {}, ui.Text)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, if phone then 16 else 20), UDim.new(0, if phone then 16 else 20)
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
	-- Bubble.Wide sprite (cream, dark text) with the Keeper portrait as the mascot at the left.
	ui.Bubble = Kit.Panel(ui.Root, { Sprite = "BubbleWide", AnchorPoint = Vector2.new(0.5, 1), Visible = false })
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
	ui.Text = Kit.Label(ui.Bubble, "", 20, Theme.Stroke)
	ui.Text.ZIndex = 3
	ui.Text.TextXAlignment = Enum.TextXAlignment.Left
	ui.Text.TextYAlignment = Enum.TextYAlignment.Center
	ui.Text.TextWrapped = true -- a fixed size; a long step wraps (the bubble holds two lines)
	Kit.FixedText(ui.Text, Theme.TextSize.Body)

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
		return Kit.Button(ui.Buttons, { Text = text, Style = style, LayoutOrder = order, Size = UDim2.fromOffset(if Scale.Phone then 150 else 170, 76), TextSize = 24, OnClick = fn })
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

	-- Pointer arrow (Arrow.Tutorial, 322 x 216 native, tip at the bottom left) above the highlighted button.
	ui.Arrow = Kit.Sprite(ui.Root, "Arrow.Tutorial", { AnchorPoint = Vector2.new(0.04, 0.96), Size = UDim2.fromOffset(78, 52), Visible = false, ZIndex = 5 })

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
