-- UIScale rule from docs/UI_SPEC.md. Phones (short side < 600) scale by height.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local Scale = { Value = 1, Phone = false, Changed = Signal.new() }

local scales: { UIScale } = {}

local function compute()
	local v = workspace.CurrentCamera.ViewportSize
	local phone = math.min(v.X, v.Y) < 600
	local s
	if phone then
		s = math.clamp(v.Y / 720, 0.7, 1.1)
	else
		s = math.clamp(math.min(v.X / 1920, v.Y / 1080), 0.6, 1.5)
	end
	Scale.Value, Scale.Phone = s, phone
	for _, u in scales do
		u.Scale = s
	end
	Scale.Changed:Fire(s, phone)
end

local hooked: RBXScriptConnection? = nil
local function hook()
	if hooked then
		hooked:Disconnect()
	end
	hooked = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(compute)
	compute()
end

hook()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)

function Scale.Attach(gui: ScreenGui)
	local u = Instance.new("UIScale")
	u.Scale = Scale.Value
	u.Parent = gui
	table.insert(scales, u)
	gui.Destroying:Once(function()
		local i = table.find(scales, u)
		if i then
			table.remove(scales, i)
		end
	end)
end

return Scale
