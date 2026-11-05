local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Core.Loader)

-- The live publisher only creates folders that hold scripts, so Services may not
-- exist until the first service ships.
local container = script:FindFirstChild("Services")
if container then
	local services = Loader.LoadChildren(container)
	Loader.Init(services)
	Loader.Start(services)
end
