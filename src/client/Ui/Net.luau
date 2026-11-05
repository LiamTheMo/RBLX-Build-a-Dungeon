-- Thin client side of ReplicatedStorage.Remotes. Invoke never throws; the
-- server decides everything, the client only shows the answer.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder: Instance? = nil

local function remotes(): Instance
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return folder :: Instance
end

-- Returns (ok, reasonOrData). A transport failure reads as "Busy".
function Net.Invoke(name: string, ...: any): (boolean, any)
	local ok, a, b = pcall(function(...)
		local remote = remotes():WaitForChild(name, 10)
		if not remote then
			error("missing remote " .. name)
		end
		return remote:InvokeServer(...)
	end, ...)
	if not ok then
		return false, "Busy"
	end
	return a == true, b
end

-- Connects once the remote exists (waits in its own thread).
function Net.OnEvent(name: string, fn: (...any) -> ())
	task.spawn(function()
		local remote = remotes():WaitForChild(name)
		remote.OnClientEvent:Connect(fn)
	end)
end

return Net
