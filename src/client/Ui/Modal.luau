-- Modal popup shared by the HUD panels (Shop, Settings, Threat, Vault, Drop card). `Modal.New` returns
-- { Group, Body, Open, Close, Layout, IsOpen }; opening one closes the others. The panel art sits behind
-- everything in the group; the body is inset past its border and the close button's row.
local Kit = require(script.Parent.Kit)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Theme = require(script.Parent.Theme)

local make = Kit.Make
local X = Enum.AutomaticSize.X

local Modal = { All = {} :: { any } }

-- Sizes are reference px (before UIScale); `phone` is used when Scale.Phone. The group never exceeds
-- the screen (clamped in Layout) so small windows keep the close button reachable.
function Modal.New(gui: ScreenGui, title: string, titleIcon: string, desktop: Vector2, phone: Vector2)
	local group = make("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		GroupTransparency = 1,
	}, gui)
	-- Dim vignette behind the modal (sibling in the screen, below the group) with the group's glow.
	local scrim = Kit.Sprite(gui, "Feedback.Scrim", { Name = "ModalScrim", Position = UDim2.fromOffset(-400, -400), Size = UDim2.new(1, 800, 1, 800), ImageTransparency = 0.35, ScaleType = Enum.ScaleType.Stretch, Visible = false, ZIndex = 0 })
	local glow = Kit.Glow(gui, Theme.Accent, 0.55)
	glow.Name, glow.Visible = "ModalGlow", false
	local back = Kit.Panel(group, { Sprite = "Large", Size = UDim2.fromScale(1, 1), ZIndex = 0, Active = false })
	back:FindFirstChild("Inset"):Destroy() -- content is placed explicitly below
	local titleBar = Kit.Panel(group, { Sprite = "TitleBar", Position = UDim2.fromOffset(24, 12), Size = UDim2.new(1, -96, 0, 52), ZIndex = 1, Active = false })
	local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 12), Size = UDim2.new(1, -120, 0, 52) }, group)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, head)
	local titleImg = Kit.Icon(head, titleIcon, UDim2.fromOffset(36, 36))
	titleImg.LayoutOrder = 1
	local label = Kit.Label(head, title, Theme.TextSize.Heading, Theme.Gold, true)
	label.AutomaticSize, label.Size, label.TextWrapped, label.LayoutOrder = X, UDim2.fromOffset(0, 40), false, 2
	local self: any = { Group = group, IsOpen = false, Title = label }
	local close = Kit.CloseButton(group, UDim2.fromOffset(52, 52), function()
		self.Close()
	end)
	close.Instance.AnchorPoint = Vector2.new(1, 0)
	close.Instance.Position = UDim2.new(1, -22, 0, 12)
	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(26, 72), ClipsDescendants = true }, group)
	self.Body = body

	function self.Layout()
		local size = if Scale.Phone then phone else desktop
		local view = (gui.AbsoluteSize / math.max(Scale.Value, 0.01)) - Vector2.new(12, 12)
		if view.X > 50 and view.Y > 50 then
			size = Vector2.new(math.min(size.X, view.X), math.min(size.Y, view.Y))
		end
		group.Size = UDim2.fromOffset(size.X, size.Y)
		glow.Size = UDim2.fromOffset(size.X * 1.3, size.Y * 1.4)
		body.Size = UDim2.new(1, -52, 1, -72 - 26)
	end
	local gen = 0
	group:GetPropertyChangedSignal("Visible"):Connect(function()
		scrim.Visible, glow.Visible = group.Visible, group.Visible
	end)
	group:GetPropertyChangedSignal("Position"):Connect(function()
		glow.Position = group.Position
	end)
	function self.Open()
		for _, m in Modal.All do
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
		if self.OnClose then
			self.OnClose()
		end
	end
	self.Layout()
	table.insert(Modal.All, self)
	return self
end

function Modal.CloseAll()
	for _, m in Modal.All do
		m.Close()
	end
end

return Modal
