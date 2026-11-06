-- Server event banner: icon + short name + countdown, top-centre under the currency and next-visitor
-- rows, shown while Workspace.ActiveEvent is set (EventEndsAt is a workspace:GetServerTimeNow() time).
-- ServerEvent {Kind = "Start" | "End"} adds a brief celebratory pop. Display only.
local Bus = require(script.Parent.Bus)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local Scale = require(script.Parent.Scale)
local Settings = require(script.Parent.Settings)
local Sound = require(script.Parent.Sound)
local Theme = require(script.Parent.Theme)

local make = Kit.Make

local Banner = {}

local started = false

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Banner.Start()
	if started then
		return
	end
	started = true
	local gui = Kit.Screen("Events", 4)
	local frame = make("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Visible = false, AutomaticSize = Enum.AutomaticSize.X }, gui)
	local pop = make("UIScale", {}, frame)
	local pill = Kit.Panel(frame, { Sprite = "Pill", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1) })
	local glow = Kit.Glow(pill, Theme.Gold, 1)
	glow.Size, glow.ZIndex = UDim2.new(1.5, 0, 3, 0), 10
	local row = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1) }, pill)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 18) }, row)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, row)
	local icon = Kit.Icon(row, "GoldenHour", UDim2.fromOffset(34, 34))
	icon.LayoutOrder = 1
	local name = Kit.Label(row, "", Theme.TextSize.Heading, Theme.Gold, true)
	name.AutomaticSize, name.Size, name.TextWrapped, name.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 36), false, 2
	name.TextStrokeColor3, name.TextStrokeTransparency = Theme.Stroke, 0.5
	local clock = Kit.Icon(row, "Clock", UDim2.fromOffset(24, 24))
	clock.LayoutOrder = 3
	local timer = Kit.Label(row, "", Theme.TextSize.Body + 2, Theme.TextPrimary, true)
	timer.AutomaticSize, timer.Size, timer.TextWrapped, timer.LayoutOrder = Enum.AutomaticSize.X, UDim2.fromOffset(0, 32), false, 4
	frame.Active = true
	Kit.Tip(frame, function()
		local id = workspace:GetAttribute("ActiveEvent")
		for _, e in Catalog.Current and Catalog.Current.Events or {} do
			if e.Id == id then
				return e.Text
			end
		end
		return ""
	end)

	local shownId = ""
	local function layout()
		local phone = Scale.Phone
		frame.Position = UDim2.new(0.5, 0, 0, if phone then 104 else 150)
		frame.Size = UDim2.fromOffset(0, if phone then 40 else 48)
		name.TextSize = if phone then 18 else Theme.TextSize.Heading
		icon.Size = UDim2.fromOffset(if phone then 28 else 34, if phone then 28 else 34)
	end
	Scale.Changed:Connect(layout)
	layout()

	local function celebrate()
		Sound.Play("Commit")
		if Settings.Reduced() then
			return
		end
		pop.Scale = 0.6
		glow.ImageTransparency = 0.25
		Settings.Tween(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		Settings.Tween(glow, TweenInfo.new(0.9), { ImageTransparency = 1 })
	end

	local function setEvent(id: string, announce: boolean)
		if id == shownId then
			return
		end
		shownId = id
		if id == "" then
			frame.Visible = false
			Bus.ToastOffset = 0
			return
		end
		local display = id
		for _, e in Catalog.Current and Catalog.Current.Events or {} do
			if e.Id == id then
				display = e.Name
			end
		end
		name.Text = display
		local sprite = Kit.Sprites3[id]
		if icon:IsA("ImageLabel") then
			icon.Image = sprite or ""
		end
		frame.Visible = true
		Bus.ToastOffset = if Scale.Phone then 50 else 62
		if announce then
			celebrate()
		end
	end

	Net.OnEvent("ServerEvent", function(e)
		if type(e) ~= "table" then
			return
		end
		if e.Kind == "Start" and type(e.Id) == "string" then
			setEvent(e.Id, true)
		elseif e.Kind == "End" then
			setEvent("", false)
		end
	end)
	local first = true
	task.spawn(function()
		while true do
			local id = workspace:GetAttribute("ActiveEvent")
			local ends = workspace:GetAttribute("EventEndsAt")
			if type(id) ~= "string" then
				id = ""
			end
			-- Joining mid-event shows the banner without the pop.
			setEvent(id, not first)
			first = false
			if id ~= "" and type(ends) == "number" then
				timer.Text = formatTime(ends - workspace:GetServerTimeNow())
			end
			task.wait(0.25)
		end
	end)
end

return Banner
