-- Server side of ReplicatedStorage.Remotes: creates every remote declared in
-- Shared.Net.Remotes and guards every client request (RemoteGuard).
--   Net.Handle(name, check, handler)  -- RemoteFunction: handler(player, ...) -> (ok, reasonOrData)
--   Net.Fire(name, player, payload) / Net.FireAll(name, payload)  -- RemoteEvents
--   Net.SetReadyCheck(fn(player) -> boolean)  -- false => "ProfileNotLoaded"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGuard = require(script.Parent.RemoteGuard)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local Net = {}

local guard = RemoteGuard.new({ clock = os.clock })
local remotes = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if folder == nil then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end
for name, kind in Remotes.Kinds do
	local remote = Instance.new(if kind == "Function" then "RemoteFunction" else "RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	remotes[name] = remote
end

local function getRemote(name: string, className: string)
	local remote = remotes[name]
	assert(remote and remote.ClassName == className, `Net: no {className} named {name}`)
	return remote
end

function Net.SetReadyCheck(ready: (Player) -> boolean)
	guard:SetReady(ready)
end

function Net.Handle(name: string, check: (...any) -> boolean, handler: (Player, ...any) -> (boolean, any))
	local remote = getRemote(name, "RemoteFunction")
	remote.OnServerInvoke = function(player: Player, ...)
		return guard:Call(player, name, check, handler, ...)
	end
end

function Net.Fire(name: string, player: Player, payload: any)
	if player.Parent == nil then
		return -- already left (delayed notices)
	end
	getRemote(name, "RemoteEvent"):FireClient(player, payload)
end

function Net.FireAll(name: string, payload: any)
	getRemote(name, "RemoteEvent"):FireAllClients(payload)
end

Players.PlayerRemoving:Connect(function(player)
	guard:Forget(player)
end)

return Net
