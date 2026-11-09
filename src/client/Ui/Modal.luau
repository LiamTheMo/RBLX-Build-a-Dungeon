-- Modal popup shared by the HUD panels (Shop, Settings, Threat, Vault, Drop card). `Modal.New` returns
-- { Group, Body, Open, Close, Layout, IsOpen }; opening one closes the others. The chrome (Panel.Modal back, the
-- Panel.SectionPlate title straddling the top edge, Round.Close on the corner) comes from Kit.ModalChrome; the body is
-- the rectangle inside its border below the title.
local Kit = require(script.Parent.Kit)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)

local make = Kit.Make

local Modal = { All = {} :: { any } }

local function topMargin(): number
	return if Scale.Phone then 64 else 100
end

-- The modal back is ONE whole image (Panel.Modal 890x494, or Panel.ModalCompact 394x270 when `compact`), so its height
-- always follows its width at the art's aspect. desktop / phone .X is the preferred width (reference px, before UIScale;
-- .Y is ignored); `phone` is used when Scale.Phone, wideFrac widens it to that fraction of the view on desktop. The width
-- shrinks until the modal and its title plate fit between the top margin and the navigation row, so small windows keep the
-- close button reachable. The body is the art's Inner rect (px, relative to the modal). titleIcon is kept for callers.
function Modal.New(gui: ScreenGui, title: string, _titleIcon: string, desktop: Vector2, phone: Vector2, wideFrac: number?, compact: boolean?)
	local group = make("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		GroupTransparency = 1,
	}, gui)
	-- Dim veil behind the modal (sibling in the screen, below the group).
	-- Global z-ordering: the scrim must sit below every layer of the modal, so it takes a negative ZIndex.
	local scrim = Kit.Scrim(gui, 0.72, { Name = "ModalScrim", Visible = false, ZIndex = -5 })
	-- Tapping the dim area (above the navigation row) dismisses the modal.
	local dismiss = make("TextButton", { Name = "Dismiss", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -(Scale.Phone and 116 or 170)), Visible = false, ZIndex = -4 }, gui)
	local self: any
	local lastOverhang = 0
	local lastView, lastHeight = 0, 0
	local chrome = Kit.ModalChrome(group, title, function()
		self.Close()
	end, if compact then "PlainCompact" else "Plain")
	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, ClipsDescendants = true }, chrome.Root)
	self = { Group = group, IsOpen = false, Title = chrome.Title, Body = body, Chrome = chrome }

	function self.Layout()
		local size = if Scale.Phone then phone else desktop
		local reserve = if Scale.Phone then 116 else 170
		local top = topMargin()
		local view = (gui.AbsoluteSize / math.max(Scale.Value, 0.01)) - Vector2.new(12, reserve + top)
		local width = size.X
		if not Scale.Phone and wideFrac then
			width = math.max(width, view.X * wideFrac)
		end
		local overhang = chrome.Layout(width)
		if view.X > 50 and view.Y > 50 then
			width = math.min(width, view.X, (view.Y - overhang) * chrome.Ratio)
			overhang = chrome.Layout(width)
			width = math.min(width, (view.Y - overhang) * chrome.Ratio)
		end
		local height = width / chrome.Ratio
		dismiss.Size = UDim2.new(1, 0, 1, -reserve)
		lastView = view.Y
		lastHeight = height + overhang
		group.Size = UDim2.fromOffset(width, height + overhang)
		chrome.Root.Position, chrome.Root.Size = UDim2.fromOffset(0, overhang), UDim2.fromOffset(width, height)
		local bx, by, bw, bh = chrome.BodyRect(width, height)
		body.Position, body.Size = UDim2.fromOffset(bx, by), UDim2.fromOffset(bw, bh)
		lastOverhang = overhang
		group.Position = UDim2.new(0.5, 0, 0, top + math.max(0, (lastView - lastHeight) / 2))
	end
	local gen = 0
	group:GetPropertyChangedSignal("Visible"):Connect(function()
		scrim.Visible = group.Visible
		dismiss.Visible = group.Visible
	end)
	dismiss.Activated:Connect(function()
		self.Close()
	end)
	local function restY(): number
		return topMargin() + math.max(0, (lastView - lastHeight) / 2)
	end
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
		local y = restY()
		group.Position = UDim2.new(0.5, 0, 0, y + 24)
		Settings.Tween(group, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, y),
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
		local y = restY()
		local t = Settings.Tween(group, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, y + 24),
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
