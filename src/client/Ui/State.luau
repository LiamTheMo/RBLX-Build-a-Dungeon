-- Latest private State snapshot pushed by the server, plus a Changed signal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)
local Net = require(script.Parent.Net)

local State = { Current = nil :: any, Changed = Signal.new(), Released = Signal.new() }

-- While held (a box is opening), incoming snapshots are buffered and only the latest is applied on release,
-- so counts, the new room and the Bag badge do not change before the reveal.
local held = false
local pending: any = nil
local holdToken = 0

local started = false
function State.Start()
	if started then
		return
	end
	started = true
	Net.OnEvent("State", function(snapshot)
		if type(snapshot) ~= "table" then
			return
		end
		if held then
			pending = snapshot
			return
		end
		State.Current = snapshot
		State.Changed:Fire(snapshot)
	end)
end

function State.IsHeld(): boolean
	return held
end

-- Hold(true) starts buffering (auto-releases after 60 s as a safety net); Hold(false) applies the latest.
function State.Hold(on: boolean)
	if on then
		held = true
		holdToken += 1
		local mine = holdToken
		task.delay(60, function()
			if held and holdToken == mine then
				State.Hold(false)
			end
		end)
		return
	end
	if not held then
		return
	end
	held = false
	local latest = pending
	pending = nil
	if latest then
		State.Current = latest
		State.Changed:Fire(latest)
	end
	State.Released:Fire()
end

-- True when the snapshot lists an instance of roomId in its layout.
function State.HasPlaced(roomId: string): boolean
	local s = State.Current
	if not s or not s.Layout or not s.Rooms then
		return false
	end
	for _, instanceId in s.Layout do
		local room = s.Rooms[instanceId]
		if room and room.Id == roomId then
			return true
		end
	end
	return false
end

return State
