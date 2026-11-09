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
-- Whole toast art: Toast.* (2.5:1) on phones, ToastWide.* (4.5:1) on desktop; the height always follows the width.
local KIND_FRAME = { Info = "ToastInfo", Good = "ToastGood", Bad = "ToastBad" }
local KIND_WIDE = { Info = "ToastWideInfo", Good = "ToastWideGood", Bad = "ToastWideBad" }
local PHONE_W, DESKTOP_W = 420, 540
local PHONE_LEFT_Y, DESKTOP_Y = 176, 204 -- phone: left column under the HUD stack; desktop: centred under the chip row
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
		local phone = Scale.Phone
		-- Phones anchor the stack at the left, below the HUD stack, clear of the visitor card on the right.
		f.AnchorPoint = if phone then Vector2.new(0, 0) else Vector2.new(0.5, 0)
		f.Position = if phone then UDim2.fromOffset(8, PHONE_LEFT_Y) else UDim2.new(0.5, 0, 0, DESKTOP_Y + Bus.ToastOffset)
		f.Size = UDim2.fromOffset(if phone then PHONE_W else DESKTOP_W, 10)
		local l = f:FindFirstChildOfClass("UIListLayout")
		if l then
			l.HorizontalAlignment = if phone then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
		end
	end
	place()
	Scale.Changed:Connect(place)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.Parent = f
	place()
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
	if panelFrame and not Scale.Phone then
		local y = (panelFrame.AbsolutePosition.Y - toastGui.AbsolutePosition.Y) / Scale.Value + 112
		parent.AnchorPoint = Vector2.new(0.5, 0)
		parent.Position = UDim2.new(0.5, 0, 0, y)
	elseif Scale.Phone then
		parent.AnchorPoint, parent.Position = Vector2.zero, UDim2.fromOffset(8, PHONE_LEFT_Y)
	else
		parent.AnchorPoint = Vector2.new(0.5, 0)
		parent.Position = UDim2.new(0.5, 0, 0, DESKTOP_Y + Bus.ToastOffset)
	end
	local live = {}
	for _, c in parent:GetChildren() do
		if c:IsA("CanvasGroup") then
			table.insert(live, c)
		end
	end
	if #live >= (if Scale.Phone then 2 else MAX) then
		table.sort(live, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		live[1]:Destroy()
	end

	local g = Instance.new("CanvasGroup")
	g.LayoutOrder = os.clock() * 1000
	-- One whole toast sprite at its own aspect; the text sits inside its Inner rect (a fixed size; long lines wrap
	-- rather than run out of the art).
	local phone = Scale.Phone
	local spec = Kit.Spec((if phone then "Toast." else "ToastWide.") .. kind)
	local width = if phone then PHONE_W else DESKTOP_W
	g.Size = UDim2.fromOffset(width, width * spec.Size.Y / spec.Size.X)
	g.BackgroundTransparency = 1
	g.GroupTransparency = 1
	local frame = Kit.Panel(g, { Sprite = (if phone then KIND_FRAME else KIND_WIDE)[kind], Size = UDim2.fromScale(1, 1), ZIndex = 0 })
	frame.ClipsDescendants = false
	-- The art's Inner rect (fractions of the sprite) holds an icon column on the left, a gap, then the text.
	local pl, pt, pr, pb = Kit.InnerPadding(spec)
	local ix0, ix1 = pl, 1 - pr
	local iy0, iy1 = pt, 1 - pb
	local iconH = g.Size.Y.Offset * (iy1 - iy0) * 0.8
	local gap = 10
	local icon = Kit.Icon(frame, KIND_ICON[kind], UDim2.fromOffset(iconH, iconH))
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio, iconAspect.AspectType, iconAspect.DominantAxis = 1, Enum.AspectType.FitWithinMaxSize, Enum.DominantAxis.Height
	iconAspect.Parent = icon
	icon.AnchorPoint, icon.Position, icon.ZIndex = Vector2.new(0, 0.5), UDim2.new(0, 6, 0.5, 0), 2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	-- The panel's Inset padding already is the art's Inner rect: the icon column, a gap, then the text fill it.
	label.Position = UDim2.fromOffset(6 + iconH + gap, 0)
	label.Size = UDim2.new(1, -(6 + iconH + gap + 8), 1, 0)
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.TextWrapped = true
	label.TextScaled = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Theme.TextPrimary
	label.TextSize = 22 -- fixed; the Inner rect holds two lines of it
	label.FontFace = Theme.BodyFont
	label.ZIndex = 2
	label.Parent = frame
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
