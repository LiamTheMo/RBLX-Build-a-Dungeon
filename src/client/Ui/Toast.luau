-- Toast stack: 0.2 s in, 2.5 s hold, 0.3 s out (instant-ish when reduced).
local Players = game:GetService("Players")

local Bus = require(script.Parent.Bus)
local Theme = require(script.Parent.Theme)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Kit = require(script.Parent.Kit)

local Toast = {}

local KIND_COLOR = { Info = Theme.Accent, Good = Theme.Success, Bad = Theme.Danger }
local KIND_ICON = { Info = "Info", Good = "Good", Bad = "Warn" }
local KIND_FRAME = { Info = "ToastInfo", Good = "ToastGood", Bad = "ToastBad" }
local MAX = 4

local stack: Frame? = nil

local function ensure(): Frame
	if stack and stack.Parent then
		return stack
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Toasts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	Scale.Attach(gui)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Parent = gui
	local function place()
		-- Centre column below the next-visitor chip.
		local phone = Scale.Phone
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.new(0.5, 0, 0, (if phone then 150 else 204) + Bus.ToastOffset)
		f.Size = UDim2.fromOffset(if phone then 300 else 460, 10)
	end
	place()
	Scale.Changed:Connect(place)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = f
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	stack = f
	return f
end

function Toast.Show(text: string, kind: string?)
	kind = if KIND_COLOR[kind or "Info"] then kind else "Info"
	local parent = ensure()
	-- While the Loot/Collection/Keeper panel is open, drop the stack below its header and tab row.
	local panels
	for _, child in Players.LocalPlayer.PlayerGui:GetChildren() do
		if child.Name == "Panels" and child:IsA("ScreenGui") and child.Enabled then panels = child; break end
	end
	local dim = panels and panels:IsA("ScreenGui") and panels.Enabled and panels:FindFirstChildWhichIsA("TextButton")
	local panelFrame = dim and dim:FindFirstChild("Modal")
	local toastGui = parent.Parent :: ScreenGui
	if panelFrame then
		local y = (panelFrame.AbsolutePosition.Y - toastGui.AbsolutePosition.Y) / Scale.Value + 112
		parent.AnchorPoint = Vector2.new(0.5, 0)
		parent.Position = UDim2.new(0.5, 0, 0, y)
	else
		parent.AnchorPoint = Vector2.new(0.5, 0)
		parent.Position = UDim2.new(0.5, 0, 0, (if Scale.Phone then 150 else 204) + Bus.ToastOffset)
	end
	local live = {}
	for _, c in parent:GetChildren() do
		if c:IsA("CanvasGroup") then
			table.insert(live, c)
		end
	end
	if #live >= MAX then
		table.sort(live, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		live[1]:Destroy()
	end

	local g = Instance.new("CanvasGroup")
	g.LayoutOrder = os.clock() * 1000
	-- Height from the measured text (automatic sizing under a CanvasGroup clipped the second line); the frame's
	-- border is ~20 px each side (Toast.Info/Good/Bad sprites).
	local width = if Scale.Phone then 300 else 460
	local lines = math.max(1, math.ceil(#text * Theme.TextSize.Body * 0.5 / math.max(width - 110, 100)))
	g.Size = UDim2.new(1, 0, 0, math.max(64, 44 + lines * (Theme.TextSize.Body + 4)))
	g.BackgroundTransparency = 1
	g.GroupTransparency = 1
	local frame = Kit.Panel(g, { Sprite = KIND_FRAME[kind], Size = UDim2.fromScale(1, 1), ZIndex = 0 })
	frame:FindFirstChild("Inset"):Destroy()
	local icon = Kit.Icon(g, KIND_ICON[kind], UDim2.fromOffset(30, 30))
	icon.AnchorPoint, icon.Position, icon.ZIndex = Vector2.new(0, 0.5), UDim2.new(0, 22, 0.5, 0), 2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(60, 0)
	label.Size = UDim2.new(1, -86, 1, 0)
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Theme.TextPrimary
	label.TextSize = Theme.TextSize.Body
	label.FontFace = Theme.BodyFont
	label.ZIndex = 2
	label.Parent = g
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = Theme.Stroke, 2
	stroke.Parent = label
	g.Parent = parent

	local fast = Settings.Reduced()
	Settings.Tween(g, TweenInfo.new(fast and 0.08 or 0.2), { GroupTransparency = 0 })
	task.delay(2.5, function()
		if g.Parent then
			local t = Settings.Tween(g, TweenInfo.new(fast and 0.08 or 0.3), { GroupTransparency = 1 })
			if t then
				t.Completed:Wait()
			end
			g:Destroy()
		end
	end)
end

return Toast
