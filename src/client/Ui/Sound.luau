-- Named sound slots backed by Ui/SoundIds. Names without an id stay
-- silent (Remove, Escaped, Robbed, Music). Volume follows the SFX setting.
local SoundService = game:GetService("SoundService")

local SoundIds = require(script.Parent.SoundIds)
local Settings = require(script.Parent.Settings)

local Sound = {}

-- Slot name -> SoundIds key when they differ.
local ALIAS: { [string]: string } = { Trap = "SpikeStrike", Defeated = "VisitorDefeated" }

function Sound.Play(name: string)
	local entry = (SoundIds :: any)[ALIAS[name] or name]
	if not entry then
		return
	end
	local volume = (entry.Volume or 0.5) * Settings.Values.SfxVolume
	if volume <= 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = entry.Id
	s.Volume = volume
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

return Sound
