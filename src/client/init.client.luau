local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage.Shared.Core.Loader)

-- The live publisher only creates folders that hold scripts, so Controllers may
-- not exist until the first controller ships.
local container = script:FindFirstChild("Controllers")
if container then
	local controllers = Loader.LoadChildren(container)
	Loader.Init(controllers)
	Loader.Start(controllers)
end
