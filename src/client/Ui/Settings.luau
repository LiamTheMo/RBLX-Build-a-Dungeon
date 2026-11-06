-- Local view of the player's settings (applied immediately; the server
-- snapshot is the truth) and the single motion gate used by all UI tweens.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)
local Net = require(script.Parent.Net)
local State = require(script.Parent.State)

local Settings = {
	Values = { ReducedMotion = false, MusicVolume = 0.5, SfxVolume = 0.4 },
	Changed = Signal.new(),
}

local pending = 0

local function adopt(snapshot)
	local s = snapshot and snapshot.Settings
	if type(s) ~= "table" or pending > 0 then
		return
	end
	local v = Settings.Values
	v.ReducedMotion = s.ReducedMotion == true
	v.MusicVolume = if type(s.MusicVolume) == "number" then s.MusicVolume else v.MusicVolume
	v.SfxVolume = if type(s.SfxVolume) == "number" then s.SfxVolume else v.SfxVolume
	Settings.Changed:Fire()
end

local started = false
function Settings.Start()
	if started then
		return
	end
	started = true
	State.Changed:Connect(adopt)
	adopt(State.Current)
end

function Settings.Reduced(): boolean
	return Settings.Values.ReducedMotion
end

-- Applies the goal instantly when motion is reduced.
function Settings.Tween(inst: Instance, info: TweenInfo, goal: { [string]: any }): Tween?
	if Settings.Values.ReducedMotion then
		for k, v in goal do
			(inst :: any)[k] = v
		end
		return nil
	end
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- Local change now, debounced SaveSettings (0.5 s).
function Settings.Set(key: string, value: any)
	Settings.Values[key] = value
	Settings.Changed:Fire()
	pending += 1
	task.delay(0.5, function()
		pending -= 1
		if pending == 0 then
			local v = Settings.Values
			Net.Invoke("SaveSettings", {
				ReducedMotion = v.ReducedMotion,
				MusicVolume = v.MusicVolume,
				SfxVolume = v.SfxVolume,
			})
		end
	end)
end

return Settings
