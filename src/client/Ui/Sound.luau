-- Named sound slots backed by Ui/SoundIds. Names without an id stay
-- silent (Remove, Escaped, Robbed, Music). Volume = slot volume x SFX setting.
-- Each slot has a short cooldown and at most MAX_LIVE overlapping instances, so a burst of
-- hits (many rooms attacking at once) cannot stack into a wall of noise.
local SoundService = game:GetService("SoundService")

local SoundIds = require(script.Parent.SoundIds)
local Settings = require(script.Parent.Settings)

local Sound = {}

-- Slot name -> SoundIds key when they differ.
local ALIAS: { [string]: string } = { Trap = "SpikeStrike", Defeated = "VisitorDefeated" }

local MAX_LIVE = 2 -- overlapping instances per slot
local DEFAULT_COOLDOWN = 0.05 -- seconds between two plays of one slot
local live: { [string]: number } = {}
local lastPlay: { [string]: number } = {}

function Sound.Play(name: string)
	local key = ALIAS[name] or name
	local entry = (SoundIds :: any)[key]
	if not entry then
		return
	end
	local volume = (entry.Volume or 0.3) * Settings.Values.SfxVolume
	if volume <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastPlay[key] or -1) < (entry.Cooldown or DEFAULT_COOLDOWN) or (live[key] or 0) >= (entry.MaxLive or MAX_LIVE) then
		return
	end
	lastPlay[key] = now
	live[key] = (live[key] or 0) + 1
	local s = Instance.new("Sound")
	s.SoundId = entry.Id
	s.Volume = volume
	s.Parent = SoundService
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		live[key] = math.max((live[key] or 1) - 1, 0)
		s:Destroy()
	end
	s.Ended:Once(finish)
	s:Play()
	task.delay(8, finish)
end

return Sound
